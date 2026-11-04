import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/main.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/screens.dart';
import 'package:aerodesk_client/travel_ui.dart';
import 'package:aerodesk_client/table_screen.dart';
import 'package:aerodesk_client/table_model.dart';
import 'package:aerodesk_client/financial_register.dart';

class _FakeApi extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/bootstrap') {
      return {
        'stats': {
          'bookings': 1,
          'customers': 1,
          'passportServices': 0,
          'cases': 0,
        },
        'wallet': {'balance': 0, 'creditLimit': 0, 'usedCredit': 0},
        'notifications': <Object>[],
      };
    }
    return [
      {
        'id': 'BK-TEST',
        'pnr': 'ABC123',
        'customerName': 'Test Passenger',
        'route': 'KTM → DXB',
        'travelDate': '2026-10-01',
        'status': 'On hold',
        'paymentStatus': 'Pending',
        'total': 100,
      },
    ];
  }
}

class _BookingEditApi extends _FakeApi {
  String? editedPath;
  Map<String, dynamic>? editedBody;
  String customerName = 'Test Passenger';

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/bookings' || path.startsWith('/api/bookings?search=')) {
      return [
        {
          'id': 'BK-TEST',
          'pnr': 'ABC123',
          'customerName': customerName,
          'origin': 'KTM',
          'destination': 'DXB',
          'travelDate': '2026-10-01',
          'status': 'On hold',
          'paymentStatus': 'Pending',
          'total': 100,
        },
      ];
    }
    return super.get(path);
  }

  @override
  Future<dynamic> patch(String path, Object body) async {
    editedPath = path;
    editedBody = Map<String, dynamic>.from(body as Map);
    customerName = editedBody!['customerName'].toString();
    return {'id': 'BK-TEST', ...editedBody!};
  }
}

class _PagedBookingApi extends _FakeApi {
  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/bookings' || path.startsWith('/api/bookings?search=')) {
      return [
        for (var number = 1; number <= 12; number++)
          {
            'id': 'BK-$number',
            'customerName': 'Passenger $number',
            'origin': 'KTM',
            'destination': 'DEL',
            'travelDate': '2026-10-22',
            'status': 'Confirmed',
          },
      ];
    }
    return super.get(path);
  }
}

class _GroceryProductEditApi extends ApiClient {
  String name = 'Rice';
  String? editedPath;
  Map<String, dynamic>? editedBody;

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/grocery/products' ||
        path.startsWith('/api/grocery/products?search=')) {
      return [
        {
          'id': 'PR-1',
          'name': name,
          'sku': 'RICE-1',
          'barcode': '10001',
          'price': 100,
          'cost': 80,
          'stock': 5,
          'status': 'Active',
        },
      ];
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<dynamic> patch(String path, Object body) async {
    editedPath = path;
    editedBody = Map<String, dynamic>.from(body as Map);
    name = editedBody!['name'].toString();
    return {'id': 'PR-1', 'name': name};
  }
}

class _GroceryReportsApi extends ApiClient {
  _GroceryReportsApi({
    this.sales = const [],
    this.products = const [],
    this.expenses = const [],
  });

  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> expenses;

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/grocery/bootstrap') {
      return {
        'stats': {
          'products': 9,
          'sales': 4,
          'purchases': 1,
          'suppliers': 2,
          'customers': 1,
          'expenses': 1,
        },
      };
    }
    if (path == '/api/grocery/sales') return sales;
    if (path == '/api/grocery/products') return products;
    if (path == '/api/grocery/expenses') return expenses;
    throw StateError('Unexpected GET $path');
  }
}

class _AirlineReportsApi extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/reports/sales') {
      return {
        'totalSales': 120,
        'count': 1,
        'sales': [
          {
            'id': 'AS-1',
            'date': '2026-11-03',
            'customerName': 'Alex',
            'description': 'Service fee',
            'total': 120,
            'payments': [
              {'method': 'Cash', 'amount': 120},
            ],
            'createdBy': 'agent@example.com',
          },
        ],
      };
    }
    throw StateError('Unexpected GET $path');
  }
}

