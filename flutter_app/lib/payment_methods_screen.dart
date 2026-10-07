import 'package:flutter/material.dart';

import 'api.dart';
import 'booking_form_fields.dart';
import 'modules.dart';
import 'payment_methods.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({
    super.key,
    required this.api,
    required this.user,
    required this.message,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final ValueChanged<String> message;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  late Future<List<PaymentProfile>> future = repository.list();
  late Future<List<PaymentMethodType>> typesFuture = repository.listTypes();

  PaymentMethodsRepository get repository =>
      PaymentMethodsRepository(widget.api);
  bool get canManage => const {
    'Agency owner',
    'Agency administrator',
  }.contains(widget.user['role']);

  void reload() => setState(() {
    future = repository.list();
    typesFuture = repository.listTypes();
  });

  Future<void> editType([PaymentMethodType? existing]) async {
    final result = await showDialog<PaymentMethodType>(
      context: context,
      builder: (_) => _PaymentTypeEditor(existing: existing),
    );
    if (result == null) return;
    try {
      await repository.saveType(result);
      widget.message('Payment system saved');
      if (mounted) reload();
    } catch (error) {
      widget.message(error.toString());
    }
  }

  Future<void> removeType(PaymentMethodType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Delete ${type.name}?'),
            content: const Text(
              'This method will no longer be available for new payments. '
              'Previously recorded transactions keep their payment details.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await repository.deleteType(type.id);
      widget.message('Payment system deleted');
      if (mounted) reload();
    } catch (error) {
      widget.message(error.toString());
    }
  }

  Future<void> edit(
    List<PaymentMethodType> types, [
    PaymentProfile? existing,
  ]) async {
    List<FieldSpec> fields;
    try {
      fields = await loadRecordFields(widget.api, 'payment_profiles');
    } catch (error) {
      widget.message('Could not load payment form fields: $error');
      return;
    }
    if (!mounted) return;
    final result = await showDialog<PaymentProfile>(
      context: context,
      builder:
          (_) => _PaymentProfileEditor(
            existing: existing,
            types: types,
            fields: fields,
            api: widget.api,
            canManage: canManage,
          ),
    );
    if (result == null) return;
    try {
      await repository.save(result);
      widget.message('Payment method saved');
      if (mounted) reload();
    } catch (error) {
      widget.message(error.toString());
    }
  }

  Future<void> remove(PaymentProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Delete ${profile.label}?'),
            content: const Text(
              'This removes the saved method from future payments. Previous '
              'transactions keep the payment details recorded at the time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await repository.delete(profile.id);
      widget.message('Payment method deleted');
      if (mounted) reload();
    } catch (error) {
      widget.message(error.toString());
    }
  }

  Widget profileCard(
    PaymentProfile profile,
    PaymentMethodType type,
    List<PaymentMethodType> types,
  ) {
    final details = switch (type.kind) {
      'bank' => [
        profile.bankName,
        if (profile.accountName.isNotEmpty) profile.accountName,
        if (profile.accountNumber.isNotEmpty) profile.accountNumber,
        if (profile.branch.isNotEmpty) profile.branch,
      ],
      'digital' => [
        profile.walletNumber,
        if (profile.accountName.isNotEmpty) profile.accountName,
      ],
      _ => <String>[],
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  type.kind == 'bank'
                      ? Icons.account_balance_outlined
                      : type.kind == 'cash'
                      ? Icons.payments_outlined
                      : Icons.phone_android_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    profile.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!profile.active) const Chip(label: Text('Inactive')),
                if (canManage) ...[
                  IconButton(
                    tooltip: 'Edit ${profile.label}',
                    onPressed: () => edit(types, profile),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete ${profile.label}',
                    onPressed: () => remove(profile),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(details.join(' · ')),
            ],
            if (profile.instructions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                profile.instructions,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PaymentMethodType>>(
    future: typesFuture,
    builder:
        (context, typesSnapshot) => FutureBuilder<List<PaymentProfile>>(
          future: future,
          builder: (context, snapshot) {
            if ((!snapshot.hasData && !snapshot.hasError) ||
                (!typesSnapshot.hasData && !typesSnapshot.hasError)) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || typesSnapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text((snapshot.error ?? typesSnapshot.error).toString()),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: reload, child: const Text('Retry')),
                  ],
                ),
              );
            }
            final profiles = snapshot.data!;
            final types = typesSnapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment methods',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Manage payment systems and saved accounts in both '
                          'AeroDesk and FreshMart. Past payments are preserved.',
                        ),
                      ],
                    ),
                    if (canManage)
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => editType(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add payment system'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                types.where((item) => item.active).isEmpty
                                    ? null
                                    : () => edit(types),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                            label: const Text('Add saved account'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                for (final type in types) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            type.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(type.kind),
                        if (!type.active)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Chip(label: Text('Inactive')),
                          ),
                        if (canManage) ...[
                          IconButton(
                            tooltip: 'Edit ${type.name}',
                            onPressed: () => editType(type),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete ${type.name}',
                            onPressed: () => removeType(type),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (profiles.where((item) => item.method == type.id).isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        type.kind == 'cash'
                            ? 'Cash can always be used without a saved profile.'
                            : 'No saved ${type.name} details yet. You can still enter '
                                'details manually during a payment.',
                      ),
                    )
                  else
                    ...profiles
                        .where((item) => item.method == type.id)
                        .map((profile) => profileCard(profile, type, types)),
                ],
              ],
            );
          },
        ),
  );
}

