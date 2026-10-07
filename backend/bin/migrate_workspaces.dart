import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:aerodesk_backend/database.dart';
import 'package:aerodesk_backend/security.dart';
import 'package:aerodesk_backend/state.dart';

Future<void> main(List<String> args) async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('DATABASE_URL is required. Load the local .env.local first.');
    exitCode = 2;
    return;
  }
  final newEmail = (args.isEmpty ? '' : args.first).trim().toLowerCase();
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(newEmail)) {
    stderr.writeln('Usage: dart run bin/migrate_workspaces.dart new@example.com');
    exitCode = 2;
    return;
  }
  final db = await openDatabase(url);
  var locked = false;
  try {
    final lock = await db.execute('SELECT pg_try_advisory_lock(4782001)');
    locked = lock.first[0] == true;
    if (!locked) throw StateError('Stop the old server before migration.');
    final schema = await File('schema_v2.sql').readAsString();
    for (final statement in schema.split(';')) {
      if (statement.trim().isNotEmpty) await db.execute(statement);
    }
    final existing = await db.execute('SELECT count(*) FROM tenant_workspaces');
    if ((existing.first[0] as int) != 0) {
      throw StateError('Workspace tables already contain data. Migration is deliberately one-time and will not overwrite records.');
    }
    final oldPassword = randomSecret(24);
    final oldHash = hashPassword(oldPassword);
    Map<String, dynamic>? oldDocument;
    await db.runTx((tx) async {
      final source = await tx.execute('SELECT document::text FROM app_state WHERE id=1 FOR UPDATE');
      if (source.isEmpty) throw StateError('No existing SQL data found in app_state.');
      oldDocument = asObject(source.first[0]);
      final sourceUsers = records(oldDocument!['users']);
      if (!sourceUsers.any((user) => user['email']?.toString().toLowerCase() == 'owner@aerodesk.local')) {
        throw StateError('The old owner email is not present in SQL; refusing to guess record ownership.');
      }
      if (sourceUsers.any((user) => user['email']?.toString().toLowerCase() == newEmail)) {
        throw StateError('The new email is already present in the old workspace.');
      }
      final oldSpace = await tx.execute(
        "INSERT INTO tenant_workspaces (name) VALUES ('AeroDesk existing records') RETURNING id::text",
      );
      final oldId = oldSpace.first[0] as String;
      await tx.execute(
        Sql.named('INSERT INTO tenant_state (workspace_id,document) VALUES (@id::uuid,@document::jsonb)'),
        parameters: {'id': oldId, 'document': jsonEncode(oldDocument)},
      );
      for (final user in sourceUsers) {
        final email = user['email']?.toString().trim().toLowerCase() ?? '';
        final hash = user['passwordHash']?.toString() ?? '';
        if (email.isEmpty || hash.isEmpty) continue;
        await tx.execute(
          Sql.named('''INSERT INTO tenant_users
              (workspace_id,email,display_name,role,password_hash,password_scheme,legacy_user_id,active)
              VALUES (@space::uuid,@email,@name,@role,@hash,'sha256',@legacy,@active)'''),
          parameters: {
            'space': oldId,
            'email': email,
            'name': user['name']?.toString() ?? email,
            'role': user['role']?.toString() ?? 'Staff',
            'hash': hash,
            'legacy': user['id']?.toString(),
            'active': user['active'] != false,
          },
        );
      }
      final newSpace = await tx.execute(
        "INSERT INTO tenant_workspaces (name) VALUES ('New empty workspace') RETURNING id::text",
      );
      final newId = newSpace.first[0] as String;
      final empty = emptyWorkspace(newEmail);
      await tx.execute(
        Sql.named('INSERT INTO tenant_state (workspace_id,document) VALUES (@id::uuid,@document::jsonb)'),
        parameters: {'id': newId, 'document': jsonEncode(empty)},
      );
      await tx.execute(
        Sql.named('''INSERT INTO tenant_users
            (workspace_id,email,display_name,role,password_hash,password_scheme,legacy_user_id)
            VALUES (@space::uuid,@email,@name,'Agency owner',@hash,'pbkdf2-sha256','USR-001')'''),
        parameters: {
          'space': newId,
          'email': newEmail,
          'name': newEmail.split('@').first,
          'hash': oldHash,
        },
      );
    });
    final credentialFile = File('.local-login.txt');
    await credentialFile.writeAsString(
      'New empty workspace login\nEmail: $newEmail\nTemporary password: $oldPassword\nChange this password after signing in.\n',
      flush: true,
    );
    stdout.writeln('Migrated existing records to owner@aerodesk.local.');
    stdout.writeln('Created empty workspace for $newEmail.');
    stdout.writeln('Temporary login saved only in backend/.local-login.txt (gitignored).');
    final counts = await db.execute('SELECT workspace, owner_email, bookings, customers, products, grocery_sales FROM tenant_record_counts ORDER BY workspace');
    for (final row in counts) {
      stdout.writeln('${row[0]}: ${row[1]} | bookings ${row[2]}, customers ${row[3]}, products ${row[4]}, grocery sales ${row[5]}');
    }
  } finally {
    if (locked) await db.execute('SELECT pg_advisory_unlock(4782001)');
    await db.close();
  }
}
