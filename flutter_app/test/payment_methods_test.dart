import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/payment_dialog.dart';
import 'package:aerodesk_client/payment_methods_screen.dart';
import 'package:aerodesk_client/payment_methods.dart';
import 'package:aerodesk_client/form_sheet.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PaymentApi extends ApiClient {
  final profiles = <Map<String, dynamic>>[];
  final formConfig = <String, dynamic>{
    'removed': <String>[],
    'custom': <Map<String, dynamic>>[],
    'labels': <String, String>{},
    'order': <String>[],
  };
  final types = <Map<String, dynamic>>[
    {'id': 'Cash', 'name': 'Cash', 'kind': 'cash', 'active': true},
    {'id': 'eSewa', 'name': 'eSewa', 'kind': 'digital', 'active': true},
    {'id': 'Khalti', 'name': 'Khalti', 'kind': 'digital', 'active': true},
    {'id': 'Bank', 'name': 'Bank', 'kind': 'bank', 'active': true},
  ];
  String? lastMethod;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> get(String path) async =>
      path == '/api/payment-method-types'
          ? types
          : path == '/api/form-fields/payment_profiles'
          ? formConfig
          : profiles;

  @override
  Future<dynamic> request(String method, String path, [Object? body]) async {
    lastMethod = method;
    lastPath = path;
    lastBody = body is Map ? asMap(body) : null;
    if (path == '/api/form-fields/payment_profiles') {
      if (method == 'PATCH' && lastBody!.containsKey('order')) {
        formConfig['order'] = List<String>.from(lastBody!['order'] as List);
      } else if (method == 'PATCH') {
        (formConfig['labels'] as Map<String, String>)[lastBody!['key']
                .toString()] =
            lastBody!['label'].toString();
      } else if (method == 'POST') {
        (formConfig['custom'] as List<Map<String, dynamic>>).add({
          'key': 'custom_1',
          ...lastBody!,
        });
      } else if (method == 'DELETE') {
        (formConfig['removed'] as List<String>).add(
          lastBody!['key'].toString(),
        );
      }
      return formConfig;
    }
    if (path.startsWith('/api/payment-method-types')) {
      if (method == 'POST') {
        final record = {'id': 'MT-1', ...lastBody!};
        types.add(record);
        return record;
      }
      if (method == 'PATCH') {
        final record = {'id': path.split('/').last, ...lastBody!};
        types[types.indexWhere((item) => item['id'] == record['id'])] = record;
        return record;
      }
      if (method == 'DELETE') {
        types.removeWhere((item) => item['id'] == path.split('/').last);
        return {'ok': true};
      }
    }
    if (method == 'POST') {
      final record = {'id': 'PM-1', ...lastBody!};
      profiles.add(record);
      return record;
    }
    if (method == 'DELETE') {
      profiles.removeWhere((profile) => path.endsWith(profile['id']));
      return {'ok': true};
    }
    return lastBody;
  }
}

