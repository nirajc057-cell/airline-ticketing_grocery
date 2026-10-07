enum TableKind { bookings, products }

enum TableValueType { text, number, date, choice, longText }

bool isNonNegativeNumber(String value) {
  final number = num.tryParse(value);
  return number != null && number.isFinite && number >= 0;
}

class TableColumnDef {
  const TableColumnDef(
    this.key,
    this.label, {
    this.type = TableValueType.text,
    this.required = false,
    this.editable = true,
    this.width = 150,
    this.choices = const [],
    this.custom = false,
  });

  final String key;
  final String label;
  final TableValueType type;
  final bool required;
  final bool editable;
  final double width;
  final List<String> choices;
  final bool custom;
}

extension TableKindDetails on TableKind {
  String get path => switch (this) {
    TableKind.bookings => '/api/bookings',
    TableKind.products => '/api/grocery/products',
  };

  String get title => switch (this) {
    TableKind.bookings => 'Booking table',
    TableKind.products => 'Product table',
  };

  List<TableColumnDef> get baseColumns => switch (this) {
    TableKind.bookings => const [
      TableColumnDef('id', 'ID', editable: false, width: 190),
      TableColumnDef('reference', 'Reference', required: true),
      TableColumnDef('pnr', 'PNR'),
      TableColumnDef('customerName', 'Passenger', required: true, width: 190),
      TableColumnDef('origin', 'From', required: true, width: 110),
      TableColumnDef('destination', 'To', required: true, width: 110),
      TableColumnDef('travelDate', 'Travel date', type: TableValueType.date),
      TableColumnDef('airline', 'Airline'),
      TableColumnDef('flight', 'Flight'),
      TableColumnDef(
        'status',
        'Status',
        type: TableValueType.choice,
        choices: ['On hold', 'Confirmed', 'Ticketed', 'Cancelled'],
      ),
      TableColumnDef('paymentStatus', 'Payment', editable: false),
      TableColumnDef(
        'total',
        'Total',
        type: TableValueType.number,
        required: true,
      ),
      TableColumnDef('cost', 'Cost', type: TableValueType.number),
      TableColumnDef(
        'specialRequirements',
        'Requirements',
        type: TableValueType.longText,
        width: 250,
      ),
      TableColumnDef(
        'notes',
        'Notes',
        type: TableValueType.longText,
        width: 250,
      ),
    ],
    TableKind.products => const [
      TableColumnDef('id', 'ID', editable: false, width: 190),
      TableColumnDef('name', 'Product', required: true, width: 190),
      TableColumnDef('sku', 'SKU'),
      TableColumnDef('barcode', 'Barcode', required: true),
      TableColumnDef('category', 'Category', required: true),
      TableColumnDef('brand', 'Brand'),
      TableColumnDef('supplier', 'Supplier'),
      TableColumnDef(
        'cost',
        'Cost',
        type: TableValueType.number,
        required: true,
      ),
      TableColumnDef(
        'price',
        'Price',
        type: TableValueType.number,
        required: true,
      ),
      TableColumnDef('stock', 'Stock', type: TableValueType.number),
      TableColumnDef('unit', 'Unit'),
      TableColumnDef('reorder', 'Reorder', type: TableValueType.number),
      TableColumnDef('expiry', 'Expiry', type: TableValueType.date),
      TableColumnDef(
        'status',
        'Status',
        type: TableValueType.choice,
        choices: ['Active', 'Inactive', 'Discontinued'],
      ),
      TableColumnDef(
        'description',
        'Description',
        type: TableValueType.longText,
        width: 250,
      ),
    ],
  };
}

class SpreadsheetRow {
  SpreadsheetRow(this.values, {this.isNew = false, this.draftId});

  final Map<String, dynamic> values;
  bool isNew;
  String? draftId;
  bool dirty = false;
  final Set<String> changedKeys = {};

  String get id => values['id']?.toString() ?? '';

  void setValue(String key, dynamic value) {
    if (values[key] == value) return;
    values[key] = value;
    dirty = true;
    changedKeys.add(key);
  }
}

String? validateSpreadsheetRow(
  SpreadsheetRow row,
  List<TableColumnDef> columns,
) {
  for (final column in columns.where((column) => column.editable)) {
    final raw = row.values[column.key];
    final value = raw?.toString().trim() ?? '';
    if (column.required && value.isEmpty) return '${column.label} is required';
    if (value.isEmpty) continue;
    if (column.type == TableValueType.number) {
      if (!isNonNegativeNumber(value)) {
        return '${column.label} must be a non-negative number';
      }
    }
    if (column.type == TableValueType.date &&
        DateTime.tryParse(value) == null) {
      return '${column.label} must be a valid date';
    }
    if (column.type == TableValueType.choice &&
        !column.choices.contains(value)) {
      return '${column.label} has an invalid choice';
    }
  }
  return null;
}

Map<String, dynamic> spreadsheetPayload(
  SpreadsheetRow row,
  List<TableColumnDef> columns, {
  bool onlyChanged = false,
}) {
  final payload = <String, dynamic>{};
  for (final column in columns.where((column) => column.editable)) {
    if (onlyChanged && !row.changedKeys.contains(column.key)) continue;
    final value = row.values[column.key];
    if (value == null || value == '') {
      if (onlyChanged) payload[column.key] = '';
      continue;
    }
    payload[column.key] =
        column.type == TableValueType.number
            ? num.parse(value.toString())
            : value;
  }
  return payload;
}
