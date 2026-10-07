import 'package:flutter/material.dart';
import 'api.dart';
import 'modules.dart';
import 'payment_methods.dart';

const _paymentDetailFields = <FieldSpec>[
  FieldSpec('bankName', 'Bank name'),
  FieldSpec('accountName', 'Account / wallet name'),
  FieldSpec('accountNumber', 'Bank account number'),
  FieldSpec('branch', 'Bank branch'),
  FieldSpec('bankDetails', 'Other bank details'),
  FieldSpec('walletNumber', 'Wallet number'),
  FieldSpec('transactionId', 'Transaction reference'),
];

List<FieldSpec> _withPaymentDetails(List<FieldSpec> fields) {
  if (!fields.any((field) => field.key == 'paymentMethod')) return fields;
  final keys = fields.map((field) => field.key).toSet();
  return [
    ...fields,
    for (final field in _paymentDetailFields)
      if (!keys.contains(field.key)) field,
  ];
}

/// Schema driven forms keep the field names aligned with the existing Express API.
Future<Map<String, dynamic>?> showRecordForm(
  BuildContext context,
  String title,
  List<FieldSpec> fields, {
  ApiClient? api,
  Map<String, dynamic> initial = const {},
  Future<List<FieldSpec>?> Function()? onManageFields,
}) async {
  var profiles = <PaymentProfile>[];
  var types = <PaymentMethodType>[];
  final usesPaymentTypes =
      api != null &&
      fields.any(
        (field) =>
            field.key == 'paymentMethod' || field.key == 'defaultPaymentMethod',
      );
  if (usesPaymentTypes) {
    try {
      final repository = PaymentMethodsRepository(api);
      types = await repository.listTypes();
      profiles = await repository.list();
    } catch (_) {
      // Manual entry remains available if saved profiles cannot be loaded.
    }
  }
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder:
        (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 850),
            child: _RecordForm(
              title: title,
              fields: fields,
              initial: initial,
              profiles: profiles,
              types: types,
              usePaymentTypes: usesPaymentTypes,
              onManageFields: onManageFields,
            ),
          ),
        ),
  );
}

class _RecordForm extends StatefulWidget {
  const _RecordForm({
    required this.title,
    required this.fields,
    required this.initial,
    required this.profiles,
    required this.types,
    required this.usePaymentTypes,
    this.onManageFields,
  });
  final String title;
  final List<FieldSpec> fields;
  final Map<String, dynamic> initial;
  final List<PaymentProfile> profiles;
  final List<PaymentMethodType> types;
  final bool usePaymentTypes;
  final Future<List<FieldSpec>?> Function()? onManageFields;
  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, dynamic> _values;
  late List<FieldSpec> _fields;
  String? _selectedProfileId;

  String get _paymentKind {
    final method = _values['paymentMethod']?.toString() ?? '';
    for (final type in widget.types) {
      if (type.id == method) return type.kind;
    }
    return switch (method) {
      'Bank' => 'bank',
      'eSewa' || 'Khalti' => 'digital',
      'Cash' => 'cash',
      _ => 'other',
    };
  }

  List<FieldSpec> _configuredFields(List<FieldSpec> fields) =>
      _withPaymentDetails(fields).map((field) {
        if (!widget.usePaymentTypes ||
            !{'paymentMethod', 'defaultPaymentMethod'}.contains(field.key)) {
          return field;
        }
        return FieldSpec(
          field.key,
          field.label,
          type: field.type,
          required: field.required,
          choices: [
            if (field.choices.contains('')) '',
            ...widget.types.where((item) => item.active).map((item) => item.id),
          ],
          initial:
              widget.types.any(
                    (item) => item.active && item.id == field.initial,
                  )
                  ? field.initial
                  : (field.choices.contains('')
                      ? ''
                      : widget.types
                          .where((item) => item.active)
                          .firstOrNull
                          ?.id),
          hint: field.hint,
        );
      }).toList();

