import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/main.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/screens.dart';
import 'package:aerodesk_client/travel_ui.dart';
import 'package:aerodesk_client/table_screen.dart';
import 'package:aerodesk_client/table_model.dart';

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

class _TableApi extends ApiClient {
  _TableApi({this.initialized = true});

  bool initialized;
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
        {
          'id': 'BK-1',
          'reference': 'BK-1',
          'customerName': 'Test Passenger',
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
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Test Passenger'), findsOneWidget);
  });

  testWidgets('module table follows form labels, edits and saves its layout', (
    tester,
  ) async {
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
    expect(find.text('Assigned equipment'), findsOneWidget);
    await tester.tap(find.text('Laptop'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('module-cell-editor')),
      'Tablet',
    );
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();
    expect(api.editedPath, '/api/company-assets/A-1');
    expect(api.editedBody!['assetName'], 'Tablet');
    await tester.tap(find.byTooltip('Table layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rearrange'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Employee name left'));
    await tester.pumpAndSettle();
    expect(api.columns.first, 'employeeName');
    await tester.tap(find.byTooltip('Move row down').first);
    await tester.pumpAndSettle();
    expect(api.order.first, 'A-2');
    await tester.tap(find.byTooltip('Table layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Table Layout'));
    await tester.pumpAndSettle();
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
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Updated Passenger');
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();
    expect(api.lastPatch, {
      'customerName': 'Updated Passenger',
      'tableEdit': true,
    });
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
    expect(find.text('Search table data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked table column order saves and reset keeps records', (
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
    await tester.tap(find.byTooltip('Table layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rearrange'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Reference right'));
    await tester.pumpAndSettle();
    expect(
      api.layoutColumns.indexOf('pnr'),
      lessThan(api.layoutColumns.indexOf('reference')),
    );
    await tester.tap(find.byTooltip('Table layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Table Layout'));
    await tester.pumpAndSettle();
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
