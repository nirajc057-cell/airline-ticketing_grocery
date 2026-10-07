import 'package:aerodesk_backend/payment_methods.dart';
import 'package:aerodesk_backend/booking_fields.dart';
import 'package:aerodesk_backend/state.dart';
import 'package:test/test.dart';

void main() {
  test('payment account fields can be removed and custom values saved', () {
    final state = emptyWorkspace('owner@example.com');
    state['paymentProfiles'] = [
      {
        'id': 'PM-1',
        'method': 'Bank',
        'label': 'Main bank',
        'bankName': 'Example Bank',
        'branch': 'Old branch'
      },
    ];
    eraseRecordField(state, 'payment_profiles', 'branch');
    expect(records(state['paymentProfiles']).single.containsKey('branch'),
        isFalse);
    state['form_payment_profiles'] = {
      'removed': ['branch', 'bankName'],
      'custom': [
        {
          'key': 'custom_iban',
          'label': 'IBAN',
          'type': 'text',
          'required': true
        },
      ],
    };
    final saved = normalizePaymentProfile({
      'method': 'Bank',
      'label': 'Main bank',
      'custom_iban': 'NP00-123',
      'bankName': 'Ignored',
    }, state: state);
    expect(saved['custom_iban'], 'NP00-123');
    expect(saved.containsKey('bankName'), isFalse);
    expect(
        () => normalizePaymentProfile({
              'method': 'Bank',
              'label': 'No IBAN',
            }, state: state),
        throwsFormatException);
  });

  test('custom method can be added and removed without changing old payments',
      () {
    final state = emptyWorkspace('owner@example.com');
    final type = normalizePaymentType({
      'name': 'IME Pay',
      'kind': 'digital',
      'active': true,
    });
    state['paymentTypes'] = [
      ...paymentTypes(state),
      {'id': 'MT-1', ...type},
    ];
    final recorded = validatedPayments(
            state,
            {
              'payments': [
                {'method': 'MT-1', 'amount': 100, 'walletNumber': '9800000000'},
              ],
            },
            100,
            exact: true)
        .single;
    expect(recorded['methodName'], 'IME Pay');
    expect(recorded['walletNumber'], '9800000000');
    state['paymentTypes'] =
        paymentTypes(state).where((item) => item['id'] != 'MT-1').toList();
    expect(
        () => validatedPayments(
            state,
            {
              'payments': [recorded],
            },
            100),
        throwsFormatException);
    expect(recorded['methodName'], 'IME Pay');
  });

  test('bank and digital profiles require their relevant details', () {
    expect(
      normalizePaymentProfile({
        'method': 'Bank',
        'label': 'Main account',
        'bankName': 'Example Bank',
        'accountNumber': '1234',
      })['bankName'],
      'Example Bank',
    );
    expect(
      () => normalizePaymentProfile({
        'method': 'Bank',
        'label': 'Missing bank',
      }),
      throwsFormatException,
    );
    expect(
      () => normalizePaymentProfile({
        'method': 'eSewa',
        'label': 'Missing wallet',
      }),
      throwsFormatException,
    );
    final khalti = normalizePaymentProfile({
      'method': 'Khalti',
      'label': 'Shop wallet',
      'walletNumber': '9800000000',
      'bankName': 'Should be ignored',
    });
    expect(khalti['walletNumber'], '9800000000');
    expect(khalti.containsKey('bankName'), isFalse);
  });

  test('a cash and wallet split uses saved details and totals exactly', () {
    final state = emptyWorkspace('owner@example.com');
    state['paymentProfiles'] = [
      {
        'id': 'PM-1',
        'method': 'eSewa',
        'label': 'Shop wallet',
        'walletNumber': '9800000000',
        'accountName': 'FreshMart',
        'active': true,
      },
    ];
    final result = validatedPayments(
        state,
        {
          'payments': [
            {'method': 'Cash', 'amount': 25},
            {
              'method': 'eSewa',
              'amount': 75,
              'profileId': 'PM-1',
              'transactionId': 'TX-123',
            },
          ],
        },
        100,
        exact: true);
    expect(result, hasLength(2));
    expect(result.first['amount'], 25);
    expect(result.last['walletNumber'], '9800000000');
    expect(result.last['accountName'], 'FreshMart');
    expect(result.last['transactionId'], 'TX-123');
    expect(result.last['profileId'], 'PM-1');
  });

  test('bank details are snapshotted and missing payment data is rejected', () {
    final state = emptyWorkspace('owner@example.com');
    state['paymentProfiles'] = [
      {
        'id': 'PM-BANK',
        'method': 'Bank',
        'label': 'Agency bank',
        'bankName': 'Example Bank',
        'accountNumber': '1234',
        'active': true,
      },
    ];
    final bank = validatedPayments(
            state,
            {
              'payments': [
                {'method': 'Bank', 'amount': 50, 'profileId': 'PM-BANK'},
              ],
            },
            50,
            exact: true)
        .single;
    expect(bank['bankName'], 'Example Bank');
    expect(bank['accountNumber'], '1234');
    records(state['paymentProfiles']).single['bankName'] = 'Changed Bank';
    expect(bank['bankName'], 'Example Bank');

    expect(
      () => validatedPayments(
          state,
          {
            'payments': [
              {'method': 'Khalti', 'amount': 10},
            ],
          },
          10),
      throwsFormatException,
    );
    expect(
      () => validatedPayments(
          state,
          {
            'payments': [
              {'method': 'Cash', 'amount': 110},
            ],
          },
          100),
      throwsFormatException,
    );
  });
}
