import 'package:aerodesk_backend/booking_fields.dart';
import 'package:aerodesk_backend/state.dart';
import 'package:test/test.dart';

void main() {
  test('company asset forms and records stay separate by workspace', () {
    final state = emptyWorkspace('owner@example.com');
    expect(formCollectionPath('company_assets'), '/api/company-assets');
    expect(formCollectionPath('grocery_company_assets'),
        '/api/grocery/company-assets');
    expect(formFieldKeys('company_assets'),
        containsAll(['employeeName', 'assetName', 'assetTag']));
    putCollection(state, '/api/company-assets', [
      {'id': 'A-1', 'employeeName': 'Alex', 'assetName': 'Laptop'}
    ]);
    putCollection(state, '/api/grocery/company-assets', [
      {'id': 'G-1', 'employeeName': 'Sam', 'assetName': 'Scanner'}
    ]);
    eraseRecordField(state, 'company_assets', 'assetName');
    expect(
        collection(state, '/api/company-assets').single['assetName'], isNull);
    expect(collection(state, '/api/grocery/company-assets').single['assetName'],
        'Scanner');
    eraseRecordField(state, 'grocery_company_assets', 'employeeName');
    expect(
        collection(state, '/api/grocery/company-assets').single['employeeName'],
        isNull);
    expect(collection(state, '/api/company-assets').single['employeeName'],
        'Alex');
  });

  test('deleting a field erases saved booking and draft values', () {
    final state = emptyWorkspace('owner@example.com');
    state['bookings'] = [
      {
        'id': 'BK-1',
        'origin': 'KTM',
        'route': 'KTM → DXB',
        'custom_test': 'private detail'
      },
    ];
    state['tableDrafts'] = {
      'bookings': [
        {
          'id': 'D-1',
          'values': {'origin': 'KTM', 'custom_test': 'draft detail'}
        },
      ],
    };
    eraseBookingField(state, 'origin');
    eraseBookingField(state, 'custom_test');
    final booking = records(state['bookings']).single;
    expect(booking.containsKey('origin'), isFalse);
    expect(booking.containsKey('route'), isFalse);
    expect(booking.containsKey('custom_test'), isFalse);
    final draft = records(asObject(state['tableDrafts'])['bookings']).single;
    expect(asObject(draft['values']), isEmpty);
  });

  test('missing config retains original form fields', () {
    final config = bookingFormConfig(emptyWorkspace('owner@example.com'));
    expect(config['removed'], isEmpty);
    expect(config['custom'], isEmpty);
    expect(bookingFieldExists(config, 'reference'), isTrue);
  });

  test('passport and refund fields erase values only in their own records', () {
    final state = emptyWorkspace('owner@example.com');
    state['passportServices'] = [
      {'id': 'PS-1', 'notes': 'collect next week', 'customerName': 'Alex'},
    ];
    state['refunds'] = [
      {'id': 'RF-1', 'reason': 'flight cancelled', 'amount': 100},
    ];
    eraseRecordField(state, 'passports', 'notes');
    eraseRecordField(state, 'refunds', 'reason');
    expect(records(state['passportServices']).single.containsKey('notes'),
        isFalse);
    expect(records(state['passportServices']).single['customerName'], 'Alex');
    expect(records(state['refunds']).single.containsKey('reason'), isFalse);
    expect(records(state['refunds']).single['amount'], 100);
    expect(formFieldKeys('refunds'), containsAll(['bookingId', 'amount']));
  });

  test('legacy workspaces get independent field configurations', () {
    final state = emptyWorkspace('owner@example.com');
    state.remove('passportForm');
    state.remove('refundForm');
    expect(recordFormConfig(state, 'passports')['removed'], isEmpty);
    expect(recordFormConfig(state, 'refunds')['custom'], isEmpty);
  });

  test('grocery and airline field deletion erases only matching records', () {
    final state = emptyWorkspace('owner@example.com');
    putCollection(state, '/api/grocery/products', [
      {
        'id': 'PR-1',
        'name': 'Rice',
        'brand': 'Old brand',
        'custom_note': 'remove me',
      },
    ]);
    putCollection(state, '/api/grocery/suppliers', [
      {'id': 'SUP-1', 'name': 'Vendor', 'brand': 'keep me'},
    ]);
    putCollection(state, '/api/customers', [
      {'id': 'CU-1', 'name': 'Alex', 'notes': 'remove me'},
    ]);
    state['tableDrafts'] = {
      'products': [
        {
          'id': 'D-1',
          'values': {'brand': 'Draft brand', 'custom_note': 'draft note'},
        },
      ],
    };

    eraseRecordField(state, 'grocery_products', 'brand');
    eraseRecordField(state, 'grocery_products', 'custom_note');
    eraseRecordField(state, 'airline_customers', 'notes');

    final product = collection(state, '/api/grocery/products').single;
    expect(product, containsPair('name', 'Rice'));
    expect(product.containsKey('brand'), isFalse);
    expect(product.containsKey('custom_note'), isFalse);
    expect(
        collection(state, '/api/grocery/suppliers').single['brand'], 'keep me');
    expect(collection(state, '/api/customers').single.containsKey('notes'),
        isFalse);
    final draft = records(asObject(state['tableDrafts'])['products']).single;
    expect(asObject(draft['values']), isEmpty);
  });

  test('form registry maps each configurable module to its own records', () {
    for (final entry in recordFormBaseKeys.entries) {
      expect(formFieldKeys(entry.key), isNotEmpty);
      expect(formCollectionPath(entry.key), isNotEmpty);
      expect(formModuleForPath(formCollectionPath(entry.key)), entry.key);
      expect(formStateKey(entry.key), 'form_${entry.key}');
    }
    expect(protectedRecordFields['grocery_purchases'],
        containsAll(['supplierId', 'status']));
  });

  test('deleting an employee approval limit clears its nested saved value', () {
    final state = emptyWorkspace('owner@example.com');
    final users = collection(state, '/api/users');
    users.first['approvalLimits'] = {
      'payment': 100,
      'adjustment': 20,
      'refund': 50,
    };
    putCollection(state, '/api/users', users);

    eraseRecordField(state, 'users', 'paymentLimit');

    final saved = collection(state, '/api/users').first;
    expect(asObject(saved['approvalLimits']).containsKey('payment'), isFalse);
    expect(asObject(saved['approvalLimits'])['adjustment'], 20);
  });

  test('passport collection fields are independent and erase old values', () {
    final state = emptyWorkspace('owner@example.com');
    state['passportServices'] = [
      {
        'id': 'PS-1',
        'status': 'Ready for collection',
        'collectorPhone': '123456789',
        'customerName': 'Alex',
      },
    ];
    eraseRecordField(state, 'passport_collection', 'collectorPhone');
    final saved = records(state['passportServices']).single;
    expect(saved.containsKey('collectorPhone'), isFalse);
    expect(saved['customerName'], 'Alex');
    expect(formFieldKeys('passport_collection'), contains('collectionDate'));
    expect(protectedRecordFields['passport_collection'], contains('status'));
  });
}
