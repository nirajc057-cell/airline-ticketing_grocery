import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'database.dart';
import 'booking_fields.dart';
import 'payment_methods.dart';
import 'grocery_pricing.dart';
import 'security.dart';
import 'state.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.message);
  final int status;
  final String message;
}

class AeroDeskServer {
  AeroDeskServer._(this.db);
  final Connection db;
  Future<void> _tail = Future.value();

  static Future<AeroDeskServer> open(String databaseUrl) async {
    final db = await openDatabase(databaseUrl);
    final lock = await db.execute('SELECT pg_try_advisory_lock(4782001)');
    if (lock.first[0] != true) {
      await db.close();
      throw StateError(
          'Another AeroDesk server is using this database. Stop it first.');
    }
    final result = await db.execute('SELECT count(*) FROM tenant_workspaces');
    if ((result.first[0] as int) < 2) {
      await db.execute('SELECT pg_advisory_unlock(4782001)');
      await db.close();
      throw StateError(
          'Run bin/migrate_workspaces.dart before starting the Dart API.');
    }
    return AeroDeskServer._(db);
  }

  Future<HttpServer> serve({String host = '127.0.0.1', int port = 4783}) =>
      shelf_io.serve(call, host, port, poweredByHeader: null);

  Future<void> close() async {
    await _tail;
    await db.execute('SELECT pg_advisory_unlock(4782001)');
    await db.close();
  }

