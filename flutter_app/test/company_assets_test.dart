import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AssetsApi extends ApiClient {
  final rows = <Map<String, dynamic>>[];

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/company-assets' ||
        path == '/api/grocery/company-assets') {
      return rows;
    }
    if (path.startsWith('/api/form-fields/')) {
      return {
        'removed': <String>[],
        'custom': <Object>[],
        'labels': <String, String>{},
        'order': <String>[],
      };
    }
    throw StateError(path);
  }

  @override
  Future<dynamic> request(String method, String path, [Object? body]) async {
    final values = asMap(body);
    if (method == 'POST') {
      rows.add({'id': 'ASSET-1', ...values});
      return rows.last;
    }
    if (method == 'PATCH') {
      rows[0] = {...rows[0], ...values};
      return rows[0];
    }
    if (method == 'DELETE') {
      rows.clear();
      return {'ok': true};
    }
    throw StateError('$method $path');
  }
}

void main() {
  testWidgets('Company Assets records can be added, edited and deleted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _AssetsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: api,
            module: airlineModules.firstWhere(
              (module) => module.key == 'company_assets',
            ),
            grocery: false,
            user: const {'role': 'Agency owner'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Record'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Employee name'),
      'Alex',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'What they took'),
      'Laptop',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.rows.single['employeeName'], 'Alex');
    expect(api.rows.single['assetName'], 'Laptop');

    await tester.tap(find.text('Laptop').first);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('module-cell-editor')),
      'Phone',
    );
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();
    expect(api.rows.single['assetName'], 'Phone');

    await tester.ensureVisible(find.byTooltip('Delete row').first);
    await tester.tap(find.byTooltip('Delete row').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete record').last);
    await tester.pumpAndSettle();
    expect(api.rows, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
