import 'package:flutter/material.dart';
import 'api.dart';
import 'form_sheet.dart';
import 'modules.dart';

const bookingFormPath = '/api/bookings/form-fields';
const configurableFormModules = {
  'payment_profiles',
  'bookings',
  'passports',
  'passport_collection',
  'refunds',
  'airline_customers',
  'cases',
  'users',
  'sales',
  'grocery_products',
  'grocery_suppliers',
  'grocery_customers',
  'grocery_expenses',
  'grocery_purchases',
  'quotes',
  'company_assets',
  'grocery_company_assets',
};

const protectedFormFields = <String, Set<String>>{
  'payment_profiles': {'method', 'label', 'active'},
  'passports': {'status'},
  'passport_collection': {'status'},
  'refunds': {'bookingId', 'amount'},
  'airline_customers': {'name'},
  'cases': {'subject', 'status'},
  'users': {'name', 'email', 'password', 'role', 'active'},
  'sales': {'total'},
  'grocery_products': {'name', 'barcode', 'cost', 'price', 'stock', 'status'},
  'grocery_suppliers': {'name'},
  'grocery_customers': {'name', 'phone'},
  'grocery_expenses': {
    'description',
    'quantity',
    'unitRate',
    'taxRate',
    'status',
  },
  'grocery_purchases': {'supplierId', 'status'},
  'quotes': {'customerName', 'origin', 'destination', 'fare'},
};

String? recordFormModule(String key, bool grocery) {
  if (grocery) {
    return switch (key) {
      'products' => 'grocery_products',
      'suppliers' => 'grocery_suppliers',
      'customers' => 'grocery_customers',
      'expenses' => 'grocery_expenses',
      'purchases' => 'grocery_purchases',
      'company_assets' => 'grocery_company_assets',
      _ => null,
    };
  }
  return switch (key) {
    'customers' => 'airline_customers',
    'bookings' ||
    'passports' ||
    'refunds' ||
    'cases' ||
    'users' ||
    'sales' ||
    'quotes' => key,
    'company_assets' => 'company_assets',
    _ => null,
  };
}

String recordFormPath(String module) =>
    {'bookings', 'passports', 'refunds'}.contains(module)
        ? '/api/$module/form-fields'
        : '/api/form-fields/$module';

List<FieldSpec> baseRecordFields(String module) => switch (module) {
  'payment_profiles' => paymentProfileFields,
  'bookings' => bookingFields,
  'passports' => passportFields,
  'passport_collection' => passportCollectionFields,
  'refunds' => refundFields,
  'sales' => directSaleFields,
  'airline_customers' => airlineCustomerFields,
  'grocery_products' => groceryProductFields,
  'grocery_suppliers' => supplierFields,
  'grocery_customers' => groceryCustomerFields,
  'grocery_expenses' => expenseFields,
  'grocery_purchases' => purchaseHeaderFields,
  'users' => userFields,
  'quotes' => quoteFields,
  'cases' =>
    airlineModules.firstWhere((module) => module.key == 'cases').fields,
  'company_assets' || 'grocery_company_assets' => companyAssetFields,
  _ => const <FieldSpec>[],
};

