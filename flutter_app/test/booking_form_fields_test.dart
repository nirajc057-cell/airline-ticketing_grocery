import 'package:aerodesk_client/booking_form_fields.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/transactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FieldsApi extends ApiClient {
  final custom = <Map<String, dynamic>>[];
  final removed = <String>[];
  List<String> order = [];
  String? lastPath;
  @override
  Future<dynamic> get(String path) async => {
    'removed': removed,
    'custom': custom,
    'labels': <String, String>{},
    'order': order,
  };
  @override
  Future<dynamic> request(String method, String path, [Object? body]) async {
    lastPath = path;
    final values = Map<String, dynamic>.from(body! as Map);
    if (method == 'POST') {
      custom.add({'key': 'custom_test', ...values});
    } else if (method == 'DELETE') {
      custom.removeWhere((field) => field['key'] == values['key']);
    } else if (method == 'PATCH' && values['order'] is List) {
      order = List<String>.from(values['order'] as List);
    }
    return get(path);
  }
}

class _OldFieldsApi extends _FieldsApi {
  @override
  Future<dynamic> request(String method, String path, [Object? body]) async {
    if (method == 'PATCH' && body is Map && body.containsKey('order')) {
      throw const ApiException('Invalid field or label', 400);
    }
    return super.request(method, path, body);
  }
}

