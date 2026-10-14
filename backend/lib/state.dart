import 'dart:convert';

Map<String, dynamic> asObject(Object? value) {
  if (value is String) return asObject(jsonDecode(value));
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> records(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.map(asObject).toList();
}

Map<String, dynamic> emptyWorkspace(String email) => {
      'settings': {
        'agencyName': 'New workspace',
        'currency': 'NPR',
        'locale': 'en-NP',
        'platformComplete': true,
        'ticketApproval': false,
      },
      'users': [
        {
          'id': 'USR-001',
          'email': email,
          'name': email.split('@').first,
          'role': 'Agency owner',
          'active': true,
          'mustChangePassword': true,
          'twoFactorEnabled': false,
          'permissions': <String, bool>{},
        },
      ],
      'roles': <Object>[],
      'bookings': <Object>[],
      'bookingForm': {
        'removed': <String>[],
        'custom': <Object>[],
        'labels': <String, String>{},
        'order': <String>[],
      },
      'passportForm': {
        'removed': <String>[],
        'custom': <Object>[],
        'labels': <String, String>{},
        'order': <String>[],
      },
      'refundForm': {
        'removed': <String>[],
        'custom': <Object>[],
        'labels': <String, String>{},
        'order': <String>[],
      },
      'customers': <Object>[],
      'quotes': <Object>[],
      'sales': <Object>[],
      'refunds': <Object>[],
      'cases': <Object>[],
      'passportServices': <Object>[],
      'ledger': <Object>[],
      'walletTransactions': <Object>[],
      'paymentProfiles': <Object>[],
      'workTasks': <Object>[],
      'workspaces': <Object>[],
      'markups': <Object>[],
      'notifications': <Object>[],
      'audit': <Object>[],
      'tableColumns': {'bookings': <Object>[], 'products': <Object>[]},
      'tableSetup': <String, Object>{},
      'tableDrafts': {'bookings': <Object>[], 'products': <Object>[]},
      'tableLayouts': <String, Object>{},
      'customTables': <Object>[],
      'companyAssets': <Object>[],
      'wallet': {
        'balance': 0,
        'creditLimit': 0,
        'usedCredit': 0,
        'currency': 'NPR'
      },
      'finance': {
        'pendingAdjustments': <Object>[],
        'reconciliations': <Object>[],
        'lockedPeriods': <Object>[],
        'settings': {
          'baseCurrency': 'NPR',
          'currencies': ['NPR'],
          'exchangeRates': {'NPR': 1},
          'expenseCategories': <Object>[],
          'incomeCategories': <Object>[],
        },
      },
      'grocery': {
        'products': <Object>[],
        'sales': <Object>[],
        'purchases': <Object>[],
        'suppliers': <Object>[],
        'customers': <Object>[],
        'expenses': <Object>[],
        'audit': <Object>[],
        'companyAssets': <Object>[],
        'settings': {'storeName': 'New store', 'currency': 'NPR', 'taxRate': 0},
      },
    };

String collectionKey(String path) => switch (path) {
      '/api/bookings' => 'bookings',
      '/api/customers' => 'customers',
      '/api/quotes' => 'quotes',
      '/api/sales' => 'sales',
      '/api/passports' => 'passportServices',
      '/api/refunds' => 'refunds',
      '/api/cases' => 'cases',
      '/api/users' => 'users',
      '/api/roles' => 'roles',
      '/api/audit' => 'audit',
      '/api/grocery/products' => 'products',
      '/api/grocery/sales' => 'sales',
      '/api/grocery/purchases' => 'purchases',
      '/api/grocery/suppliers' => 'suppliers',
      '/api/grocery/customers' => 'customers',
      '/api/grocery/expenses' => 'expenses',
      '/api/grocery/audit' => 'audit',
      '/api/company-assets' => 'companyAssets',
      '/api/grocery/company-assets' => 'companyAssets',
      _ => '',
    };

List<Map<String, dynamic>> collection(Map<String, dynamic> state, String path) {
  final key = collectionKey(path);
  if (key.isEmpty) return [];
  final root =
      path.startsWith('/api/grocery/') ? asObject(state['grocery']) : state;
  return records(root[key]);
}

void putCollection(
    Map<String, dynamic> state, String path, List<Map<String, dynamic>> value) {
  final key = collectionKey(path);
  if (key.isEmpty) throw StateError('Unknown collection: $path');
  if (path.startsWith('/api/grocery/')) {
    final grocery = asObject(state['grocery']);
    grocery[key] = value;
    state['grocery'] = grocery;
  } else {
    state[key] = value;
  }
}