class _EmptyAirlineSalesApi extends ApiClient {
  int writes = 0;

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/sales' || path.startsWith('/api/sales?search=')) {
      return <Object>[];
    }
    if (path == '/api/reports/sales') {
      return {'totalSales': 0, 'count': 0, 'sales': <Object>[]};
    }
    if (path == '/api/form-fields/sales') {
      return {
        'removed': <Object>[],
        'custom': <Object>[],
        'labels': <String, String>{},
        'order': <Object>[],
      };
    }
    if (path == '/api/table-layouts/airline/sales') {
      return {'columns': <Object>[], 'rows': <Object>[]};
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<dynamic> post(String path, Object body) async {
    writes++;
    throw StateError('Preview must not write to $path');
  }
}

class _RecordedAirlineSalesApi extends _EmptyAirlineSalesApi {
  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/sales' || path.startsWith('/api/sales?search=')) {
      return [
        {
          'id': 'AS-2',
          'date': '2026-11-03',
          'customerName': 'Alex',
          'description': 'Service fee',
          'total': 0.52,
          'payments': [
            {'method': 'eSewa', 'amount': 0.52},
          ],
        },
      ];
    }
    return super.get(path);
  }
}

class _RolePermissionsApi extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/roles') {
      return [
        {
          'id': 'ROLE-1',
          'name': 'Agency owner',
          'system': true,
          'permissions': {
            'audit': true,
            'cases': true,
            'sales': true,
            'users': true,
            'quotes': true,
            'finance': true,
            'refunds': true,
            'bookings': true,
            'customers': true,
            'dashboard': true,
            'reports': true,
            'settings': true,
          },
        },
        {
          'id': 'ROLE-2',
          'name': 'A long role name that wraps naturally onto another line',
          'system': true,
          'permissions': {'bookings': true},
        },
      ];
    }
    if (path == '/api/table-layouts/airline/roles') {
      return {'columns': <String>[], 'rows': <String>[]};
    }
    throw StateError('Unexpected GET $path');
  }
}

class _TableApi extends ApiClient {
  _TableApi({this.initialized = true, this.recordCount = 1});

  bool initialized;
  final int recordCount;
  Map<String, dynamic>? lastPatch;
  Map<String, dynamic>? setupBody;
  List<String> layoutColumns = [];
  List<String> layoutRows = [];
  int layoutRevision = 0;

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/bookings/table-columns') return <Object>[];
    if (path == '/api/bookings/table-setup') {
      return {'initialized': initialized};
    }
    if (path == '/api/bookings/table-drafts') return <Object>[];
    if (path == '/api/bookings/form-fields') {
      return {
        'removed': <String>[],
        'custom': <Object>[],
        'labels': <String, String>{},
        'order': <String>[],
      };
    }
    if (path == '/api/bookings/table-layout') {
      return {
        'columns': layoutColumns,
        'rows': layoutRows,
        'revision': layoutRevision,
      };
    }
    if (path == '/api/bookings' || path.startsWith('/api/bookings?search=')) {
      return [
        for (var index = 0; index < recordCount; index++)
          {
            'id': 'BK-${index + 1}',
            'reference': 'BK-${index + 1}',
            'customerName':
                index == 0 ? 'Test Passenger' : 'Passenger ${index + 1}',
            'origin': 'KTM',
            'destination': 'DXB',
            'total': 100,
            'status': 'On hold',
            'paymentStatus': 'Pending',
          },
      ];
    }
    throw StateError('Unexpected request: $path');
  }

  @override
  Future<dynamic> post(String path, Object body) async {
    if (path == '/api/bookings/table-setup') {
      setupBody = Map<String, dynamic>.from(body as Map);
      initialized = true;
      return {'initialized': true};
    }
    throw StateError('Unexpected POST: $path');
  }

  @override
  Future<dynamic> patch(String path, Object body) async {
    lastPatch = Map<String, dynamic>.from(body as Map);
    if (path == '/api/bookings/table-layout') {
      if (lastPatch!.containsKey('columns')) {
        layoutColumns = (lastPatch!['columns'] as List).cast<String>();
      }
      if (lastPatch!.containsKey('rows')) {
        layoutRows = (lastPatch!['rows'] as List).cast<String>();
      }
      layoutRevision++;
      return {
        'columns': layoutColumns,
        'rows': layoutRows,
        'revision': layoutRevision,
      };
    }
    return {
      'id': 'BK-1',
      'reference': 'BK-1',
      'customerName': lastPatch!['customerName'],
      'origin': 'KTM',
      'destination': 'DXB',
      'total': 100,
      'status': 'On hold',
      'paymentStatus': 'Pending',
    };
  }
}

