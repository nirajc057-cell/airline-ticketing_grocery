import 'package:flutter/material.dart';

import 'modules.dart';
import 'named_table_repository.dart';

const _navInk = Color(0xff0e2039);
const _navPanel = Color(0xff1a3555);
const _navText = Color(0xffeff5ff);
const _navMuted = Color(0xffacc0da);

class WorkspaceNavigation extends StatefulWidget {
  const WorkspaceNavigation({
    super.key,
    required this.modules,
    required this.selectedKey,
    this.selectedTableId,
    this.tables = const [],
    required this.user,
    required this.grocery,
    required this.isWide,
    required this.collapsed,
    required this.onNavigate,
    this.onSelectTable,
    required this.onSwitch,
    required this.onChangePassword,
    required this.onTwoFactor,
    required this.onSignOut,
    required this.onToggleCollapsed,
    required this.onClose,
  });

  final List<ModuleSpec> modules;
  final String selectedKey;
  final String? selectedTableId;
  final List<NamedTableSummary> tables;
  final Map<String, dynamic> user;
  final bool grocery;
  final bool isWide;
  final bool collapsed;
  final void Function(ModuleSpec) onNavigate;
  final ValueChanged<String?>? onSelectTable;
  final VoidCallback onSwitch;
  final VoidCallback onChangePassword;
  final VoidCallback onTwoFactor;
  final VoidCallback onSignOut;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onClose;

  @override
  State<WorkspaceNavigation> createState() => _WorkspaceNavigationState();
}

class _NavNode {
  const _NavNode(
    this.id,
    this.title,
    this.icon, {
    this.module,
    this.tableId,
    this.children = const [],
  });

  final String id;
  final String title;
  final IconData icon;
  final ModuleSpec? module;
  final String? tableId;
  final List<_NavNode> children;
  bool get isGroup => children.isNotEmpty;

  _NavNode withChildren(List<_NavNode> value) => _NavNode(
    id,
    title,
    icon,
    module: module,
    tableId: tableId,
    children: value,
  );
}

class _WorkspaceNavigationState extends State<WorkspaceNavigation> {
  final searchController = TextEditingController();
  final searchFocus = FocusNode();
  final Set<String> expanded = {};
  String query = '';

  Color get accent =>
      widget.grocery ? const Color(0xff168f68) : const Color(0xff2378f2);