class _PaymentTypeEditor extends StatefulWidget {
  const _PaymentTypeEditor({this.existing});
  final PaymentMethodType? existing;

  @override
  State<_PaymentTypeEditor> createState() => _PaymentTypeEditorState();
}

class _PaymentTypeEditorState extends State<_PaymentTypeEditor> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late String kind = widget.existing?.kind ?? 'digital';
  late bool active = widget.existing?.active ?? true;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Add payment system' : 'Edit payment system',
    ),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. IME Pay or Card',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Details to collect'),
            items: const [
              DropdownMenuItem(
                value: 'cash',
                child: Text('Cash - amount only'),
              ),
              DropdownMenuItem(
                value: 'bank',
                child: Text('Bank - bank and account details'),
              ),
              DropdownMenuItem(
                value: 'digital',
                child: Text('Digital wallet - wallet number'),
              ),
              DropdownMenuItem(
                value: 'other',
                child: Text('Other - account name and reference'),
              ),
            ],
            onChanged: (value) => setState(() => kind = value!),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Available for new payments'),
            value: active,
            onChanged: (value) => setState(() => active = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                  context,
                  PaymentMethodType(
                    id: widget.existing?.id ?? '',
                    name: name.text.trim(),
                    kind: kind,
                    active: active,
                  ),
                ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _PaymentProfileEditor extends StatefulWidget {
  const _PaymentProfileEditor({
    this.existing,
    required this.types,
    required this.fields,
    required this.api,
    required this.canManage,
  });
  final PaymentProfile? existing;
  final List<PaymentMethodType> types;
  final List<FieldSpec> fields;
  final ApiClient api;
  final bool canManage;

  @override
  State<_PaymentProfileEditor> createState() => _PaymentProfileEditorState();
}

class _PaymentProfileEditorState extends State<_PaymentProfileEditor> {
  late String method =
      widget.existing?.method ??
      widget.types
          .firstWhere(
            (item) => item.active && item.kind == 'bank',
            orElse: () => widget.types.firstWhere((item) => item.active),
          )
          .id;
  PaymentMethodType get type =>
      widget.types.firstWhere((item) => item.id == method);
  late bool active = widget.existing?.active ?? true;
  late List<FieldSpec> fields = widget.fields;
  String? error;
  late final controllers = <String, TextEditingController>{
    'label': TextEditingController(text: widget.existing?.label ?? ''),
    'bankName': TextEditingController(text: widget.existing?.bankName ?? ''),
    'accountName': TextEditingController(
      text: widget.existing?.accountName ?? '',
    ),
    'accountNumber': TextEditingController(
      text: widget.existing?.accountNumber ?? '',
    ),
    'branch': TextEditingController(text: widget.existing?.branch ?? ''),
    'walletNumber': TextEditingController(
      text: widget.existing?.walletNumber ?? '',
    ),
    'instructions': TextEditingController(
      text: widget.existing?.instructions ?? '',
    ),
    for (final field in widget.fields)
      if (field.key.startsWith('custom_'))
        field.key: TextEditingController(
          text: widget.existing?.customValues[field.key] ?? '',
        ),
  };

  bool get hasBankName => fields.any((field) => field.key == 'bankName');
  bool get hasWalletNumber =>
      fields.any((field) => field.key == 'walletNumber');

  Future<void> manageFields() async {
    final changed = await showRecordFieldsManager(
      context,
      widget.api,
      'payment_profiles',
    );
    if (!changed || !mounted) return;
    try {
      final updated = await loadRecordFields(widget.api, 'payment_profiles');
      if (!mounted) return;
      final keys = updated.map((field) => field.key).toSet();
      for (final key in controllers.keys.toList()) {
        if (!keys.contains(key)) controllers.remove(key)?.dispose();
      }
      for (final field in updated) {
        if (field.key != 'method' &&
            field.key != 'active' &&
            !controllers.containsKey(field.key)) {
          controllers[field.key] = TextEditingController(
            text: widget.existing?.customValues[field.key] ?? '',
          );
        }
      }
      setState(() {
        fields = updated;
        error = null;
      });
    } catch (failure) {
      setState(() => error = failure.toString());
    }
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool visible(FieldSpec spec) {
    if (spec.key.startsWith('custom_')) return true;
    if (const {'bankName', 'accountNumber', 'branch'}.contains(spec.key)) {
      return type.kind == 'bank';
    }
    if (spec.key == 'walletNumber') return type.kind == 'digital';
    if (spec.key == 'accountName') {
      return type.kind == 'bank' ||
          type.kind == 'digital' ||
          type.kind == 'other';
    }
    return true;
  }

  Widget renderField(FieldSpec spec) {
    if (spec.key == 'method') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: method,
          isExpanded: true,
          decoration: InputDecoration(labelText: spec.label),
          items:
              widget.types
                  .where((item) => item.active || item.id == method)
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  )
                  .toList(),
          onChanged: (value) => setState(() => method = value!),
        ),
      );
    }
    if (spec.key == 'active') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(spec.label),
        value: active,
        onChanged: (value) => setState(() => active = value),
      );
    }
    final controller = controllers[spec.key];
    if (controller == null) return const SizedBox.shrink();
    if (spec.type == FieldType.choice) {
      final choices = [...spec.choices];
      if (controller.text.isNotEmpty && !choices.contains(controller.text)) {
        choices.add(controller.text);
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: controller.text.isEmpty ? null : controller.text,
          isExpanded: true,
          decoration: InputDecoration(labelText: spec.label),
          items:
              choices
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
          onChanged: (value) => setState(() => controller.text = value ?? ''),
        ),
      );
    }
    if (spec.type == FieldType.date) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          readOnly: true,
          decoration: InputDecoration(
            labelText: spec.label,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(controller.text) ?? now,
              firstDate: DateTime(1900),
              lastDate: DateTime(2150),
            );
            if (picked != null) {
              setState(
                () =>
                    controller.text = picked.toIso8601String().substring(0, 10),
              );
            }
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: spec.type == FieldType.paragraph ? 3 : 1,
        keyboardType:
            spec.type == FieldType.number
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
        decoration: InputDecoration(labelText: spec.label),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  bool get valid {
    if (controllers['label']?.text.trim().isEmpty ?? true) return false;
    if (type.kind == 'bank' &&
        hasBankName &&
        (controllers['bankName']?.text.trim().isEmpty ?? true)) {
      return false;
    }
    if (type.kind == 'digital' &&
        hasWalletNumber &&
        (controllers['walletNumber']?.text.trim().isEmpty ?? true)) {
      return false;
    }
    for (final spec in fields.where(
      (field) => field.key.startsWith('custom_'),
    )) {
      final value = controllers[spec.key]?.text.trim() ?? '';
      if (spec.required && value.isEmpty) return false;
      if (spec.type == FieldType.number &&
          value.isNotEmpty &&
          num.tryParse(value) == null) {
        return false;
      }
    }
    return true;
  }

  void save() {
    String value(String key) => controllers[key]?.text.trim() ?? '';
    final label = value('label');
    final bankName = value('bankName');
    final walletNumber = value('walletNumber');
    if (!valid) {
      return;
    }
    Navigator.pop(
      context,
      PaymentProfile(
        id: widget.existing?.id ?? '',
        method: method,
        label: label,
        active: active,
        bankName: bankName,
        accountName: value('accountName'),
        accountNumber: value('accountNumber'),
        branch: value('branch'),
        walletNumber: walletNumber,
        instructions: value('instructions'),
        customValues: {
          for (final spec in fields.where(
            (field) => field.key.startsWith('custom_'),
          ))
            spec.key: controllers[spec.key]?.text.trim() ?? '',
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Add payment method'
                          : 'Edit payment method',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (widget.canManage)
                    IconButton(
                      tooltip: 'Manage payment form fields',
                      onPressed: manageFields,
                      icon: const Icon(Icons.tune),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final spec in fields)
                      if (visible(spec)) renderField(spec),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: valid ? save : null,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
