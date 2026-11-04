import 'package:aerodesk_client/financial_register.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testPage(FinancialRegister register) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(16), child: register),
    ),
  ),
);

void main() {
  testWidgets('sample sales stack on a phone and cannot be printed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opens = 0;
    var prints = 0;
    await tester.pumpWidget(
      _testPage(
        FinancialRegister(
          title: 'Sales register',
          kind: FinancialRecordKind.grocerySale,
          demo: true,
          rows: const [
            {
              'id': 'DEMO-GS-1',
              'receipt': 'DEMO-FM-1',
              'total': 18.52,
              'items': [
                {'name': 'Rice', 'qty': 1, 'total': 18.52},
              ],
            },
            {
              'id': 'DEMO-GS-2',
              'receipt': 'DEMO-FM-2',
              'total': 2.50,
              'items': [
                {'name': 'Water', 'qty': 2, 'total': 2.50},
              ],
            },
          ],
          onOpenRecord: (_) => opens++,
          onPrintRecord: (_) => prints++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sales register (2)'), findsOneWidget);
    expect(find.text('RECEIPT PREVIEW'), findsOneWidget);
    expect(find.textContaining('SAMPLE ONLY'), findsOneWidget);
    expect(find.text('Print receipt'), findsNothing);
    expect(find.text('Open full record'), findsNothing);
    expect(find.text('Expand selected'), findsOneWidget);
    expect(find.text('Water'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('financial-record-select-1')),
    );
    await tester.tap(find.byKey(const ValueKey('financial-record-select-1')));
    await tester.pumpAndSettle();
    expect(find.text('2× Water'), findsOneWidget);
    expect(find.text('Water'), findsNothing);
    expect(find.text('Expand selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('financial-record-expand-1')));
    await tester.pumpAndSettle();
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Collapse all'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('financial-record-expand-0')),
    );
    await tester.tap(find.byKey(const ValueKey('financial-record-expand-0')));
    await tester.pumpAndSettle();
    expect(find.text('2× Water'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(opens, 0);
    expect(prints, 0);
  });

  testWidgets('recorded expense provides its real record actions', (
    tester,
  ) async {
    Map<String, dynamic>? printed;
    await tester.pumpWidget(
      _testPage(
        FinancialRegister(
          title: 'Expense register',
          kind: FinancialRecordKind.expense,
          rows: const [
            {
              'id': 'EXP-1',
              'reference': 'BILL-1',
              'payee': 'Landlord',
              'description': 'Rent',
              'total': 500,
              'paidAmount': 200,
              'outstanding': 300,
            },
          ],
          onPrintRecord: (row) => printed = row,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EXPENSE PREVIEW'), findsOneWidget);
    expect(find.text('PAYMENT POSITION'), findsOneWidget);
    expect(find.text('Print voucher'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('financial-record-expand-0')));
    await tester.pumpAndSettle();
    expect(find.text('300.00'), findsWidgets);
    await tester.ensureVisible(find.text('Print voucher'));
    await tester.tap(find.text('Print voucher'));
    expect(printed?['id'], 'EXP-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AeroDesk sample sale shows disabled receipt actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opens = 0;
    var prints = 0;
    await tester.pumpWidget(
      _testPage(
        FinancialRegister(
          title: 'Sales',
          kind: FinancialRecordKind.airlineSale,
          demo: true,
          rows: const [
            {
              'id': 'DEMO-AS-1',
              'customerName': 'Sample Traveler',
              'description': 'Sample service',
              'total': 0.52,
              'payments': [
                {'method': 'eSewa', 'amount': 0.52},
              ],
            },
          ],
          onOpenRecord: (_) => opens++,
          onPrintRecord: (_) => prints++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('eSewa: 0.52'), findsOneWidget);
    expect(find.text('Open full record'), findsOneWidget);
    expect(find.text('Print receipt'), findsOneWidget);
    for (final label in ['Open full record', 'Print receipt']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    }
    expect(opens, 0);
    expect(prints, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AeroDesk actions target the selected sale', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? openedId;
    String? printedId;
    await tester.pumpWidget(
      _testPage(
        FinancialRegister(
          title: 'Sales',
          kind: FinancialRecordKind.airlineSale,
          rows: const [
            {'id': 'AS-1', 'customerName': 'First traveler', 'total': 10},
            {'id': 'AS-2', 'customerName': 'Second traveler', 'total': 20},
          ],
          onOpenRecord: (row) => openedId = row['id']?.toString(),
          onPrintRecord: (row) => printedId = row['id']?.toString(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('financial-record-select-1')));
    await tester.pumpAndSettle();
    expect(find.text('Second traveler'), findsOneWidget);
    await tester.tap(find.text('Open full record'));
    await tester.tap(find.text('Print receipt'));
    expect(openedId, 'AS-2');
    expect(printedId, 'AS-2');
    expect(tester.takeException(), isNull);
  });
}
