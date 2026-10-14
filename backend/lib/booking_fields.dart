import 'state.dart';

const bookingFieldKeys = <String>{
  'reference',
  'pnr',
  'customerName',
  'origin',
  'destination',
  'travelDate',
  'airline',
  'flight',
  'status',
  'paymentStatus',
  'paymentMethod',
  'bankName',
  'bankDetails',
  'total',
  'cost',
  'specialRequirements',
  'notes',
};

const passportFieldKeys = <String>{
  'customerName',
  'phone',
  'serviceType',
  'passportNumber',
  'currentExpiry',
  'applicationReference',
  'applicationDate',
  'appointmentDate',
  'submissionOffice',
  'expectedReadyDate',
  'status',
  'fee',
  'paymentStatus',
  'paymentMethod',
  'notes',
};

const passportCollectionFieldKeys = <String>{
  'status',
  'newPassportNumber',
  'newExpiry',
  'collectionDate',
  'collectionMethod',
  'collectorName',
  'collectorRelation',
  'collectorPhone',
  'collectorIdType',
  'collectorId',
  'documentCondition',
  'collectionNote',
};

const refundFieldKeys = <String>{
  'bookingId',
  'amount',
  'penalty',
  'reason',
};

const refundRequiredFieldKeys = <String>{'bookingId', 'amount'};

const recordFormBaseKeys = <String, Set<String>>{
  'payment_profiles': {
    'method',
    'label',
    'bankName',
    'accountName',
    'accountNumber',
    'branch',
    'walletNumber',
    'instructions',
    'active',
  },
  'airline_customers': {
    'title',
    'name',
    'email',
    'phone',
    'dob',
    'gender',
    'nationality',
    'passport',
    'passportExpiry',
    'issuingCountry',
    'address',
    'emergencyName',
    'emergencyPhone',
    'preferredAirline',
    'frequentFlyer',
    'specialRequirements',
    'notes',
  },
  'cases': {
    'category',
    'subject',
    'bookingId',
    'priority',
    'assignee',
    'status'
  },
  'users': {
    'name',
    'email',
    'password',
    'role',
    'branch',
    'phone',
    'jobTitle',
    'department',
    'joiningDate',
    'terminationDate',
    'shift',
    'workingHours',
    'paymentLimit',
    'adjustmentLimit',
    'refundLimit',
    'address',
    'emergencyName',
    'emergencyPhone',
    'active',
    'mustChangePassword',
  },
  'sales': {
    'date',
    'customerName',
    'description',
    'reference',
    'total',
    'note'
  },
  'grocery_products': {
    'name',
    'sku',
    'barcode',
    'category',
    'brand',
    'supplier',
    'description',
    'cost',
    'price',
    'discountPrice',
    'taxRate',
    'stock',
    'unit',
    'purchaseUnit',
    'sellingUnit',
    'packSize',
    'reorder',
    'minStock',
    'maxStock',
    'location',
    'batchNumber',
    'manufacturingDate',
    'trackExpiry',
    'expiry',
    'expiryWarningDays',
    'status',
  },
  'grocery_suppliers': {
    'code',
    'name',
    'legalName',
    'contact',
    'email',
    'phone',
    'secondaryPhone',
    'billingAddress',
    'deliveryAddress',
    'panVat',
    'registrationNumber',
    'category',
    'bankName',
    'bankBranch',
    'accountName',
    'accountNumber',
    'esewa',
    'khalti',
    'openingBalance',
    'creditLimit',
    'paymentTerms',
    'defaultPaymentMethod',
    'currency',
    'deliveryRating',
    'qualityRating',
    'primary',
    'status',
    'assignedUser',
    'notes',
  },
  'grocery_customers': {
    'name',
    'phone',
    'email',
    'address',
    'dob',
    'gender',
    'points',
    'spent',
    'tier',
    'status',
    'notes',
  },
  'grocery_expenses': {
    'reference',
    'date',
    'dueDate',
    'payee',
    'payeeType',
    'category',
    'subcategory',
    'description',
    'quantity',
    'unitRate',
    'discount',
    'taxRate',
    'panVat',
    'taxDeductible',
    'department',
    'branch',
    'costCentre',
    'linkedReference',
    'currency',
    'exchangeRate',
    'status',
    'recurring',
    'frequency',
    'nextPaymentDate',
    'reimbursement',
    'employee',
    'notes',
    'internalNotes',
  },
  'grocery_purchases': {
    'supplierId',
    'poNumber',
    'supplierInvoice',
    'expectedDate',
    'dueDate',
    'shipping',
    'otherCosts',
    'status',
    'notes',
  },
  'quotes': {
    'customerName',
    'origin',
    'destination',
    'travelDate',
    'validUntil',
    'airline',
    'flight',
    'fare',
    'serviceFee',
    'baggage',
    'status',
    'conditions',
    'notes',
  },
  'company_assets': {
    'employeeName',
    'assetName',
    'assetTag',
    'quantity',
    'issuedDate',
    'expectedReturnDate',
    'returnedDate',
    'condition',
    'notes',
  },
  'grocery_company_assets': {
    'employeeName',
    'assetName',
    'assetTag',
    'quantity',
    'issuedDate',
    'expectedReturnDate',
    'returnedDate',
    'condition',
    'notes',
  },
};

