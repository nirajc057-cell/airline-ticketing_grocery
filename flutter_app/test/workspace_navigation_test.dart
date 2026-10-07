import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/modules.dart';
import 'package:aerodesk_client/workspace_navigation.dart';
import 'package:aerodesk_client/named_table_repository.dart';

Widget navigationHarness({
  bool grocery = false,
  bool collapsed = false,
  void Function(ModuleSpec)? onNavigate,
  VoidCallback? onToggleCollapsed,
  VoidCallback? onChangePassword,
  VoidCallback? onTwoFactor,
  VoidCallback? onSignOut,
  List<NamedTableSummary> tables = const [],
  ValueChanged<String?>? onSelectTable,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: collapsed ? 78 : 304,
      height: 800,
      child: WorkspaceNavigation(
        modules: grocery ? groceryModules : airlineModules,
        selectedKey: 'dashboard',
        tables: tables,
        onSelectTable: onSelectTable,
        user: const {'name': 'Nischal Chaudhary', 'role': 'Agency owner'},
        grocery: grocery,
        isWide: true,
        collapsed: collapsed,
        onNavigate: onNavigate ?? (_) {},
        onSwitch: () {},
        onChangePassword: onChangePassword ?? () {},
        onTwoFactor: onTwoFactor ?? () {},
        onSignOut: onSignOut ?? () {},
        onToggleCollapsed: onToggleCollapsed ?? () {},
        onClose: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('Company Assets opens from AeroDesk and FreshMart sidebars', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      navigationHarness(onNavigate: (module) => selected = module.key),
    );
    await tester.tap(find.text('Company Assets'));
    expect(selected, 'company_assets');
    selected = null;
    await tester.pumpWidget(
      navigationHarness(
        grocery: true,
        onNavigate: (module) => selected = module.key,
      ),
    );
    await tester.tap(find.text('Company Assets'));
    expect(selected, 'company_assets');
  });

  testWidgets('created table appears by name in sidebar and opens', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      navigationHarness(
        tables: const [
          NamedTableSummary(
            id: 'T-1',
            name: 'My Accounts',
            platform: 'airline',
            rowCount: 2,
            columnCount: 3,
          ),
        ],
        onSelectTable: (id) => opened = id,
      ),
    );
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(find.text('My Accounts'), findsOneWidget);
    await tester.tap(find.text('My Accounts'));
    expect(opened, 'T-1');
  });

  testWidgets('AeroDesk Table is a separate top-level sidebar item', (
    tester,
  ) async {
    String? destination;
    await tester.pumpWidget(
      navigationHarness(onNavigate: (module) => destination = module.key),
    );
    await tester.tap(find.text('Table'));
    expect(destination, 'table');
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu search finds a nested destination', (tester) async {
    await tester.pumpWidget(navigationHarness());
    await tester.enterText(find.byType(TextField), 'passport');
    await tester.pumpAndSettle();
    expect(find.text('Passport services'), findsOneWidget);
    expect(find.text('Customers'), findsNothing);
  });

  testWidgets('all AeroDesk destinations remain searchable', (tester) async {
    await tester.pumpWidget(navigationHarness());
    for (final module in airlineModules.where(
      (module) => !{'quotes', 'audit'}.contains(module.key),
    )) {
      await tester.enterText(find.byType(TextField), module.title);
      await tester.pump();
      expect(find.text(module.title), findsWidgets, reason: module.key);
    }
  });

  testWidgets('collapsed sidebar keeps icons and expand action', (
    tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      navigationHarness(
        collapsed: true,
        onToggleCollapsed: () => toggled = true,
      ),
    );
    expect(find.text('Travel operations'), findsNothing);
    await tester.tap(find.byTooltip('Expand sidebar'));
    expect(toggled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FreshMart Table is separate from Inventory', (tester) async {
    await tester.pumpWidget(navigationHarness(grocery: true));
    expect(find.text('Table'), findsOneWidget);
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(find.text('Products & inventory'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
  });

  testWidgets('Payment methods is a sidebar destination in both workspaces', (
    tester,
  ) async {
    for (final grocery in [false, true]) {
      String? destination;
      await tester.pumpWidget(
        navigationHarness(
          grocery: grocery,
          onNavigate: (module) => destination = module.key,
        ),
      );
      await tester.tap(find.text('Payment methods'));
      expect(destination, 'payment_methods');
    }
  });

  testWidgets('all FreshMart destinations remain searchable', (tester) async {
    await tester.pumpWidget(navigationHarness(grocery: true));
    for (final module in groceryModules.where(
      (module) => module.key != 'audit',
    )) {
      await tester.enterText(find.byType(TextField), module.title);
      await tester.pump();
      expect(find.text(module.title), findsWidgets, reason: module.key);
    }
  });

  testWidgets('Quotations and Audit are absent from the sidebar', (
    tester,
  ) async {
    await tester.pumpWidget(navigationHarness());
    await tester.enterText(find.byType(TextField), 'quotations');
    await tester.pumpAndSettle();
    expect(find.text('Quotations'), findsNothing);
    await tester.enterText(find.byType(TextField), 'audit');
    await tester.pumpAndSettle();
    expect(find.text('Audit trail'), findsNothing);
  });

  testWidgets('account footer retains password action', (tester) async {
    var passwordRequested = false;
    var twoFactorRequested = false;
    var signOutRequested = false;
    await tester.pumpWidget(
      navigationHarness(
        onChangePassword: () => passwordRequested = true,
        onTwoFactor: () => twoFactorRequested = true,
        onSignOut: () => signOutRequested = true,
      ),
    );
    await tester.tap(find.byTooltip('Account actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change password'));
    expect(passwordRequested, isTrue);
    expect(twoFactorRequested, isFalse);
    expect(signOutRequested, isFalse);
  });
}
