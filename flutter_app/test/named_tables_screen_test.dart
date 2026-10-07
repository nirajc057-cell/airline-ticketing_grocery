import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/named_tables_screen.dart';

class _FakeApi extends ApiClient {
  Map<String, dynamic>? creation;

  @override
  Future<dynamic> post(String path, Object body) async {
    creation = Map<String, dynamic>.from(body as Map);
    return {
      'id': 'T-1',
      'name': creation!['name'],
      'platform': creation!['platform'],
      'revision': 1,
      'columns': [
        {'id': 'C-1', 'label': 'Passenger'},
      ],
      'rows': <Object>[],
    };
  }
}

class _EditableApi extends ApiClient {
  Map<String, dynamic>? lastSave;
  final table = <String, dynamic>{
    'id': 'T-3',
    'name': 'Three by three',
    'platform': 'airline',
    'revision': 1,
    'columns': [
      {'id': 'C-1', 'label': 'A'},
      {'id': 'C-2', 'label': 'B'},
      {'id': 'C-3', 'label': 'C'},
    ],
    'rows': [
      {'id': 'R-1', 'cells': <String, String>{}},
      {'id': 'R-2', 'cells': <String, String>{}},
      {'id': 'R-3', 'cells': <String, String>{}},
    ],
  };

  @override
  Future<dynamic> get(String path) async => table;

  @override
  Future<dynamic> patch(String path, Object body) async {
    lastSave = Map<String, dynamic>.from(body as Map);
    table.addAll(lastSave!);
    table['revision'] = (lastSave!['revision'] as int) + 1;
    return table;
  }
}

Widget _editor(_EditableApi api, {ValueChanged<String>? onMessage}) =>
    MaterialApp(
      home: Scaffold(
        body: NamedTablesScreen(
          api: api,
          grocery: false,
          selectedTableId: 'T-3',
          tables: const [],
          onSelectTable: (_) {},
          onTablesChanged: () {},
          onOpenLinked: () {},
          message: onMessage ?? (_) {},
        ),
      ),
    );