  Future<Response> call(Request request) async {
    if (request.method == 'OPTIONS') return _response(null, 204, request);
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      final result = await _dispatch(request);
      return _response(result, 200, request);
    } on ApiFailure catch (error) {
      return _response({'error': error.message}, error.status, request);
    } catch (error, stack) {
      stderr.writeln('API error: $error\n$stack');
      return _response({'error': 'Internal server error'}, 500, request);
    } finally {
      done.complete();
    }
  }

  Response _response(Object? body, int status, Request request) {
    final origin = request.headers['origin'] ?? '';
    final localOrigin =
        RegExp(r'^http://(localhost|127\.0\.0\.1)(:\d+)?$').hasMatch(origin);
    return Response(status,
        body: body == null ? null : jsonEncode(body),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
          if (localOrigin) 'access-control-allow-origin': origin,
          'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
          'access-control-allow-headers': 'Authorization, Content-Type',
          'vary': 'Origin',
        });
  }

  Future<Map<String, dynamic>> _body(Request request) async {
    final raw = await request.readAsString();
    if (raw.length > 2000000) throw const ApiFailure(413, 'Request too large');
    try {
      return asObject(jsonDecode(raw));
    } catch (_) {
      throw const ApiFailure(400, 'Invalid JSON request');
    }
  }

  Future<Map<String, dynamic>> _session(Request request) async {
    final auth = request.headers['authorization'] ?? '';
    if (!auth.startsWith('Bearer '))
      throw const ApiFailure(401, 'Sign in required');
    final rows = await db.execute(
        Sql.named(
            '''SELECT u.id::text,u.workspace_id::text,u.email,u.display_name,u.role,u.active
      FROM tenant_sessions s JOIN tenant_users u ON u.id=s.user_id
      WHERE s.token_hash=@token AND s.expires_at>now()'''),
        parameters: {'token': sha256Hex(auth.substring(7))});
    if (rows.isEmpty || rows.first[5] != true)
      throw const ApiFailure(401, 'Session expired');
    final row = rows.first;
    return {
      'id': row[0],
      'workspaceId': row[1],
      'email': row[2],
      'name': row[3],
      'role': row[4]
    };
  }

  Future<Map<String, dynamic>> _state(String workspaceId) async {
    final rows = await db.execute(
        Sql.named(
            'SELECT document::text FROM tenant_state WHERE workspace_id=@id::uuid'),
        parameters: {'id': workspaceId});
    if (rows.isEmpty) throw const ApiFailure(404, 'Workspace not found');
    return asObject(rows.first[0]);
  }

  Future<void> _save(String workspaceId, Map<String, dynamic> state) async {
    await db.execute(Sql.named('''UPDATE tenant_state SET document=@doc::jsonb,
      revision=revision+1,updated_at=now() WHERE workspace_id=@id::uuid'''),
        parameters: {'id': workspaceId, 'doc': jsonEncode(state)});
  }

  Map<String, dynamic> _currentUser(
      Map<String, dynamic> state, Map<String, dynamic> account) {
    final users = records(state['users']);
    final user = users
        .where((u) => u['email']?.toString().toLowerCase() == account['email'])
        .firstOrNull;
    final result = {
      ...?user,
      'email': account['email'],
      'name': account['name'],
      'role': account['role']
    };
    result.remove('passwordHash');
    result.remove('twoFactorSecret');
    return result;
  }

  Future<Object?> _dispatch(Request request) async {
    final path = request.url.path.startsWith('/')
        ? request.url.path
        : '/${request.url.path}';
    final method = request.method;
    if (path == '/api/health' && method == 'GET')
      return {'ok': true, 'storage': 'postgresql'};
    if (path == '/api/login' && method == 'POST')
      return _login(await _body(request));
    final account = await _session(request);
    final space = account['workspaceId'] as String;
    if (path == '/api/logout' && method == 'POST') {
      final token = request.headers['authorization']!.substring(7);
      await db.execute(
          Sql.named('DELETE FROM tenant_sessions WHERE token_hash=@token'),
          parameters: {'token': sha256Hex(token)});
      return {'ok': true};
    }
    if (path == '/api/account/change-password' && method == 'POST') {
      return _changePassword(account, await _body(request));
    }
    if (path.startsWith('/api/account/2fa/')) {
      throw const ApiFailure(
          501, 'Two-factor setup is not yet available in the SQL-only backend');
    }
    final state = await _state(space);
    _authorize(state, account, path);
    if (path == '/api/payment-method-types' ||
        path.startsWith('/api/payment-method-types/')) {
      final types = paymentTypes(state);
      if (path == '/api/payment-method-types' && method == 'GET') return types;
      _requireOwner(account);
      if (path == '/api/payment-method-types' && method == 'POST') {
        if (types.length >= 30) {
          throw const ApiFailure(409, 'Payment method limit reached');
        }
        late final Map<String, dynamic> value;
        try {
          value = normalizePaymentType(await _body(request));
        } on FormatException catch (error) {
          throw ApiFailure(400, error.message);
        }
        if (types.any((item) =>
            item['name'].toString().toLowerCase() ==
            value['name'].toString().toLowerCase())) {
          throw const ApiFailure(409, 'Payment method name already exists');
        }
        final created = {'id': _id('MT'), ...value};
        types.add(created);
        state['paymentTypes'] = types;
        _audit(state, account, 'Added payment method type',
            created['id'].toString());
        await _save(space, state);
        return created;
      }
      final id = path.substring('/api/payment-method-types/'.length);
      final index = types.indexWhere((item) => item['id'] == id);
      if (id.isEmpty || id.contains('/') || index < 0) {
        throw const ApiFailure(404, 'Payment method not found');
      }
      if (method == 'PATCH') {
        late final Map<String, dynamic> value;
        try {
          value =
              normalizePaymentType({...types[index], ...await _body(request)});
        } on FormatException catch (error) {
          throw ApiFailure(400, error.message);
        }
        if (types.any((item) =>
            item['id'] != id &&
            item['name'].toString().toLowerCase() ==
                value['name'].toString().toLowerCase())) {
          throw const ApiFailure(409, 'Payment method name already exists');
        }
        types[index] = {'id': id, ...value};
        state['paymentTypes'] = types;
        _audit(state, account, 'Updated payment method type', id);
        await _save(space, state);
        return types[index];
      }
      if (method == 'DELETE') {
        final removed = types.removeAt(index);
        state['paymentTypes'] = types;
        _audit(state, account, 'Deleted payment method type', id);
        await _save(space, state);
        return {'ok': true, 'name': removed['name']};
      }
      throw const ApiFailure(405, 'Method not allowed');
    }
    if (path == '/api/payment-methods' ||
        path.startsWith('/api/payment-methods/')) {
      final profiles = records(state['paymentProfiles']);
      if (path == '/api/payment-methods' && method == 'GET') return profiles;
      _requireOwner(account);
      if (path == '/api/payment-methods' && method == 'POST') {
        if (profiles.length >= 50) {
          throw const ApiFailure(409, 'Payment method limit reached');
        }
        final input = await _body(request);
        late final Map<String, dynamic> profile;
        try {
          profile = normalizePaymentProfile(input, state: state);
        } on FormatException catch (error) {
          throw ApiFailure(400, error.message);
        }
        if (profiles.any((item) =>
            item['method'] == profile['method'] &&
            item['label'].toString().toLowerCase() ==
                profile['label'].toString().toLowerCase())) {
          throw const ApiFailure(409, 'Payment method name already exists');
        }
        profile['id'] = _id('PM');
        profile['createdAt'] = _now();
        profile['createdBy'] = account['email'];
        profiles.add(profile);
        state['paymentProfiles'] = profiles;
        _audit(state, account, 'Added payment method',
            profile['label'].toString());
        await _save(space, state);
        return profile;
      }
      if (path.startsWith('/api/payment-methods/')) {
        final id = path.substring('/api/payment-methods/'.length);
        final index = profiles.indexWhere((profile) => profile['id'] == id);
        if (id.isEmpty || id.contains('/') || index < 0) {
          throw const ApiFailure(404, 'Payment method not found');
        }
        if (method == 'PATCH') {
          final input = await _body(request);
          late final Map<String, dynamic> normalized;
          try {
            normalized = normalizePaymentProfile({...profiles[index], ...input},
                state: state);
          } on FormatException catch (error) {
            throw ApiFailure(400, error.message);
          }
          if (profiles.any((item) =>
              item['id'] != id &&
              item['method'] == normalized['method'] &&
              item['label'].toString().toLowerCase() ==
                  normalized['label'].toString().toLowerCase())) {
            throw const ApiFailure(409, 'Payment method name already exists');
          }
          profiles[index] = {
            'id': id,
            'createdAt': profiles[index]['createdAt'],
            'createdBy': profiles[index]['createdBy'],
            ...normalized,
            'updatedAt': _now(),
            'updatedBy': account['email'],
          };
          state['paymentProfiles'] = profiles;
          _audit(state, account, 'Updated payment method', id);
          await _save(space, state);
          return profiles[index];
        }
        if (method == 'DELETE') {
          final removed = profiles.removeAt(index);
          state['paymentProfiles'] = profiles;
          _audit(state, account, 'Deleted payment method', id);
          await _save(space, state);
          return {'ok': true, 'label': removed['label']};
        }
      }
      throw const ApiFailure(405, 'Method not allowed');
    }
    if (path == '/api/custom-tables' ||
        path.startsWith('/api/custom-tables/')) {
      return _customTables(state, account, space, request, path, method);
    }
    if (path == '/api/bootstrap' && method == 'GET') {
      return _bootstrap(state, account);
    }
    if (path == '/api/grocery/bootstrap' && method == 'GET') {
      return _groceryBootstrap(state);
    }
    if (const {
          '/api/bookings/form-fields',
          '/api/passports/form-fields',
          '/api/refunds/form-fields',
        }.contains(path) ||
        path.startsWith('/api/form-fields/')) {
      final module = path.startsWith('/api/form-fields/')
          ? path.substring('/api/form-fields/'.length)
          : path.split('/')[2];
      final baseKeys = formFieldKeys(module);
      if (baseKeys.isEmpty) throw const ApiFailure(404, 'Form not found');
      final config = recordFormConfig(state, module);
      if (method == 'GET') return config;
      _requireOwner(account);
      final body = await _body(request);
      final key = (body['key'] ?? '').toString();
      final custom = records(config['custom']);
      final archived = records(config['archivedCustom']);
      final removed = List<String>.from(config['removed'] as List);
      final labels = asObject(config['labels']);
      final order = List<String>.from(config['order'] as List);
      if (method == 'POST' && body['restoreKey'] is String) {
        final restoreKey = body['restoreKey'] as String;
        if (baseKeys.contains(restoreKey) && removed.remove(restoreKey)) {
          config['removed'] = removed;
        } else {
          final index =
              archived.indexWhere((field) => field['key'] == restoreKey);
          if (index < 0 || custom.length >= 50) {
            throw const ApiFailure(400, 'Field is not available to restore');
          }
          custom.add(archived.removeAt(index));
          config['custom'] = custom;
          config['archivedCustom'] = archived;
        }
        if (order.isNotEmpty) {
          order.add(restoreKey);
          config['order'] = order;
        }
      } else if (method == 'POST') {
        final label = (body['label'] ?? '').toString().trim();
        final type = (body['type'] ?? 'text').toString();
        final choices = body['choices'] is List
            ? (body['choices'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];
        if (label.isEmpty ||
            label.length > 60 ||
            !{'text', 'number', 'date', 'paragraph', 'choice'}.contains(type) ||
            (type == 'choice' && choices.isEmpty) ||
            custom.length >= 50 ||
            choices.length > 30 ||
            choices.any((choice) => choice.length > 80) ||
            custom.any((field) =>
                field['label'].toString().toLowerCase() ==
                label.toLowerCase())) {
          throw const ApiFailure(400, 'Invalid field name, type, or choices');
        }
        final newKey = 'custom_${_id('FIELD')}';
        custom.add({
          'key': newKey,
          'label': label,
          'type': type,
          'choices': choices,
          'required': body['required'] == true,
        });
        config['custom'] = custom;
        if (order.isNotEmpty) {
          order.add(newKey);
          config['order'] = order;
        }
      } else if (method == 'PATCH') {
        if (body['order'] is List) {
          final requested =
              (body['order'] as List).whereType<String>().toList();
          final active = <String>{
            ...baseKeys.where((field) => !removed.contains(field)),
            ...custom.map((field) => field['key'].toString()),
          };
          if (requested.length != active.length ||
              requested.toSet().length != active.length ||
              !requested.toSet().containsAll(active)) {
            throw const ApiFailure(
                400, 'Field order must include each active field once');
          }
          config['order'] = requested;
          state[formStateKey(module)] = config;
          _audit(state, account, 'Reordered $module form', '$module fields');
          await _save(space, state);
          return config;
        }
        final label = (body['label'] ?? '').toString().trim();
        if (!recordFieldExists(config, module, key) ||
            label.isEmpty ||
            label.length > 60) {
          throw const ApiFailure(400, 'Invalid field or label');
        }
        final index = custom.indexWhere((field) => field['key'] == key);
        if (index >= 0) {
          custom[index]['label'] = label;
          config['custom'] = custom;
        } else {
          labels[key] = label;
          config['labels'] = labels;
        }
      } else if (method == 'DELETE') {
        if (!recordFieldExists(config, module, key) || removed.contains(key)) {
          throw const ApiFailure(400, 'Field is not available');
        }
        if ((protectedRecordFields[module] ?? const <String>{}).contains(key)) {
          throw const ApiFailure(409,
              'This field is required for this workflow and cannot be deleted');
        }
        final customIndex = custom.indexWhere((field) => field['key'] == key);
        if (customIndex >= 0) archived.add(custom.removeAt(customIndex));
        if (baseKeys.contains(key)) removed.add(key);
        labels.remove(key);
        config['custom'] = custom;
        config['archivedCustom'] = archived;
        config['removed'] = removed;
        config['labels'] = labels;
        order.remove(key);
        config['order'] = order;
      } else {
        throw const ApiFailure(405, 'Method not allowed');
      }
      state[formStateKey(module)] = config;
      _audit(
          state,
          account,
          'Changed $module form',
          method == 'DELETE'
              ? 'Removed $key from active form; saved values retained'
              : method == 'PATCH'
                  ? 'Renamed $key'
                  : 'Added or restored field');
      await _save(space, state);
      return config;
    }
    if (path == '/api/finance/overview' && method == 'GET') {
      return _financeOverview(state);
    }
    if (path == '/api/finance/reports' && method == 'GET') {
      return _financeReports(state);
    }
    if (path == '/api/reports/sales' && method == 'GET') {
      return _salesReport(state);
    }
    if (path == '/api/finance/settings' && method == 'PATCH') {
      _requireOwner(account);
      final finance = asObject(state['finance']);
      finance['settings'] = {
        ...asObject(finance['settings']),
        ...await _body(request)
      };
      state['finance'] = finance;
      await _save(space, state);
      return finance['settings'];
    }
    if (path == '/api/ledger' && method == 'POST') {
      final result = _postJournal(state, await _body(request), account);
      await _save(space, state);
      return result;
    }
    if (path == '/api/wallet/adjustments' && method == 'POST') {
      final finance = asObject(state['finance']);
      final rows = records(finance['pendingAdjustments']);
      final input = await _body(request);
      _recordPaymentMethods(state, input);
      final record = {
        ...input,
        'id': _id('ADJ'),
        'status': 'Pending',
        'createdAt': _now(),
        'createdBy': account['email']
      };
      rows.insert(0, record);
      finance['pendingAdjustments'] = rows;
      state['finance'] = finance;
      _audit(state, account, 'Adjustment requested', record['id'].toString());
      await _save(space, state);
      return record;
    }
    if (path == '/api/finance/reconciliations' && method == 'POST') {
      final finance = asObject(state['finance']);
      final rows = records(finance['reconciliations']);
      final body = await _body(request);
      _recordPaymentMethods(state, body);
      final record = {
        ...body,
        'id': _id('REC'),
        'createdAt': _now(),
        'difference':
            _num(body['statementBalance']) - _num(body['systemBalance'])
      };
      rows.insert(0, record);
      finance['reconciliations'] = rows;
      state['finance'] = finance;
      await _save(space, state);
      return record;
    }
    if (path == '/api/finance/periods' && method == 'POST') {
      _requireOwner(account);
      final body = await _body(request);
      if ((body['from'] ?? '').toString().isEmpty ||
          (body['to'] ?? '').toString().isEmpty) {
        throw const ApiFailure(400, 'Start and end dates are required');
      }
      final finance = asObject(state['finance']);
      final rows = records(finance['lockedPeriods']);
      final record = {
        ...body,
        'id': _id('PER'),
        'status': 'Locked',
        'createdAt': _now()
      };
      rows.insert(0, record);
      finance['lockedPeriods'] = rows;
      state['finance'] = finance;
      await _save(space, state);
      return record;
    }
    if (path == '/api/grocery/sales' && method == 'POST') {
      final sale = _grocerySale(state, await _body(request), account);
      await _save(space, state);
      return sale;
    }
    if (path == '/api/grocery/purchases' && method == 'POST') {
      final purchase = _newPurchase(state, await _body(request), account);
      await _save(space, state);
      return purchase;
    }
    if (path == '/api/grocery/expenses' && method == 'POST') {
      final expense = _newExpense(state, await _body(request), account);
      await _save(space, state);
      return expense;
    }
    if (path == '/api/users' && method == 'POST') {
      _requireOwner(account);
      return _addUser(state, account, await _body(request));
    }
    if (path == '/api/refunds' && method == 'POST') {
      final refund = _newRefund(state, await _body(request), account);
      await _save(space, state);
      return refund;
    }
    if (path == '/api/sales' && method == 'POST') {
      final sale = _directSale(state, await _body(request), account);
      await _save(space, state);
      return sale;
    }
    if (path == '/api/bookings/table-setup' ||
        path == '/api/grocery/products/table-setup') {
      final key = path.startsWith('/api/grocery/') ? 'products' : 'bookings';
      final setup = asObject(state['tableSetup']);
      if (method == 'GET') return {'initialized': setup[key] == true};
      if (method != 'POST') throw const ApiFailure(405, 'Method not allowed');
      if (setup[key] == true)
        throw const ApiFailure(409, 'Table already created');
      final body = await _body(request);
      final rowCount = body['rows'];
      final columnCount = body['extraColumns'];
      if (rowCount is! int ||
          rowCount < 0 ||
          rowCount > 5000 ||
          columnCount is! int ||
          columnCount < 0 ||
          columnCount > 50) {
        throw const ApiFailure(
            400, 'Choose 0–5000 rows and 0–50 extra columns');
      }
      final allColumns = asObject(state['tableColumns']);
      final columns = records(allColumns[key]);
      if (columns.length + columnCount > 50) {
        throw const ApiFailure(400, 'Maximum 50 extra columns');
      }
      for (var index = 0; index < columnCount; index++) {
        columns.add({
          'key': 'custom_${_id('COL')}',
          'label': 'Column ${columns.length + 1}'
        });
      }
      allColumns[key] = columns;
      state['tableColumns'] = allColumns;
      final allDrafts = asObject(state['tableDrafts']);
      final drafts = records(allDrafts[key]);
      drafts.addAll(List.generate(rowCount,
          (_) => {'id': _id('DRAFT'), 'values': <String, dynamic>{}}));
      allDrafts[key] = drafts;
      state['tableDrafts'] = allDrafts;
      setup[key] = true;
      state['tableSetup'] = setup;
      _audit(state, account, 'Created table',
          '$key: $rowCount rows, $columnCount extra columns',
          grocery: key == 'products');
      await _save(space, state);
      return {'initialized': true};
    }
    if (path == '/api/bookings/table-layout' ||
        path == '/api/grocery/products/table-layout') {
      final grocery = path.startsWith('/api/grocery/');
      final key = grocery ? 'products' : 'bookings';
      _requireTableAccess(state, account, grocery ? 'grocery' : 'airline');
      final layouts = asObject(state['tableLayouts']);
      final layout = asObject(layouts[key]);
      final users = asObject(layout['columnsByUser']);
      final userId = account['id'].toString();
      Object result() => {
            'columns': users[userId] ?? <String>[],
            'rows': layout['rows'] ?? <String>[],
            'revision': layout['revision'] ?? 0,
          };
      if (method == 'GET') return result();
      if (method != 'PATCH') throw const ApiFailure(405, 'Method not allowed');
      final body = await _body(request);
      if (body['revision'] != (layout['revision'] ?? 0)) {
        throw const ApiFailure(
            409, 'Table order changed elsewhere. Reload before saving.');
      }
      if (body['columns'] is List) {
        final requested =
            (body['columns'] as List).map((e) => e.toString()).toList();
        final form =
            recordFormConfig(state, grocery ? 'grocery_products' : 'bookings');
        final removed =
            (form['removed'] as List).map((e) => e.toString()).toSet();
        final valid = <String>{
          ...formFieldKeys(grocery ? 'grocery_products' : 'bookings')
              .where((field) => !removed.contains(field)),
          ...records(form['custom']).map((field) => field['key'].toString()),
          ...records(asObject(state['tableColumns'])[key])
              .map((field) => field['key'].toString()),
          'id',
        };
        if (requested.length > 100 ||
            requested.toSet().length != requested.length ||
            requested.any((field) => !valid.contains(field))) {
          throw const ApiFailure(400, 'Invalid column order');
        }
        users[userId] = requested;
        layout['columnsByUser'] = users;
      }
      if (body['rows'] is List) {
        final requested =
            (body['rows'] as List).map((e) => e.toString()).toList();
        final valid = <String>{
          ...collection(
                  state, grocery ? '/api/grocery/products' : '/api/bookings')
              .map((row) => row['id'].toString()),
          ...records(asObject(state['tableDrafts'])[key])
              .map((row) => row['id'].toString()),
        };
        if (requested.length > 50000 ||
            requested.toSet().length != requested.length ||
            requested.any((id) => !valid.contains(id))) {
          throw const ApiFailure(400, 'Invalid row order');
        }
        layout['rows'] = requested;
      }
      layout['revision'] = (layout['revision'] as int? ?? 0) + 1;
      layouts[key] = layout;
      state['tableLayouts'] = layouts;
      _audit(state, account, 'Updated table layout', key, grocery: grocery);
      await _save(space, state);
      return result();
    }
    if (path.startsWith('/api/table-layouts/')) {
      final parts = path.split('/');
      if (parts.length != 5 ||
          (parts[3] != 'airline' && parts[3] != 'grocery')) {
        throw const ApiFailure(404, 'Table not found');
      }
      final grocery = parts[3] == 'grocery';
      final module = parts[4];
      final root = grocery ? '/api/grocery/$module' : '/api/$module';
      if (collectionKey(root).isEmpty) {
        throw const ApiFailure(404, 'Table not found');
      }
      final layoutKey = '${parts[3]}:$module';
      final layouts = asObject(state['tableLayouts']);
      final layout = asObject(layouts[layoutKey]);
      final users = asObject(layout['columnsByUser']);
      final userId = account['id'].toString();
      Object result() => {
            'columns': users[userId] ?? <String>[],
            'rows': layout['rows'] ?? <String>[],
            'revision': layout['revision'] ?? 0,
          };
      if (method == 'GET') return result();
      if (method != 'PATCH') throw const ApiFailure(405, 'Method not allowed');
      final body = await _body(request);
      if (body['revision'] != (layout['revision'] ?? 0)) {
        throw const ApiFailure(
            409, 'Table order changed elsewhere. Reload before saving.');
      }
      if (body['columns'] is List) {
        final requested =
            (body['columns'] as List).map((item) => item.toString()).toList();
        if (requested.length > 100 ||
            requested.toSet().length != requested.length ||
            requested.any((key) =>
                key.isEmpty ||
                key.length > 100 ||
                !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(key) ||
                {'password', 'passwordHash', 'twoFactorSecret'}
                    .contains(key))) {
          throw const ApiFailure(400, 'Invalid column order');
        }
        users[userId] = requested;
        layout['columnsByUser'] = users;
      }
      if (body['rows'] is List) {
        _requireOwner(account);
        final requested =
            (body['rows'] as List).map((item) => item.toString()).toList();
        final valid = collection(state, root)
            .map((row) => row['id']?.toString())
            .whereType<String>()
            .toSet();
        if (requested.length > 50000 ||
            requested.toSet().length != requested.length ||
            requested.any((id) => !valid.contains(id))) {
          throw const ApiFailure(400, 'Invalid row order');
        }
        layout['rows'] = requested;
      }
      layout['revision'] = (layout['revision'] as int? ?? 0) + 1;
      layouts[layoutKey] = layout;
      state['tableLayouts'] = layouts;
      _audit(state, account, 'Updated table layout', layoutKey,
          grocery: grocery);
      await _save(space, state);
      return result();
    }
    if (path == '/api/bookings/table-drafts' ||
        path == '/api/grocery/products/table-drafts' ||
        path.startsWith('/api/bookings/table-drafts/') ||
        path.startsWith('/api/grocery/products/table-drafts/')) {
      final key = path.startsWith('/api/grocery/') ? 'products' : 'bookings';
      final root = key == 'products'
          ? '/api/grocery/products/table-drafts'
          : '/api/bookings/table-drafts';
      final all = asObject(state['tableDrafts']);
      final drafts = records(all[key]);
      if (path == root && method == 'GET') return drafts;
      if (path == root && method == 'POST') {
        if (drafts.length >= 50000) {
          throw const ApiFailure(409, 'Draft row limit reached');
        }
        final draft = {'id': _id('DRAFT'), 'values': await _body(request)};
        drafts.add(draft);
        all[key] = drafts;
        state['tableDrafts'] = all;
        await _save(space, state);
        return draft;
      }
      if (!path.startsWith('$root/')) {
        throw const ApiFailure(405, 'Method not allowed');
      }
      final id = path.substring(root.length + 1);
      final index = drafts.indexWhere((draft) => draft['id'] == id);
      if (index < 0) throw const ApiFailure(404, 'Draft not found');
      if (method == 'PATCH') {
        drafts[index]['values'] = await _body(request);
        all[key] = drafts;
        state['tableDrafts'] = all;
        await _save(space, state);
        return drafts[index];
      }
      if (method == 'DELETE') {
        drafts.removeAt(index);
        all[key] = drafts;
        state['tableDrafts'] = all;
        await _save(space, state);
        return {'ok': true};
      }
      throw const ApiFailure(405, 'Method not allowed');
    }
    if (path == '/api/bookings/table-columns' ||
        path == '/api/grocery/products/table-columns') {
      final key = path.startsWith('/api/grocery/') ? 'products' : 'bookings';
      final all = asObject(state['tableColumns']);
      final columns = records(all[key]);
      if (method == 'GET') return columns;
      final body = await _body(request);
      final label = (body['label'] ?? '').toString().trim();
      if (label.isEmpty || label.length > 60) {
        throw const ApiFailure(400, 'Column name must be 1–60 characters');
      }
      if (method == 'POST') {
        if (columns.length >= 50 ||
            columns.any((c) =>
                c['label'].toString().toLowerCase() == label.toLowerCase())) {
          throw const ApiFailure(
              409, 'Column already exists or column limit reached');
        }
        final column = {'key': 'custom_${_id('COL')}', 'label': label};
        columns.add(column);
        all[key] = columns;
        state['tableColumns'] = all;
        _audit(state, account, 'Added table column', '$key: $label',
            grocery: key == 'products');
        await _save(space, state);
        return column;
      }
      if (method == 'PATCH') {
        final index = columns.indexWhere((c) => c['key'] == body['key']);
        if (index < 0 ||
            columns.any((c) =>
                c['key'] != body['key'] &&
                c['label'].toString().toLowerCase() == label.toLowerCase())) {
          throw const ApiFailure(
              409, 'Column not found or name already exists');
        }
        columns[index]['label'] = label;
        all[key] = columns;
        state['tableColumns'] = all;
        _audit(state, account, 'Renamed table column', '$key: $label',
            grocery: key == 'products');
        await _save(space, state);
        return columns[index];
      }
      throw const ApiFailure(405, 'Method not allowed');
    }
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    final root = parts.length >= 3 && parts[1] == 'grocery'
        ? '/api/grocery/${parts[2]}'
        : parts.length >= 2
            ? '/api/${parts[1]}'
            : path;
    if (collectionKey(root).isNotEmpty) {
      final detailIndex = root.startsWith('/api/grocery/') ? 3 : 2;
      if (parts.length == detailIndex && method == 'GET') {
        final rows = collection(state, root);
        final visible =
            root == '/api/users' ? rows.map(_safeUser).toList() : rows;
        final search =
            request.url.queryParameters['search']?.trim().toLowerCase() ?? '';
        if (search.length > 200) {
          throw const ApiFailure(400, 'Search is too long');
        }
        if (search.isEmpty) return visible;
        return visible.where((row) {
          final text = row.entries
              .where((entry) => !{
                    'password',
                    'passwordHash',
                    'twoFactorSecret',
                  }.contains(entry.key))
              .map((entry) => jsonEncode(entry.value))
              .join(' ')
              .toLowerCase();
          return text.contains(search);
        }).toList();
      }
      if (parts.length == detailIndex && method == 'POST') {
        if (root == '/api/audit' || root == '/api/grocery/audit') {
          throw const ApiFailure(
              405, 'Audit entries cannot be created directly');
        }
        if (root == '/api/roles') _requireOwner(account);
        final record = _newRecord(state, root, await _body(request), account);
        await _save(space, state);
        return record;
      }
      if (parts.length >= detailIndex + 1) {
        final id = parts[detailIndex];
        final action =
            parts.length > detailIndex + 1 ? parts[detailIndex + 1] : '';
        if (root == '/api/users') _requireOwner(account);
        if (method == 'GET' && root == '/api/users' && action == 'sessions') {
          return _userSessions(state, id);
        }
        if (method == 'GET' &&
            root == '/api/grocery/suppliers' &&
            action == 'statement') {
          return _supplierStatement(state, id);
        }
        if (method == 'PATCH' && action.isEmpty) {
          final updated = await _updateRecord(
              state, root, id, await _body(request), account);
          if (root == '/api/users') {
            await _saveUserState(space, state, updated);
          } else {
            await _save(space, state);
          }
          return updated;
        }
        if (method == 'DELETE' &&
            action.isEmpty &&
            (root == '/api/bookings' ||
                root == '/api/grocery/products' ||
                root == '/api/company-assets' ||
                root == '/api/grocery/company-assets')) {
          _deleteTableRecord(state, root, id, account);
          await _save(space, state);
          return {'ok': true};
        }
        if (method == 'POST' && action.isNotEmpty) {
          final updated = await _action(
              state, account, root, id, action, await _body(request));
          await _save(space, state);
          return updated;
        }
      }
    }
    if (method == 'POST' && path.startsWith('/api/ledger/')) {
      final id = parts.length >= 3 ? parts[2] : '';
      final result = _reverseJournal(state, id, await _body(request), account);
      await _save(space, state);
      return result;
    }
    if (method == 'POST' && path.startsWith('/api/wallet/adjustments/')) {
      _requireOwner(account);
      final result =
          _approveAdjustment(state, parts[3], await _body(request), account);
      await _save(space, state);
      return result;
    }
    if (method == 'POST' && path.startsWith('/api/finance/periods/')) {
      _requireOwner(account);
      final result = _unlockPeriod(state, parts[3]);
      await _save(space, state);
      return result;
    }
    throw const ApiFailure(404, 'API route not found');
  }

  Future<Object> _login(Map<String, dynamic> body) async {
    final email = body['email']?.toString().trim().toLowerCase() ?? '';
    final password = body['password']?.toString() ?? '';
    final rows = await db.execute(
        Sql.named('''SELECT id::text,workspace_id::text,email,display_name,role,
        password_hash,password_scheme,active FROM tenant_users WHERE lower(email)=@email'''),
        parameters: {'email': email});
    if (rows.isEmpty ||
        rows.first[7] != true ||
        !verifyPassword(
            password, rows.first[5] as String, rows.first[6] as String)) {
      throw const ApiFailure(401, 'Invalid email or password');
    }
    final row = rows.first;
    final account = {
      'id': row[0],
      'workspaceId': row[1],
      'email': row[2],
      'name': row[3],
      'role': row[4]
    };
    final state = await _state(row[1] as String);
    final user = _currentUser(state, account);
    if (user['twoFactorEnabled'] == true) {
      throw const ApiFailure(501,
          'This account uses two-factor authentication, which the new backend does not yet support');
    }
    final token = randomSecret();
    await db.execute(
        Sql.named('''INSERT INTO tenant_sessions(token_hash,user_id,expires_at)
      VALUES (@token,@user::uuid,now()+interval '30 days')'''),
        parameters: {'token': sha256Hex(token), 'user': row[0]});
    return {'token': token, 'user': user};
  }

  Future<Object> _changePassword(
      Map<String, dynamic> account, Map<String, dynamic> body) async {
    final current = body['currentPassword']?.toString() ?? '';
    final next = body['password']?.toString() ?? '';
    if (next != body['confirmPassword'] || next.length < 12) {
      throw const ApiFailure(400,
          'New password must match confirmation and be at least 12 characters');
    }
    final rows = await db.execute(
        Sql.named(
            'SELECT password_hash,password_scheme FROM tenant_users WHERE id=@id::uuid'),
        parameters: {'id': account['id']});
    if (!verifyPassword(
        current, rows.first[0] as String, rows.first[1] as String)) {
      throw const ApiFailure(401, 'Current password is incorrect');
    }
    final state = await _state(account['workspaceId'] as String);
    final users = records(state['users']);
    final user = users
        .where((u) => u['email']?.toString().toLowerCase() == account['email'])
        .firstOrNull;
    if (user != null) {
      user['mustChangePassword'] = false;
      user.remove('passwordHash');
      state['users'] = users;
    }
    await db.runTx((tx) async {
      await tx.execute(
          Sql.named(
              '''UPDATE tenant_users SET password_hash=@hash,password_scheme='pbkdf2-sha256'
        WHERE id=@id::uuid'''),
          parameters: {'hash': hashPassword(next), 'id': account['id']});
      await tx.execute(
          Sql.named(
              '''UPDATE tenant_state SET document=@doc::jsonb,revision=revision+1,
        updated_at=now() WHERE workspace_id=@space::uuid'''),
          parameters: {
            'doc': jsonEncode(state),
            'space': account['workspaceId']
          });
    });
    return {'ok': true};
  }

  void _requireOwner(Map<String, dynamic> account) {
    if (!{'Agency owner', 'Agency administrator'}.contains(account['role'])) {
      throw const ApiFailure(403, 'Owner permission required');
    }
  }

  void _authorize(
      Map<String, dynamic> state, Map<String, dynamic> account, String path) {
    if (path.startsWith('/api/table-layouts/')) {
      final parts = path.split('/');
      if (parts.length != 5 ||
          (parts[3] != 'airline' && parts[3] != 'grocery') ||
          collectionKey(parts[3] == 'grocery'
                  ? '/api/grocery/${parts[4]}'
                  : '/api/${parts[4]}')
              .isEmpty) {
        throw const ApiFailure(404, 'Table not found');
      }
      _authorize(
          state,
          account,
          parts[3] == 'grocery'
              ? '/api/grocery/${parts[4]}'
              : '/api/${parts[4]}');
      return;
    }
    if (path == '/api/payment-method-types' ||
        path.startsWith('/api/payment-method-types/') ||
        path == '/api/payment-methods' ||
        path.startsWith('/api/payment-methods/')) return;
    if (path.startsWith('/api/form-fields/')) {
      final module = path.substring('/api/form-fields/'.length);
      final target = formCollectionPath(module);
      if (target.isEmpty) throw const ApiFailure(404, 'Form not found');
      _authorize(state, account, target);
      return;
    }
    if (account['role'] == 'Agency owner' || path.startsWith('/api/grocery/'))
      return;
    if (path.startsWith('/api/custom-tables')) return;
    final module = path.startsWith('/api/finance/') ||
            path.startsWith('/api/wallet/') ||
            path.startsWith('/api/ledger')
        ? 'finance'
        : path.startsWith('/api/company-assets')
            ? 'company_assets'
            : path.startsWith('/api/reports/')
                ? 'reports'
                : path.startsWith('/api/passports')
                    ? 'passports'
                    : path.startsWith('/api/users') ||
                            path.startsWith('/api/roles')
                        ? 'users'
                        : path.startsWith('/api/audit')
                            ? 'audit'
                            : path.split('/').length > 2
                                ? path.split('/')[2]
                                : '';
    if (module.isEmpty || module == 'bootstrap') return;
    final user = _currentUser(state, account);
    if (asObject(user['permissions'])[module] != true) {
      throw const ApiFailure(403, 'You do not have access to this module');
    }
  }

  Future<Object> _customTables(
      Map<String, dynamic> state,
      Map<String, dynamic> account,
      String space,
      Request request,
      String path,
      String method) async {
    final tables = records(state['customTables']);
    const root = '/api/custom-tables';
    if (path == '$root/reminders' && method == 'GET') {
      final platform = request.url.queryParameters['platform'];
      if (platform != 'airline' && platform != 'grocery') {
        throw const ApiFailure(400, 'Choose an airline or grocery workspace');
      }
      _requireTableAccess(state, account, platform!);
      final now = DateTime.now().toUtc();
      final due = <Map<String, dynamic>>[];
      for (final table
          in tables.where((item) => item['platform'] == platform)) {
        final rows = records(table['rows']);
        for (var index = 0; index < rows.length; index++) {
          final row = rows[index];
          final when = DateTime.tryParse(row['notifyAt']?.toString() ?? '');
          if (when == null ||
              when.isAfter(now) ||
              row['reminderDismissedAt'] != null) continue;
          final cells = asObject(row['cells']);
          final preview = cells.values
                  .where((value) => value.toString().trim().isNotEmpty)
                  .firstOrNull
                  ?.toString() ??
              '';
          due.add({
            'tableId': table['id'],
            'tableName': table['name'],
            'rowId': row['id'],
            'rowNumber': index + 1,
            'notifyAt': row['notifyAt'],
            'preview':
                preview.length > 100 ? preview.substring(0, 100) : preview
          });
        }
      }
      due.sort((a, b) =>
          a['notifyAt'].toString().compareTo(b['notifyAt'].toString()));
      return due;
    }
    if (path.startsWith('$root/reminders/') && method == 'POST') {
      final parts = path.substring('$root/reminders/'.length).split('/');
      if (parts.length != 3 || parts[2] != 'dismiss') {
        throw const ApiFailure(404, 'Reminder not found');
      }
      final tableId = Uri.decodeComponent(parts[0]);
      final rowId = Uri.decodeComponent(parts[1]);
      final index = tables.indexWhere((item) => item['id'] == tableId);
      if (index < 0) throw const ApiFailure(404, 'Reminder not found');
      final table = tables[index];
      _requireTableAccess(state, account, table['platform'].toString());
      final rows = records(table['rows']);
      final row = rows.where((item) => item['id'] == rowId).firstOrNull;
      if (row == null || row['notifyAt'] == null) {
        throw const ApiFailure(404, 'Reminder not found');
      }
      row['reminderDismissedAt'] = _now();
      table['rows'] = rows;
      table['revision'] = (table['revision'] as int) + 1;
      tables[index] = table;
      state['customTables'] = tables;
      _audit(state, account, 'Dismissed table reminder',
          '${table['name']}: $rowId',
          grocery: table['platform'] == 'grocery');
      await _save(space, state);
      return {'ok': true};
    }
    if (path == root) {
      if (method == 'GET') {
        final platform = request.url.queryParameters['platform'];
        if (platform != 'airline' && platform != 'grocery') {
          throw const ApiFailure(400, 'Choose an airline or grocery workspace');
        }
        _requireTableAccess(state, account, platform!);
        return tables
            .where((table) => table['platform'] == platform)
            .map(
              (table) => {
                'id': table['id'],
                'name': table['name'],
                'platform': platform,
                'rowCount': records(table['rows']).length,
                'columnCount': records(table['columns']).length
              },
            )
            .toList();
      }
      if (method != 'POST') throw const ApiFailure(405, 'Method not allowed');
      final body = await _body(request);
      final platform = body['platform']?.toString();
      final name = body['name']?.toString().trim() ?? '';
      final rowCount = body['rows'];
      final columnCount = body['columns'];
      if (platform != 'airline' && platform != 'grocery') {
        throw const ApiFailure(400, 'Choose an airline or grocery workspace');
      }
      _requireTableAccess(state, account, platform!);
      if (name.isEmpty || name.length > 80) {
        throw const ApiFailure(400, 'Table name must be 1–80 characters');
      }
      if (rowCount is! int ||
          rowCount < 0 ||
          rowCount > 5000 ||
          columnCount is! int ||
          columnCount < 1 ||
          columnCount > 50) {
        throw const ApiFailure(400, 'Choose 0–5000 rows and 1–50 columns');
      }
      if (tables.any((table) =>
          table['platform'] == platform &&
          table['name'].toString().toLowerCase() == name.toLowerCase())) {
        throw const ApiFailure(409, 'A table with that name already exists');
      }
      final headers = body['headers'] is List ? body['headers'] as List : null;
      if (headers != null &&
          (headers.length != columnCount ||
              headers.any(
                  (value) => value is! String || value.trim().length > 80))) {
        throw const ApiFailure(400, 'Invalid column headers');
      }
      final table = <String, dynamic>{
        'id': _id('TABLE'),
        'name': name,
        'platform': platform,
        'revision': 1,
        'createdAt': _now(),
        'columns': List.generate(
            columnCount,
            (index) =>
                {'id': _id('COL'), 'label': headers?[index].trim() ?? ''}),
        'rows': List.generate(
            rowCount, (_) => {'id': _id('ROW'), 'cells': <String, String>{}})
      };
      table['defaultColumnIds'] = records(table['columns'])
          .map((column) => column['id'].toString())
          .toList();
      table['defaultRowIds'] =
          records(table['rows']).map((row) => row['id'].toString()).toList();
      table['archivedColumns'] = <Object>[];
      tables.add(table);
      state['customTables'] = tables;
      _audit(state, account, 'Created custom table', name,
          grocery: platform == 'grocery');
      await _save(space, state);
      return table;
    }
    if (path.startsWith('$root/') && path.endsWith('/search')) {
      if (method != 'GET') throw const ApiFailure(405, 'Method not allowed');
      final rawId =
          path.substring(root.length + 1, path.length - '/search'.length);
      final searchId = Uri.decodeComponent(rawId);
      if (searchId.isEmpty || searchId.contains('/')) {
        throw const ApiFailure(404, 'Table not found');
      }
      final match = tables.where((item) => item['id'] == searchId).firstOrNull;
      if (match == null) throw const ApiFailure(404, 'Table not found');
      _requireTableAccess(state, account, match['platform'].toString());
      final query =
          request.url.queryParameters['query']?.trim().toLowerCase() ?? '';
      if (query.length > 200) throw const ApiFailure(400, 'Search is too long');
      final activeIds = records(match['columns'])
          .map((column) => column['id'].toString())
          .toSet();
      return [
        for (final row in records(match['rows']))
          if (query.isEmpty ||
              asObject(row['cells']).entries.any((cell) =>
                  activeIds.contains(cell.key) &&
                  cell.value.toString().toLowerCase().contains(query)))
            row['id'].toString(),
      ];
    }
    final id = Uri.decodeComponent(path.substring(root.length + 1));
    if (id.isEmpty || id.contains('/'))
      throw const ApiFailure(404, 'Table not found');
    final index = tables.indexWhere((table) => table['id'] == id);
    if (index < 0) throw const ApiFailure(404, 'Table not found');
    final table = tables[index];
    _requireTableAccess(state, account, table['platform'].toString());
    Map<String, dynamic> personalizedTable() {
      final order =
          (asObject(table['columnOrderByUser'])[account['id'].toString()]
                      as List?)
                  ?.map((value) => value.toString())
                  .toList() ??
              (table['defaultColumnIds'] as List?)
                  ?.map((value) => value.toString())
                  .toList() ??
              <String>[];
      final positions = {
        for (var position = 0; position < order.length; position++)
          order[position]: position,
      };
      final columns = records(table['columns']);
      final original = [for (final column in columns) column['id'].toString()];
      columns.sort((left, right) {
        final leftId = left['id'].toString();
        final rightId = right['id'].toString();
        return (positions[leftId] ?? order.length + original.indexOf(leftId))
            .compareTo(
                positions[rightId] ?? order.length + original.indexOf(rightId));
      });
      return {...table, 'columns': columns};
    }

    if (method == 'GET') return personalizedTable();
    if (method == 'DELETE') {
      tables.removeAt(index);
      state['customTables'] = tables;
      _audit(state, account, 'Deleted custom table', table['name'].toString(),
          grocery: table['platform'] == 'grocery');
      await _save(space, state);
      return {'ok': true};
    }
    if (method != 'PATCH') throw const ApiFailure(405, 'Method not allowed');
    final body = await _body(request);
    if (body['revision'] != table['revision']) {
      throw const ApiFailure(
          409, 'This table changed elsewhere. Reload before saving.');
    }
    table['defaultColumnIds'] ??= records(table['columns'])
        .map((column) => column['id'].toString())
        .toList();
    table['defaultRowIds'] ??=
        records(table['rows']).map((row) => row['id'].toString()).toList();
    final name = body['name']?.toString().trim() ?? table['name'].toString();
    if (name.isEmpty ||
        name.length > 80 ||
        tables.any((other) =>
            other['id'] != id &&
            other['platform'] == table['platform'] &&
            other['name'].toString().toLowerCase() == name.toLowerCase())) {
      throw const ApiFailure(
          400, 'Choose a unique table name (1–80 characters)');
    }
    final columns = body.containsKey('columns')
        ? records(body['columns'])
        : records(table['columns']);
    if (columns.isEmpty || columns.length > 50) {
      throw const ApiFailure(400, 'A table needs 1–50 columns');
    }
    final columnIds = <String>{};
    for (final column in columns) {
      final columnId = column['id']?.toString() ?? '';
      final label = column['label']?.toString().trim() ?? '';
      final color = column['color']?.toString();
      if (columnId.isEmpty ||
          columnId.length > 80 ||
          label.length > 80 ||
          (color != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) ||
          !columnIds.add(columnId)) {
        throw const ApiFailure(400, 'Invalid or duplicate column');
      }
      column
        ..clear()
        ..addAll({
          'id': columnId,
          'label': label,
          if (color != null) 'color': color
        });
    }
    final archivedColumns = records(table['archivedColumns']);
    for (final previous in records(table['columns'])) {
      final previousId = previous['id']?.toString() ?? '';
      if (!columnIds.contains(previousId) &&
          !archivedColumns.any((item) => item['id'] == previousId)) {
        archivedColumns.add(previous);
      }
    }
    archivedColumns.removeWhere((item) => columnIds.contains(item['id']));
    final validCellIds = {
      ...columnIds,
      ...archivedColumns.map((item) => item['id'].toString()),
    };
    final rows = body.containsKey('rows')
        ? records(body['rows'])
        : records(table['rows']);
    final previousRows = {
      for (final item in records(table['rows'])) item['id']?.toString(): item
    };
    if (rows.length > 5000) throw const ApiFailure(400, 'Maximum 5000 rows');
    final rowIds = <String>{};
    for (final row in rows) {
      final rowId = row['id']?.toString() ?? '';
      if (rowId.isEmpty || rowId.length > 80 || !rowIds.add(rowId)) {
        throw const ApiFailure(400, 'Invalid or duplicate row');
      }
      final cells = asObject(row['cells']);
      final color = row['color']?.toString();
      final notifyAt = row['notifyAt']?.toString();
      if (cells.keys.any((key) => !validCellIds.contains(key)) ||
          cells.values
              .any((value) => value is! String || value.length > 10000) ||
          (color != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) ||
          (notifyAt != null &&
              (notifyAt.length > 40 ||
                  !notifyAt.endsWith('Z') ||
                  DateTime.tryParse(notifyAt) == null))) {
        throw const ApiFailure(400, 'Invalid cell value');
      }
      row
        ..clear()
        ..addAll({
          'id': rowId,
          'cells': cells,
          if (color != null) 'color': color,
          if (notifyAt != null) 'notifyAt': notifyAt,
          if (notifyAt != null &&
              previousRows[rowId]?['notifyAt'] == notifyAt &&
              previousRows[rowId]?['reminderDismissedAt'] != null)
            'reminderDismissedAt': previousRows[rowId]!['reminderDismissedAt']
        });
    }
    final userOrders = asObject(table['columnOrderByUser']);
    if (body['resetColumnOrder'] == true) {
      userOrders.remove(account['id'].toString());
    } else {
      userOrders[account['id'].toString()] = columnIds.toList();
    }
    table['columnOrderByUser'] = userOrders;
    final defaultIds = (table['defaultColumnIds'] as List)
        .map((value) => value.toString())
        .toList();
    final defaultPositions = {
      for (var position = 0; position < defaultIds.length; position++)
        defaultIds[position]: position,
    };
    final requestedOrder = [
      for (final column in columns) column['id'].toString()
    ];
    columns.sort((left, right) {
      final leftId = left['id'].toString();
      final rightId = right['id'].toString();
      return (defaultPositions[leftId] ??
              defaultIds.length + requestedOrder.indexOf(leftId))
          .compareTo(defaultPositions[rightId] ??
              defaultIds.length + requestedOrder.indexOf(rightId));
    });
    table['name'] = name;
    table['columns'] = columns;
    table['archivedColumns'] = archivedColumns;
    table['rows'] = rows;
    table['revision'] = (table['revision'] as int) + 1;
    table['updatedAt'] = _now();
    tables[index] = table;
    state['customTables'] = tables;
    _audit(state, account, 'Updated custom table', name,
        grocery: table['platform'] == 'grocery');
    await _save(space, state);
    return personalizedTable();
  }

  void _requireTableAccess(Map<String, dynamic> state,
      Map<String, dynamic> account, String platform) {
    if (platform == 'grocery' || account['role'] == 'Agency owner') return;
    final user = _currentUser(state, account);
    if (asObject(user['permissions'])['bookings'] != true) {
      throw const ApiFailure(403, 'You do not have access to this table');
    }
  }

  Future<void> _saveUserState(String space, Map<String, dynamic> state,
      Map<String, dynamic> user) async {
    await db.runTx((tx) async {
      await tx.execute(Sql.named('''UPDATE tenant_users SET display_name=@name,
        role=@role,active=@active WHERE workspace_id=@space::uuid AND legacy_user_id=@legacy'''),
          parameters: {
            'space': space,
            'legacy': user['id'],
            'name': user['name']?.toString() ?? '',
            'role': user['role']?.toString() ?? 'Staff',
            'active': user['active'] != false
          });
      await tx.execute(
          Sql.named('''UPDATE tenant_state SET document=@doc::jsonb,
        revision=revision+1,updated_at=now() WHERE workspace_id=@space::uuid'''),
          parameters: {'space': space, 'doc': jsonEncode(state)});
    });
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${randomSecret(3)}';
  double _num(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  double _paidAmount(Map<String, dynamic> row) => row['paidAmount'] != null
      ? _num(row['paidAmount'])
      : row['paymentStatus'] == 'Paid'
          ? _num(row['total'])
          : 0;
  Map<String, dynamic> _safeUser(Map<String, dynamic> row) => {...row}
    ..remove('passwordHash')
    ..remove('twoFactorSecret');

  void _audit(Map<String, dynamic> state, Map<String, dynamic> account,
      String action, String detail,
      {bool grocery = false}) {
    final target = grocery ? asObject(state['grocery']) : state;
    final audit = records(target['audit']);
    audit.insert(0, {
      'id': _id('AUD'),
      'createdAt': _now(),
      'action': action,
      'user': account['email'],
      'detail': detail
    });
    target['audit'] = audit;
    if (grocery) state['grocery'] = target;
  }

  Map<String, dynamic> _bootstrap(
      Map<String, dynamic> state, Map<String, dynamic> account) {
    final bookings = records(state['bookings']);
    return {
      'user': _currentUser(state, account),
      'settings': state['settings'],
      'wallet': state['wallet'],
      'notifications': state['notifications'],
      'stats': {
        'bookings': bookings.length,
        'customers': records(state['customers']).length,
        'cases': records(state['cases'])
            .where((r) => r['status'] != 'Resolved')
            .length,
        'passportServices': records(state['passportServices']).length,
        'quotes': records(state['quotes']).length
      }
    };
  }

  Map<String, dynamic> _groceryBootstrap(Map<String, dynamic> state) {
    final grocery = asObject(state['grocery']);
    return {
      'settings': grocery['settings'],
      'stats': {
        'products': records(grocery['products']).length,
        'sales': records(grocery['sales']).length,
        'purchases': records(grocery['purchases']).length,
        'suppliers': records(grocery['suppliers']).length,
        'customers': records(grocery['customers']).length,
        'expenses': records(grocery['expenses']).length,
      }
    };
  }

  Map<String, dynamic> _financeOverview(Map<String, dynamic> state) {
    final finance = asObject(state['finance']);
    final wallet = asObject(state['wallet']);
    final movements = records(state['walletTransactions']);
    final bookings = records(state['bookings']);
    final purchases = records(asObject(state['grocery'])['purchases']);
    return {
      'wallet': wallet,
      'walletRows': movements,
      'ledgerRows': state['ledger'],
      'pendingAdjustments': finance['pendingAdjustments'],
      'reconciliations': finance['reconciliations'],
      'lockedPeriods': finance['lockedPeriods'],
      'settings': finance['settings'],
      'openingBalance': movements.isEmpty
          ? _num(wallet['balance'])
          : _num(wallet['balance']) -
              movements.fold<double>(0, (v, r) => v + _num(r['amount'])),
      'closingBalance': wallet['balance'] ?? 0,
      'receivables':
          bookings.where((b) => _num(b['total']) > _paidAmount(b)).toList(),
      'payables': purchases.where((p) => _num(p['outstanding']) > 0).toList()
    };
  }

  Map<String, dynamic> _financeReports(Map<String, dynamic> state) {
    final sales = records(state['sales']);
    final grocery = asObject(state['grocery']);
    final grocerySales = records(grocery['sales']);
    final expenses = records(grocery['expenses']);
    final revenue = [...sales, ...grocerySales]
        .fold<double>(0, (v, r) => v + _num(r['total']));
    final cost = grocerySales.fold<double>(0, (v, r) => v + _num(r['cost'])) +
        expenses.fold<double>(0, (v, r) => v + _num(r['total']));
    return {
      'profitLoss': {
        'revenue': revenue,
        'expenses': cost,
        'netProfit': revenue - cost
      },
      'cashFlow': {'closingCash': asObject(state['wallet'])['balance'] ?? 0},
      'balanceSheet': {'cash': asObject(state['wallet'])['balance'] ?? 0},
      'daily': <Object>[],
      'monthly': <Object>[]
    };
  }

  Map<String, dynamic> _salesReport(Map<String, dynamic> state) {
    final sales = records(state['sales']);
    return {
      'totalSales': sales.fold<double>(0, (v, r) => v + _num(r['total'])),
      'sales': sales,
      'count': sales.length
    };
  }

  Map<String, dynamic> _newRecord(Map<String, dynamic> state, String path,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    final formModule = formModuleForPath(path);
    if (formModule.isNotEmpty) {
      final module = formModule;
      for (final key in recordFormConfig(state, module)['removed'] as List) {
        body.remove(key);
      }
    }
    if (path == '/api/passports') {
      for (final key
          in recordFormConfig(state, 'passport_collection')['removed']
              as List) {
        body.remove(key);
      }
    }
    _recordPaymentMethods(state, body);
    final draftId = body.remove('tableDraftId');
    if (draftId != null &&
        (path == '/api/bookings' || path == '/api/grocery/products')) {
      final key = path == '/api/bookings' ? 'bookings' : 'products';
      final allDrafts = asObject(state['tableDrafts']);
      final drafts = records(allDrafts[key]);
      final index = drafts.indexWhere((draft) => draft['id'] == draftId);
      if (index < 0)
        throw const ApiFailure(409, 'Table draft no longer exists');
      drafts.removeAt(index);
      allDrafts[key] = drafts;
      state['tableDrafts'] = allDrafts;
    }
    final prefixes = {
      '/api/bookings': 'BK',
      '/api/customers': 'CU',
      '/api/quotes': 'QT',
      '/api/passports': 'PS',
      '/api/cases': 'CS',
      '/api/roles': 'ROLE',
      '/api/grocery/products': 'PR',
      '/api/grocery/suppliers': 'SUP',
      '/api/grocery/customers': 'GC',
      '/api/company-assets': 'ASSET',
      '/api/grocery/company-assets': 'ASSET',
    };
    final record = {
      ...body,
      'id': _id(prefixes[path] ?? 'REC'),
      'createdAt': _now(),
      'createdBy': account['email']
    };
    if (path == '/api/bookings' || path == '/api/quotes') {
      if (body.containsKey('origin') && body.containsKey('destination')) {
        record['route'] =
            '${body['origin'] ?? ''} → ${body['destination'] ?? ''}';
      }
      if (path == '/api/bookings') {
        final removed = bookingFormConfig(state)['removed'] as List;
        if (!removed.contains('status')) record['status'] ??= 'On hold';
        if (!removed.contains('paymentStatus'))
          record['paymentStatus'] ??= 'Pending';
        record['paidAmount'] ??= 0;
        if (!removed.contains('total')) {
          record['outstanding'] =
              _num(body['total']) - _num(record['paidAmount']);
        }
      } else {
        record['total'] = _num(body['fare']) + _num(body['serviceFee']);
        final removed = recordFormConfig(state, 'quotes')['removed'] as List;
        if (!removed.contains('status')) record['status'] ??= 'Draft';
      }
    }
    if (path == '/api/grocery/products') {
      record['status'] ??= 'Active';
      if (_num(record['stock']) < 0)
        throw const ApiFailure(400, 'Stock cannot be negative');
    }
    final rows = collection(state, path);
    rows.insert(0, record);
    putCollection(state, path, rows);
    _audit(state, account, 'Created ${collectionKey(path)}',
        record['id'].toString(),
        grocery: path.startsWith('/api/grocery/'));
    return record;
  }

  Future<Map<String, dynamic>> _updateRecord(
      Map<String, dynamic> state,
      String path,
      String id,
      Map<String, dynamic> body,
      Map<String, dynamic> account) async {
    if (path == '/api/audit' || path == '/api/grocery/audit') {
      throw const ApiFailure(405, 'Audit entries cannot be changed');
    }
    final rows = collection(state, path);
    final index = rows.indexWhere((r) => r['id']?.toString() == id);
    if (index < 0) throw const ApiFailure(404, 'Record not found');
    final tableEdit = body.remove('tableEdit') == true;
    final formModule = formModuleForPath(path);
    if (formModule.isNotEmpty) {
      final module = formModule;
      for (final key in recordFormConfig(state, module)['removed'] as List) {
        body.remove(key);
      }
    }
    if (path == '/api/passports') {
      for (final key
          in recordFormConfig(state, 'passport_collection')['removed']
              as List) {
        body.remove(key);
      }
    }
    if (path == '/api/users') {
      body.remove('password');
      body.remove('passwordHash');
      body.remove('email');
      if (body['approvalLimits'] is Map) {
        final limits = asObject(body['approvalLimits']);
        final removed = recordFormConfig(state, 'users')['removed'] as List;
        for (final field in const {
          'paymentLimit': 'payment',
          'adjustmentLimit': 'adjustment',
          'refundLimit': 'refund',
        }.entries) {
          if (removed.contains(field.key)) limits.remove(field.value);
        }
        body['approvalLimits'] = limits;
      }
    }
    _recordPaymentMethods(state, body, previous: rows[index]);
    final updated = {
      ...rows[index],
      ...body,
      'id': id,
      'updatedAt': _now(),
      'updatedBy': account['email']
    };
    if (path == '/api/bookings' || path == '/api/quotes') {
      if (updated.containsKey('origin') && updated.containsKey('destination')) {
        updated['route'] =
            '${updated['origin'] ?? ''} → ${updated['destination'] ?? ''}';
      }
    }
    if (tableEdit && path == '/api/bookings') {
      final removed = bookingFormConfig(state)['removed'] as List;
      final total = _num(updated['total']);
      final paid = _paidAmount(rows[index]);
      if (!removed.contains('total') && total < paid - .009) {
        throw const ApiFailure(
            409, 'Total cannot be less than payments received');
      }
      updated['paidAmount'] = paid;
      if (!removed.contains('total')) updated['outstanding'] = total - paid;
      if (!removed.contains('paymentStatus')) {
        updated['paymentStatus'] = paid <= 0
            ? 'Pending'
            : total - paid < .01
                ? 'Paid'
                : 'Partially paid';
      }
    }
    if (tableEdit &&
        path == '/api/grocery/products' &&
        (_num(updated['stock']) < 0 ||
            _num(updated['cost']) < 0 ||
            _num(updated['price']) < 0)) {
      throw const ApiFailure(400, 'Stock, cost, and price cannot be negative');
    }
    rows[index] = updated;
    putCollection(state, path, rows);
    _audit(state, account, 'Updated ${collectionKey(path)}', id,
        grocery: path.startsWith('/api/grocery/'));
    return path == '/api/users' ? _safeUser(updated) : updated;
  }

  void _deleteTableRecord(Map<String, dynamic> state, String path, String id,
      Map<String, dynamic> account) {
    final rows = collection(state, path);
    final index = rows.indexWhere((r) => r['id']?.toString() == id);
    if (index < 0) throw const ApiFailure(404, 'Record not found');
    final row = rows[index];
    if (path == '/api/bookings') {
      final linked =
          records(state['refunds']).any((r) => r['bookingId'] == id) ||
              records(state['cases']).any((r) => r['bookingId'] == id);
      if (linked || _paidAmount(row) > 0 || row['status'] == 'Ticketed') {
        throw const ApiFailure(
            409, 'Paid, ticketed, or linked bookings cannot be deleted');
      }
    } else if (path == '/api/grocery/products') {
      final grocery = asObject(state['grocery']);
      final sold = records(grocery['sales']).any(
          (sale) => records(sale['items']).any((item) => item['id'] == id));
      final purchased = records(grocery['purchases']).any((purchase) =>
          records(purchase['items']).any((item) => item['productId'] == id));
      if (sold || purchased || _num(row['stock']) != 0) {
        throw const ApiFailure(
            409, 'Products with stock, sales, or purchases cannot be deleted');
      }
    }
    rows.removeAt(index);
    putCollection(state, path, rows);
    _audit(state, account, 'Deleted ${collectionKey(path)}', id,
        grocery: path.startsWith('/api/grocery/'));
  }

  Future<Object> _addUser(Map<String, dynamic> state,
      Map<String, dynamic> account, Map<String, dynamic> body) async {
    for (final key in recordFormConfig(state, 'users')['removed'] as List) {
      body.remove(key);
    }
    final email = body['email']?.toString().trim().toLowerCase() ?? '';
    final password = body['password']?.toString() ?? '';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        password.length < 12) {
      throw const ApiFailure(400,
          'Valid email and a temporary password of at least 12 characters are required');
    }
    final record = {
      ...body,
      'email': email,
      'id': _id('USR'),
      'active': body['active'] != false,
      'createdAt': _now()
    };
    record.remove('password');
    final users = records(state['users'])..insert(0, record);
    state['users'] = users;
    await db.runTx((tx) async {
      await tx.execute(Sql.named('''INSERT INTO tenant_users
        (workspace_id,email,display_name,role,password_hash,password_scheme,legacy_user_id,active)
        VALUES (@space::uuid,@email,@name,@role,@hash,'pbkdf2-sha256',@legacy,@active)'''),
          parameters: {
            'space': account['workspaceId'],
            'email': email,
            'name': record['name']?.toString() ?? email,
            'role': record['role']?.toString() ?? 'Sales agent',
            'hash': hashPassword(password),
            'legacy': record['id'],
            'active': record['active']
          });
      await tx.execute(
          Sql.named('''UPDATE tenant_state SET document=@doc::jsonb,
        revision=revision+1,updated_at=now() WHERE workspace_id=@space::uuid'''),
          parameters: {
            'doc': jsonEncode(state),
            'space': account['workspaceId']
          });
    });
    return record;
  }

  Future<Object> _userSessions(Map<String, dynamic> state, String id) async {
    final user =
        records(state['users']).where((r) => r['id'] == id).firstOrNull;
    if (user == null) throw const ApiFailure(404, 'User not found');
    final rows = await db.execute(
        Sql.named('''SELECT s.created_at::text,s.expires_at::text
      FROM tenant_sessions s JOIN tenant_users u ON u.id=s.user_id
      WHERE u.legacy_user_id=@legacy AND lower(u.email)=@email'''),
        parameters: {
          'legacy': id,
          'email': user['email']?.toString().toLowerCase()
        });
    return rows.map((r) => {'createdAt': r[0], 'expiresAt': r[1]}).toList();
  }

  Object _supplierStatement(Map<String, dynamic> state, String id) {
    final supplier = records(asObject(state['grocery'])['suppliers'])
        .where((r) => r['id'] == id)
        .firstOrNull;
    if (supplier == null) throw const ApiFailure(404, 'Supplier not found');
    final purchases = records(asObject(state['grocery'])['purchases'])
        .where((r) => r['supplierId'] == id)
        .toList();
    return {
      'supplier': supplier,
      'purchases': purchases,
      'outstanding':
          purchases.fold<double>(0, (v, r) => v + _num(r['outstanding']))
    };
  }

  List<Map<String, dynamic>> _payments(
      Map<String, dynamic> state, Map<String, dynamic> body, double max,
      {bool exact = false}) {
    try {
      return validatedPayments(state, body, max, exact: exact);
    } on FormatException catch (error) {
      throw ApiFailure(400, error.message);
    }
  }

  void _recordPaymentMethods(
      Map<String, dynamic> state, Map<String, dynamic> body,
      {Map<String, dynamic>? previous}) {
    for (final key in const ['paymentMethod', 'defaultPaymentMethod']) {
      if (!body.containsKey(key)) continue;
      final id = body[key]?.toString().trim() ?? '';
      final nameKey = '${key}Name';
      if (id.isEmpty) {
        body[nameKey] = '';
        continue;
      }
      final type = activePaymentType(state, id);
      if (type == null) {
        if (previous?[key] == id) {
          body[nameKey] = previous?[nameKey] ?? id;
          continue;
        }
        throw const ApiFailure(400, 'Payment method is unavailable');
      }
      body[nameKey] = type['name'];
    }
  }

  void _ensureOpenDate(Map<String, dynamic> state, Object? date) {
    final value = (date ?? _now()).toString();
    final day = value.length >= 10 ? value.substring(0, 10) : value;
    for (final period in records(asObject(state['finance'])['lockedPeriods'])) {
      if (period['status'] == 'Locked' &&
          day.compareTo('${period['from']}') >= 0 &&
          day.compareTo('${period['to']}') <= 0) {
        throw const ApiFailure(409, 'Accounting period is locked');
      }
    }
  }

  void _walletMovement(
      Map<String, dynamic> state,
      Map<String, dynamic> account,
      double amount,
      String type,
      Map<String, dynamic> payment,
      String reference,
      Object? date) {
    _ensureOpenDate(state, date);
    final wallet = asObject(state['wallet']);
    final before = _num(wallet['balance']);
    wallet['balance'] = before + amount;
    state['wallet'] = wallet;
    final rows = records(state['walletTransactions']);
    rows.insert(0, {
      'id': _id('WT'),
      'date': date ?? _now().substring(0, 10),
      'type': type,
      'amount': amount,
      'reference': reference,
      'paymentMethod': payment['method'],
      'paymentMethodName': payment['methodName'] ??
          paymentTypes(state)
              .where((item) => item['id'] == payment['method'])
              .firstOrNull?['name'] ??
          payment['method'],
      'bankName': payment['bankName'],
      'bankDetails': payment['bankDetails'],
      'profileId': payment['profileId'],
      'accountName': payment['accountName'],
      'accountNumber': payment['accountNumber'],
      'branch': payment['branch'],
      'walletNumber': payment['walletNumber'],
      'transactionId': payment['transactionId'],
      'openingBalance': before,
      'runningBalance': before + amount,
      'createdBy': account['email'],
      'createdAt': _now()
    });
    state['walletTransactions'] = rows;
  }

  Map<String, dynamic> _postJournal(Map<String, dynamic> state,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    final amount = _num(body['amount']);
    final debit = body['debitAccount']?.toString().trim() ?? '';
    final credit = body['creditAccount']?.toString().trim() ?? '';
    if (amount <= 0 || debit.isEmpty || credit.isEmpty || debit == credit) {
      throw const ApiFailure(400,
          'Journal needs equal positive debit and credit on different accounts');
    }
    _ensureOpenDate(state, body['date']);
    final record = {
      ...body,
      'id': _id('LE'),
      'status': 'Posted',
      'amount': amount,
      'debit': amount,
      'credit': amount,
      'createdBy': account['email'],
      'createdAt': _now()
    };
    final rows = records(state['ledger'])..insert(0, record);
    state['ledger'] = rows;
    _audit(state, account, 'Journal posted', record['id'].toString());
    return record;
  }

  Map<String, dynamic> _reverseJournal(Map<String, dynamic> state, String id,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    final rows = records(state['ledger']);
    final original = rows.where((r) => r['id'] == id).firstOrNull;
    if (original == null ||
        original['status'] != 'Posted' ||
        original['reversedByJournalId'] != null) {
      throw const ApiFailure(409, 'Journal cannot be reversed');
    }
    if ((body['reason'] ?? '').toString().trim().isEmpty) {
      throw const ApiFailure(400, 'Reversal reason is required');
    }
    final reversal = _postJournal(
        state,
        {
          ...original,
          'id': null,
          'debitAccount': original['creditAccount'],
          'creditAccount': original['debitAccount'],
          'date': body['date'] ?? _now().substring(0, 10),
          'type': 'Reversal',
          'reference': original['reference'],
          'reason': body['reason'],
          'reversesJournalId': id,
        },
        account);
    final updatedRows = records(state['ledger']);
    updatedRows.firstWhere((r) => r['id'] == id)['reversedByJournalId'] =
        reversal['id'];
    state['ledger'] = updatedRows;
    return reversal;
  }

  Map<String, dynamic> _directSale(Map<String, dynamic> state,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    for (final key in recordFormConfig(state, 'sales')['removed'] as List) {
      body.remove(key);
    }
    final total = _num(body['total']);
    if (total <= 0) throw const ApiFailure(400, 'Sale total must be positive');
    final payments = _payments(state, body, total, exact: true);
    final sale = {
      ...body,
      'id': _id('AS'),
      'createdBy': account['email'],
      'createdAt': _now(),
      'payments': payments,
      'paymentStatus': 'Paid'
    };
    state['sales'] = records(state['sales'])..insert(0, sale);
    for (final payment in payments) {
      _walletMovement(state, account, _num(payment['amount']), 'Direct sale',
          payment, sale['id'].toString(), body['date']);
    }
    _audit(state, account, 'Direct sale', sale['id'].toString());
    return sale;
  }

  Map<String, dynamic> _grocerySale(Map<String, dynamic> state,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    final grocery = asObject(state['grocery']);
    final products = records(grocery['products']);
    final items = records(body['items']);
    if (items.isEmpty) throw const ApiFailure(400, 'Cart is empty');
    var subtotal = 0.0;
    var cost = 0.0;
    final saleItems = <Map<String, dynamic>>[];
    for (final item in items) {
      final product = products.where((p) => p['id'] == item['id']).firstOrNull;
      final qty = _num(item['qty']);
      if (product == null || qty <= 0 || _num(product['stock']) < qty) {
        throw const ApiFailure(
            409, 'Product unavailable or insufficient stock');
      }
      final price = _num(product['price']);
      subtotal += price * qty;
      cost += _num(product['cost']) * qty;
      product['stock'] = _num(product['stock']) - qty;
      saleItems.add({
        'id': product['id'],
        'name': product['name'],
        'qty': qty,
        'price': price,
        'total': price * qty
      });
    }
    double fieldAmount(Object? value, String label) {
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (parsed == null || !parsed.isFinite) {
        throw ApiFailure(400, 'Invalid $label');
      }
      return parsed;
    }

    final settings = asObject(grocery['settings']);
    if (body.containsKey('roundToWhole') && body['roundToWhole'] is! bool) {
      throw const ApiFailure(400, 'Invalid round-off setting');
    }
    final roundToWhole = body['roundToWhole'] == true;
    late final GrocerySaleTotals pricing;
    try {
      pricing = calculateGrocerySaleTotals(
        subtotal: subtotal,
        discountType: body['discountType']?.toString() ?? 'amount',
        discountValue: body.containsKey('discountValue')
            ? fieldAmount(body['discountValue'], 'discount')
            : 0,
        taxRate: body.containsKey('taxRate')
            ? fieldAmount(body['taxRate'], 'tax rate')
            : fieldAmount(settings['taxRate'] ?? 5, 'default tax rate'),
        roundToWhole: roundToWhole,
      );
    } on FormatException catch (error) {
      throw ApiFailure(400, error.message);
    }
    if (pricing.total <= 0) {
      throw const ApiFailure(400, 'Sale total must be greater than zero');
    }
    final payments = _payments(state, body, pricing.total, exact: true);
    final sale = {
      'id': _id('GS'),
      'receipt': _id('FM'),
      'createdAt': _now(),
      'cashier': account['name'],
      'items': saleItems,
      'subtotal': pricing.subtotal,
      'discountType': pricing.discountType,
      'discountValue': pricing.discountValue,
      'discount': pricing.discount,
      'taxableSubtotal': pricing.taxableSubtotal,
      'taxRate': pricing.taxRate,
      'tax': pricing.tax,
      'roundToWhole': roundToWhole,
      'beforeRounding': pricing.beforeRounding,
      'roundingAdjustment': pricing.roundingAdjustment,
      'total': pricing.total,
      'cost': cost,
      'profit':
          ((pricing.taxableSubtotal - cost + pricing.roundingAdjustment) * 100)
                  .round() /
              100,
      'payments': payments,
      'payment': payments.map((p) => p['method']).join(' + ')
    };
    grocery['products'] = products;
    grocery['sales'] = records(grocery['sales'])..insert(0, sale);
    state['grocery'] = grocery;
    for (final payment in payments) {
      _walletMovement(state, account, _num(payment['amount']), 'Grocery sale',
          payment, sale['receipt'].toString(), _now().substring(0, 10));
    }
    _audit(state, account, 'Grocery sale', sale['receipt'].toString(),
        grocery: true);
    return sale;
  }

  Map<String, dynamic> _newPurchase(Map<String, dynamic> state,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    for (final key
        in recordFormConfig(state, 'grocery_purchases')['removed'] as List) {
      body.remove(key);
    }
    final grocery = asObject(state['grocery']);
    final supplier = records(grocery['suppliers'])
        .where((r) => r['id'] == body['supplierId'])
        .firstOrNull;
    if (supplier == null)
      throw const ApiFailure(400, 'Select an existing supplier');
    final products = records(grocery['products']);
    final items = <Map<String, dynamic>>[];
    var total = _num(body['shipping']) + _num(body['otherCosts']);
    for (final line in records(body['items'])) {
      final product =
          products.where((p) => p['id'] == line['productId']).firstOrNull;
      final qty = _num(line['quantity']);
      if (product == null || qty <= 0 || _num(line['unitCost']) < 0) {
        throw const ApiFailure(400, 'Invalid purchase line');
      }
      final lineTotal =
          (qty * _num(line['unitCost']) - _num(line['discount'])) *
              (1 + _num(line['taxRate']) / 100);
      if (lineTotal < 0)
        throw const ApiFailure(400, 'Invalid purchase discount');
      total += lineTotal;
      items.add({
        ...line,
        'id': _id('PLI'),
        'productName': product['name'],
        'orderedQty': qty,
        'receivedQty': 0,
        'rejectedQty': 0,
        'returnedQty': 0,
        'total': lineTotal
      });
    }
    if (items.isEmpty)
      throw const ApiFailure(400, 'Purchase needs a product line');
    final record = {
      ...body,
      'id': _id('PO'),
      'supplier': supplier['name'],
      'items': items,
      'total': total,
      'paidAmount': 0,
      'outstanding': total,
      'receivingStatus': 'Pending',
      'paymentStatus': 'Unpaid',
      'status': body['status'] == 'Draft' ? 'Draft' : 'Ordered',
      'createdAt': _now(),
      'createdBy': account['email']
    };
    grocery['purchases'] = records(grocery['purchases'])..insert(0, record);
    state['grocery'] = grocery;
    _audit(state, account, 'Purchase created', record['id'].toString(),
        grocery: true);
    return record;
  }

  Map<String, dynamic> _newExpense(Map<String, dynamic> state,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    for (final key
        in recordFormConfig(state, 'grocery_expenses')['removed'] as List) {
      body.remove(key);
    }
    final gross = _num(body['quantity'] ?? 1) * _num(body['unitRate']);
    final discounted = gross - _num(body['discount']);
    final total = discounted * (1 + _num(body['taxRate']) / 100);
    if (total < 0 || (body['description'] ?? '').toString().trim().isEmpty) {
      throw const ApiFailure(400, 'Invalid expense details');
    }
    final record = {
      ...body,
      'id': _id('EXP'),
      'total': total,
      'paidAmount': 0,
      'outstanding': total,
      'status': body['status'] ?? 'Approved',
      'createdAt': _now(),
      'createdBy': account['email']
    };
    final grocery = asObject(state['grocery']);
    grocery['expenses'] = records(grocery['expenses'])..insert(0, record);
    state['grocery'] = grocery;
    _audit(state, account, 'Expense recorded', record['id'].toString(),
        grocery: true);
    return record;
  }

  Map<String, dynamic> _newRefund(Map<String, dynamic> state,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    for (final key in recordFormConfig(state, 'refunds')['removed'] as List) {
      body.remove(key);
    }
    final booking = records(state['bookings'])
        .where((b) => b['id'] == body['bookingId'])
        .firstOrNull;
    final amount = _num(body['amount']);
    if (booking == null ||
        amount <= 0 ||
        amount > _paidAmount(booking) + .009) {
      throw const ApiFailure(400,
          'Refund must reference a paid booking and not exceed its payments');
    }
    final record = {
      ...body,
      'id': _id('RF'),
      'customerName': booking['customerName'],
      'status': 'Requested',
      'createdAt': _now(),
      'createdBy': account['email']
    };
    state['refunds'] = records(state['refunds'])..insert(0, record);
    _audit(state, account, 'Refund requested', record['id'].toString());
    return record;
  }

  Map<String, dynamic> _approveAdjustment(Map<String, dynamic> state, String id,
      Map<String, dynamic> body, Map<String, dynamic> account) {
    final finance = asObject(state['finance']);
    final rows = records(finance['pendingAdjustments']);
    final adjustment = rows.where((r) => r['id'] == id).firstOrNull;
    if (adjustment == null || adjustment['status'] != 'Pending') {
      throw const ApiFailure(409, 'Adjustment not pending');
    }
    if (adjustment['createdBy'] == account['email']) {
      throw const ApiFailure(403, 'Creator cannot approve own adjustment');
    }
    adjustment['status'] = body['approve'] == true ? 'Approved' : 'Rejected';
    adjustment['approvedBy'] = account['email'];
    adjustment['approvedAt'] = _now();
    if (body['approve'] == true) {
      final amount = _num(adjustment['amount']);
      if (amount == 0) throw const ApiFailure(400, 'Adjustment cannot be zero');
      _walletMovement(
          state,
          account,
          amount,
          'Adjustment',
          {
            'method': adjustment['paymentMethod'] ?? 'Cash',
            'methodName': adjustment['paymentMethodName'],
            'bankName': adjustment['bankName'],
            'bankDetails': adjustment['bankDetails'],
            'accountName': adjustment['accountName'],
            'accountNumber': adjustment['accountNumber'],
            'branch': adjustment['branch'],
            'walletNumber': adjustment['walletNumber'],
            'transactionId': adjustment['transactionId'],
            'profileId': adjustment['paymentProfileId'],
          },
          id,
          adjustment['date']);
    }
    finance['pendingAdjustments'] = rows;
    state['finance'] = finance;
    _audit(state, account, 'Adjustment ${adjustment['status']}', id);
    return adjustment;
  }

  Map<String, dynamic> _unlockPeriod(Map<String, dynamic> state, String id) {
    final finance = asObject(state['finance']);
    final rows = records(finance['lockedPeriods']);
    final period = rows.where((r) => r['id'] == id).firstOrNull;
    if (period == null) throw const ApiFailure(404, 'Period not found');
    period['status'] = 'Unlocked';
    finance['lockedPeriods'] = rows;
    state['finance'] = finance;
    return period;
  }

  Future<Object> businessAction(
      Map<String, dynamic> state,
      Map<String, dynamic> account,
      String path,
      String id,
      String action,
      Map<String, dynamic> body) async {
    final rows = collection(state, path);
    final record = rows.where((r) => r['id']?.toString() == id).firstOrNull;
    if (record == null) throw const ApiFailure(404, 'Record not found');
    if (path == '/api/bookings' && action == 'pay') {
      final due = _num(record['total']) - _paidAmount(record);
      final payments = _payments(state, body, due);
      final paid = payments.fold<double>(0, (v, p) => v + _num(p['amount']));
      record['paidAmount'] = _paidAmount(record) + paid;
      record['outstanding'] =
          _num(record['total']) - _num(record['paidAmount']);
      record['paymentStatus'] =
          _num(record['outstanding']) < .01 ? 'Paid' : 'Partially paid';
      record['payments'] = [...records(record['payments']), ...payments];
      for (final payment in payments) {
        _walletMovement(state, account, _num(payment['amount']),
            'Booking payment', payment, id, body['date']);
      }
    } else if (path == '/api/bookings' && action == 'ticket') {
      if (record['status'] == 'Cancelled')
        throw const ApiFailure(409, 'Cancelled booking cannot be ticketed');
      record['status'] = 'Ticketed';
    } else if (path == '/api/grocery/purchases' && action == 'approve') {
      _requireOwner(account);
      record['status'] = body['approve'] == true ? 'Ordered' : 'Rejected';
    } else if (path == '/api/grocery/purchases' && action == 'receive') {
      if (!{'Ordered', 'Partially received'}.contains(record['status'])) {
        throw const ApiFailure(409, 'Purchase is not ready to receive');
      }
      final grocery = asObject(state['grocery']);
      final products = records(grocery['products']);
      final lines = records(record['items']);
      for (final incoming in records(body['items'])) {
        final line =
            lines.where((l) => l['id'] == incoming['itemId']).firstOrNull;
        if (line == null)
          throw const ApiFailure(400, 'Purchase line not found');
        final qty = _num(incoming['quantity']);
        final rejected = _num(incoming['rejected']);
        if (qty < 0 ||
            rejected < 0 ||
            _num(line['receivedQty']) +
                    _num(line['rejectedQty']) +
                    qty +
                    rejected >
                _num(line['orderedQty']) + .009) {
          throw const ApiFailure(
              400, 'Received quantity exceeds ordered quantity');
        }
        final product =
            products.where((p) => p['id'] == line['productId']).firstOrNull;
        if (product == null)
          throw const ApiFailure(409, 'Product no longer exists');
        product['stock'] = _num(product['stock']) + qty;
        line['receivedQty'] = _num(line['receivedQty']) + qty;
        line['rejectedQty'] = _num(line['rejectedQty']) + rejected;
        line['batchNumber'] = incoming['batchNumber'] ?? line['batchNumber'];
        line['expiry'] = incoming['expiry'] ?? line['expiry'];
      }
      final complete = lines.every((l) =>
          _num(l['receivedQty']) + _num(l['rejectedQty']) >=
          _num(l['orderedQty']) - .009);
      record['receivingStatus'] = complete ? 'Received' : 'Partially received';
      record['status'] = complete ? 'Received' : 'Partially received';
      record['items'] = lines;
      grocery['products'] = products;
      state['grocery'] = grocery;
    } else if (path == '/api/grocery/purchases' && action == 'pay') {
      final due = _num(record['outstanding']);
      final payments = _payments(state, body, due);
      final paid = payments.fold<double>(0, (v, p) => v + _num(p['amount']));
      record['paidAmount'] = _num(record['paidAmount']) + paid;
      record['outstanding'] = due - paid;
      record['paymentStatus'] =
          _num(record['outstanding']) < .01 ? 'Paid' : 'Partially paid';
      record['payments'] = [...records(record['payments']), ...payments];
      for (final payment in payments) {
        _walletMovement(state, account, -_num(payment['amount']),
            'Supplier payment', payment, id, body['date']);
      }
    } else if (path == '/api/grocery/purchases' && action == 'return') {
      final lines = records(record['items']);
      final line = lines.where((l) => l['id'] == body['itemId']).firstOrNull;
      final qty = _num(body['quantity']);
      if (line == null ||
          qty <= 0 ||
          qty > _num(line['receivedQty']) - _num(line['returnedQty'])) {
        throw const ApiFailure(400, 'Invalid return quantity');
      }
      final grocery = asObject(state['grocery']);
      final products = records(grocery['products']);
      final product =
          products.where((p) => p['id'] == line['productId']).firstOrNull;
      if (product == null || _num(product['stock']) < qty) {
        throw const ApiFailure(409, 'Insufficient stock to return');
      }
      product['stock'] = _num(product['stock']) - qty;
      line['returnedQty'] = _num(line['returnedQty']) + qty;
      record['returns'] = [
        ...records(record['returns']),
        {'id': _id('RET'), ...body, 'createdAt': _now()}
      ];
      record['items'] = lines;
      grocery['products'] = products;
      state['grocery'] = grocery;
    } else if (path == '/api/grocery/expenses' && action == 'approve') {
      _requireOwner(account);
      record['status'] = body['approve'] == true ? 'Approved' : 'Rejected';
    } else if (path == '/api/grocery/expenses' && action == 'pay') {
      if (record['status'] != 'Approved' &&
          record['status'] != 'Partially paid') {
        throw const ApiFailure(409, 'Expense must be approved first');
      }
      final due = _num(record['outstanding']);
      final payments = _payments(state, body, due);
      final paid = payments.fold<double>(0, (v, p) => v + _num(p['amount']));
      record['paidAmount'] = _num(record['paidAmount']) + paid;
      record['outstanding'] = due - paid;
      record['status'] =
          _num(record['outstanding']) < .01 ? 'Paid' : 'Partially paid';
      record['payments'] = [...records(record['payments']), ...payments];
      for (final payment in payments) {
        _walletMovement(state, account, -_num(payment['amount']),
            'Expense payment', payment, id, body['date']);
      }
    } else if (path == '/api/grocery/expenses' && action == 'reverse') {
      if (_num(record['paidAmount']) > 0) {
        throw const ApiFailure(
            409, 'Paid expense needs a separate refund entry before reversal');
      }
      if ((body['reason'] ?? '').toString().trim().isEmpty) {
        throw const ApiFailure(400, 'Reversal reason is required');
      }
      record['reversed'] = true;
      record['status'] = 'Reversed';
      record['reversalReason'] = body['reason'];
    } else if (path == '/api/grocery/suppliers' && action == 'archive') {
      record['archived'] = true;
      record['status'] = 'Inactive';
    } else if (path == '/api/users' && action == 'reset-password') {
      _requireOwner(account);
      final password = body['password']?.toString() ?? '';
      if (password.length < 12 || password != body['confirmPassword']) {
        throw const ApiFailure(400,
            'Password must match confirmation and be at least 12 characters');
      }
      await db.execute(Sql.named('''UPDATE tenant_users SET password_hash=@hash,
        password_scheme='pbkdf2-sha256' WHERE workspace_id=@space::uuid AND legacy_user_id=@legacy'''),
          parameters: {
            'hash': hashPassword(password),
            'space': account['workspaceId'],
            'legacy': id
          });
      record['mustChangePassword'] = true;
    } else if (path == '/api/users' && action == 'signout') {
      _requireOwner(account);
      await db.execute(Sql.named('''DELETE FROM tenant_sessions WHERE user_id IN
        (SELECT id FROM tenant_users WHERE workspace_id=@space::uuid AND legacy_user_id=@legacy)'''),
          parameters: {'space': account['workspaceId'], 'legacy': id});
    } else if (path == '/api/users' && action == 'archive') {
      _requireOwner(account);
      if (record['email'] == account['email']) {
        throw const ApiFailure(409, 'Cannot archive your own account');
      }
      record['archived'] = true;
      record['active'] = false;
      await db.execute(Sql.named('''UPDATE tenant_users SET active=false WHERE
        workspace_id=@space::uuid AND legacy_user_id=@legacy'''),
          parameters: {'space': account['workspaceId'], 'legacy': id});
    } else {
      throw const ApiFailure(404, 'Action not found');
    }
    record['updatedAt'] = _now();
    putCollection(state, path, rows);
    _audit(state, account, '$action ${collectionKey(path)}', id,
        grocery: path.startsWith('/api/grocery/'));
    return record;
  }

  Future<Object> _action(
          Map<String, dynamic> state,
          Map<String, dynamic> account,
          String path,
          String id,
          String action,
          Map<String, dynamic> body) async =>
      businessAction(state, account, path, id, action, body);
}
