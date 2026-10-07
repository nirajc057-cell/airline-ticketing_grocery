import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FinanceApi extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/finance/overview')) {
      return {
        'wallet': {'balance': 100},
        'openingBalance': 80,
        'closingBalance': 100,
        'walletRows': [
          {
            'id': 'WT-1',
            'reference': 'Wallet receipt',
            'type': 'Payment',
            'amount': 20,
          },
        ],
        'ledgerRows': [
          {'id': 'LD-1', 'reference': 'Journal entry', 'amount': 20},
        ],
        'receivables': [
          {'id': 'BK-1', 'reference': 'Customer balance', 'outstanding': 40},
        ],
        'payables': [
          {'id': 'PO-1', 'reference': 'Supplier balance', 'outstanding': 10},
        ],
        'pendingAdjustments': [
          {'id': 'ADJ-1', 'reference': 'Adjustment request'},
        ],
        'reconciliations': [
          {'id': 'REC-1', 'reference': 'Bank reconciliation'},
        ],
        'lockedPeriods': [
          {'id': 'PER-1', 'reference': 'Closed month'},
        ],
        'settings': <String, dynamic>{},
      };
    }
    throw StateError('Unexpected request: $path');
  }
}

void main() {
  testWidgets('finance view keeps all records and actions on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final finance = airlineModules.firstWhere(
      (module) => module.key == 'finance',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(
            api: _FinanceApi(),
            module: finance,
            grocery: false,
            user: const {'role': 'Agency owner'},
            onUpdated: () {},
            message: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wallet movements (1)'), findsOneWidget);
    expect(find.text('Wallet receipt'), findsOneWidget);
    expect(find.text('CURRENT WALLET BALANCE'), findsOneWidget);

    await tester.ensureVisible(find.text('Ledger (1)').first);
    await tester.tap(find.text('Ledger (1)').first);
    await tester.pumpAndSettle();
    expect(find.text('Journal entry'), findsOneWidget);

    await tester.ensureVisible(find.text('Receivables (1)').first);
    await tester.tap(find.text('Receivables (1)').first);
    await tester.pumpAndSettle();
    expect(find.text('Customer balance'), findsOneWidget);

    await tester.ensureVisible(find.text('Payables (1)').first);
    await tester.tap(find.text('Payables (1)').first);
    await tester.pumpAndSettle();
    expect(find.text('Supplier balance'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Other finance views'));
    await tester.tap(find.byTooltip('Other finance views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjustments (1)').last);
    await tester.pumpAndSettle();
    expect(find.text('Adjustment request'), findsOneWidget);

    await tester.ensureVisible(find.text('More actions'));
    await tester.tap(find.text('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Post journal'), findsOneWidget);
    expect(find.text('Financial reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
