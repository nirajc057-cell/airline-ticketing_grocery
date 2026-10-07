import 'state.dart';
import 'booking_fields.dart';

const supportedPaymentMethods = {'Cash', 'eSewa', 'Khalti', 'Bank'};

const defaultPaymentTypes = <Map<String, dynamic>>[
  {'id': 'Cash', 'name': 'Cash', 'kind': 'cash', 'active': true},
  {'id': 'eSewa', 'name': 'eSewa', 'kind': 'digital', 'active': true},
  {'id': 'Khalti', 'name': 'Khalti', 'kind': 'digital', 'active': true},
  {'id': 'Bank', 'name': 'Bank', 'kind': 'bank', 'active': true},
];

List<Map<String, dynamic>> paymentTypes(Map<String, dynamic> state) =>
    state['paymentTypes'] is List
        ? records(state['paymentTypes'])
        : defaultPaymentTypes
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

Map<String, dynamic>? activePaymentType(Map<String, dynamic> state, String id) {
  for (final item in paymentTypes(state)) {
    if (item['id'] == id && item['active'] != false) return item;
  }
  return null;
}

Map<String, dynamic> normalizePaymentType(Map<String, dynamic> input) {
  final name = _string(input['name']);
  final kind = _string(input['kind']);
  if (name.isEmpty ||
      name.length > 60 ||
      !RegExp(r'^[\p{L}\p{N}][\p{L}\p{N} ._+&()/\-]*$', unicode: true)
          .hasMatch(name)) {
    throw const FormatException('Enter a short payment method name');
  }
  if (!{'cash', 'bank', 'digital', 'other'}.contains(kind)) {
    throw const FormatException('Choose a payment method type');
  }
  return {'name': name, 'kind': kind, 'active': input['active'] != false};
}

String _string(Object? value) => value?.toString().trim() ?? '';

double _amount(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_string(value)) ?? double.nan;
}

Map<String, dynamic> normalizePaymentProfile(Map<String, dynamic> input,
    {Map<String, dynamic>? state}) {
  final method = _string(input['method']);
  final label = _string(input['label']);
  final type = state == null ? null : activePaymentType(state, method);
  if ((state == null
          ? !supportedPaymentMethods.contains(method)
          : type == null) ||
      label.isEmpty ||
      label.length > 80) {
    throw const FormatException('Choose a payment method and a short name');
  }
  final result = <String, dynamic>{
    'method': method,
    'label': label,
    'active': input['active'] != false,
  };
  final kind = _string(type?['kind']);
  final config = state == null
      ? <String, dynamic>{}
      : recordFormConfig(state, 'payment_profiles');
  final removed =
      (config['removed'] is List ? config['removed'] as List : const <Object>[])
          .map((item) => item.toString())
          .toSet();
  final allowed = switch (kind.isEmpty ? method : kind) {
    'bank' || 'Bank' => ['bankName', 'accountName', 'accountNumber', 'branch'],
    'digital' || 'eSewa' || 'Khalti' => ['accountName', 'walletNumber'],
    _ => <String>[],
  };
  for (final key in [...allowed, 'instructions']) {
    if (removed.contains(key)) continue;
    final value = _string(input[key]);
    if (value.length > (key == 'instructions' ? 500 : 120)) {
      throw FormatException('$key is too long');
    }
    result[key] = value;
  }
  for (final field in records(config['custom'])) {
    final key = _string(field['key']);
    if (!key.startsWith('custom_')) continue;
    final value = _string(input[key]);
    final numeric = double.tryParse(value);
    if (value.length > 500 ||
        (field['required'] == true && value.isEmpty) ||
        (field['type'] == 'number' &&
            value.isNotEmpty &&
            (numeric == null || !numeric.isFinite)) ||
        (field['type'] == 'date' &&
            value.isNotEmpty &&
            DateTime.tryParse(value) == null) ||
        (field['type'] == 'choice' &&
            value.isNotEmpty &&
            !(field['choices'] is List &&
                (field['choices'] as List).contains(value)))) {
      throw FormatException('Invalid value for ${field['label']}');
    }
    result[key] = value;
  }
  if (!removed.contains('bankName') &&
      (kind == 'bank' || (kind.isEmpty && method == 'Bank')) &&
      _string(result['bankName']).isEmpty) {
    throw const FormatException('Bank name is required');
  }
  if (!removed.contains('walletNumber') &&
      (kind == 'digital' ||
          (kind.isEmpty && (method == 'eSewa' || method == 'Khalti'))) &&
      _string(result['walletNumber']).isEmpty) {
    throw const FormatException('Wallet number is required');
  }
  return result;
}

List<Map<String, dynamic>> validatedPayments(
  Map<String, dynamic> state,
  Map<String, dynamic> body,
  double max, {
  bool exact = false,
}) {
  final payments = records(body['payments']);
  if (payments.isEmpty || !max.isFinite || max <= 0) {
    throw const FormatException('Enter at least one payment');
  }
  final profiles = records(state['paymentProfiles']);
  final result = <Map<String, dynamic>>[];
  var total = 0.0;
  for (final payment in payments) {
    final method = _string(payment['method']);
    final type = activePaymentType(state, method);
    final amount = _amount(payment['amount']);
    if (type == null || !amount.isFinite || amount <= 0) {
      throw const FormatException('Invalid payment method or amount');
    }
    final profileId = _string(payment['profileId']);
    Map<String, dynamic>? profile;
    if (profileId.isNotEmpty) {
      for (final item in profiles) {
        if (item['id'] == profileId) profile = item;
      }
      if (profile == null ||
          profile['active'] == false ||
          profile['method'] != method) {
        throw const FormatException('Saved payment method is unavailable');
      }
    }
    String detail(String key) {
      final provided = _string(payment[key]);
      return provided.isNotEmpty ? provided : _string(profile?[key]);
    }

    final entry = <String, dynamic>{'method': method, 'amount': amount};
    if (profile != null) entry['profileId'] = profileId;
    if (profile != null) {
      for (final item in profile.entries) {
        if (item.key.startsWith('custom_')) entry[item.key] = item.value;
      }
    }
    final kind = _string(type['kind']);
    entry['methodName'] = _string(type['name']);
    if (kind == 'bank') {
      for (final key in [
        'bankName',
        'accountName',
        'accountNumber',
        'branch',
        'bankDetails',
        'transactionId',
      ]) {
        entry[key] = detail(key);
      }
      if (_string(entry['bankName']).isEmpty) {
        throw const FormatException('Bank name is required');
      }
    } else if (kind == 'digital') {
      for (final key in ['accountName', 'walletNumber', 'transactionId']) {
        entry[key] = detail(key);
      }
      if (_string(entry['walletNumber']).isEmpty) {
        throw FormatException('$method wallet number is required');
      }
    } else if (kind == 'other') {
      entry['transactionId'] = detail('transactionId');
      entry['accountName'] = detail('accountName');
    }
    for (final value in entry.values.whereType<String>()) {
      if (value.length > 500) {
        throw const FormatException('Payment detail is too long');
      }
    }
    total += amount;
    result.add(entry);
  }
  if (total > max + .009 || (exact && (total - max).abs() > .009)) {
    throw const FormatException('Payment amounts do not match the amount due');
  }
  return result;
}
