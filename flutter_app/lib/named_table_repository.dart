import 'api.dart';

class NamedTableSummary {
  const NamedTableSummary({
    required this.id,
    required this.name,
    required this.platform,
    required this.rowCount,
    required this.columnCount,
  });

  final String id;
  final String name;
  final String platform;
  final int rowCount;
  final int columnCount;

  factory NamedTableSummary.fromJson(Map<String, dynamic> data) =>
      NamedTableSummary(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        platform: data['platform']?.toString() ?? '',
        rowCount: (data['rowCount'] as num?)?.toInt() ?? 0,
        columnCount: (data['columnCount'] as num?)?.toInt() ?? 0,
      );
}

class TableReminder {
  const TableReminder({
    required this.tableId,
    required this.tableName,
    required this.rowId,
    required this.rowNumber,
    required this.notifyAt,
    required this.preview,
  });

  final String tableId;
  final String tableName;
  final String rowId;
  final int rowNumber;
  final DateTime notifyAt;
  final String preview;

  factory TableReminder.fromJson(Map<String, dynamic> data) => TableReminder(
    tableId: data['tableId']?.toString() ?? '',
    tableName: data['tableName']?.toString() ?? '',
    rowId: data['rowId']?.toString() ?? '',
    rowNumber: (data['rowNumber'] as num?)?.toInt() ?? 0,
    notifyAt: DateTime.parse(data['notifyAt'].toString()).toLocal(),
    preview: data['preview']?.toString() ?? '',
  );
}

class NamedTableColumn {
  NamedTableColumn(this.id, this.label, {this.color});
  final String id;
  String label;
  String? color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    if (color != null) 'color': color,
  };
}

class NamedTableRow {
  NamedTableRow(this.id, this.cells, {this.color, this.notifyAt});
  final String id;
  final Map<String, String> cells;
  String? color;
  String? notifyAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'cells': cells,
    if (color != null) 'color': color,
    if (notifyAt != null) 'notifyAt': notifyAt,
  };
}

class NamedTable {
  NamedTable({
    required this.id,
    required this.name,
    required this.platform,
    required this.revision,
    required this.columns,
    required this.archivedColumns,
    required this.rows,
    required this.defaultColumnIds,
    required this.defaultRowIds,
  });

  final String id;
  String name;
  final String platform;
  int revision;
  final List<NamedTableColumn> columns;
  final List<NamedTableColumn> archivedColumns;
  final List<NamedTableRow> rows;
  final List<String> defaultColumnIds;
  final List<String> defaultRowIds;

  NamedTable copy() => NamedTable(
    id: id,
    name: name,
    platform: platform,
    revision: revision,
    columns: [
      for (final column in columns)
        NamedTableColumn(column.id, column.label, color: column.color),
    ],
    archivedColumns: [
      for (final column in archivedColumns)
        NamedTableColumn(column.id, column.label, color: column.color),
    ],
    rows: [
      for (final row in rows)
        NamedTableRow(
          row.id,
          Map.of(row.cells),
          color: row.color,
          notifyAt: row.notifyAt,
        ),
    ],
    defaultColumnIds: [...defaultColumnIds],
    defaultRowIds: [...defaultRowIds],
  );

  factory NamedTable.fromJson(Map<String, dynamic> data) => NamedTable(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    platform: data['platform']?.toString() ?? '',
    revision: (data['revision'] as num?)?.toInt() ?? 1,
    columns: [
      for (final column in asRows(data['columns']))
        NamedTableColumn(
          column['id']?.toString() ?? '',
          column['label']?.toString() ?? '',
          color: column['color']?.toString(),
        ),
    ],
    archivedColumns: [
      for (final column in asRows(data['archivedColumns']))
        NamedTableColumn(
          column['id']?.toString() ?? '',
          column['label']?.toString() ?? '',
          color: column['color']?.toString(),
        ),
    ],
    rows: [
      for (final row in asRows(data['rows']))
        NamedTableRow(
          row['id']?.toString() ?? '',
          {
            for (final cell in asMap(row['cells']).entries)
              cell.key: cell.value?.toString() ?? '',
          },
          color: row['color']?.toString(),
          notifyAt: row['notifyAt']?.toString(),
        ),
    ],
    defaultColumnIds:
        data['defaultColumnIds'] is List
            ? (data['defaultColumnIds'] as List)
                .map((e) => e.toString())
                .toList()
            : asRows(data['columns']).map((e) => e['id'].toString()).toList(),
    defaultRowIds:
        data['defaultRowIds'] is List
            ? (data['defaultRowIds'] as List).map((e) => e.toString()).toList()
            : asRows(data['rows']).map((e) => e['id'].toString()).toList(),
  );

  Map<String, dynamic> toUpdateJson() => {
    'revision': revision,
    'name': name,
    'columns': [for (final column in columns) column.toJson()],
    'rows': [for (final row in rows) row.toJson()],
  };
}

class NamedTableRepository {
  const NamedTableRepository(this.api);
  final ApiClient api;

  Future<List<NamedTableSummary>> list(bool grocery) async => [
    for (final row in asRows(
      await api.get(
        '/api/custom-tables?platform=${grocery ? 'grocery' : 'airline'}',
      ),
    ))
      NamedTableSummary.fromJson(row),
  ];

  Future<List<TableReminder>> dueReminders(bool grocery) async => [
    for (final row in asRows(
      await api.get(
        '/api/custom-tables/reminders?platform=${grocery ? 'grocery' : 'airline'}',
      ),
    ))
      TableReminder.fromJson(row),
  ];

  Future<void> dismissReminder(TableReminder reminder) => api
      .post(
        '/api/custom-tables/reminders/'
        '${Uri.encodeComponent(reminder.tableId)}/'
        '${Uri.encodeComponent(reminder.rowId)}/dismiss',
        <String, dynamic>{},
      )
      .then((_) {});

  Future<NamedTable> load(String id) async => NamedTable.fromJson(
    asMap(await api.get('/api/custom-tables/${Uri.encodeComponent(id)}')),
  );

  Future<Set<String>> search(String id, String query) async => {
    for (final value
        in (await api.get(
              '/api/custom-tables/${Uri.encodeComponent(id)}/search?query=${Uri.encodeQueryComponent(query)}',
            )
            as List))
      value.toString(),
  };

  Future<NamedTable> create({
    required String name,
    required bool grocery,
    required int rows,
    required int columns,
    required List<String> headers,
  }) async => NamedTable.fromJson(
    asMap(
      await api.post('/api/custom-tables', {
        'name': name.trim(),
        'platform': grocery ? 'grocery' : 'airline',
        'rows': rows,
        'columns': columns,
        'headers': headers,
      }),
    ),
  );

  Future<NamedTable> save(
    NamedTable table, {
    bool resetColumnOrder = false,
  }) async => NamedTable.fromJson(
    asMap(
      await api.patch('/api/custom-tables/${Uri.encodeComponent(table.id)}', {
        ...table.toUpdateJson(),
        if (resetColumnOrder) 'resetColumnOrder': true,
      }),
    ),
  );

  Future<void> delete(String id) => api
      .request('DELETE', '/api/custom-tables/${Uri.encodeComponent(id)}')
      .then((_) {});
}