void main() {
  test('company asset fields can be renamed, removed and reordered', () {
    expect(recordFormModule('company_assets', false), 'company_assets');
    expect(recordFormModule('company_assets', true), 'grocery_company_assets');
    final fields = recordFieldsFor('company_assets', {
      'removed': ['assetTag'],
      'labels': {'employeeName': 'Staff member'},
      'custom': [
        {'key': 'custom_location', 'label': 'Office location', 'type': 'text'},
      ],
      'order': ['assetName', 'employeeName', 'custom_location'],
    });
    expect(fields.first.key, 'assetName');
    expect(fields.any((field) => field.key == 'assetTag'), isFalse);
    expect(
      fields.firstWhere((field) => field.key == 'employeeName').label,
      'Staff member',
    );
    expect(fields.any((field) => field.key == 'custom_location'), isTrue);
  });

  testWidgets('Company Assets field manager adds and moves a field', (
    tester,
  ) async {
    final api = _FieldsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showRecordFieldsManager(
                        context,
                        api,
                        'grocery_company_assets',
                      ),
                  child: const Text('Manage assets'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage assets'));
    await tester.pumpAndSettle();
    expect(find.text('Company asset form fields'), findsOneWidget);
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Office location');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.lastPath, '/api/form-fields/grocery_company_assets');
    expect(api.custom.single['label'], 'Office location');
    await tester.scrollUntilVisible(
      find.byTooltip('Move Office location up'),
      200,
      scrollable:
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Scrollable),
              )
              .last,
    );
    await tester.tap(find.byTooltip('Move Office location up'));
    await tester.pumpAndSettle();
    expect(api.order, contains('custom_test'));
    expect(tester.takeException(), isNull);
  });

  test('configuration removes old fields and adds custom fields', () {
    final fields = bookingFieldsFor({
      'removed': ['pnr'],
      'labels': {'reference': 'Booking reference'},
      'custom': [
        {
          'key': 'custom_meal',
          'label': 'Meal preference',
          'type': 'paragraph',
          'required': false,
          'choices': [],
        },
      ],
    });
    expect(fields.any((field) => field.key == 'pnr'), isFalse);
    expect(fields.first.label, 'Booking reference');
    expect(fields.last.key, 'custom_meal');
    expect(fields.last.type, FieldType.paragraph);
  });

  test('an unset configuration shows the original booking form', () {
    expect(bookingFieldsFor({}).length, bookingFields.length);
  });

  test('saved order controls where fields appear in booking form', () {
    final fields = bookingFieldsFor({
      'order': ['pnr', 'reference'],
    });
    expect(fields.take(2).map((field) => field.key), ['pnr', 'reference']);
  });

  test('passport and refund form layouts use their own fields', () {
    final passport = recordFieldsFor('passports', {
      'removed': ['phone'],
      'custom': [
        {'key': 'custom_priority', 'label': 'Priority', 'type': 'text'},
      ],
    });
    expect(passport.any((field) => field.key == 'phone'), isFalse);
    expect(passport.last.label, 'Priority');
    final refund = recordFieldsFor('refunds', {});
    expect(refund.map((field) => field.key), [
      'bookingId',
      'amount',
      'penalty',
      'reason',
    ]);
  });

  test(
    'customer, product and purchase forms use independent configurations',
    () {
      final customer = recordFieldsFor('airline_customers', {
        'removed': ['notes'],
        'labels': {'name': 'Passenger name'},
      });
      expect(customer.any((field) => field.key == 'notes'), isFalse);
      expect(
        customer.firstWhere((field) => field.key == 'name').label,
        'Passenger name',
      );

      final product = recordFieldsFor('grocery_products', {
        'order': ['barcode', 'name'],
        'custom': [
          {'key': 'custom_aisle', 'label': 'Aisle', 'type': 'text'},
        ],
      });
      expect(product.take(2).map((field) => field.key), ['barcode', 'name']);
      expect(product.last.key, 'custom_aisle');

      final purchase = recordFieldsFor('grocery_purchases', {
        'removed': ['supplierInvoice'],
        'labels': {'poNumber': 'Order reference'},
      });
      expect(purchase.any((field) => field.key == 'supplierInvoice'), isFalse);
      expect(
        purchase.firstWhere((field) => field.key == 'poNumber').label,
        'Order reference',
      );
      expect(
        recordFormPath('grocery_purchases'),
        '/api/form-fields/grocery_purchases',
      );
    },
  );

  test('passport collection form can hide and rename collection fields', () {
    final fields = recordFieldsFor('passport_collection', {
      'removed': ['collectorPhone'],
      'labels': {'collectorName': 'Collected by'},
    });
    expect(fields.any((field) => field.key == 'collectorPhone'), isFalse);
    expect(
      fields.firstWhere((field) => field.key == 'collectorName').label,
      'Collected by',
    );
    expect(
      recordFormPath('passport_collection'),
      '/api/form-fields/passport_collection',
    );
  });

  test(
    'passport collection and booking refund actions use shared field forms',
    () {
      final passportAction =
          recordActions('passports', false, {'id': 'PS-1'}).single;
      expect(passportAction.formModule, 'passport_collection');
      final refundAction = recordActions('bookings', false, {
        'id': 'BK-1',
        'status': 'Ticketed',
        'paymentStatus': 'Paid',
        'total': 100,
      }).firstWhere((action) => action.label == 'Request refund');
      expect(refundAction.formModule, 'refunds');
      final caseAction =
          recordActions('cases', false, {
            'id': 'CS-1',
            'status': 'Open',
          }).single;
      expect(caseAction.formModule, 'cases');
    },
  );

  testWidgets('passport manager saves fields to passport endpoint', (
    tester,
  ) async {
    final api = _FieldsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showRecordFieldsManager(context, api, 'passports'),
                  child: const Text('Manage'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('Passport service form fields'), findsOneWidget);
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Collection date');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.lastPath, '/api/passports/form-fields');
    expect(api.custom.single['label'], 'Collection date');
  });

  testWidgets('refund manager keeps booking ID and amount required', (
    tester,
  ) async {
    final api = _FieldsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showRecordFieldsManager(context, api, 'refunds'),
                  child: const Text('Manage'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('Refund form fields'), findsOneWidget);
    final protected = tester.widgetList<IconButton>(
      find.ancestor(
        of: find.byTooltip('Required for this workflow'),
        matching: find.byType(IconButton),
      ),
    );
    expect(protected, hasLength(2));
    expect(protected.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('manager moves a field down and persists the order', (
    tester,
  ) async {
    final api = _FieldsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () => showBookingFieldsManager(context, api),
                  child: const Text('Manage'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Reference down'));
    await tester.pumpAndSettle();
    expect(api.order.take(2), ['pnr', 'reference']);
    expect(bookingFieldsFor(await api.get(bookingFormPath)).first.key, 'pnr');
    await tester.tap(find.byTooltip('Move Reference up'));
    await tester.pumpAndSettle();
    expect(api.order.take(2), ['reference', 'pnr']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old backend error explains that restart is needed', (
    tester,
  ) async {
    final api = _OldFieldsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () => showBookingFieldsManager(context, api),
                  child: const Text('Manage'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Reference down'));
    await tester.pumpAndSettle();
    expect(find.textContaining('local backend is out of date'), findsOneWidget);
    expect(find.text('Invalid field or label'), findsNothing);
  });

  testWidgets('manager adds and deletes a booking form field', (tester) async {
    final api = _FieldsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () => showBookingFieldsManager(context, api),
                  child: const Text('Manage'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Visa number');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.custom, hasLength(1));
    await tester.scrollUntilVisible(
      find.text('Visa number'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Visa number'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete Visa number'));
    await tester.pumpAndSettle();
    expect(find.textContaining('permanently erases'), findsOneWidget);
    await tester.tap(find.text('Delete field and data'));
    await tester.pumpAndSettle();
    expect(api.custom, isEmpty);
  });
}
