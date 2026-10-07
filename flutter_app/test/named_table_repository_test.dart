import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/named_table_repository.dart';

class _Api extends ApiClient {
  String? method;
  String? path;
  Map<String, dynamic>? body;

  final table = <String, dynamic>{
    'id': 'T-1',
    'name': 'My table',
    'platform': 'airline',
    'revision': 1,
    'columns': [
      {'id': 'C-1', 'label': 'Customer'},
    ],
    'rows': [
      {
        'id': 'R-1',
        'cells': {'C-1': 'Jane'},
      },
    ],
  };

  @override
  Future<dynamic> request(String method, String path, [Object? body]) async {
    this.method = method;
    this.path = path;
    this.body = body == null ? null : Map<String, dynamic>.from(body as Map);
    if (method == 'GET' && path.contains('?platform=')) {
      if (path.contains('/reminders?')) {
        return [
          {
            'tableId': 'T-1',
            'tableName': 'My table',
            'rowId': 'R-1',
            'rowNumber': 1,
            'notifyAt': '2026-10-04T10:00:00Z',
            'preview': 'Jane',
          },
        ];
      }
      return [
        {
          'id': 'T-1',
          'name': 'My table',
          'platform': 'airline',
          'rowCount': 1,
          'columnCount': 1,
        },
      ];
    }
    if (method == 'DELETE') return {'ok': true};
    return table;
  }
}

void main() {
  test(
    'creation sends user name and chosen headers, not preset columns',
    () async {
      final api = _Api();
      final repository = NamedTableRepository(api);
      await repository.create(
        name: 'My table',
        grocery: false,
        rows: 4,
        columns: 2,
        headers: ['Date', 'Notes'],
      );
      expect(api.method, 'POST');
      expect(api.path, '/api/custom-tables');
      expect(api.body, containsPair('name', 'My table'));
      expect(api.body!['headers'], ['Date', 'Notes']);
      expect(api.body!['rows'], 4);
    },
  );

  test('load, rename and save retain cell data and revision', () async {
    final api = _Api();
    final repository = NamedTableRepository(api);
    final table = await repository.load('T-1');
    expect(table.rows.single.cells['C-1'], 'Jane');
    table.name = 'New sidebar name';
    table.columns.single.label = 'Full name';
    table.rows.single.cells['C-1'] = 'Janet';
    await repository.save(table);
    expect(api.method, 'PATCH');
    expect(api.body!['revision'], 1);
    expect(api.body!['name'], 'New sidebar name');
    expect((api.body!['columns'] as List).single['label'], 'Full name');
    expect((api.body!['rows'] as List).single['cells']['C-1'], 'Janet');
  });

  test('list is platform-specific and delete targets one table', () async {
    final api = _Api();
    final repository = NamedTableRepository(api);
    final tables = await repository.list(false);
    expect(api.path, '/api/custom-tables?platform=airline');
    expect(tables.single.name, 'My table');
    await repository.delete('T-1');
    expect(api.method, 'DELETE');
    expect(api.path, '/api/custom-tables/T-1');
  });

  test('row reminder and row/column colors survive serialization', () async {
    final repository = NamedTableRepository(_Api());
    final table = await repository.load('T-1');
    table.rows.single.notifyAt = '2026-10-04T10:00:00Z';
    table.rows.single.color = '#DDEBFF';
    table.columns.single.color = '#DDF5E8';
    final update = table.toUpdateJson();
    expect((update['rows'] as List).single['notifyAt'], '2026-10-04T10:00:00Z');
    expect((update['rows'] as List).single['color'], '#DDEBFF');
    expect((update['columns'] as List).single['color'], '#DDF5E8');
    final reloaded = NamedTable.fromJson({
      'id': table.id,
      'name': table.name,
      'platform': table.platform,
      'revision': 2,
      'rows': update['rows'],
      'columns': update['columns'],
    });
    expect(reloaded.rows.single.notifyAt, '2026-10-04T10:00:00Z');
    expect(reloaded.rows.single.color, '#DDEBFF');
    expect(reloaded.columns.single.color, '#DDF5E8');
  });

  test('due reminders can be loaded and dismissed', () async {
    final api = _Api();
    final repository = NamedTableRepository(api);
    final due = await repository.dueReminders(false);
    expect(due.single.tableName, 'My table');
    expect(due.single.rowNumber, 1);
    await repository.dismissReminder(due.single);
    expect(api.method, 'POST');
    expect(api.path, '/api/custom-tables/reminders/T-1/R-1/dismiss');
  });
}
