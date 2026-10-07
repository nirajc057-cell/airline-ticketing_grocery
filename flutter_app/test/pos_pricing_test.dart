import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/pos_pricing.dart';
import 'package:aerodesk_client/transactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PosApi extends ApiClient {
  Map<String, dynamic>? sale;

  @override
  Future<dynamic> get(String path) async => switch (path) {
    '/api/grocery/bootstrap' => {
      'settings': {'taxRate': 5},
    },
    '/api/payment-method-types' => [
      {'id': 'Cash', 'name': 'Cash', 'kind': 'cash', 'active': true},
    ],
    '/api/payment-methods' => <Object>[],
    _ => throw StateError('Unexpected GET: $path'),
  };

  @override
  Future<dynamic> post(String path, Object body) async {
    if (path != '/api/grocery/sales') throw StateError(path);
    sale = Map<String, dynamic>.from(body as Map);
    return {'receipt': 'FM-1'};
  }
}

void main() {
  test('discount is deducted before custom tax', () {
    final value = calculatePosPricing(
      subtotal: 100,
      discountType: 'percent',
      discountValue: 10,
      taxRate: 7.5,
    );
    expect(value.discount, 10);
    expect(value.tax, 6.75);
    expect(value.total, 96.75);
  });

  test('fixed discount can be combined with no tax', () {
    final value = calculatePosPricing(
      subtotal: 100,
      discountType: 'amount',
      discountValue: 25,
      taxRate: 0,
    );
    expect(value.discount, 25);
    expect(value.tax, 0);
    expect(value.total, 75);
    expect(
      () => calculatePosPricing(
        subtotal: 10,
        discountType: 'amount',
        discountValue: 11,
        taxRate: 0,
      ),
      throwsFormatException,
    );
  });

  test('nearest rupee shows positive and negative round-off', () {
    final down = calculatePosPricing(
      subtotal: 16.32,
      discountType: 'amount',
      discountValue: 0,
      taxRate: 0,
      roundToWhole: true,
    );
    expect(down.beforeRounding, 16.32);
    expect(down.roundingAdjustment, -0.32);
    expect(down.total, 16);

    final up = calculatePosPricing(
      subtotal: 16.50,
      discountType: 'amount',
      discountValue: 0,
      taxRate: 0,
      roundToWhole: true,
    );
    expect(up.roundingAdjustment, 0.50);
    expect(up.total, 17);
  });

  testWidgets('desktop cart and checkout fill the right panel to the bottom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosScreen(
            api: _PosApi(),
            products: const [
              {
                'id': 'P-1',
                'name': 'Rice',
                'price': 100,
                'stock': 5,
                'status': 'Active',
              },
            ],
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice').first);
    await tester.pumpAndSettle();

    final cart =
        find
            .ancestor(
              of: find.text('Current sale'),
              matching: find.byType(Card),
            )
            .first;
    final checkout = find.widgetWithText(
      FilledButton,
      'Choose payment & complete',
    );
    expect(
      tester.getBottomLeft(cart).dy - tester.getBottomLeft(checkout).dy,
      lessThan(35),
    );
    expect(800 - tester.getBottomLeft(cart).dy, lessThan(30));
    expect(800 - tester.getBottomLeft(checkout).dy, lessThan(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop product grid fills the space below its last row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosScreen(
            api: _PosApi(),
            products: List.generate(
              9,
              (index) => {
                'id': 'P-$index',
                'name': 'Item ${index + 1}',
                'price': 10,
                'stock': 5,
                'status': 'Active',
              },
            ),
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final lastProductCard =
        find
            .ancestor(of: find.text('Item 9'), matching: find.byType(Card))
            .first;
    expect(800 - tester.getBottomLeft(lastProductCard).dy, lessThan(35));
    expect(tester.takeException(), isNull);
  });

  testWidgets('POS saves chosen discount, tax and matching payment on phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _PosApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosScreen(
            api: api,
            products: const [
              {
                'id': 'P-1',
                'name': 'Rice',
                'price': 100,
                'stock': 5,
                'status': 'Active',
              },
            ],
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pos-discount-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percent').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pos-discount-value')),
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('pos-tax-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom rate').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pos-custom-tax-rate')),
      '7.5',
    );
    await tester.pumpAndSettle();
    expect(find.text('97.00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pos-rounding-adjustment')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('pos-round-to-whole')));
    await tester.pumpAndSettle();
    expect(find.text('96.75'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pos-round-to-whole')));
    await tester.pumpAndSettle();
    expect(find.text('97.00'), findsOneWidget);
    await tester.tap(find.text('Choose payment & complete'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-amount-Cash')),
      '97',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();
    expect(api.sale?['discountType'], 'percent');
    expect(api.sale?['discountValue'], 10);
    expect(api.sale?['taxRate'], 7.5);
    expect((api.sale?['payments'] as List).single['amount'], 97);
    expect(api.sale?['roundToWhole'], true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty sale hides totals and checkout until a product is added', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosScreen(
            api: _PosApi(),
            products: const [
              {
                'id': 'P-1',
                'name': 'Rice',
                'barcode': '00123',
                'price': 10,
                'stock': 2,
                'status': 'Active',
              },
            ],
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No items in this sale'), findsOneWidget);
    expect(find.text('Subtotal'), findsNothing);
    expect(find.text('Choose payment & complete'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('pos-scan-barcode')),
      '00123',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('No items in this sale'), findsNothing);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Choose payment & complete'), findsOneWidget);
    expect(find.textContaining('Rice added'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('pos-scan-barcode')),
      '00123',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('2 in sale'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('pos-scan-barcode')),
      '00123',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('out of stock'), findsOneWidget);
  });

  testWidgets('unknown and duplicate barcodes never add the wrong product', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosScreen(
            api: _PosApi(),
            products: const [
              {
                'id': 'P-1',
                'name': 'Rice',
                'barcode': 'DUP',
                'price': 10,
                'stock': 2,
                'status': 'Active',
              },
              {
                'id': 'P-2',
                'name': 'Milk',
                'barcode': 'DUP',
                'price': 5,
                'stock': 2,
                'status': 'Active',
              },
            ],
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pos-scan-barcode')),
      'MISSING',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('not found'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('pos-scan-barcode')),
      'DUP',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('multiple products'), findsOneWidget);
    expect(find.text('No items in this sale'), findsOneWidget);
  });

  testWidgets(
    'zero-stock products are hidden and cannot be scanned into a sale',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosScreen(
              api: _PosApi(),
              products: const [
                {
                  'id': 'P-0',
                  'name': 'Empty item',
                  'barcode': '0000',
                  'price': 3,
                  'stock': 0,
                  'status': 'Active',
                },
              ],
              onUpdated: () {},
              message: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Empty item'), findsNothing);
      expect(find.textContaining('No in-stock products'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pos-scan-barcode')),
        '0000',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.textContaining('out of stock'), findsOneWidget);
      expect(find.text('No items in this sale'), findsOneWidget);
    },
  );
}
