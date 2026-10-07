import 'package:flutter/material.dart';

import 'api.dart';
import 'payment_methods.dart';

Future<Map<String, dynamic>?> showConfiguredSplitPayment(
  BuildContext context, {
  required ApiClient api,
  required double max,
  bool exact = false,
}) async {
  var profiles = <PaymentProfile>[];
  var types = <PaymentMethodType>[];
  String? loadError;
  try {
    final repository = PaymentMethodsRepository(api);
    types = await repository.listTypes();
    profiles = await repository.list();
  } catch (_) {
    loadError =
        'Payment systems are unavailable. Check the local backend connection.';
  }
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder:
        (_) => _SplitPaymentDialog(
          max: max,
          exact: exact,
          profiles: profiles,
          types: types.where((item) => item.active).toList(),
          loadError: loadError,
        ),
  );
}

class _SplitPaymentDialog extends StatefulWidget {
  const _SplitPaymentDialog({
    required this.max,
    required this.exact,
    required this.profiles,
    required this.types,
    this.loadError,
  });
  final double max;
  final bool exact;
  final List<PaymentProfile> profiles;
  final List<PaymentMethodType> types;
  final String? loadError;

  @override
  State<_SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<_SplitPaymentDialog> {
  late final Map<String, TextEditingController> amounts;
  late final Map<String, Map<String, TextEditingController>> details;
  @override
  void initState() {
    super.initState();
    amounts = {
      for (final type in widget.types)
        type.id: TextEditingController(text: '0'),
    };
    details = {
      for (final type in widget.types)
        type.id: {
          for (final key in [
            'bankName',
            'accountName',
            'accountNumber',
            'branch',
            'bankDetails',
            'walletNumber',
            'transactionId',
          ])
            key: TextEditingController(),
        },
    };
  }

  final selectedProfile = <String, String>{};

  @override
  void dispose() {
    for (final controller in amounts.values) {
      controller.dispose();
    }
    for (final method in details.values) {
      for (final controller in method.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  double amountFor(String method) =>
      double.tryParse(amounts[method]!.text.trim()) ?? double.nan;

  double get total =>
      widget.types.fold<double>(0, (sum, type) => sum + amountFor(type.id));

  bool get valid {
    if (widget.types.any(
      (type) => !amountFor(type.id).isFinite || amountFor(type.id) < 0,
    )) {
      return false;
    }
    if (total <= 0 || total > widget.max + .009) {
      return false;
    }
    if (widget.exact && (total - widget.max).abs() > .009) {
      return false;
    }
    for (final type in widget.types) {
      if (amountFor(type.id) > 0 &&
          type.kind == 'bank' &&
          details[type.id]!['bankName']!.text.trim().isEmpty) {
        return false;
      }
      if (amountFor(type.id) > 0 &&
          type.kind == 'digital' &&
          details[type.id]!['walletNumber']!.text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  void chooseProfile(String method, String value) {
    setState(() {
      selectedProfile[method] = value;
      final profile =
          widget.profiles
              .where((item) => item.id == value && item.method == method)
              .firstOrNull;
      final target = details[method]!;
      target['bankName']!.text = profile?.bankName ?? '';
      target['accountName']!.text = profile?.accountName ?? '';
      target['accountNumber']!.text = profile?.accountNumber ?? '';
      target['branch']!.text = profile?.branch ?? '';
      target['walletNumber']!.text = profile?.walletNumber ?? '';
      target['bankDetails']!.clear();
      target['transactionId']!.clear();
    });
  }

  Widget detailField(String method, String key, String label) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: TextField(
      controller: details[method]![key],
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    ),
  );

  Widget methodCard(PaymentMethodType type) {
    final method = type.id;
    final activeProfiles =
        widget.profiles
            .where((profile) => profile.active && profile.method == method)
            .toList();
    final chosen = selectedProfile[method] ?? '';
    final profile =
        activeProfiles.where((item) => item.id == chosen).firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              key: ValueKey('payment-amount-$method'),
              controller: amounts[method],
              decoration: InputDecoration(labelText: '${type.name} amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (amountFor(method) > 0) ...[
              if (activeProfiles.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: chosen,
                  decoration: const InputDecoration(labelText: 'Saved details'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Enter manually'),
                    ),
                    ...activeProfiles.map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => chooseProfile(method, value ?? ''),
                ),
              ],
              if (profile != null && profile.instructions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  profile.instructions,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (type.kind == 'bank') ...[
                detailField(method, 'bankName', 'Bank name *'),
                detailField(method, 'accountName', 'Account holder'),
                detailField(method, 'accountNumber', 'Account number'),
                detailField(method, 'branch', 'Branch'),
                detailField(method, 'transactionId', 'Transaction reference'),
                detailField(method, 'bankDetails', 'Other bank details'),
              ],
              if (type.kind == 'digital') ...[
                detailField(method, 'accountName', 'Wallet account name'),
                detailField(method, 'walletNumber', 'Wallet number *'),
                detailField(method, 'transactionId', 'Transaction ID'),
              ],
              if (type.kind == 'other') ...[
                detailField(method, 'accountName', 'Account / source name'),
                detailField(method, 'transactionId', 'Transaction reference'),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void submit() {
    if (!valid) return;
    Navigator.pop(context, {
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'payments': [
        for (final type in widget.types)
          if (amountFor(type.id) > 0)
            {
              'method': type.id,
              'amount': amountFor(type.id),
              if ((selectedProfile[type.id] ?? '').isNotEmpty)
                'profileId': selectedProfile[type.id],
              if (type.kind == 'bank')
                for (final key in [
                  'bankName',
                  'accountName',
                  'accountNumber',
                  'branch',
                  'transactionId',
                  'bankDetails',
                ])
                  key: details[type.id]![key]!.text.trim(),
              if (type.kind == 'digital' || type.kind == 'other')
                for (final key in [
                  'accountName',
                  'walletNumber',
                  'transactionId',
                ])
                  key: details[type.id]![key]!.text.trim(),
            },
      ],
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(14),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 820),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record payment',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            Text(
              widget.exact
                  ? 'Enter exactly ${widget.max.toStringAsFixed(2)} across one or more methods.'
                  : 'Outstanding ${widget.max.toStringAsFixed(2)}. Partial payment is allowed.',
            ),
            if (widget.loadError != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.loadError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [for (final type in widget.types) methodCard(type)],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Entered ${total.isFinite ? total.toStringAsFixed(2) : '—'} · '
              'Remaining ${total.isFinite ? (widget.max - total).toStringAsFixed(2) : '—'}',
              style: TextStyle(
                color: valid ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: valid ? submit : null,
                  child: const Text('Record payment'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
