// In-memory examples for previewing empty AeroDesk and FreshMart sales screens.
// These records are never sent to the API or included in real balances.
const demoAirlineSales = <Map<String, dynamic>>[
  {
    'id': 'DEMO-AS-001',
    'date': '2026-11-02',
    'customerName': 'Sample Traveler A',
    'description': 'Kathmandu to Delhi flight service',
    'reference': 'DEMO-INV-001',
    'total': 12450,
    'paymentStatus': 'Paid',
    'payments': [
      {'method': 'Cash', 'amount': 12450},
    ],
    'createdBy': 'Demo agent',
  },
  {
    'id': 'DEMO-AS-002',
    'date': '2026-10-30',
    'customerName': 'Sample Traveler B',
    'description': 'Passport assistance service',
    'reference': 'DEMO-INV-002',
    'total': 8990,
    'paymentStatus': 'Paid',
    'payments': [
      {'method': 'Cash', 'amount': 5000},
      {'method': 'Bank transfer', 'amount': 3990},
    ],
    'createdBy': 'Demo agent',
  },
  {
    'id': 'DEMO-AS-003',
    'date': '2026-10-27',
    'customerName': 'Sample Traveler C',
    'description': 'Ticket change service fee',
    'reference': 'DEMO-INV-003',
    'total': 3550,
    'paymentStatus': 'Paid',
    'payments': [
      {'method': 'Digital wallet', 'amount': 3550},
    ],
    'createdBy': 'Demo agent',
  },
];

// Preview-only FreshMart transactions. The API never receives these rows.
const demoGrocerySales = <Map<String, dynamic>>[
  {
    'id': 'DEMO-GS-001',
    'receipt': 'DEMO-FM-001',
    'createdAt': '2026-11-02T14:32:00Z',
    'cashier': 'Sample Cashier',
    'customer': 'Walk-in customer',
    'items': [
      {'name': 'Rice 5 kg', 'qty': 1, 'price': 15.99, 'total': 15.99},
      {'name': 'Milk 1 L', 'qty': 1, 'price': 1.65, 'total': 1.65},
    ],
    'subtotal': 17.64,
    'discount': 0,
    'tax': 0.88,
    'total': 18.52,
    'cost': 13.62,
    'profit': 4.02,
    'payment': 'Card',
    'payments': [
      {'method': 'Card', 'amount': 18.52},
    ],
  },
  {
    'id': 'DEMO-GS-002',
    'receipt': 'DEMO-FM-002',
    'createdAt': '2026-11-01T10:15:00Z',
    'cashier': 'Sample Cashier',
    'customer': 'Walk-in customer',
    'items': [
      {'name': 'Mineral water 1 L', 'qty': 2, 'price': 0.75, 'total': 1.50},
    ],
    'subtotal': 1.50,
    'discount': 0,
    'tax': 0,
    'total': 1.50,
    'cost': 0.90,
    'profit': 0.60,
    'payment': 'Cash',
    'payments': [
      {'method': 'Cash', 'amount': 1.50},
    ],
  },
];

const demoGroceryExpenses = <Map<String, dynamic>>[
  {
    'id': 'DEMO-EXP-001',
    'reference': 'DEMO-BILL-001',
    'date': '2026-11-02',
    'payee': 'Sample Property Co.',
    'category': 'Rent',
    'description': 'November store rent',
    'quantity': 1,
    'unitRate': 15000,
    'subtotal': 15000,
    'discount': 0,
    'tax': 0,
    'total': 15000,
    'paidAmount': 8000,
    'outstanding': 7000,
    'status': 'Approved',
    'paymentStatus': 'Partially paid',
    'payments': [
      {'method': 'Bank transfer', 'amount': 8000},
    ],
  },
  {
    'id': 'DEMO-EXP-002',
    'reference': 'DEMO-BILL-002',
    'date': '2026-10-30',
    'payee': 'Sample Utility Co.',
    'category': 'Utilities',
    'description': 'Electricity bill',
    'quantity': 1,
    'unitRate': 3250,
    'subtotal': 3250,
    'discount': 0,
    'tax': 0,
    'total': 3250,
    'paidAmount': 3250,
    'outstanding': 0,
    'status': 'Paid',
    'paymentStatus': 'Paid',
    'payments': [
      {'method': 'Cash', 'amount': 3250},
    ],
  },
];
