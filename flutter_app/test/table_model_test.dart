import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/table_model.dart';

void main() {
  test('booking table uses existing record fields', () {
    final columns = TableKind.bookings.baseColumns;
    expect(columns.first.key, 'id');
    expect(columns.first.editable, isFalse);
    expect(columns.any((column) => column.key == 'customerName'), isTrue);
    expect(columns.any((column) => column.key == 'origin'), isTrue);
    expect(columns.any((column) => column.key == 'destination'), isTrue);
  });

  test('row validation and payload retain numeric values', () {
    final row = SpreadsheetRow({
      'reference': 'BK-TEST',
      'customerName': 'Test Passenger',
      'origin': 'KTM',
      'destination': 'DXB',
      'total': '125.50',
    }, isNew: true);
    expect(validateSpreadsheetRow(row, TableKind.bookings.baseColumns), isNull);
    final payload = spreadsheetPayload(row, TableKind.bookings.baseColumns);
    expect(payload['total'], 125.5);
    expect(payload.containsKey('id'), isFalse);
    row.setValue('total', '-1');
    expect(
      validateSpreadsheetRow(row, TableKind.bookings.baseColumns),
      contains('non-negative'),
    );
  });

  test('existing row patch includes only edited fields', () {
    final row = SpreadsheetRow({'id': 'PR-1', 'name': 'Soap', 'price': 20});
    row.setValue('price', '25');
    expect(
      spreadsheetPayload(
        row,
        TableKind.products.baseColumns,
        onlyChanged: true,
      ),
      {'price': 25},
    );
  });
}