List<FieldSpec> recordFieldsFor(String module, dynamic response) {
  final config = asMap(response);
  final removed =
      (config['removed'] is List ? config['removed'] as List : [])
          .map((value) => value.toString())
          .toSet();
  final labels = asMap(config['labels']);
  final fields = <FieldSpec>[
    for (final field in baseRecordFields(module))
      if (!removed.contains(field.key))
        FieldSpec(
          field.key,
          labels[field.key]?.toString() ?? field.label,
          type: field.type,
          required: field.required,
          choices: field.choices,
          initial: field.initial,
          hint: field.hint,
        ),
  ];
  for (final custom in asRows(config['custom'])) {
    final key = custom['key']?.toString() ?? '';
    final label = custom['label']?.toString() ?? '';
    if (!key.startsWith('custom_') || label.isEmpty) continue;
    final type = FieldType.values.firstWhere(
      (value) => value.name == custom['type'],
      orElse: () => FieldType.text,
    );
    fields.add(
      FieldSpec(
        key,
        label,
        type: type,
        required: custom['required'] == true,
        choices:
            (custom['choices'] is List ? custom['choices'] as List : [])
                .map((value) => value.toString())
                .toList(),
      ),
    );
  }
  final order =
      config['order'] is List
          ? (config['order'] as List).map((value) => value.toString()).toList()
          : <String>[];
  if (order.isNotEmpty) {
    final positions = <String, int>{
      for (var index = 0; index < fields.length; index++)
        fields[index].key: index,
    };
    final requested = <String, int>{
      for (var index = 0; index < order.length; index++) order[index]: index,
    };
    fields.sort((a, b) {
      final left = requested[a.key] ?? order.length + positions[a.key]!;
      final right = requested[b.key] ?? order.length + positions[b.key]!;
      return left.compareTo(right);
    });
  }
  return fields;
}

List<FieldSpec> bookingFieldsFor(dynamic response) =>
    recordFieldsFor('bookings', response);

Future<List<FieldSpec>> loadRecordFields(ApiClient api, String module) async =>
    recordFieldsFor(module, await api.get(recordFormPath(module)));

Future<List<FieldSpec>> loadBookingFields(ApiClient api) async =>
    loadRecordFields(api, 'bookings');

Future<bool> showRecordFieldsManager(
  BuildContext context,
  ApiClient api,
  String module,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _BookingFieldsManager(api: api, module: module),
    ) ??
    false;

Future<bool> showBookingFieldsManager(
  BuildContext context,
  ApiClient api,
) async => showRecordFieldsManager(context, api, 'bookings');

class _BookingFieldsManager extends StatefulWidget {
  const _BookingFieldsManager({required this.api, required this.module});
  final ApiClient api;
  final String module;
  @override
  State<_BookingFieldsManager> createState() => _BookingFieldsManagerState();
}

class _BookingFieldsManagerState extends State<_BookingFieldsManager> {
  late Future<dynamic> _future = widget.api.get(recordFormPath(widget.module));
  bool changed = false;
  bool busy = false;
  String? error;

  String get formName => switch (widget.module) {
    'payment_profiles' => 'Payment account',
    'bookings' => 'Booking',
    'passports' => 'Passport service',
    'passport_collection' => 'Passport collection',
    'refunds' => 'Refund',
    'airline_customers' || 'grocery_customers' => 'Customer',
    'grocery_products' => 'Product',
    'grocery_suppliers' => 'Supplier',
    'grocery_expenses' => 'Expense',
    'grocery_purchases' => 'Purchase order',
    'users' => 'Employee',
    'sales' => 'Sale',
    'cases' => 'Support case',
    'quotes' => 'Quotation',
    'company_assets' || 'grocery_company_assets' => 'Company asset',
    _ => 'Record',
  };

  bool isProtected(FieldSpec field) =>
      (protectedFormFields[widget.module] ?? const <String>{}).contains(
        field.key,
      );

  void _refresh() => setState(() {
    _future = widget.api.get(recordFormPath(widget.module));
  });

  Future<void> _move(List<FieldSpec> fields, int index, int direction) async {
    final target = index + direction;
    if (target < 0 || target >= fields.length) return;
    final order = fields.map((field) => field.key).toList();
    final current = order[index];
    order[index] = order[target];
    order[target] = current;
    await _write('PATCH', {'order': order});
  }

