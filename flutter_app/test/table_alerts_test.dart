import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/screens.dart';

class _ReminderApi extends ApiClient {
  bool dismissed = false;

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/grocery/bootstrap') {
      return {'stats': <String, dynamic>{}, 'wallet': <String, dynamic>{}};
    }
    if (path == '/api/custom-tables/reminders?platform=grocery') {
      if (dismissed) return <Object>[];
      return [
        {
          'tableId': 'T-1',
          'tableName': 'Daily checks',
          'rowId': 'R-1',
          'rowNumber': 2,
          'notifyAt':
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(minutes: 1))
                  .toIso8601String(),
          'preview': 'Check freezer',
        },
      ];
    }
    throw StateError(path);
  }

  @override
  Future<dynamic> post(String path, Object body) async {
    if (path.endsWith('/dismiss')) {
      dismissed = true;
      return {'ok': true};
    }
    throw StateError(path);
  }
}

void main() {
  testWidgets('due table reminder appears on dashboard and can be dismissed', (
    tester,
  ) async {
    final api = _ReminderApi();
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: api,
            module: groceryModules.first,
            grocery: true,
            user: const {'name': 'Owner'},
            onUpdated: () {},
            message: (_) {},
            onOpenTable: (id) => opened = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Table alerts'), findsOneWidget);
    expect(find.text('Daily checks · Row 2'), findsOneWidget);
    await tester.tap(find.text('Open table'));
    expect(opened, 'T-1');
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(api.dismissed, isTrue);
    expect(find.text('No due table reminders.'), findsOneWidget);
  });
}
