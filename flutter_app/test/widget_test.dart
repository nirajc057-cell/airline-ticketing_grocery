import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/main.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/screens.dart';
import 'package:aerodesk_client/travel_ui.dart';
import 'package:aerodesk_client/table_screen.dart';

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

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/bookings/table-columns') return <Object>[];
    if (path == '/api/bookings/table-setup') {
      return {'initialized': initialized};
    }
    if (path == '/api/bookings/table-drafts') return <Object>[];
    if (path == '/api/bookings') {
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
    await tester.tap(find.text('New booking'));
    await tester.pumpAndSettle();
    expect(find.text('Passenger full name'), findsOneWidget);
    expect(find.text('From airport'), findsOneWidget);
    expect(find.text('To airport'), findsOneWidget);
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
      await tester.tap(find.text(module.createLabel!));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Manage form fields'), findsOneWidget);
      expect(
        find.text(key == 'passports' ? 'Service type' : 'Refund amount'),
        findsOneWidget,
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
    expect(find.text('Add Row'), findsOneWidget);
    await tester.longPress(find.text('Test Passenger'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Updated Passenger');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.lastPatch, {
      'customerName': 'Updated Passenger',
      'tableEdit': true,
    });
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
    expect(find.text('Add Row'), findsOneWidget);
    expect(find.text('Search table data'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.text('Add Row'), findsNothing);
    await tester.tap(find.text('Create table'));
    await tester.pumpAndSettle();
    expect(api.setupBody, {'rows': 5, 'extraColumns': 0});
    expect(find.text('Add Row'), findsOneWidget);
  });
}