  @override
  void initState() {
    super.initState();
    _values = <String, dynamic>{};
    _fields = _configuredFields(widget.fields);
    _selectedProfileId = widget.initial['paymentProfileId']?.toString();
    _controllers = <String, TextEditingController>{};
    for (final field in _fields) {
      final value =
          widget.initial.containsKey(field.key)
              ? widget.initial[field.key]
              : field.initial;
      if (field.type == FieldType.choice || field.type == FieldType.toggle) {
        _values[field.key] =
            value ??
            (field.type == FieldType.toggle
                ? false
                : field.choices.firstOrNull);
      } else {
        _controllers[field.key] = TextEditingController(
          text: value?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(FieldSpec field) {
    if (field.type == FieldType.toggle) {
      return SwitchListTile.adaptive(
        title: Text(field.label),
        value: _values[field.key] == true,
        onChanged: (value) => setState(() => _values[field.key] = value),
      );
    }
    if (field.type == FieldType.choice) {
      final choices = <String>{...field.choices};
      final current = _values[field.key]?.toString() ?? '';
      if (!choices.contains(current)) choices.add(current);
      return DropdownButtonFormField<String>(
        value: current,
        decoration: InputDecoration(labelText: field.label),
        isExpanded: true,
        items:
            choices
                .map(
                  (choice) => DropdownMenuItem(
                    value: choice,
                    child: Text(
                      choice.isEmpty
                          ? 'Select'
                          : {
                            'paymentMethod',
                            'defaultPaymentMethod',
                          }.contains(field.key)
                          ? widget.types
                                  .where((item) => item.id == choice)
                                  .firstOrNull
                                  ?.name ??
                              choice
                          : choice,
                    ),
                  ),
                )
                .toList(),
        onChanged:
            (value) => setState(() {
              _values[field.key] = value;
              if (field.key == 'paymentMethod') _selectedProfileId = null;
            }),
        validator:
            (value) =>
                field.required && (value == null || value.isEmpty)
                    ? '${field.label} is required'
                    : null,
      );
    }
    final controller = _controllers[field.key]!;
    return TextFormField(
      controller: controller,
      obscureText: field.type == FieldType.password,
      keyboardType:
          field.type == FieldType.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
      maxLines: field.type == FieldType.paragraph ? 3 : 1,
      readOnly: field.type == FieldType.date,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        suffixIcon:
            field.type == FieldType.date
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : null,
      ),
      onTap:
          field.type == FieldType.date
              ? () async {
                final initial =
                    DateTime.tryParse(controller.text) ?? DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2150),
                );
                if (picked != null) {
                  controller.text = picked.toIso8601String().substring(0, 10);
                }
              }
              : null,
      validator: (value) {
        final kind = _paymentKind;
        if (field.key == 'bankName' &&
            kind == 'bank' &&
            (value == null || value.trim().isEmpty)) {
          return 'Bank name is required';
        }
        if (field.key == 'walletNumber' &&
            kind == 'digital' &&
            (value == null || value.trim().isEmpty)) {
          return 'Wallet number is required';
        }
        if (field.required && (value == null || value.trim().isEmpty)) {
          return '${field.label} is required';
        }
        if (field.type == FieldType.number &&
            value != null &&
            value.isNotEmpty &&
            num.tryParse(value) == null) {
          return 'Enter a valid number';
        }
        return null;
      },
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final result = Map<String, dynamic>.from(_values);
    for (final field in _fields) {
      if (!_controllers.containsKey(field.key)) continue;
      final value = _controllers[field.key]!.text.trim();
      result[field.key] =
          field.type == FieldType.number ? (num.tryParse(value) ?? 0) : value;
    }
    if (_fields.any((field) => field.key == 'paymentMethod')) {
      result['paymentProfileId'] = _selectedProfileId ?? '';
      for (final field in _paymentDetailFields) {
        if (!_paymentFieldVisible(field.key)) result[field.key] = '';
      }
    }
    Navigator.pop(context, result);
  }

  bool _paymentFieldVisible(String key) {
    if (!_fields.any((field) => field.key == 'paymentMethod')) return true;
    final kind = _paymentKind;
    if (const {
      'bankName',
      'bankDetails',
      'accountNumber',
      'branch',
    }.contains(key)) {
      return kind == 'bank';
    }
    if (key == 'walletNumber') return kind == 'digital';
    if (key == 'accountName' || key == 'transactionId') {
      return kind == 'bank' || kind == 'digital' || kind == 'other';
    }
    return true;
  }

  Widget _profilePicker(double width) {
    final method = _values['paymentMethod']?.toString() ?? '';
    final available =
        widget.profiles
            .where((profile) => profile.active && profile.method == method)
            .toList();
    if (available.isEmpty) return const SizedBox.shrink();
    final selected =
        available.any((item) => item.id == _selectedProfileId)
            ? _selectedProfileId!
            : '';
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: selected,
        decoration: const InputDecoration(labelText: 'Saved payment details'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Enter manually')),
          ...available.map(
            (profile) =>
                DropdownMenuItem(value: profile.id, child: Text(profile.label)),
          ),
        ],
        onChanged: (value) {
          final chosen =
              available.where((item) => item.id == value).firstOrNull;
          setState(() {
            _selectedProfileId = chosen?.id;
            for (final entry
                in {
                  'bankName': chosen?.bankName ?? '',
                  'accountName': chosen?.accountName ?? '',
                  'accountNumber': chosen?.accountNumber ?? '',
                  'branch': chosen?.branch ?? '',
                  'walletNumber': chosen?.walletNumber ?? '',
                }.entries) {
              _controllers[entry.key]?.text = entry.value;
            }
          });
        },
      ),
    );
  }

  Future<void> _manageFields() async {
    final updated = await widget.onManageFields?.call();
    if (updated == null || !mounted) return;
    final allFields = _configuredFields(updated);
    final newKeys = allFields.map((field) => field.key).toSet();
    for (final key in _controllers.keys.toList()) {
      if (!newKeys.contains(key)) {
        _controllers.remove(key)?.dispose();
        _values.remove(key);
      }
    }
    _values.removeWhere((key, _) => !newKeys.contains(key));
    for (final field in allFields) {
      if (_controllers.containsKey(field.key) ||
          _values.containsKey(field.key)) {
        continue;
      }
      if (field.type == FieldType.choice || field.type == FieldType.toggle) {
        _values[field.key] =
            field.initial ??
            (field.type == FieldType.toggle
                ? false
                : field.choices.firstOrNull);
      } else {
        _controllers[field.key] = TextEditingController(
          text: widget.initial[field.key]?.toString() ?? '',
        );
      }
    }
    setState(() => _fields = allFields);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (widget.onManageFields != null)
              IconButton(
                tooltip: 'Manage form fields',
                onPressed: _manageFields,
                icon: const Icon(Icons.tune),
              ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    constraints.maxWidth < 560
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2;
                return SingleChildScrollView(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      for (final field in _fields)
                        if (!const {
                              'bankName',
                              'bankDetails',
                              'accountName',
                              'accountNumber',
                              'branch',
                              'walletNumber',
                              'transactionId',
                            }.contains(field.key) ||
                            _paymentFieldVisible(field.key)) ...[
                          SizedBox(
                            width:
                                field.type == FieldType.paragraph
                                    ? constraints.maxWidth
                                    : width,
                            child: _field(field),
                          ),
                          if (field.key == 'paymentMethod')
                            _profilePicker(width),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ),
      ],
    ),
  );
}