void main() {
  test('custom account field values are included when saving', () {
    final profile = PaymentProfile.fromJson({
      'id': 'PM-1',
      'method': 'Bank',
      'label': 'Main bank',
      'active': true,
      'custom_iban': 'NP00-123',
    });
    expect(profile.toPayload()['custom_iban'], 'NP00-123');
  });

  testWidgets('payment account form manager reorders and adds fields', (
    tester,
  ) async {
    final api = _PaymentApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentMethodsScreen(
            api: api,
            user: const {'role': 'Agency owner'},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add saved account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage payment form fields'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Method down'));
    await tester.pumpAndSettle();
    expect((api.formConfig['order'] as List).first, 'label');
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Field name'),
      'Account nickname',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save_outlined).last);
    await tester.pumpAndSettle();
    expect(
      (api.formConfig['custom'] as List).single['label'],
      'Account nickname',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Manage payment form fields'), findsOneWidget);
    expect(find.text('Account nickname', skipOffstage: false), findsWidgets);
  });

  testWidgets('owner adds and deletes a payment system from the sidebar page', (
    tester,
  ) async {
    final api = _PaymentApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentMethodsScreen(
            api: api,
            user: const {'role': 'Agency owner'},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add payment system'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'IME Pay');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.types.any((item) => item['name'] == 'IME Pay'), isTrue);
    await tester.scrollUntilVisible(find.byTooltip('Delete IME Pay'), 300);
    expect(find.text('IME Pay'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete IME Pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(api.types.any((item) => item['name'] == 'IME Pay'), isFalse);
  });

  test(
    'payment system definitions can be created, renamed and deleted',
    () async {
      final api = _PaymentApi();
      final repository = PaymentMethodsRepository(api);
      final created = await repository.saveType(
        const PaymentMethodType(id: '', name: 'IME Pay', kind: 'digital'),
      );
      expect(created.name, 'IME Pay');
      expect((await repository.listTypes()).last.name, 'IME Pay');
      await repository.saveType(
        PaymentMethodType(id: created.id, name: 'IME Wallet', kind: 'digital'),
      );
      expect((await repository.listTypes()).last.name, 'IME Wallet');
      await repository.deleteType(created.id);
      expect(
        (await repository.listTypes()).any((item) => item.id == created.id),
        isFalse,
      );
    },
  );

  testWidgets('a custom digital method appears in payment collection', (
    tester,
  ) async {
    final api = _PaymentApi();
    api.types.add({
      'id': 'MT-9',
      'name': 'IME Pay',
      'kind': 'digital',
      'active': true,
    });
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () async =>
                          result = await showConfiguredSplitPayment(
                            context,
                            api: api,
                            max: 20,
                            exact: true,
                          ),
                  child: const Text('Open payment'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open payment'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('payment-amount-MT-9')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-amount-MT-9')),
      '20',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(TextField, 'Wallet number *').last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Wallet number *').last,
      '9800000000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();
    expect(asRows(result?['payments']).single['method'], 'MT-9');
  });

  testWidgets('payment method page saves a bank profile', (tester) async {
    final api = _PaymentApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentMethodsScreen(
            api: api,
            user: const {'role': 'Agency owner'},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add saved account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name shown when selecting this method'),
      'Main bank',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Bank name *'),
      'Example Bank',
    );
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(
              TextField,
              'Name shown when selecting this method',
            ),
          )
          .controller!
          .text,
      'Main bank',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Bank name *'))
          .controller!
          .text,
      'Example Bank',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.lastMethod, 'POST');
    expect(api.lastPath, '/api/payment-methods');
    expect(api.lastBody!['bankName'], 'Example Bank');
    expect(api.profiles.single['label'], 'Main bank');
  });

  testWidgets('split payment records cash and eSewa with wallet details', (
    tester,
  ) async {
    final api = _PaymentApi();
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () async =>
                          result = await showConfiguredSplitPayment(
                            context,
                            api: api,
                            max: 100,
                            exact: true,
                          ),
                  child: const Text('Open payment'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open payment'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-amount-Cash')),
      '25',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-amount-eSewa')),
      '75',
    );
    await tester.pumpAndSettle();
    final walletField = find.widgetWithText(TextField, 'Wallet number *');
    await tester.ensureVisible(walletField);
    await tester.enterText(walletField, '9800000000');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();
    final payments = asRows(result?['payments']);
    expect(payments, hasLength(2));
    expect(payments.first['method'], 'Cash');
    expect(payments.first['amount'], 25);
    expect(payments.last['method'], 'eSewa');
    expect(payments.last['amount'], 75);
    expect(payments.last['walletNumber'], '9800000000');
  });

  testWidgets('saved bank profile fills the bank fields', (tester) async {
    final api = _PaymentApi();
    api.profiles.add({
      'id': 'PM-BANK',
      'method': 'Bank',
      'label': 'Agency bank',
      'bankName': 'Example Bank',
      'accountNumber': '1234',
      'active': true,
    });
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () async =>
                          result = await showConfiguredSplitPayment(
                            context,
                            api: api,
                            max: 50,
                            exact: true,
                          ),
                  child: const Text('Open payment'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open payment'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('payment-amount-Bank')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-amount-Bank')),
      '50',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enter manually'));
    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agency bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();
    final payment = asRows(result?['payments']).single;
    expect(payment['profileId'], 'PM-BANK');
    expect(payment['bankName'], 'Example Bank');
    expect(payment['accountNumber'], '1234');
  });

  testWidgets('record forms show fields for the chosen payment method', (
    tester,
  ) async {
    final api = _PaymentApi();
    api.profiles.add({
      'id': 'PM-BANK',
      'method': 'Bank',
      'label': 'Agency bank',
      'bankName': 'Example Bank',
      'active': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showRecordForm(context, 'Payment details', const [
                        FieldSpec(
                          'paymentMethod',
                          'Payment method',
                          type: FieldType.choice,
                          choices: paymentMethods,
                          initial: 'Cash',
                        ),
                      ], api: api),
                  child: const Text('Open form'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Bank name'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Bank name'), findsOneWidget);
    expect(find.text('Saved payment details'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agency bank').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Bank name'),
          )
          .controller!
          .text,
      'Example Bank',
    );
  });
}