class _ModuleTableApi extends ApiClient {
  final rows = <Map<String, dynamic>>[
    {
      'id': 'A-1',
      'assetName': 'Laptop',
      'employeeName': 'Nischal',
      'quantity': 1,
    },
    {'id': 'A-2', 'assetName': 'Phone', 'employeeName': 'Rita', 'quantity': 1},
  ];
  List<String> columns = [];
  List<String> order = [];
  int revision = 0;
  String? editedPath;
  Map<String, dynamic>? editedBody;

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/company-assets') return rows;
    if (path == '/api/form-fields/company_assets') {
      return {
        'removed': <String>[],
        'custom': <Object>[],
        'labels': {'assetName': 'Assigned equipment'},
        'order': ['assetName', 'employeeName'],
      };
    }
    if (path == '/api/table-layouts/airline/company-assets') {
      return {'columns': columns, 'rows': order, 'revision': revision};
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<dynamic> patch(String path, Object body) async {
    final data = Map<String, dynamic>.from(body as Map);
    if (path == '/api/table-layouts/airline/company-assets') {
      if (data['columns'] is List) {
        columns = (data['columns'] as List).cast<String>();
      }
      if (data['rows'] is List) order = (data['rows'] as List).cast<String>();
      revision++;
      return {'columns': columns, 'rows': order, 'revision': revision};
    }
    editedPath = path;
    editedBody = data;
    rows.firstWhere((row) => row['id'] == 'A-1').addAll(data);
    return rows.first;
  }
}

Future<void> _doubleTapCell(WidgetTester tester, Finder cell) async {
  await tester.tap(cell);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(cell);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('shows the sign in form on a phone sized screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AeroDeskApp());
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Server connection'), findsNothing);
    expect(find.text('Server URL'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('booking list and manual entry work on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Test Passenger'), findsWidgets);
    await tester.tap(find.text('Add Record'));
    await tester.pumpAndSettle();
    expect(find.text('Passenger full name'), findsWidgets);
    expect(find.text('From airport'), findsWidgets);
    expect(find.text('To airport'), findsWidgets);
  });

  testWidgets('booking records use a scrollable table on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-table')), findsOneWidget);
    expect(find.text('Test Passenger'), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more), findsNothing);
  });

  testWidgets('wrapped role values fit inside their rows and columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final roles = airlineModules.firstWhere((module) => module.key == 'roles');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _RolePermissionsApi(),
            module: roles,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstRow = tester.getRect(
      find.byKey(const ValueKey('record-data-row-0')),
    );
    final secondRow = tester.getRect(
      find.byKey(const ValueKey('record-data-row-1')),
    );
    final permissions = find.byKey(
      const ValueKey('module-cell-ROLE-1-permissions'),
    );
    expect(tester.getSize(permissions).width, greaterThan(300));
    expect(firstRow.height, greaterThan(52));
    expect(secondRow.height, greaterThan(52));
    expect(firstRow.bottom, closeTo(secondRow.top, 1));
    expect(
      tester.getRect(find.textContaining('audit: true')).bottom,
      lessThanOrEqualTo(firstRow.bottom + 1),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('record-action-0'))).dy,
      closeTo(firstRow.center.dy, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking details stay pinned while columns scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('record-action-0'));
    final horizontal = find.byKey(
      const ValueKey('record-table-horizontal-scroll'),
    );
    await tester.ensureVisible(horizontal);
    await tester.pumpAndSettle();
    final initialX = tester.getCenter(action).dx;
    await tester.drag(horizontal, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(action).dx, closeTo(initialX, 1));
    expect(
      tester.widget<SingleChildScrollView>(horizontal).controller!.offset,
      greaterThan(0),
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned row actions follow vertical table scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _PagedBookingApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
        .onChanged!(25);
    await tester.pumpAndSettle();
    final dataScroll =
        tester
            .widget<ListView>(find.byKey(const ValueKey('record-table')))
            .controller!;
    final actionsScroll =
        tester
            .widget<ListView>(find.byKey(const ValueKey('record-actions')))
            .controller!;
    expect(dataScroll.position.maxScrollExtent, greaterThan(80));
    dataScroll.jumpTo(80);
    await tester.pumpAndSettle();
    expect(actionsScroll.offset, closeTo(80, 1));
    actionsScroll.jumpTo(40);
    await tester.pumpAndSettle();
    expect(dataScroll.offset, closeTo(40, 1));
    expect(
      tester.getCenter(find.byKey(const ValueKey('record-data-row-5'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('record-action-5'))).dy,
        1,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('record search, status, manage and add share one toolbar row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester', 'role': 'Agency owner'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final centers = [
      tester.getCenter(find.byType(TextField).first).dy,
      tester.getCenter(find.byType(DropdownButtonFormField<String>).first).dy,
      tester.getCenter(find.text('Manage form fields')).dy,
      tester.getCenter(find.text('Add Record')).dy,
    ];
    expect(
      centers.reduce((a, b) => a > b ? a : b) -
          centers.reduce((a, b) => a < b ? a : b),
      lessThan(12),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('FreshMart record controls share a desktop row', (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final products = groceryModules.firstWhere(
      (module) => module.key == 'products',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _GroceryProductEditApi(),
            module: products,
            grocery: true,
            user: const {'name': 'Tester', 'role': 'Agency owner'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final centers = [
      tester.getCenter(find.byType(TextField).first).dy,
      tester.getCenter(find.byType(DropdownButtonFormField<String>).first).dy,
      tester.getCenter(find.text('Manage form fields')).dy,
      tester.getCenter(find.text('Add Record')).dy,
    ];
    expect(
      centers.reduce((a, b) => a > b ? a : b) -
          centers.reduce((a, b) => a < b ? a : b),
      lessThan(12),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('record controls wrap without overflow on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester', 'role': 'Agency owner'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Manage form fields'), findsOneWidget);
    expect(find.text('Add Record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking records paginate in the reference table layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _PagedBookingApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 to 10 of 12 entries'), findsOneWidget);
    expect(find.text('Passenger 11'), findsNothing);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 11 to 12 of 12 entries'), findsOneWidget);
    expect(find.text('Passenger 11'), findsOneWidget);
  });

  testWidgets('booking cell uses newline and explicit save or cancel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _BookingEditApi();
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: api,
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Passenger'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-cell-editor')), findsNothing);
    await _doubleTapCell(tester, find.text('Test Passenger'));
    final editor = find.byKey(const ValueKey('module-cell-editor'));
    expect(
      tester.widget<TextField>(editor).textInputAction,
      TextInputAction.newline,
    );
    await tester.enterText(editor, 'First line');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(api.editedBody, isNull);
    await tester.enterText(editor, 'First line\nSecond line');
    await tester.pump();
    expect(find.byTooltip('Save cell'), findsOneWidget);
    expect(find.byTooltip('Cancel edit'), findsOneWidget);
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();
    expect(api.editedPath, '/api/bookings/BK-TEST');
    expect(api.editedBody?['customerName'], 'First line\nSecond line');
    final cell = find.byKey(const ValueKey('module-cell-BK-TEST-customerName'));
    expect(
      tester
          .widget<Text>(find.descendant(of: cell, matching: find.byType(Text)))
          .data,
      'First line\nSecond line',
    );

    await _doubleTapCell(tester, cell);
    await tester.enterText(editor, 'Discard me');
    await tester.tap(find.byTooltip('Cancel edit'));
    await tester.pumpAndSettle();
    expect(api.editedBody?['customerName'], 'First line\nSecond line');
  });

  testWidgets('FreshMart product table saves multiline text with tick', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _GroceryProductEditApi();
    final products = groceryModules.firstWhere(
      (module) => module.key == 'products',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: api,
            module: products,
            grocery: true,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-cell-editor')), findsNothing);
    await _doubleTapCell(tester, find.text('Rice'));
    final editor = find.byKey(const ValueKey('module-cell-editor'));
    expect(
      tester.widget<TextField>(editor).textInputAction,
      TextInputAction.newline,
    );
    await tester.enterText(editor, 'Rice\nPremium');
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('module-cell-PR-1-name')))
          .height,
      greaterThan(48),
    );
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();
    expect(api.editedPath, '/api/grocery/products/PR-1');
    expect(api.editedBody?['name'], 'Rice\nPremium');
    expect(api.editedBody?['tableEdit'], true);
  });

  testWidgets('booking details offer a print option', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bookings = airlineModules.firstWhere(
      (module) => module.key == 'bookings',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: bookings,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Details'));
    await tester.tap(find.byTooltip('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Print'), findsOneWidget);
    expect(find.byIcon(Icons.print_outlined), findsOneWidget);
    expect(find.text('Issue ticket'), findsOneWidget);
  });

  testWidgets('FreshMart record details offer a print option', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final products = groceryModules.firstWhere(
      (module) => module.key == 'products',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: products,
            grocery: true,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Details'));
    await tester.tap(find.byTooltip('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Print'), findsOneWidget);
    expect(find.byIcon(Icons.print_outlined), findsOneWidget);
  });

  testWidgets('module table edits cells without a layout menu', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _ModuleTableApi();
    final module = airlineModules.firstWhere(
      (item) => item.key == 'company_assets',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: api,
            module: module,
            grocery: false,
            user: const {'name': 'Owner', 'role': 'Agency owner'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ASSIGNED EQUIPMENT'), findsOneWidget);
    await _doubleTapCell(tester, find.text('Laptop'));
    await tester.enterText(
      find.byKey(const ValueKey('module-cell-editor')),
      'Tablet',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(api.editedPath, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('module-cell-editor')),
      'Tablet\nExtra line',
    );
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('module-cell-A-1-assetName')))
          .height,
      greaterThan(48),
    );
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();
    expect(api.editedPath, '/api/company-assets/A-1');
    expect(api.editedBody!['assetName'], 'Tablet\nExtra line');
    expect(find.byTooltip('Table layout'), findsNothing);
    expect(find.text('Rearrange'), findsNothing);
    expect(find.text('Reset Table Layout'), findsNothing);
    expect(api.columns, isEmpty);
    expect(api.order, isEmpty);
  });

  testWidgets('passport service and refund have new-record forms', (
    tester,
  ) async {
    for (final key in ['passports', 'refunds']) {
      final module = airlineModules.firstWhere((item) => item.key == key);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModuleScreen(
              api: _FakeApi(),
              module: module,
              grocery: false,
              user: const {'name': 'Owner', 'role': 'Agency owner'},
              onUpdated: () {},
              message: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manage form fields'), findsOneWidget);
      await tester.tap(find.text('Add Record'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Manage form fields'), findsOneWidget);
      expect(
        find.text(key == 'passports' ? 'Service type' : 'Refund amount'),
        findsWidgets,
      );
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('travel dashboard uses real data cards and charts on phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dashboard = airlineModules.firstWhere(
      (module) => module.key == 'dashboard',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: travelTheme(ThemeData()),
        home: Scaffold(
          body: ModuleScreen(
            api: _FakeApi(),
            module: dashboard,
            grocery: false,
            user: const {'name': 'Test Traveler'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome back, Test'), findsOneWidget);
    expect(find.byType(TravelMetricCard), findsNWidgets(4));
    expect(find.byType(TravelActivityChart), findsOneWidget);
    expect(find.byType(TravelBookingDonut), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('store performance metrics stay in one scrollable row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reports = groceryModules.firstWhere(
      (module) => module.key == 'reports',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _GroceryReportsApi(),
            module: reports,
            grocery: true,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = find.byKey(const ValueKey('store-performance-metrics'));
    expect(strip, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(strip).scrollDirection,
      Axis.horizontal,
    );
    final tops = [
      for (final label in [
        'PRODUCTS',
        'SALES',
        'PURCHASES',
        'SUPPLIERS',
        'CUSTOMERS',
        'EXPENSES',
      ])
        tester
            .getTopLeft(find.descendant(of: strip, matching: find.text(label)))
            .dy,
    ];
    expect(
      tops.reduce((a, b) => a > b ? a : b) -
          tops.reduce((a, b) => a < b ? a : b),
      lessThan(2),
    );
    final financialTops = [
      for (final label in [
        'TOTAL SALES',
        'GROSS PROFIT',
        'NET AFTER EXPENSES',
        'STOCK AT COST',
        'STOCK AT RETAIL',
      ])
        tester.getTopLeft(find.text(label)).dy,
    ];
    expect(
      financialTops.reduce((a, b) => a > b ? a : b) -
          financialTops.reduce((a, b) => a < b ? a : b),
      lessThan(2),
    );
    final expenseCount = find.descendant(
      of: strip,
      matching: find.text('EXPENSES'),
    );
    final initialPosition = tester.getTopLeft(expenseCount).dx;
    await tester.drag(strip, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(expenseCount).dx, lessThan(initialPosition));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AeroDesk sales report shows the API sales and details', (
    tester,
  ) async {
    final reports = airlineModules.firstWhere(
      (module) => module.key == 'reports',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _AirlineReportsApi(),
            module: reports,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('DEMO PREVIEW'), findsNothing);
    expect(find.text('SALES COUNT'), findsOneWidget);
    expect(find.text('TOTAL SALES'), findsOneWidget);
    expect(find.text('Sales (1)'), findsOneWidget);
    expect(find.byType(FinancialRegister), findsOneWidget);
    expect(find.text('AS-1'), findsNWidgets(2));
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Service fee'), findsOneWidget);
    expect(find.text('Payment method'), findsNothing);
    final expand = find.byKey(const ValueKey('financial-record-expand-0'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Cash: 120.00'), findsWidgets);
    expect(find.text('Open full record'), findsOneWidget);
    expect(find.text('Print receipt'), findsOneWidget);
  });

  testWidgets('AeroDesk Sales exposes recorded sale actions in the preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sales = airlineModules.firstWhere((module) => module.key == 'sales');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _RecordedAirlineSalesApi(),
            module: sales,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Expand selected'), findsOneWidget);
    expect(find.text('eSewa: 0.52'), findsOneWidget);
    expect(find.text('Open full record'), findsOneWidget);
    expect(find.text('Print receipt'), findsOneWidget);
    await tester.tap(find.text('Open full record'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AeroDesk Reports exposes sale actions without expanding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reports = airlineModules.firstWhere(
      (module) => module.key == 'reports',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _AirlineReportsApi(),
            module: reports,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open full record'), findsOneWidget);
    expect(find.text('Print receipt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('financial-record-expand-0')));
    await tester.pumpAndSettle();
    expect(find.text('Open full record'), findsOneWidget);
    expect(find.text('Print receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty AeroDesk Sales shows a removable demo preview', (
    tester,
  ) async {
    final api = _EmptyAirlineSalesApi();
    final sales = airlineModules.firstWhere((module) => module.key == 'sales');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: api,
            module: sales,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('DEMO PREVIEW'), findsOneWidget);
    expect(find.text('3 records in this view'), findsOneWidget);
    expect(find.text('Sample Traveler A'), findsWidgets);
    await tester.tap(find.text('Hide sample data'));
    await tester.pumpAndSettle();
    expect(find.text('0 records in this view'), findsOneWidget);
    expect(find.text('Sample Traveler A'), findsNothing);
    await tester.tap(find.text('Preview sample sales'));
    await tester.pumpAndSettle();
    expect(find.text('3 records in this view'), findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets('empty AeroDesk report previews sales without persisting', (
    tester,
  ) async {
    final api = _EmptyAirlineSalesApi();
    final reports = airlineModules.firstWhere(
      (module) => module.key == 'reports',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: api,
            module: reports,
            grocery: false,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('DEMO PREVIEW'), findsOneWidget);
    expect(find.text('Sales (3)'), findsOneWidget);
    expect(find.text('24990.0'), findsOneWidget);
    expect(find.text('DEMO-INV-001'), findsNWidgets(2));
    expect(find.textContaining('SAMPLE ONLY'), findsOneWidget);
    await tester.tap(find.text('Hide sample data'));
    await tester.pumpAndSettle();
    expect(find.text('Sales (0)'), findsOneWidget);
    expect(find.text('No sales recorded'), findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets('FreshMart sales report uses expense totals and marks gaps', (
    tester,
  ) async {
    final reports = groceryModules.firstWhere(
      (module) => module.key == 'reports',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _GroceryReportsApi(
              sales: [
                {
                  'receipt': 'FM-1',
                  'createdAt': '2026-11-03',
                  'total': 120,
                  'profit': 30,
                  'payment': 'Cash',
                  'items': [
                    {'name': 'Rice', 'qty': 2, 'price': 50, 'total': 100},
                  ],
                },
              ],
              expenses: [
                {'total': 10},
              ],
              products: [
                {'price': 50, 'cost': 30, 'stock': 5},
              ],
            ),
            module: reports,
            grocery: true,
            user: const {'name': 'Tester'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sales register (1)'), findsOneWidget);
    expect(find.text('20.00'), findsOneWidget);
    expect(find.text('150.00'), findsOneWidget);
    expect(find.text('250.00'), findsOneWidget);
    expect(find.byType(FinancialRegister), findsNWidgets(2));
    expect(find.text('Expenses (1)'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Payment method'), findsNothing);
    expect(find.text('Cash'), findsWidgets);
    expect(find.text('Rice'), findsNothing);
    final expandSale = find.descendant(
      of: find.byType(FinancialRegister).first,
      matching: find.byKey(const ValueKey('financial-record-expand-0')),
    );
    await tester.ensureVisible(expandSale);
    await tester.tap(expandSale);
    await tester.pumpAndSettle();
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('2× Rice'), findsOneWidget);
  });

  testWidgets('FreshMart sales log and expenses use the register layout', (
    tester,
  ) async {
    final api = _GroceryReportsApi(
      sales: [
        {
          'id': 'GS-1',
          'receipt': 'FM-123',
          'total': 18.52,
          'profit': 4.02,
          'payment': 'Cash',
          'items': [
            {'name': 'Rice', 'qty': 1, 'total': 18.52},
          ],
        },
      ],
      expenses: [
        {
          'id': 'EXP-1',
          'reference': 'RENT-1',
          'payee': 'Landlord',
          'description': 'Store rent',
          'total': 500,
          'paidAmount': 200,
          'outstanding': 300,
        },
      ],
    );
    for (final key in ['sales', 'expenses']) {
      final module = groceryModules.firstWhere((item) => item.key == key);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModuleScreen(
              key: ValueKey(key),
              api: api,
              module: module,
              grocery: true,
              user: const {'name': 'Tester'},
              onUpdated: () {},
              message: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final register = tester.widget<FinancialRegister>(
        find.byType(FinancialRegister),
      );
      expect(register.demo, isFalse);
      expect(register.rows, hasLength(1));
      expect(
        register.kind,
        key == 'sales'
            ? FinancialRecordKind.grocerySale
            : FinancialRecordKind.expense,
      );
      expect(find.text(key == 'sales' ? 'FM-123' : 'RENT-1'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('table edits a booking cell and saves via the existing API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TableApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableScreen(
            api: api,
            grocery: false,
            message: (_) {},
            onUpdated: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Passenger'), findsOneWidget);
    expect(find.text('Add Record'), findsOneWidget);
    await tester.tap(find.text('Test Passenger'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save cell'), findsNothing);
    await _doubleTapCell(tester, find.text('Test Passenger'));
    await tester.enterText(find.byType(TextField).last, 'Updated');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(api.lastPatch, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).textInputAction,
      TextInputAction.newline,
    );
    await tester.enterText(find.byType(TextField).last, 'Updated\nPassenger');
    await tester.pump();
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('spreadsheet-cell-BK-1-customerName')),
          )
          .height,
      greaterThan(46),
    );
    expect(find.byTooltip('Save cell'), findsOneWidget);
    expect(find.byTooltip('Cancel edit'), findsOneWidget);
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();
    expect(api.lastPatch, {
      'customerName': 'Updated\nPassenger',
      'tableEdit': true,
    });
    await _doubleTapCell(tester, find.text('Updated\nPassenger'));
    await tester.enterText(find.byType(TextField).last, 'Discarded');
    await tester.tap(find.byTooltip('Cancel edit'));
    await tester.pumpAndSettle();
    expect(api.lastPatch?['customerName'], 'Updated\nPassenger');
    expect(find.byTooltip('Print row'), findsOneWidget);
  });

  testWidgets('linked booking table paginates records', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableScreen(
            api: _TableApi(recordCount: 12),
            grocery: false,
            message: (_) {},
            onUpdated: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 to 10 of 12 entries'), findsOneWidget);
    expect(find.text('Passenger 11'), findsNothing);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 11 to 12 of 12 entries'), findsOneWidget);
    expect(find.text('Passenger 11'), findsOneWidget);
  });

  testWidgets('search refresh keeps an unsaved draft row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableScreen(
            api: _TableApi(),
            grocery: false,
            message: (_) {},
            onUpdated: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<TableScreenState>(find.byType(TableScreen));
    state.rows.insert(
      0,
      SpreadsheetRow({'customerName': 'Unsaved Draft'}, isNew: true),
    );
    state.searchController.text = 'Unsaved';
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(state.hasPendingChanges, true);
    expect(find.text('Unsaved Draft'), findsOneWidget);
  });

  testWidgets('table toolbar remains usable on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableScreen(
            api: _TableApi(),
            grocery: false,
            message: (_) {},
            onUpdated: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add Record'), findsOneWidget);
    expect(find.text('Search records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked table controls align in one row on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableScreen(
            api: _TableApi(),
            grocery: false,
            message: (_) {},
            onUpdated: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final centers = [
      tester.getCenter(find.widgetWithText(TextField, 'Search records')).dy,
      tester.getCenter(find.text('All fields')).dy,
      tester.getCenter(find.text('Export')).dy,
      tester.getCenter(find.byTooltip('Spreadsheet tools')).dy,
      tester.getCenter(find.text('Add Record')).dy,
    ];
    expect(
      centers.reduce((a, b) => a > b ? a : b) -
          centers.reduce((a, b) => a < b ? a : b),
      lessThan(14),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked table keeps records without a layout menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TableApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableScreen(
            api: api,
            grocery: false,
            message: (_) {},
            onUpdated: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Table layout'), findsNothing);
    expect(find.text('Rearrange'), findsNothing);
    expect(find.text('Reset Table Layout'), findsNothing);
    expect(find.byIcon(Icons.unfold_more), findsNothing);
    expect(api.layoutColumns, isEmpty);
    expect(find.text('Test Passenger'), findsOneWidget);
  });

  testWidgets('table asks for rows and columns before editing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TableApi(initialized: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableScreen(
            api: api,
            grocery: false,
            message: (_) {},
            onUpdated: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Number of blank rows'), findsOneWidget);
    expect(find.text('Number of extra columns'), findsOneWidget);
    expect(find.text('Add Record'), findsNothing);
    await tester.tap(find.text('Create table'));
    await tester.pumpAndSettle();
    expect(api.setupBody, {'rows': 5, 'extraColumns': 0});
    expect(find.text('Add Record'), findsOneWidget);
  });
}