const protectedRecordFields = <String, Set<String>>{
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
    'status'
  },
  'grocery_purchases': {'supplierId', 'status'},
  'quotes': {'customerName', 'origin', 'destination', 'fare'},
};

String formCollectionPath(String module) => switch (module) {
      'payment_profiles' => '/api/payment-methods',
      'passport_collection' => '/api/passports',
      'airline_customers' => '/api/customers',
      'cases' => '/api/cases',
      'users' => '/api/users',
      'sales' => '/api/sales',
      'grocery_products' => '/api/grocery/products',
      'grocery_suppliers' => '/api/grocery/suppliers',
      'grocery_customers' => '/api/grocery/customers',
      'grocery_expenses' => '/api/grocery/expenses',
      'grocery_purchases' => '/api/grocery/purchases',
      'quotes' => '/api/quotes',
      'company_assets' => '/api/company-assets',
      'grocery_company_assets' => '/api/grocery/company-assets',
      _ => '',
    };

String formModuleForPath(String path) => switch (path) {
      '/api/payment-methods' => 'payment_profiles',
      '/api/customers' => 'airline_customers',
      '/api/cases' => 'cases',
      '/api/users' => 'users',
      '/api/sales' => 'sales',
      '/api/grocery/products' => 'grocery_products',
      '/api/grocery/suppliers' => 'grocery_suppliers',
      '/api/grocery/customers' => 'grocery_customers',
      '/api/grocery/expenses' => 'grocery_expenses',
      '/api/grocery/purchases' => 'grocery_purchases',
      '/api/quotes' => 'quotes',
      '/api/company-assets' => 'company_assets',
      '/api/grocery/company-assets' => 'grocery_company_assets',
      _ => path == '/api/bookings'
          ? 'bookings'
          : path == '/api/passports'
              ? 'passports'
              : path == '/api/refunds'
                  ? 'refunds'
                  : '',
    };

Set<String> formFieldKeys(String module) => switch (module) {
      'bookings' => bookingFieldKeys,
      'passports' => passportFieldKeys,
      'passport_collection' => passportCollectionFieldKeys,
      'refunds' => refundFieldKeys,
      _ when recordFormBaseKeys.containsKey(module) =>
        recordFormBaseKeys[module]!,
      _ => const <String>{},
    };

String formStateKey(String module) => switch (module) {
      'bookings' => 'bookingForm',
      'passports' => 'passportForm',
      'refunds' => 'refundForm',
      _ => 'form_$module',
    };

String formCollectionKey(String module) => switch (module) {
      'payment_profiles' => 'paymentProfiles',
      'bookings' => 'bookings',
      'passports' => 'passportServices',
      'refunds' => 'refunds',
      _ => formCollectionPath(module),
    };

Map<String, dynamic> recordFormConfig(
    Map<String, dynamic> state, String module) {
  final value = asObject(state[formStateKey(module)]);
  return {
    'removed': value['removed'] is List
        ? (value['removed'] as List).whereType<String>().toList()
        : <String>[],
    'custom': records(value['custom']),
    'archivedCustom': records(value['archivedCustom']),
    'labels': asObject(value['labels']),
    'order': value['order'] is List
        ? (value['order'] as List).whereType<String>().toList()
        : <String>[],
  };
}

Map<String, dynamic> bookingFormConfig(Map<String, dynamic> state) =>
    recordFormConfig(state, 'bookings');

bool recordFieldExists(
        Map<String, dynamic> config, String module, String key) =>
    formFieldKeys(module).contains(key) ||
    records(config['custom']).any((field) => field['key'] == key);

bool bookingFieldExists(Map<String, dynamic> config, String key) =>
    recordFieldExists(config, 'bookings', key);

void eraseRecordField(Map<String, dynamic> state, String module, String key) {
  final collectionKey = formCollectionKey(module);
  final path = formCollectionPath(module);
  final rows = module == 'payment_profiles'
      ? records(state['paymentProfiles'])
      : path.isNotEmpty
          ? collection(state, path)
          : records(state[collectionKey]);
  for (final row in rows) {
    row.remove(key);
    if (module == 'users') {
      final limitKey = switch (key) {
        'paymentLimit' => 'payment',
        'adjustmentLimit' => 'adjustment',
        'refundLimit' => 'refund',
        _ => '',
      };
      if (limitKey.isNotEmpty && row['approvalLimits'] is Map) {
        final limits = asObject(row['approvalLimits']);
        limits.remove(limitKey);
        row['approvalLimits'] = limits;
      }
    }
    if (module == 'bookings') {
      if (key == 'origin' || key == 'destination') row.remove('route');
      if (key == 'total') row.remove('outstanding');
    }
  }
  if (path.isNotEmpty && module != 'payment_profiles') {
    putCollection(state, path, rows);
  } else {
    state[collectionKey] = rows;
  }
  final draftKind = switch (module) {
    'bookings' => 'bookings',
    'grocery_products' => 'products',
    _ => '',
  };
  if (draftKind.isEmpty) return;
  final allDrafts = asObject(state['tableDrafts']);
  final drafts = records(allDrafts[draftKind]);
  for (final draft in drafts) {
    final values = asObject(draft['values']);
    values.remove(key);
    draft['values'] = values;
  }
  allDrafts[draftKind] = drafts;
  state['tableDrafts'] = allDrafts;
}

void eraseBookingField(Map<String, dynamic> state, String key) =>
    eraseRecordField(state, 'bookings', key);