void main() {
  testWidgets('a row number selects a row and deletion persists', (
    tester,
  ) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').first);
    await tester.pump();
    expect(find.text('Row 2 selected'), findsOneWidget);
    await tester.tap(find.text('Delete Row'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((api.lastSave!['rows'] as List).length, 2);
  });

  testWidgets('a column header selects a column and deletion persists', (
    tester,
  ) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(find.text('Column 2 selected'), findsOneWidget);
    await tester.tap(find.text('Delete Column'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((api.lastSave!['columns'] as List).length, 2);
  });

  testWidgets('row and column colors are saved', (tester) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pump();
    await tester.tap(find.text('Row color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-Blue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.text('Column color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-Green')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((api.lastSave!['rows'] as List).first['color'], '#DDEBFF');
    expect((api.lastSave!['columns'] as List).first['color'], '#DDF5E8');
  });

  testWidgets('row three-dot menu colors its own row', (tester) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Row 2 actions'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate row'), findsOneWidget);
    expect(find.text('Delete row'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('row-action-color-R-2')));
    await tester.pumpAndSettle();
    expect(find.text('Row 2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('palette-Green')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rows = api.lastSave!['rows'] as List;
    expect((rows[1] as Map)['color'], '#DDF5E8');
    expect((rows[0] as Map)['color'], isNull);
  });

  testWidgets('row three-dot menu opens notification for its own row', (
    tester,
  ) async {
    await tester.pumpWidget(_editor(_EditableApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Row 3 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('row-action-notification-R-3')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Row 3 selected'), findsOneWidget);
  });

  testWidgets('one tap types in a cell without opening a dialog', (
    tester,
  ) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('table-cell-R-1-C-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('table-cell-editor')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      'First cell',
    );

    await tester.tap(find.byKey(const ValueKey('table-cell-R-1-C-2')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      'Second cell',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rows = api.lastSave!['rows'] as List;
    final cells = (rows.first as Map)['cells'] as Map;
    expect(cells['C-1'], 'First cell');
    expect(cells['C-2'], 'Second cell');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    expect(find.text('First cell'), findsOneWidget);
    expect(find.text('Second cell'), findsOneWidget);
  });

  testWidgets('Enter text can span lines and Next row keeps the column', (
    tester,
  ) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('table-cell-R-1-C-1')));
    await tester.pump();
    final editor = find.byKey(const ValueKey('table-cell-editor'));
    expect(
      tester.widget<TextField>(editor).decoration!.focusedBorder,
      InputBorder.none,
    );
    await tester.enterText(editor, 'First line');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, 'First line\n');
    await tester.enterText(editor, 'First line\nSecond line');
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('table-cell-R-1-C-1'))).height,
      greaterThan(52),
    );

    await tester.tap(find.text('Next row'));
    await tester.pump();
    expect(find.byKey(const ValueKey('table-cell-editor')), findsOneWidget);
    await tester.enterText(editor, 'Following row');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rows = api.lastSave!['rows'] as List;
    expect((rows[0] as Map)['cells']['C-1'], 'First line\nSecond line');
    expect((rows[1] as Map)['cells']['C-1'], 'Following row');
  });

  testWidgets('notification control explains selection and opens the picker', (
    tester,
  ) async {
    String? message;
    await tester.pumpWidget(
      _editor(_EditableApi(), onMessage: (value) => message = value),
    );
    await tester.pumpAndSettle();
    final notification = find.ancestor(
      of: find.text('Set notification'),
      matching: find.bySubtype<OutlinedButton>(),
    );
    expect(notification, findsOneWidget);
    await tester.tap(notification);
    await tester.pump();
    expect(message, contains('Select a row number or cell'));

    await tester.tap(find.text('1').first);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(notification).onPressed, isNotNull);
    await tester.tap(notification);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('common tools stay separate from selection actions', (
    tester,
  ) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();

    expect(find.text('Add Row'), findsOneWidget);
    expect(find.text('Add Column'), findsOneWidget);
    expect(find.text('Import / Export'), findsOneWidget);
    expect(find.text('Delete Row'), findsNothing);

    await tester.tap(find.text('1').first);
    await tester.pump();
    expect(find.text('Row 1 selected'), findsOneWidget);
    expect(find.text('Delete Row'), findsOneWidget);
    expect(find.text('Delete Column'), findsNothing);

    await tester.tap(find.text('A'));
    await tester.pump();
    expect(find.text('Column 1 selected'), findsOneWidget);
    expect(find.text('Delete Column'), findsOneWidget);
    expect(find.text('Delete Row'), findsNothing);

    await tester.tap(find.text('Import / Export'));
    await tester.pumpAndSettle();
    expect(find.text('Import CSV'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
  });

  testWidgets('table editor fits a narrow screen without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_editor(_EditableApi()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Three by three'), findsOneWidget);
    expect(find.text('Add Row'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('1').first);
    await tester.pump();
    await tester.tap(find.text('Row actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Row'), findsOneWidget);
    expect(find.text('Set notification'), findsWidgets);
  });

  testWidgets('row three-dot menu is usable on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_editor(_EditableApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Row 1 actions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row-action-color-R-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('row-action-notification-R-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone can type and save directly in a cell', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('table-cell-R-1-C-1')));
    await tester.pump();
    expect(find.text('Next row'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      'Typed on phone',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rows = api.lastSave!['rows'] as List;
    expect((rows.first as Map)['cells']['C-1'], 'Typed on phone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation asks for sidebar name and editable headings', (
    tester,
  ) async {
    final api = _FakeApi();
    String? selectedId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NamedTablesScreen(
            api: api,
            grocery: false,
            selectedTableId: null,
            tables: const [],
            onSelectTable: (id) => selectedId = id,
            onTablesChanged: () {},
            onOpenLinked: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create table').first);
    await tester.pumpAndSettle();
    expect(find.text('Name shown in sidebar'), findsOneWidget);
    expect(find.text('Header 1'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Flights 2026');
    await tester.enterText(fields.at(1), '4');
    await tester.enterText(fields.at(2), '1');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(3), 'Passenger');
    await tester.tap(find.text('Create table').last);
    await tester.pumpAndSettle();
    expect(api.creation!['name'], 'Flights 2026');
    expect(api.creation!['rows'], 4);
    expect(api.creation!['columns'], 1);
    expect(api.creation!['headers'], ['Passenger']);
    expect(selectedId, 'T-1');
  });
}