  Future<void> _write(String method, Map<String, dynamic> body) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(method, recordFormPath(widget.module), body);
      if (!mounted) return;
      changed = true;
      _refresh();
    } catch (failure) {
      if (mounted) {
        final message = failure.toString();
        setState(() {
          error =
              method == 'PATCH' &&
                      body.containsKey('order') &&
                      message.contains('Invalid field or label')
                  ? 'The local backend is out of date. Stop its PowerShell window '
                      'with Ctrl+C, then start it again.'
                  : message;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _add() async {
    final result = await showRecordForm(context, 'Add field', const [
      FieldSpec('label', 'Field name', required: true),
      FieldSpec(
        'type',
        'Field type',
        type: FieldType.choice,
        choices: ['text', 'paragraph', 'number', 'date', 'choice'],
        initial: 'text',
      ),
      FieldSpec('choices', 'Dropdown options (comma-separated)'),
      FieldSpec('required', 'Required field', type: FieldType.toggle),
    ]);
    if (result == null || !mounted) return;
    if (result['type'] == 'choice' &&
        result['choices'].toString().trim().isEmpty) {
      setState(() => error = 'Enter at least one dropdown option.');
      return;
    }
    await _write('POST', {
      'label': result['label'],
      'type': result['type'],
      'required': result['required'] == true,
      'choices':
          result['choices']
              .toString()
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
    });
  }

  Future<void> _rename(FieldSpec field) async {
    final result = await showRecordForm(
      context,
      'Rename field',
      const [FieldSpec('label', 'Field name', required: true)],
      initial: {'label': field.label},
    );
    if (result == null || !mounted) return;
    await _write('PATCH', {'key': field.key, 'label': result['label']});
  }

  Future<void> _delete(FieldSpec field) async {
    if (isProtected(field)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Remove ${field.label} from form?'),
            content: const Text(
              'This hides the field from the active form and table. Existing '
              'record values are retained, and the field can be restored later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove field'),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) {
      await _write('DELETE', {'key': field.key});
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650, maxHeight: 750),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$formName form fields',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed:
                      busy ? null : () => Navigator.pop(context, changed),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add field'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<dynamic>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    if (snapshot.hasError) {
                      return Center(child: Text(snapshot.error.toString()));
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  final config = asMap(snapshot.data);
                  final fields = recordFieldsFor(widget.module, config);
                  final removed =
                      (config['removed'] is List
                              ? config['removed'] as List
                              : [])
                          .map((item) => item.toString())
                          .toSet();
                  final archived = asRows(config['archivedCustom']);
                  return ListView(
                    key: PageStorageKey('form-field-list-${widget.module}'),
                    children: [
                      for (var index = 0; index < fields.length; index++)
                        ListTile(
                          dense: true,
                          title: Text(
                            fields[index].label,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Move ${fields[index].label} up',
                                onPressed:
                                    busy || index == 0
                                        ? null
                                        : () => _move(fields, index, -1),
                                icon: const Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 20,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 34,
                                  height: 40,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              IconButton(
                                tooltip: 'Move ${fields[index].label} down',
                                onPressed:
                                    busy || index == fields.length - 1
                                        ? null
                                        : () => _move(fields, index, 1),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 20,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 34,
                                  height: 40,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              IconButton(
                                tooltip: 'Rename ${fields[index].label}',
                                onPressed:
                                    busy ? null : () => _rename(fields[index]),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                constraints: const BoxConstraints.tightFor(
                                  width: 34,
                                  height: 40,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              IconButton(
                                tooltip:
                                    isProtected(fields[index])
                                        ? 'Required for this workflow'
                                        : 'Delete ${fields[index].label}',
                                onPressed:
                                    busy || isProtected(fields[index])
                                        ? null
                                        : () => _delete(fields[index]),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 34,
                                  height: 40,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                      if (removed.isNotEmpty || archived.isNotEmpty) ...[
                        const Divider(),
                        for (final field in baseRecordFields(widget.module))
                          if (removed.contains(field.key))
                            ListTile(
                              title: Text(field.label),
                              trailing: TextButton(
                                onPressed:
                                    busy
                                        ? null
                                        : () => _write('POST', {
                                          'restoreKey': field.key,
                                        }),
                                child: const Text('Restore'),
                              ),
                            ),
                        for (final field in archived)
                          ListTile(
                            title: Text(field['label']?.toString() ?? 'Field'),
                            trailing: TextButton(
                              onPressed:
                                  busy
                                      ? null
                                      : () => _write('POST', {
                                        'restoreKey': field['key'],
                                      }),
                              child: const Text('Restore'),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: busy ? null : () => Navigator.pop(context, changed),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
