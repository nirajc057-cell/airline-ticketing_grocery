import 'package:flutter/material.dart';
import 'api.dart';
import 'form_sheet.dart';
import 'modules.dart';
import 'named_table_repository.dart';
import 'named_tables_screen.dart';
import 'payment_methods_screen.dart';
import 'screens.dart';
import 'table_screen.dart';
import 'travel_ui.dart';
import 'workspace_navigation.dart';

const legacyAccent = Color(0xff0e897b);

void main() => runApp(const AeroDeskApp());

class AeroDeskApp extends StatelessWidget {
  const AeroDeskApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AeroDesk & FreshMart',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: legacyAccent,
      ).copyWith(primary: legacyAccent, surface: Colors.white),
      scaffoldBackgroundColor: const Color(0xfff5f7f8),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xffe4eaee)),
        ),
      ),
    ),
    home: const Workspace(),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final ApiClient api = ApiClient();
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<TableScreenState> tableKey = GlobalKey<TableScreenState>();
  final GlobalKey<NamedTablesScreenState> namedTableKey =
      GlobalKey<NamedTablesScreenState>();
  Map<String, dynamic>? user;
  bool restoring = false;
  bool grocery = false;
  bool sidebarCollapsed = false;
  String selected = 'dashboard';
  String? selectedTableId;
  List<NamedTableSummary> namedTables = [];
  int refreshKey = 0;

  @override
  void initState() {
    super.initState();
    if (api.token != null) {
      restoring = true;
      _restoreSession();
    }
  }

  Future<void> _restoreSession() async {
    try {
      final bootstrap = asMap(await api.get('/api/bootstrap'));
      if (mounted) {
        setState(() => user = asMap(bootstrap['user']));
        await _loadTableSummaries();
      }
    } catch (_) {
      await api.logout();
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> signIn(String email, String password, String otp) async {
    final login = await api.login(email, password, otp);
    final bootstrap = asMap(await api.get('/api/bootstrap'));
    if (!mounted) return;
    setState(() {
      user = asMap(bootstrap['user']);
      selected = 'dashboard';
      selectedTableId = null;
      refreshKey++;
    });
    await _loadTableSummaries();
    if (asMap(login['user'])['mustChangePassword'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => changePassword());
    }
  }

  Future<void> signOut() async {
    if (!await _confirmTableExit()) return;
    await api.logout();
    if (mounted) {
      setState(() {
        user = null;
        grocery = false;
        selected = 'dashboard';
        selectedTableId = null;
        namedTables = [];
      });
    }
  }

  Future<void> changePassword() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        final current = TextEditingController(),
            next = TextEditingController(),
            confirm = TextEditingController();
        return AlertDialog(
          title: const Text('Change password'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.pop(context, {
                    'currentPassword': current.text,
                    'password': next.text,
                    'confirmPassword': confirm.text,
                  }),
              child: const Text('Change'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    try {
      await api.post('/api/account/change-password', result);
      message('Password changed');
      final bootstrap = asMap(await api.get('/api/bootstrap'));
      if (mounted) setState(() => user = asMap(bootstrap['user']));
    } catch (error) {
      message(error.toString());
    }
  }

  Future<void> twoFactor() async {
    try {
      if (user?['twoFactorEnabled'] == true) {
        final result = await showRecordForm(
          context,
          'Disable two-factor authentication',
          const [
            FieldSpec(
              'password',
              'Current password',
              required: true,
              type: FieldType.password,
            ),
          ],
        );
        if (result == null) return;
        await api.post('/api/account/2fa/disable', result);
        message('Two-factor authentication disabled');
      } else {
        final setup = asMap(
          await api.post('/api/account/2fa/setup', <String, dynamic>{}),
        );
        if (!mounted) return;
        final result = await showRecordForm(
          context,
          'Add this secret to your authenticator: ${setup['secret']}',
          const [
            FieldSpec('code', '6-digit authenticator code', required: true),
          ],
        );
        if (result == null) return;
        await api.post('/api/account/2fa/verify', result);
        message('Two-factor authentication enabled');
      }
      final bootstrap = asMap(await api.get('/api/bootstrap'));
      if (mounted) setState(() => user = asMap(bootstrap['user']));
    } catch (error) {
      message(error.toString());
    }
  }

  List<ModuleSpec> get modules {
    if (grocery) return groceryModules;
    final permissions = asMap(user?['permissions']);
    return airlineModules
        .where(
          (module) =>
              module.key == 'dashboard' ||
              module.key == 'payment_methods' ||
              (module.key == 'table' && permissions['bookings'] == true) ||
              (module.key == 'roles' && permissions['users'] == true) ||
              permissions[module.key] == true ||
              user?['role'] == 'Agency owner',
        )
        .toList();
  }

  Future<bool> _confirmTableExit() async {
    if (selected != 'table' ||
        (tableKey.currentState?.hasPendingChanges != true &&
            namedTableKey.currentState?.hasPendingChanges != true)) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Discard unsaved table changes?'),
                content: const Text(
                  'Use Save to keep your edits before leaving the table.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Stay'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Discard'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> navigate(ModuleSpec module) async {
    if ((module.key != selected ||
            (module.key == 'table' && selectedTableId != null)) &&
        !await _confirmTableExit()) {
      return;
    }
    setState(() {
      selected = module.key;
      if (module.key == 'table') selectedTableId = null;
      refreshKey++;
    });
    scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> _loadTableSummaries() async {
    final requestedPlatform = grocery;
    final requestedUser = user?['email'];
    try {
      final loaded = await NamedTableRepository(api).list(requestedPlatform);
      if (mounted &&
          grocery == requestedPlatform &&
          user?['email'] == requestedUser) {
        setState(() => namedTables = loaded);
      }
    } catch (exception) {
      if (mounted) message('Could not load tables: $exception');
    }
  }

  Future<void> selectTable(String? id) async {
    if (selected == 'table' &&
        selectedTableId != id &&
        !await _confirmTableExit()) {
      return;
    }
    if (!mounted) return;
    setState(() {
      selected = 'table';
      selectedTableId = id;
      refreshKey++;
    });
    scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> switchPlatform() async {
    if (!await _confirmTableExit()) return;
    setState(() {
      grocery = !grocery;
      selected = 'dashboard';
      selectedTableId = null;
      namedTables = [];
      refreshKey++;
    });
    await _loadTableSummaries();
    scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> refreshScreen() async {
    if (!await _confirmTableExit()) return;
    if (mounted) setState(() => refreshKey++);
  }

  Widget _workspaceNavigation({required bool isWide}) => WorkspaceNavigation(
    key: ValueKey(grocery ? 'grocery-navigation' : 'airline-navigation'),
    modules: modules,
    selectedKey: selected,
    selectedTableId: selectedTableId,
    tables: namedTables,
    user: user!,
    grocery: grocery,
    isWide: isWide,
    collapsed: sidebarCollapsed,
    onNavigate: navigate,
    onSelectTable: selectTable,
    onSwitch: switchPlatform,
    onChangePassword: changePassword,
    onTwoFactor: twoFactor,
    onSignOut: signOut,
    onToggleCollapsed:
        () => setState(() => sidebarCollapsed = !sidebarCollapsed),
    onClose: () => scaffoldKey.currentState?.closeDrawer(),
  );

  Widget _travelTopBar(ModuleSpec current, bool isWide) {
    final subtitle = switch (current.key) {
      'dashboard' => 'Your travel workspace at a glance',
      'bookings' => 'Journeys, reservations and tickets',
      'passports' => 'Passport applications and collections',
      'quotes' => 'Travel plans and quotations',
      'table' => 'Create and manage your own tables',
      'company_assets' => 'Track items issued to employees',
      'payment_methods' =>
        'Bank and wallet details used throughout the workspace',
      'finance' => 'Track money in, money out, and what is owed',
      _ => 'Manage your travel experience',
    };
    final name = user?['name']?.toString() ?? 'Traveler';
    return Container(
      height: isWide ? 95 : 76,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 28 : 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: TravelPalette.border)),
      ),
      child: Row(
        children: [
          if (!isWide) ...[
            Builder(
              builder:
                  (context) => IconButton(
                    tooltip: 'Open menu',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
            ),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TravelPalette.ink,
                    fontSize: isWide ? 25 : 19,
                    letterSpacing: -.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isWide)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        color: TravelPalette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isWide) ...[
            OutlinedButton.icon(
              onPressed: switchPlatform,
              icon: const Icon(Icons.storefront_outlined, size: 17),
              label: const Text('FreshMart'),
            ),
            const SizedBox(width: 10),
          ],
          IconButton.outlined(
            tooltip: 'Refresh',
            onPressed: refreshScreen,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          const SizedBox(width: 13),
          CircleAvatar(
            radius: 20,
            backgroundColor: TravelPalette.purpleSoft,
            child: Text(
              name.isEmpty ? 'A' : name[0].toUpperCase(),
              style: const TextStyle(
                color: TravelPalette.purple,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groceryTopBar(ModuleSpec current, bool isWide) => Material(
    elevation: 0,
    color: Colors.white,
    child: SizedBox(
      height: 76,
      child: Row(
        children: [
          if (!isWide)
            Builder(
              builder:
                  (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
            ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff18242e),
                  ),
                ),
                if (isWide)
                  Text(
                    current.key == 'table'
                        ? 'Create and manage your own tables'
                        : 'Store operations and performance',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff70808d),
                    ),
                  ),
              ],
            ),
          ),
          if (isWide)
            OutlinedButton.icon(
              onPressed: switchPlatform,
              icon: const Icon(Icons.swap_horiz, size: 17),
              label: const Text('AeroDesk'),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: refreshScreen,
            icon: const Icon(Icons.refresh),
          ),
          if (isWide)
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xffd6a04b),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                (user?['name']
                            ?.toString()
                            .split(' ')
                            .map((part) => part.isEmpty ? '' : part[0])
                            .take(2)
                            .join() ??
                        'U')
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 10),
        ],
      ),
    ),
  );

  Widget _bottomNavigation() {
    final primaryKeys =
        grocery
            ? const ['dashboard', 'pos', 'products', 'table']
            : const ['dashboard', 'bookings', 'table', 'customers'];
    final primary =
        primaryKeys
            .map(
              (key) => modules.where((module) => module.key == key).firstOrNull,
            )
            .whereType<ModuleSpec>()
            .toList();
    final selectedIndex = primary.indexWhere(
      (module) => module.key == selected,
    );
    return NavigationBar(
      height: 70,
      selectedIndex: selectedIndex < 0 ? primary.length : selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        ...primary.map(
          (module) => NavigationDestination(
            icon: Icon(module.icon),
            label:
                module.key == 'dashboard'
                    ? 'Home'
                    : module.key == 'bookings'
                    ? 'Bookings'
                    : module.key == 'products'
                    ? 'Products'
                    : module.key == 'customers'
                    ? 'Customers'
                    : module.key == 'pos'
                    ? 'POS'
                    : module.title,
          ),
        ),
        const NavigationDestination(
          icon: Icon(Icons.menu_rounded),
          label: 'More',
        ),
      ],
      onDestinationSelected: (index) {
        if (index == primary.length) {
          scaffoldKey.currentState?.openDrawer();
        } else {
          navigate(primary[index]);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user == null) {
      return Theme(
        data: travelTheme(Theme.of(context)),
        child: LoginScreen(api: api, onSubmit: signIn),
      );
    }
    final isWide = MediaQuery.sizeOf(context).width >= 850;
    final current = modules.firstWhere(
      (module) => module.key == selected,
      orElse: () => modules.first,
    );
    final shell = Scaffold(
      key: scaffoldKey,
      backgroundColor: grocery ? null : TravelPalette.canvas,
      bottomNavigationBar: isWide ? null : _bottomNavigation(),
      drawer:
          isWide
              ? null
              : Drawer(
                width:
                    MediaQuery.sizeOf(context).width < 350
                        ? MediaQuery.sizeOf(context).width * .9
                        : 304,
                child: SafeArea(child: _workspaceNavigation(isWide: false)),
              ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white),
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  if (isWide)
                    SizedBox(
                      width: sidebarCollapsed ? 78 : 282,
                      child: _workspaceNavigation(isWide: true),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        grocery
                            ? _groceryTopBar(current, isWide)
                            : _travelTopBar(current, isWide),
                        Expanded(
                          child: ColoredBox(
                            color:
                                grocery
                                    ? const Color(0xfff5f7f8)
                                    : const Color(0xfffcfcfe),
                            child: KeyedSubtree(
                              key: ValueKey('$grocery-$selected-$refreshKey'),
                              child:
                                  current.key == 'table' &&
                                          selectedTableId == '__linked__'
                                      ? Column(
                                        children: [
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                              onPressed:
                                                  () => selectTable(null),
                                              icon: const Icon(
                                                Icons.arrow_back,
                                              ),
                                              label: const Text('All tables'),
                                            ),
                                          ),
                                          Expanded(
                                            child: TableScreen(
                                              key: tableKey,
                                              api: api,
                                              grocery: grocery,
                                              onUpdated:
                                                  () => setState(
                                                    () => refreshKey++,
                                                  ),
                                              message: message,
                                            ),
                                          ),
                                        ],
                                      )
                                      : current.key == 'table'
                                      ? NamedTablesScreen(
                                        key: namedTableKey,
                                        api: api,
                                        grocery: grocery,
                                        selectedTableId: selectedTableId,
                                        tables: namedTables,
                                        onSelectTable: selectTable,
                                        onTablesChanged: _loadTableSummaries,
                                        onOpenLinked:
                                            () => selectTable('__linked__'),
                                        message: message,
                                      )
                                      : current.key == 'payment_methods'
                                      ? PaymentMethodsScreen(
                                        api: api,
                                        user: user!,
                                        message: message,
                                      )
                                      : ModuleScreen(
                                        api: api,
                                        module: current,
                                        grocery: grocery,
                                        user: user!,
                                        onUpdated:
                                            () => setState(() => refreshKey++),
                                        message: message,
                                        onOpenTable: (id) => selectTable(id),
                                      ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return grocery
        ? shell
        : Theme(data: travelTheme(Theme.of(context)), child: shell);
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onSubmit});
  final ApiClient api;
  final Future<void> Function(String email, String password, String otp)
  onSubmit;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      otp = TextEditingController();
  String? error;
  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    otp.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.onSubmit(email.text, password.text, otp.text);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget signInForm(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.flight_takeoff_rounded,
                  color: TravelPalette.purple,
                  size: 25,
                ),
                SizedBox(width: 9),
                Text(
                  'AeroDesk',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: TravelPalette.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sign in to your travel workspace',
              style: TextStyle(color: TravelPalette.muted),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otp,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Authenticator code (if enabled)',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : submit,
                child:
                    loading
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('Sign in'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 760;
    return Scaffold(
      backgroundColor: TravelPalette.canvas,
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Expanded(
                flex: 11,
                child: Container(
                  height: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 42,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff24204c), Color(0xff5943cb)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.flight_takeoff_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'AeroDesk',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'YOUR TRAVEL WORKSPACE',
                            style: TextStyle(
                              color: Color(0xffc5b9ff),
                              fontSize: 11,
                              letterSpacing: 3,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Every journey.\nOne seamless place.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 50,
                              fontWeight: FontWeight.w700,
                              height: 1.07,
                            ),
                          ),
                          SizedBox(height: 18),
                          Text(
                            'Bookings, tickets, passport services and support, beautifully organized around your journey.',
                            style: TextStyle(
                              color: Color(0xffe0dcff),
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Local-first  ·  Private  ·  Ready for travel',
                        style: TextStyle(color: Color(0xffe0dcff)),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              flex: wide ? 9 : 1,
              child: ColoredBox(
                color: Colors.white,
                child: signInForm(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
