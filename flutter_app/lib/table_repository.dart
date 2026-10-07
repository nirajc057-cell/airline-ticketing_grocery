import 'api.dart';
import 'table_model.dart';

class TableSnapshot {
  const TableSnapshot(this.rows, this.customColumns, this.initialized);

  final List<SpreadsheetRow> rows;
  final List<TableColumnDef> customColumns;
  final bool initialized;
}

class TableSaveResult {
  const TableSaveResult(this.values, {required this.isNew, this.draftId});

  final Map<String, dynamic> values;
  final bool isNew;
  final String? draftId;
}

class TableRepository {
  const TableRepository(this.api, this.kind);

  final ApiClient api;
  final TableKind kind;

  Future<TableSnapshot> load() async {
    final results = await Future.wait<dynamic>([
      api.get(kind.path),
      api.get('${kind.path}/table-columns'),
      api.get('${kind.path}/table-setup'),
      api.get('${kind.path}/table-drafts'),
    ]);
    final columns =
        asRows(results[1])
            .map(
              (row) => TableColumnDef(
                row['key']?.toString() ?? '',
                row['label']?.toString() ?? '',
                width: 180,
                custom: true,
              ),
            )
            .where((column) => column.key.isNotEmpty)
            .toList();
    return TableSnapshot(
      [
        ...asRows(results[3]).map(
          (draft) => SpreadsheetRow(
            asMap(draft['values']),
            isNew: true,
            draftId: draft['id']?.toString(),
          ),
        ),
        ...asRows(results[0]).map((row) => SpreadsheetRow(row)),
      ],
      columns,
      asMap(results[2])['initialized'] == true,
    );
  }

  Future<void> createSetup({
    required int rows,
    required int extraColumns,
  }) async {
    await api.post('${kind.path}/table-setup', {
      'rows': rows,
      'extraColumns': extraColumns,
    });
  }

  Future<TableColumnDef> addColumn(String label) async {
    final row = asMap(
      await api.post('${kind.path}/table-columns', {'label': label.trim()}),
    );
    return TableColumnDef(
      row['key']?.toString() ?? '',
      row['label']?.toString() ?? label.trim(),
      width: 180,
      custom: true,
    );
  }

  Future<void> renameColumn(TableColumnDef column, String label) => api
      .patch('${kind.path}/table-columns', {
        'key': column.key,
        'label': label.trim(),
      })
      .then((_) {});

  Future<TableSaveResult> saveRow(
    SpreadsheetRow row,
    List<TableColumnDef> columns,
  ) async {
    final payload = spreadsheetPayload(row, columns, onlyChanged: !row.isNew);
    if (row.isNew) {
      if (validateSpreadsheetRow(row, columns) != null) {
        final draft =
            row.draftId == null
                ? asMap(await api.post('${kind.path}/table-drafts', payload))
                : asMap(
                  await api.patch(
                    '${kind.path}/table-drafts/${Uri.encodeComponent(row.draftId!)}',
                    payload,
                  ),
                );
        return TableSaveResult(
          asMap(draft['values']),
          isNew: true,
          draftId: draft['id']?.toString(),
        );
      }
      if (kind == TableKind.bookings) payload['manual'] = true;
      if (row.draftId != null) payload['tableDraftId'] = row.draftId;
      return TableSaveResult(
        asMap(await api.post(kind.path, payload)),
        isNew: false,
      );
    }
    payload['tableEdit'] = true;
    return TableSaveResult(
      asMap(
        await api.patch('${kind.path}/${Uri.encodeComponent(row.id)}', payload),
      ),
      isNew: false,
    );
  }

  Future<void> deleteRow(SpreadsheetRow row) async {
    if (row.draftId != null) {
      await api.request(
        'DELETE',
        '${kind.path}/table-drafts/${Uri.encodeComponent(row.draftId!)}',
      );
      return;
    }
    if (row.isNew) return;
    await api.request('DELETE', '${kind.path}/${Uri.encodeComponent(row.id)}');
  }
}
