import 'api.dart';

class PaymentMethodType {
  const PaymentMethodType({
    required this.id,
    required this.name,
    required this.kind,
    this.active = true,
  });

  final String id;
  final String name;
  final String kind;
  final bool active;

  factory PaymentMethodType.fromJson(Map<String, dynamic> value) =>
      PaymentMethodType(
        id: value['id']?.toString() ?? '',
        name: value['name']?.toString() ?? '',
        kind: value['kind']?.toString() ?? 'other',
        active: value['active'] != false,
      );

  Map<String, dynamic> toPayload() => {
    'name': name,
    'kind': kind,
    'active': active,
  };
}

class PaymentProfile {
  const PaymentProfile({
    required this.id,
    required this.method,
    required this.label,
    required this.active,
    this.bankName = '',
    this.accountName = '',
    this.accountNumber = '',
    this.branch = '',
    this.walletNumber = '',
    this.instructions = '',
    this.customValues = const {},
  });

  final String id;
  final String method;
  final String label;
  final bool active;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String branch;
  final String walletNumber;
  final String instructions;
  final Map<String, String> customValues;

  factory PaymentProfile.fromJson(Map<String, dynamic> value) => PaymentProfile(
    id: value['id']?.toString() ?? '',
    method: value['method']?.toString() ?? '',
    label: value['label']?.toString() ?? '',
    active: value['active'] != false,
    bankName: value['bankName']?.toString() ?? '',
    accountName: value['accountName']?.toString() ?? '',
    accountNumber: value['accountNumber']?.toString() ?? '',
    branch: value['branch']?.toString() ?? '',
    walletNumber: value['walletNumber']?.toString() ?? '',
    instructions: value['instructions']?.toString() ?? '',
    customValues: {
      for (final entry in value.entries)
        if (entry.key.startsWith('custom_'))
          entry.key: entry.value?.toString() ?? '',
    },
  );

  Map<String, dynamic> toPayload() => {
    'method': method,
    'label': label,
    'active': active,
    'bankName': bankName,
    'accountName': accountName,
    'accountNumber': accountNumber,
    'branch': branch,
    'walletNumber': walletNumber,
    'instructions': instructions,
    ...customValues,
  };
}

class PaymentMethodsRepository {
  const PaymentMethodsRepository(this.api);
  final ApiClient api;

  Future<List<PaymentMethodType>> listTypes() async =>
      asRows(
        await api.get('/api/payment-method-types'),
      ).map(PaymentMethodType.fromJson).toList();

  Future<PaymentMethodType> saveType(PaymentMethodType type) async {
    final value = await api.request(
      type.id.isEmpty ? 'POST' : 'PATCH',
      type.id.isEmpty
          ? '/api/payment-method-types'
          : '/api/payment-method-types/${type.id}',
      type.toPayload(),
    );
    return PaymentMethodType.fromJson(asMap(value));
  }

  Future<void> deleteType(String id) async {
    await api.request('DELETE', '/api/payment-method-types/$id');
  }

  Future<List<PaymentProfile>> list() async =>
      asRows(
        await api.get('/api/payment-methods'),
      ).map(PaymentProfile.fromJson).toList();

  Future<PaymentProfile> save(PaymentProfile profile) async {
    final value = await api.request(
      profile.id.isEmpty ? 'POST' : 'PATCH',
      profile.id.isEmpty
          ? '/api/payment-methods'
          : '/api/payment-methods/${profile.id}',
      profile.toPayload(),
    );
    return PaymentProfile.fromJson(asMap(value));
  }

  Future<void> delete(String id) async {
    await api.request('DELETE', '/api/payment-methods/$id');
  }
}