  bool get compact => widget.isWide && widget.collapsed;

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(covariant WorkspaceNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedKey != widget.selectedKey ||
        oldWidget.grocery != widget.grocery ||
        oldWidget.modules.length != widget.modules.length ||
        oldWidget.selectedTableId != widget.selectedTableId ||
        oldWidget.tables.length != widget.tables.length) {
      if (oldWidget.grocery != widget.grocery) {
        expanded.clear();
        query = '';
        searchController.clear();
      }
      _revealSelection();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  List<_NavNode> _tree() {
    final byKey = {for (final module in widget.modules) module.key: module};
    _NavNode? leaf(String key) {
      final module = byKey[key];
      return module == null
          ? null
          : _NavNode(key, module.title, module.icon, module: module);
    }

    _NavNode? tableNode() {
      final module = byKey['table'];
      if (module == null) return null;
      final tables =
          widget.tables
              .where(
                (item) =>
                    item.platform == (widget.grocery ? 'grocery' : 'airline'),
              )
              .toList();
      if (tables.isEmpty) return leaf('table');
      return _NavNode(
        'table_root',
        'Table',
        module.icon,
        module: module,
        children: [
          _NavNode(
            'table_all',
            'All tables',
            Icons.grid_view_outlined,
            module: module,
          ),
          for (final item in tables)
            _NavNode(
              'table_${item.id}',
              item.name,
              Icons.table_chart_outlined,
              tableId: item.id,
            ),
        ],
      );
    }

    _NavNode? group(
      String id,
      String title,
      IconData icon,
      List<_NavNode?> entries,
    ) {
      final children = entries.whereType<_NavNode>().toList();
      return children.isEmpty
          ? null
          : _NavNode(id, title, icon, children: children);
    }

    final entries =
        widget.grocery
            ? <_NavNode?>[
              leaf('dashboard'),
              group('store_sales', 'Sales', Icons.point_of_sale_outlined, [
                leaf('pos'),
                leaf('sales'),
              ]),
              group(
                'store_inventory',
                'Inventory',
                Icons.inventory_2_outlined,
                [
                  group('store_products', 'Products', Icons.grid_on_outlined, [
                    leaf('products'),
                  ]),
                  leaf('purchases'),
                ],
              ),
              tableNode(),
              leaf('company_assets'),
              leaf('payment_methods'),
              group(
                'store_relationships',
                'Relationships',
                Icons.people_outline,
                [leaf('suppliers'), leaf('customers')],
              ),
              group('store_finance', 'Finance', Icons.payments_outlined, [
                leaf('expenses'),
                leaf('reports'),
              ]),
            ]
            : <_NavNode?>[
              leaf('dashboard'),
              group(
                'travel',
                'Travel operations',
                Icons.flight_takeoff_outlined,
                [
                  group(
                    'travel_bookings',
                    'Bookings',
                    Icons.airplane_ticket_outlined,
                    [leaf('bookings')],
                  ),
                  leaf('passports'),
                  leaf('refunds'),
                  leaf('cases'),
                ],
              ),
              tableNode(),
              leaf('company_assets'),
              leaf('payment_methods'),
              leaf('customers'),
              group(
                'business',
                'Business',
                Icons.account_balance_wallet_outlined,
                [leaf('sales'), leaf('finance'), leaf('reports')],
              ),
              group(
                'administration',
                'Administration',
                Icons.admin_panel_settings_outlined,
                [leaf('users'), leaf('roles')],
              ),
            ];
    return entries.whereType<_NavNode>().toList();
  }

  bool _containsSelected(_NavNode node) =>
      (node.tableId != null &&
          node.tableId == widget.selectedTableId &&
          widget.selectedKey == 'table') ||
      (node.module?.key == widget.selectedKey &&
          (node.id != 'table_all' || widget.selectedTableId == null)) ||
      node.children.any(_containsSelected);

  void _revealSelection() {
    void visit(_NavNode node) {
      if (node.isGroup && _containsSelected(node)) expanded.add(node.id);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in _tree()) {
      visit(node);
    }
  }

  List<_NavNode> _filtered(List<_NavNode> nodes) {
    if (query.trim().isEmpty) return nodes;
    final needle = query.trim().toLowerCase();
    _NavNode? matching(_NavNode node) {
      if (node.title.toLowerCase().contains(needle)) return node;
      final children =
          node.children.map(matching).whereType<_NavNode>().toList();
      return children.isEmpty ? null : node.withChildren(children);
    }

    return nodes.map(matching).whereType<_NavNode>().toList();
  }

  Widget _brand() {
    final title = widget.grocery ? 'FreshMart' : 'AeroDesk';
    final icon =
        widget.grocery
            ? Icons.storefront_rounded
            : Icons.flight_takeoff_rounded;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 13 : 20,
        20,
        compact ? 13 : 12,
        compact ? 14 : 18,
      ),
      child:
          compact
              ? Column(
                children: [
                  _brandIcon(icon),
                  const SizedBox(height: 14),
                  IconButton(
                    tooltip: 'Expand sidebar',
                    onPressed: widget.onToggleCollapsed,
                    icon: const Icon(
                      Icons.keyboard_double_arrow_right_rounded,
                      color: _navMuted,
                      size: 22,
                    ),
                  ),
                ],
              )
              : Row(
                children: [
                  _brandIcon(icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.isWide ? 'Collapse sidebar' : 'Close menu',
                    onPressed:
                        widget.isWide
                            ? widget.onToggleCollapsed
                            : widget.onClose,
                    icon: Icon(
                      widget.isWide
                          ? Icons.keyboard_double_arrow_left_rounded
                          : Icons.close_rounded,
                      color: _navMuted,
                      size: 22,
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _brandIcon(IconData icon) => Container(
    height: 42,
    width: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: Colors.white, size: 25),
  );

  Widget _search() {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        child: IconButton(
          tooltip: 'Search menu',
          onPressed: () {
            widget.onToggleCollapsed();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) searchFocus.requestFocus();
            });
          },
          icon: const Icon(Icons.search_rounded, color: _navMuted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: TextField(
        controller: searchController,
        focusNode: searchFocus,
        onChanged: (value) => setState(() => query = value),
        style: const TextStyle(color: _navText, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: _navPanel,
          hintText: 'Search menu…',
          hintStyle: const TextStyle(color: _navMuted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _navMuted,
            size: 20,
          ),
          suffixIcon:
              query.isEmpty
                  ? null
                  : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _navMuted,
                      size: 18,
                    ),
                  ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accent, width: 1.3),
          ),
        ),
      ),
    );
  }

  Widget _node(_NavNode node, int depth) {
    final selected =
        node.tableId != null
            ? node.tableId == widget.selectedTableId &&
                widget.selectedKey == 'table'
            : node.module?.key == widget.selectedKey &&
                (node.id != 'table_all' || widget.selectedTableId == null) &&
                (node.id != 'table_root' || widget.selectedTableId == null);
    final containsSelected = _containsSelected(node);
    final open = query.isNotEmpty || expanded.contains(node.id);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Tooltip(
          message: node.title,
          child: Material(
            color: containsSelected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (node.isGroup) {
                  expanded.add(node.id);
                  widget.onToggleCollapsed();
                } else if (node.tableId != null) {
                  widget.onSelectTable?.call(node.tableId);
                } else if (node.module != null) {
                  widget.onNavigate(node.module!);
                }
              },
              child: SizedBox(
                height: 48,
                child: Icon(
                  node.icon,
                  color: containsSelected ? Colors.white : _navMuted,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final background =
        selected
            ? accent
            : node.isGroup && open
            ? _navPanel
            : Colors.transparent;
    final textColor = selected ? Colors.white : _navText;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(13 + depth * 10, 2, 13, 2),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () {
                if (node.isGroup) {
                  setState(() {
                    if (!expanded.add(node.id)) expanded.remove(node.id);
                  });
                  if (node.id == 'table_root' && node.module != null) {
                    widget.onNavigate(node.module!);
                  }
                } else if (node.tableId != null) {
                  widget.onSelectTable?.call(node.tableId);
                } else if (node.module != null) {
                  widget.onNavigate(node.module!);
                }
              },
              child: SizedBox(
                height: depth > 1 ? 39 : 48,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: depth > 0 ? 11 : 13,
                  ),
                  child: Row(
                    children: [
                      if (depth > 1)
                        Container(
                          width: 3,
                          height: 22,
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )
                      else
                        Icon(
                          node.icon,
                          size: 20,
                          color: selected ? Colors.white : _navMuted,
                        ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          node.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: depth > 1 ? 12.5 : 13.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (node.isGroup)
                        Icon(
                          open
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.chevron_right_rounded,
                          size: 19,
                          color: selected ? Colors.white : _navMuted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (node.isGroup && open)
          Padding(
            padding: EdgeInsets.only(left: 7 + depth * 10, bottom: 5),
            child: Column(
              children:
                  node.children
                      .map((child) => _node(child, depth + 1))
                      .toList(),
            ),
          ),
      ],
    );
  }

  Widget _footer() {
    final name = widget.user['name']?.toString() ?? 'Account';
    final role = widget.user['role']?.toString() ?? 'Team member';
    final initials =
        name.trim().isEmpty
            ? 'A'
            : name
                .trim()
                .split(RegExp(r'\s+'))
                .take(2)
                .map((part) => part[0].toUpperCase())
                .join();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(color: Color(0xff36506d), height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 14,
            10,
            compact ? 12 : 14,
            3,
          ),
          child: Tooltip(
            message:
                widget.grocery ? 'Switch to AeroDesk' : 'Switch to FreshMart',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onSwitch,
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisAlignment:
                        compact
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.swap_horiz_rounded,
                        color: _navMuted,
                        size: 21,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.grocery
                                ? 'Switch to AeroDesk'
                                : 'Switch to FreshMart',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _navMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 14,
            5,
            compact ? 8 : 14,
            14,
          ),
          child: PopupMenuButton<String>(
            tooltip: 'Account actions',
            onSelected: (value) {
              switch (value) {
                case 'password':
                  widget.onChangePassword();
                case 'twoFactor':
                  widget.onTwoFactor();
                case 'signOut':
                  widget.onSignOut();
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'password',
                    child: Text('Change password'),
                  ),
                  PopupMenuItem(
                    value: 'twoFactor',
                    child: Text(
                      widget.user['twoFactorEnabled'] == true
                          ? 'Disable two-factor'
                          : 'Enable two-factor',
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'signOut',
                    child: Text('Sign out'),
                  ),
                ],
            child: Container(
              height: 56,
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
              decoration: BoxDecoration(
                color: _navPanel,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment:
                    compact
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xff47698d),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _navText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _navMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _navMuted,
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _filtered(_tree());
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navInk, Color(0xff112b49)],
        ),
      ),
      child: Column(
        children: [
          _brand(),
          _search(),
          Expanded(
            child:
                nodes.isEmpty
                    ? const Center(
                      child: Text(
                        'No matching menu items',
                        style: TextStyle(color: _navMuted),
                      ),
                    )
                    : ListView(
                      padding: const EdgeInsets.fromLTRB(0, 1, 0, 16),
                      children: nodes.map((node) => _node(node, 0)).toList(),
                    ),
          ),
          _footer(),
        ],
      ),
    );
  }
}
