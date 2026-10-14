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
  String? searchPath;
  bool failPatch = false;
  final table = <String, dynamic>{
    'id': 'T-3',
    'name': 'Three by three',
    'platform': 'airline',
    'revision': 1,
    'defaultColumnIds': ['C-1', 'C-2', 'C-3'],
    'defaultRowIds': ['R-1', 'R-2', 'R-3'],
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
  Future<dynamic> get(String path) async {
    if (path.contains('/search?query=')) {
      searchPath = path;
      final query = Uri.parse(path).queryParameters['query']!.toLowerCase();
      return [
        for (final row in table['rows'] as List)
          if ((row['cells'] as Map).values.any(
            (value) => value.toString().toLowerCase().contains(query),
          ))
            row['id'],
      ];
    }
    return table;
  }

  @override
  Future<dynamic> patch(String path, Object body) async {
    if (failPatch) throw StateError('Server refused the save');
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
  testWidgets('row delete action confirms and persists', (tester) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete row').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete row').last);
    await tester.pumpAndSettle();
    expect((api.lastSave!['rows'] as List).length, 2);
  });

  testWidgets('failed row deletion restores the saved row', (tester) async {
    final api = _EditableApi()..failPatch = true;
    String? message;
    await tester.pumpWidget(
      _editor(api, onMessage: (value) => message = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete row').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete row').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Row 1 actions'), findsOneWidget);
    expect(find.byTooltip('Row 2 actions'), findsOneWidget);
    expect(find.byTooltip('Row 3 actions'), findsOneWidget);
    expect(message, contains('changes reverted'));
  });

  testWidgets('column menu deletes and persists the column', (tester) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Column actions').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete column'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect((api.lastSave!['columns'] as List).length, 2);
  });

  testWidgets('restoring a removed field shows its saved values', (
    tester,
  ) async {
    final api = _EditableApi();
    api.table['archivedColumns'] = [
      {'id': 'C-4', 'label': 'Old reference'},
    ];
    (api.table['rows'] as List).first['cells']['C-4'] = 'Stored value';
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add form field'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore Old reference'));
    await tester.pumpAndSettle();

    expect((api.lastSave!['columns'] as List).last['id'], 'C-4');
    expect(find.text('Stored value'), findsOneWidget);
  });

  testWidgets('search is debounced and includes rows outside the viewport', (
    tester,
  ) async {
    final api = _EditableApi();
    (api.table['rows'] as List).last['cells']['C-1'] = 'Long distance flight';
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search this table'),
      'DISTANCE',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.searchPath, contains('query=DISTANCE'));
    expect(find.text('Long distance flight'), findsOneWidget);
  });

  testWidgets('row and column colors are saved', (tester) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Row 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Color row'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-Blue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Column actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Color column'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-Green')));
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
    await tester.tap(find.byKey(const ValueKey('palette-Green')));
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
    expect(find.byTooltip('Row 3 actions'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('table-cell-R-1-C-2')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      'Second cell',
    );
    await tester.tap(find.byTooltip('Save cell'));
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

  testWidgets('Enter saves a compact single-line cell', (tester) async {
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
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('table-cell-R-1-C-1'))).height,
      52,
    );
    final rows = api.lastSave!['rows'] as List;
    expect((rows[0] as Map)['cells']['C-1'], 'First line');
  });

  testWidgets('row notification action opens the picker', (tester) async {
    await tester.pumpWidget(_editor(_EditableApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Row 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set notification'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('toolbar has one layout menu and a table field action', (
    tester,
  ) async {
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();

    expect(find.text('Add Record'), findsOneWidget);
    expect(find.byTooltip('Add form field'), findsOneWidget);
    expect(find.byTooltip('Table layout'), findsOneWidget);
    expect(find.text('Import / Export'), findsNothing);
    await tester.tap(find.byTooltip('Table layout'));
    await tester.pumpAndSettle();
    expect(find.text('Rearrange'), findsOneWidget);
    expect(find.text('Reset Table Layout'), findsOneWidget);
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
    expect(find.text('Add Record'), findsOneWidget);
    await tester.tap(find.byTooltip('Row 1 actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete row'), findsOneWidget);
    expect(find.text('Set notification'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('table-cell-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      'Typed on phone',
    );
    await tester.tap(find.byTooltip('Save cell'));
    await tester.pumpAndSettle();

    final rows = api.lastSave!['rows'] as List;
    expect((rows.first as Map)['cells']['C-1'], 'Typed on phone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('named table rearranges and resets row and column layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _EditableApi();
    await tester.pumpWidget(_editor(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Table layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rearrange'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move column right').first);
    await tester.pumpAndSettle();
    expect((api.lastSave!['columns'] as List).first['id'], 'C-2');
    await tester.tap(find.byTooltip('Move row down').first);
    await tester.pumpAndSettle();
    expect((api.lastSave!['rows'] as List).first['id'], 'R-2');
    await tester.tap(find.byTooltip('Table layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Table Layout'));
    await tester.pumpAndSettle();
    expect(api.lastSave!['resetColumnOrder'], true);
    expect((api.lastSave!['columns'] as List).first['id'], 'C-1');
    expect((api.lastSave!['rows'] as List).first['id'], 'R-1');
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
