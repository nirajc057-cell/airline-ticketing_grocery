import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'booking_form_fields.dart';
import 'demo_sales_preview.dart';
import 'financial_register.dart';
import 'inline_cell_layout.dart';
import 'record_print.dart';
import 'table_view_ui.dart';
import 'form_sheet.dart';
import 'modules.dart';
import 'named_table_repository.dart';
import 'payment_dialog.dart';
import 'transactions.dart';
import 'travel_ui.dart';

class _RecordTableMeta {
  _RecordTableMeta(this.fields, this.columnOrder, this.rowOrder);
  final List<FieldSpec> fields;
  final List<String> columnOrder;
  final List<String> rowOrder;
}

class ModuleScreen extends StatefulWidget {
  const ModuleScreen({
    super.key,
    required this.api,
    required this.module,
    required this.grocery,
    required this.user,
    required this.onUpdated,
    required this.message,
    this.onOpenTable,
  });
  final ApiClient api;
  final ModuleSpec module;
  final bool grocery;
  final Map<String, dynamic> user;
  final VoidCallback onUpdated;
  final void Function(String) message;
  final ValueChanged<String>? onOpenTable;
  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  late Future<dynamic> future = widget.api.get(widget.module.path);
  Future<List<dynamic>>? groceryReportsFuture;
  bool _showDemoFinancialPreview = kDebugMode;
  Future<dynamic>? recentBookingsFuture;
  String search = '';
  String status = '';
  final _recordSearchController = TextEditingController();
  int _tablePage = 0;
  int _tablePageSize = 10;
  String? _tableSortKey;
  bool _tableSortAscending = true;
  Future<_RecordTableMeta>? _tableMetaFuture;
  String? _editingRecordId;
  String? _editingFieldKey;
  final _cellEditor = TextEditingController();
  final _tableHorizontal = ScrollController();
  final _tableVertical = ScrollController();
  final _tableActionsVertical = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tableVertical.addListener(_syncActionsToTable);
    _tableActionsVertical.addListener(_syncTableToActions);
  }

  void _syncActionsToTable() =>
      _syncTableVerticalScroll(_tableVertical, _tableActionsVertical);

  void _syncTableToActions() =>
      _syncTableVerticalScroll(_tableActionsVertical, _tableVertical);

  void _syncTableVerticalScroll(
    ScrollController source,
    ScrollController target,
  ) {
    if (!source.hasClients || !target.hasClients) return;
    final offset =
        source.offset
            .clamp(
              target.position.minScrollExtent,
              target.position.maxScrollExtent,
            )
            .toDouble();
    if ((target.offset - offset).abs() > 0.5) target.jumpTo(offset);
  }

  @override
  void dispose() {
    _recordSearchController.dispose();
    _cellEditor.dispose();
    _tableHorizontal.dispose();
    _tableVertical.dispose();
    _tableActionsVertical.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Widget _tableAlerts() => _TableAlerts(
    api: widget.api,
    grocery: widget.grocery,
    message: widget.message,
    onOpenTable: widget.onOpenTable,
  );

  void reload() => setState(() {
    future = widget.api.get(_collectionSearchPath);
    _tableMetaFuture = null;
    groceryReportsFuture = null;
    recentBookingsFuture = null;
  });

  String get _collectionSearchPath {
    if (widget.module.columns.isEmpty || search.trim().isEmpty) {
      return widget.module.path;
    }
    return '${widget.module.path}?search=${Uri.encodeQueryComponent(search.trim())}';
  }

  void _searchRecords(String value) {
    setState(() {
      search = value;
      _tablePage = 0;
    });
    _searchDebounce?.cancel();
    if (widget.module.columns.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => future = widget.api.get(_collectionSearchPath));
      }
    });
  }

  Future<void> request(
    String method,
    String path,
    Map<String, dynamic> body,
    String success,
  ) async {
    try {
      await widget.api.request(method, path, body);
      widget.message(success);
      reload();
    } catch (error) {
      widget.message(error.toString());
    }
  }

  Future<void> create() async {
    if (widget.module.key == 'sales' && !widget.grocery) {
      final fields = await _loadRecordFields();
      if (!mounted || fields == null) return;
      final details = await showRecordForm(
        context,
        'New direct sale',
        fields,
        api: widget.api,
        onManageFields:
            _canManageRecordFields ? _manageRecordFieldsInForm : null,
      );
      if (details == null || !mounted) return;
      final total = (details['total'] as num).toDouble();
      if (total <= 0) {
        widget.message('Total must be greater than zero');
        return;
      }
      final split = await showConfiguredSplitPayment(
        context,
        api: widget.api,
        max: total,
        exact: true,
      );
      if (split != null) {
        await request('POST', '/api/sales', {
          ...details,
          'payments': split['payments'],
        }, 'Sale recorded');
      }
      return;
    }
    if (widget.module.key == 'roles') {
      final result = await showRoleForm(context);
      if (result != null) {
        await request('POST', '/api/roles', result, 'Role created');
      }
      return;
    }
    if (widget.module.key == 'purchases' && widget.grocery) {
      try {
        final result = await showPurchaseForm(
          context,
          widget.api,
          canManageFields: _canManageRecordFields,
        );
        if (result != null) {
          await request(
            'POST',
            widget.module.path,
            result,
            'Purchase order created',
          );
        }
      } catch (error) {
        widget.message(error.toString());
      }
      return;
    }
    final configurableForm = _hasConfigurableForm;
    final fields =
        configurableForm ? await _loadRecordFields() : widget.module.fields;
    if (!mounted || fields == null) return;
    final result = await showRecordForm(
      context,
      widget.module.createLabel ?? 'New record',
      fields,
      api: widget.api,
      onManageFields:
          configurableForm && _canManageRecordFields
              ? _manageRecordFieldsInForm
              : null,
    );
    if (result == null) return;
    if (!widget.grocery && widget.module.key == 'bookings') {
      result['manual'] = true;
    }
    await request('POST', widget.module.path, result, 'Record saved');
  }

  Future<void> edit(Map<String, dynamic> row) async {
    if (widget.module.key == 'roles') {
      final result = await showRoleForm(context, row: row);
      if (result != null) {
        await request(
          'PATCH',
          '/api/roles/${row['id']}',
          result,
          'Role updated',
        );
      }
      return;
    }
    final fields =
        _hasConfigurableForm
            ? (await _loadRecordFields())
                ?.where((field) => field.key != 'password')
                .toList()
            : widget.module.fields
                .where((field) => field.key != 'password')
                .toList();
    if (!mounted || fields == null) return;
    final result = await showRecordForm(
      context,
      'Edit ${displayValue(row['name'] ?? row['id'])}',
      fields,
      api: widget.api,
      onManageFields:
          _hasConfigurableForm && _canManageRecordFields
              ? _manageRecordFieldsInForm
              : null,
      initial:
          widget.module.key == 'users'
              ? {
                ...row,
                'paymentLimit': asMap(row['approvalLimits'])['payment'],
                'adjustmentLimit': asMap(row['approvalLimits'])['adjustment'],
                'refundLimit': asMap(row['approvalLimits'])['refund'],
              }
              : row,
    );
    if (result == null) return;
    if (widget.module.key == 'users') {
      final limits = <String, dynamic>{};
      for (final field
          in const {
            'paymentLimit': 'payment',
            'adjustmentLimit': 'adjustment',
            'refundLimit': 'refund',
          }.entries) {
        if (result.containsKey(field.key)) {
          limits[field.value] = result.remove(field.key);
        }
      }
      result['approvalLimits'] = limits;
      result['permissions'] = row['permissions'] ?? {};
    }
    await request(
      'PATCH',
      '${widget.module.editPath ?? widget.module.path}/${row['id']}',
      result,
      'Changes saved',
    );
  }

  String? get _formModule =>
      recordFormModule(widget.module.key, widget.grocery);

  bool get _hasConfigurableForm =>
      _formModule != null && configurableFormModules.contains(_formModule);

  bool get _canManageRecordFields =>
      widget.user['role'] == 'Agency owner' ||
      widget.user['role'] == 'Agency administrator';

  Future<List<FieldSpec>?> _loadRecordFields() async {
    try {
      return await loadRecordFields(widget.api, _formModule!);
    } catch (error) {
      widget.message(error.toString());
      return null;
    }
  }

  Future<List<FieldSpec>?> _manageRecordFieldsInForm() async {
    final changed = await showRecordFieldsManager(
      context,
      widget.api,
      _formModule!,
    );
    if (!changed || !mounted) return null;
    reload();
    return _loadRecordFields();
  }

  Future<void> _manageRecordFields() async {
    final changed = await showRecordFieldsManager(
      context,
      widget.api,
      _formModule!,
    );
    if (changed && mounted) reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(snapshot.error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: reload, child: const Text('Retry')),
              ],
            ),
          ),
        );
      }
      final data = snapshot.data;
      if (widget.module.key == 'pos') {
        return PosScreen(
          api: widget.api,
          products: asRows(data),
          onUpdated: reload,
          message: widget.message,
        );
      }
      if (widget.module.key == 'dashboard') return _dashboard(asMap(data));
      if (widget.module.key == 'reports') return _reports(asMap(data));
      return _collection(asRows(data));
    },
  );

  Widget _dashboard(Map<String, dynamic> data) {
    if (!widget.grocery) return _travelDashboard(data);
    final stats = asMap(data['stats']);
    final wallet = asMap(data['wallet']);
    final availableFunds =
        ((wallet['balance'] as num?)?.toDouble() ?? 0) +
        ((wallet['creditLimit'] as num?)?.toDouble() ?? 0) -
        ((wallet['usedCredit'] as num?)?.toDouble() ?? 0);
    final headline =
        widget.grocery
            ? 'FreshMart Grocery'
            : 'Good day, ${widget.user['name']?.toString().split(' ').first ?? 'Agent'}.';
    return _page(
      ux: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  widget.grocery
                      ? const [Color(0xff204d36), Color(0xff38805a)]
                      : const [Color(0xff102d40), Color(0xff126e68)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 18,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Georgia',
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.grocery
                        ? 'Store operations and performance'
                        : '${stats['cases'] ?? 0} operational items need attention.',
                    style: const TextStyle(color: Color(0xffbdd9d8)),
                  ),
                ],
              ),
              if (!widget.grocery)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'AVAILABLE FUNDS',
                      style: TextStyle(
                        color: Color(0xffbdd9d8),
                        fontSize: 11,
                        letterSpacing: .7,
                      ),
                    ),
                    Text(
                      availableFunds.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Wallet + available credit',
                      style: TextStyle(color: Color(0xffbdd9d8), fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _tableAlerts(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              stats.entries
                  .map((entry) => _metric(entry.key, displayValue(entry.value)))
                  .toList(),
        ),
        if (!widget.grocery) ...[
          const SizedBox(height: 16),
          _dashboardExtras(data),
        ],
      ],
    );
  }

  Widget _travelDashboard(Map<String, dynamic> data) {
    final stats = asMap(data['stats']);
    final firstName =
        widget.user['name']?.toString().split(' ').first ?? 'there';
    final wallet = asMap(data['wallet']);
    final availableFunds =
        ((wallet['balance'] as num?)?.toDouble() ?? 0) +
        ((wallet['creditLimit'] as num?)?.toDouble() ?? 0) -
        ((wallet['usedCredit'] as num?)?.toDouble() ?? 0);
    final metrics = <
      ({String label, String value, IconData icon, String detail, Color accent})
    >[
      (
        label: 'Bookings',
        value: displayValue(stats['bookings'] ?? 0),
        icon: Icons.airplane_ticket_outlined,
        detail: 'Journey records',
        accent: TravelPalette.purple,
      ),
      (
        label: 'Travelers',
        value: displayValue(stats['customers'] ?? 0),
        icon: Icons.people_outline_rounded,
        detail: 'Traveler profiles',
        accent: const Color(0xff4984cb),
      ),
      (
        label: 'Passport services',
        value: displayValue(stats['passportServices'] ?? 0),
        icon: Icons.badge_outlined,
        detail: 'Applications and collections',
        accent: TravelPalette.green,
      ),
      (
        label: 'Open support cases',
        value: displayValue(stats['cases'] ?? 0),
        icon: Icons.support_agent_outlined,
        detail: 'Needs attention',
        accent: TravelPalette.amber,
      ),
    ];
    return _page(
      ux: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 650;
            return Container(
              width: double.infinity,
              padding: EdgeInsets.all(narrow ? 22 : 28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xfff0ecff), Color(0xfff5f8ff), Colors.white],
                ),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xffe4ddff)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR TRAVEL OVERVIEW',
                        style: TextStyle(
                          color: TravelPalette.purple,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'Welcome back, $firstName',
                        style: TextStyle(
                          color: TravelPalette.ink,
                          fontSize: narrow ? 24 : 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.8,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Everything for your next journey, in one place.',
                        style: TextStyle(
                          color: TravelPalette.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TravelPalette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AVAILABLE FUNDS',
                          style: TextStyle(
                            color: TravelPalette.muted,
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          availableFunds.toStringAsFixed(2),
                          style: const TextStyle(
                            color: TravelPalette.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        _tableAlerts(),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final count =
                constraints.maxWidth >= 1040
                    ? 4
                    : constraints.maxWidth >= 580
                    ? 2
                    : 1;
            final gap = 12.0;
            final width = (constraints.maxWidth - gap * (count - 1)) / count;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children:
                  metrics
                      .map(
                        (metric) => SizedBox(
                          width: width,
                          height: 155,
                          child: TravelMetricCard(
                            label: metric.label,
                            value: metric.value,
                            icon: metric.icon,
                            detail: metric.detail,
                            accent: metric.accent,
                          ),
                        ),
                      )
                      .toList(),
            );
          },
        ),
        const SizedBox(height: 18),
        FutureBuilder<dynamic>(
          future: recentBookingsFuture ??= widget.api.get('/api/bookings'),
          builder: (context, snapshot) {
            final bookings =
                snapshot.hasData
                    ? asRows(snapshot.data)
                    : <Map<String, dynamic>>[];
            return Column(
              children: [
                _travelAnalytics(
                  bookings,
                  loading: !snapshot.hasData && !snapshot.hasError,
                ),
                const SizedBox(height: 18),
                _travelActivityDetails(
                  bookings,
                  asRows(data['notifications']),
                  error: snapshot.error?.toString(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _travelAnalytics(
    List<Map<String, dynamic>> bookings, {
    required bool loading,
  }) {
    final months = List<int>.filled(12, 0);
    final currentYear = DateTime.now().year;
    var ticketed = 0;
    var confirmed = 0;
    for (final booking in bookings) {
      final date = DateTime.tryParse(booking['travelDate']?.toString() ?? '');
      if (date != null && date.year == currentYear) months[date.month - 1]++;
      final state = booking['status']?.toString().toLowerCase();
      if (state == 'ticketed') ticketed++;
      if (state == 'confirmed') confirmed++;
    }
    final other = bookings.length - ticketed - confirmed;
    final activity = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Travel activity',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Bookings by travel month · $currentYear',
              style: const TextStyle(color: TravelPalette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (loading)
              const SizedBox(
                height: 230,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              TravelActivityChart(monthlyCounts: months),
          ],
        ),
      ),
    );
    final progress = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Booking progress',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${bookings.length} total bookings',
              style: const TextStyle(color: TravelPalette.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Center(
              child:
                  loading
                      ? const SizedBox(
                        height: 225,
                        child: Center(child: CircularProgressIndicator()),
                      )
                      : TravelBookingDonut(
                        ticketed: ticketed,
                        confirmed: confirmed,
                        other: other,
                      ),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder:
          (context, constraints) =>
              constraints.maxWidth >= 830
                  ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: activity),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: progress),
                    ],
                  )
                  : Column(
                    children: [activity, const SizedBox(height: 16), progress],
                  ),
    );
  }

  Widget _travelActivityDetails(
    List<Map<String, dynamic>> bookings,
    List<Map<String, dynamic>> notifications, {
    String? error,
  }) {
    final recent = Card(
      child: Padding(
        padding: const EdgeInsets.all(21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent bookings',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your latest travel records',
              style: TextStyle(color: TravelPalette.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (error != null)
              Text(error, style: const TextStyle(color: TravelPalette.red))
            else if (bookings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 27),
                child: Center(
                  child: Text(
                    'No bookings yet',
                    style: TextStyle(color: TravelPalette.muted),
                  ),
                ),
              )
            else
              ...bookings
                  .take(5)
                  .map(
                    (booking) => Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 37,
                            height: 37,
                            decoration: BoxDecoration(
                              color: TravelPalette.purpleSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.flight_rounded,
                              color: TravelPalette.purple,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayValue(
                                    booking['route'] ?? booking['id'],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${booking['customerName'] ?? ''} · '
                                  '${booking['travelDate'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TravelPalette.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          TravelStatusChip(
                            booking['status']?.toString() ?? 'Pending',
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
    final notices = Card(
      child: Padding(
        padding: const EdgeInsets.all(21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Action center',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Updates that matter to your trip',
              style: TextStyle(color: TravelPalette.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 27),
                child: Center(
                  child: Text(
                    'You are all caught up',
                    style: TextStyle(color: TravelPalette.muted),
                  ),
                ),
              )
            else
              ...notifications
                  .take(5)
                  .map(
                    (notice) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xfff6f3ff),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayValue(notice['title']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            displayValue(notice['message']),
                            style: const TextStyle(
                              color: TravelPalette.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder:
          (context, constraints) =>
              constraints.maxWidth >= 830
                  ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: recent),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: notices),
                    ],
                  )
                  : Column(
                    children: [recent, const SizedBox(height: 16), notices],
                  ),
    );
  }

  Widget _dashboardExtras(Map<String, dynamic> data) {
    final bookings = Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent bookings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            FutureBuilder<dynamic>(
              future: recentBookingsFuture ??= widget.api.get('/api/bookings'),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(snapshot.error.toString());
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final rows = asRows(snapshot.data).take(5).toList();
                if (rows.isEmpty) return const Text('No bookings yet');
                return Column(
                  children:
                      rows
                          .map(
                            (row) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${row['id']}  ${row['customerName'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${row['route'] ?? ''}  ${row['travelDate'] ?? ''}',
                              ),
                              trailing: Text(displayValue(row['status'])),
                            ),
                          )
                          .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
    final notices = Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Action center',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...asRows(data['notifications']).map(
              (notice) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xfffff5e9),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayValue(notice['title']),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(displayValue(notice['message'])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder:
          (context, constraints) =>
              constraints.maxWidth >= 760
                  ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 8, child: bookings),
                      const SizedBox(width: 18),
                      Expanded(flex: 5, child: notices),
                    ],
                  )
                  : Column(children: [bookings, notices]),
    );
  }

  Widget _metric(String label, String value) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _label(label).toUpperCase(),
              style: const TextStyle(
                color: Color(0xff70808d),
                fontSize: 10,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _metricStrip(List<Widget> metrics, {Key? key}) =>
      SingleChildScrollView(
        key: key,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              if (index > 0) const SizedBox(width: 12),
              metrics[index],
            ],
          ],
        ),
      );

  Widget _infoCard(String title, Map<String, dynamic> data) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...data.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${_label(entry.key)}: ${displayValue(entry.value)}'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _reports(Map<String, dynamic> data) {
    if (widget.grocery) {
      groceryReportsFuture ??= Future.wait([
        widget.api.get('/api/grocery/sales'),
        widget.api.get('/api/grocery/products'),
        widget.api.get('/api/grocery/expenses'),
      ]);
      return _page(
        ux: [
          Text(
            'Store performance',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text('Recorded store counts'),
          const SizedBox(height: 8),
          _metricStrip([
            for (final entry in asMap(data['stats']).entries)
              _metric(_label(entry.key), displayValue(entry.value)),
          ], key: const ValueKey('store-performance-metrics')),
          const SizedBox(height: 16),
          FutureBuilder<List<dynamic>>(
            future: groceryReportsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return snapshot.hasError
                    ? Text(snapshot.error.toString())
                    : const Center(child: CircularProgressIndicator());
              }
              final recordedSales = asRows(snapshot.data![0]);
              final products = asRows(snapshot.data![1]);
              final recordedExpenses = asRows(snapshot.data![2]);
              final previewAvailable =
                  recordedSales.isEmpty && recordedExpenses.isEmpty;
              final previewActive =
                  previewAvailable && _showDemoFinancialPreview;
              final sales = previewActive ? demoGrocerySales : recordedSales;
              final expenses =
                  previewActive ? demoGroceryExpenses : recordedExpenses;
              double sum(List<Map<String, dynamic>> rows, String key) =>
                  rows.fold(
                    0,
                    (total, row) =>
                        total + ((row[key] as num?)?.toDouble() ?? 0),
                  );
              final expensesKnown = expenses.every(
                (row) => row['total'] is num || row['amount'] is num,
              );
              final salesTotalKnown = sales.every((row) => row['total'] is num);
              final profitKnown = sales.every((row) => row['profit'] is num);
              final stockCostKnown = products.every(
                (row) => row['cost'] is num && row['stock'] is num,
              );
              final stockRetailKnown = products.every(
                (row) => row['price'] is num && row['stock'] is num,
              );
              final grossProfit = sum(sales, 'profit');
              final expenseTotal = expenses.fold<double>(
                0,
                (total, row) =>
                    total +
                    (((row['total'] ?? row['amount']) as num?)?.toDouble() ??
                        0),
              );
              final stockCost = products.fold<double>(
                0,
                (total, row) =>
                    total +
                    ((row['cost'] as num?)?.toDouble() ?? 0) *
                        ((row['stock'] as num?)?.toDouble() ?? 0),
              );
              final stockRetail = products.fold<double>(
                0,
                (total, row) =>
                    total +
                    ((row['price'] as num?)?.toDouble() ?? 0) *
                        ((row['stock'] as num?)?.toDouble() ?? 0),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (previewAvailable) ...[
                    _demoFinancialControl('sales and expenses'),
                    const SizedBox(height: 16),
                  ],
                  _metricStrip([
                    _metric('Sales count', '${sales.length}'),
                    _metric(
                      'Total sales',
                      salesTotalKnown
                          ? sum(sales, 'total').toStringAsFixed(2)
                          : 'Not available',
                    ),
                    _metric(
                      'Gross profit',
                      profitKnown
                          ? grossProfit.toStringAsFixed(2)
                          : 'Not available',
                    ),
                    _metric(
                      'Expenses',
                      expensesKnown
                          ? expenseTotal.toStringAsFixed(2)
                          : 'Not available',
                    ),
                    _metric(
                      'Net after expenses',
                      profitKnown && expensesKnown
                          ? (grossProfit - expenseTotal).toStringAsFixed(2)
                          : 'Not available',
                    ),
                    _metric(
                      'Stock at cost',
                      stockCostKnown
                          ? stockCost.toStringAsFixed(2)
                          : 'Not available',
                    ),
                    _metric(
                      'Stock at retail',
                      stockRetailKnown
                          ? stockRetail.toStringAsFixed(2)
                          : 'Not available',
                    ),
                  ]),
                  const SizedBox(height: 16),
                  FinancialRegister(
                    title: 'Sales register',
                    rows: sales,
                    kind: FinancialRecordKind.grocerySale,
                    demo: previewActive,
                    onOpenRecord: _detail,
                    onPrintRecord: _printRecord,
                  ),
                  const SizedBox(height: 20),
                  FinancialRegister(
                    title: 'Expenses',
                    rows: expenses,
                    kind: FinancialRecordKind.expense,
                    demo: previewActive,
                    onOpenRecord: _detail,
                    onPrintRecord: _printRecord,
                  ),
                ],
              );
            },
          ),
        ],
      );
    }
    final recordedSales =
        data.containsKey('rows') ? asRows(data['rows']) : asRows(data['sales']);
    final previewAvailable =
        recordedSales.isEmpty && (data['count'] == null || data['count'] == 0);
    final previewActive = previewAvailable && _showDemoFinancialPreview;
    final sales = previewActive ? demoAirlineSales : recordedSales;
    final totalFromRows =
        sales.every((row) => row['total'] is num)
            ? sales.fold<double>(
              0,
              (total, row) => total + (row['total'] as num).toDouble(),
            )
            : null;
    final totals =
        previewActive
            ? <String, dynamic>{
              'salesCount': sales.length,
              'totalSales': totalFromRows ?? 0,
            }
            : <String, dynamic>{
              'salesCount': data['count'] ?? sales.length,
              'totalSales':
                  data['totalSales'] ?? totalFromRows ?? 'Not available',
              ...asMap(data['totals']),
            };
    return _page(
      ux: [
        if (previewAvailable) ...[
          _demoFinancialControl('sales'),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              totals.entries
                  .map(
                    (entry) =>
                        _metric(_label(entry.key), displayValue(entry.value)),
                  )
                  .toList(),
        ),
        const SizedBox(height: 16),
        FinancialRegister(
          title: 'Sales',
          rows: sales,
          kind: FinancialRecordKind.airlineSale,
          demo: previewActive,
          onOpenRecord: _detail,
          onPrintRecord: _printRecord,
        ),
      ],
    );
  }

  Widget _collection(List<Map<String, dynamic>> rows) {
    final previewAvailable =
        (widget.module.key == 'sales' ||
            (widget.grocery && widget.module.key == 'expenses')) &&
        rows.isEmpty &&
        search.trim().isEmpty;
    final previewActive = previewAvailable && _showDemoFinancialPreview;
    final visibleRows =
        previewActive
            ? widget.grocery
                ? widget.module.key == 'expenses'
                    ? demoGroceryExpenses
                    : demoGrocerySales
                : demoAirlineSales
            : rows;
    final statuses = <String>{};
    for (final row in visibleRows) {
      final value = row['status']?.toString();
      if (value != null && value.isNotEmpty) statuses.add(value);
    }
    final selectedStatus = statuses.contains(status) ? status : '';
    final filtered =
        visibleRows.where((row) {
          final query = search.toLowerCase();
          return (selectedStatus.isEmpty || row['status'] == selectedStatus) &&
              row.values.any(
                (value) => displayValue(value).toLowerCase().contains(query),
              );
        }).toList();
    if (!widget.grocery) {
      return _travelCollection(
        filtered,
        statuses,
        selectedStatus,
        showDemoSalesControl: previewAvailable,
        demo: previewActive,
      );
    }
    return _page(
      ux: [
        if (previewAvailable) ...[
          _demoFinancialControl(
            widget.module.key == 'expenses' ? 'expenses' : 'sales',
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.module.title,
                  style: const TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${filtered.length} records in this view',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _collectionToolbar(
          statuses,
          selectedStatus,
          canCreate:
              widget.module.fields.isNotEmpty ||
              widget.module.key == 'purchases' ||
              widget.module.key == 'roles',
        ),
        const SizedBox(height: 14),
        if (widget.module.key == 'sales' || widget.module.key == 'expenses')
          FinancialRegister(
            title:
                widget.module.key == 'sales'
                    ? 'Sales register'
                    : 'Expense register',
            rows: filtered,
            kind:
                widget.module.key == 'sales'
                    ? FinancialRecordKind.grocerySale
                    : FinancialRecordKind.expense,
            demo: previewActive,
            onOpenRecord: _detail,
            onPrintRecord: _printRecord,
          )
        else
          _recordTable(filtered),
      ],
    );
  }

  Widget _travelCollection(
    List<Map<String, dynamic>> filtered,
    Set<String> statuses,
    String selectedStatus, {
    bool showDemoSalesControl = false,
    bool demo = false,
  }) {
    final canCreate =
        widget.module.fields.isNotEmpty ||
        widget.module.key == 'purchases' ||
        widget.module.key == 'roles' ||
        widget.module.key == 'sales';
    return _page(
      ux: [
        if (showDemoSalesControl) ...[
          _demoFinancialControl('sales'),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder:
              (context, constraints) => Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 14,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TRAVEL WORKSPACE',
                        style: TextStyle(
                          color: TravelPalette.purple,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        widget.module.title,
                        style: const TextStyle(
                          fontSize: 28,
                          color: TravelPalette.ink,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${filtered.length} records in this view',
                        style: const TextStyle(
                          color: TravelPalette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        ),
        const SizedBox(height: 20),
        _collectionToolbar(statuses, selectedStatus, canCreate: canCreate),
        const SizedBox(height: 16),
        if (widget.module.key == 'sales')
          FinancialRegister(
            title: 'Sales register',
            rows: filtered,
            kind: FinancialRecordKind.airlineSale,
            demo: demo,
            onOpenRecord: _detail,
            onPrintRecord: _printRecord,
          )
        else
          _recordTable(filtered),
      ],
    );
  }

  Widget _demoFinancialControl(String kind) => Card(
    color: const Color(0xfffff4d9),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _showDemoFinancialPreview
                ? 'DEMO PREVIEW — sample $kind, not real transactions'
                : 'No $kind recorded yet',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _showDemoFinancialPreview
                ? 'These examples are not saved to the database and do not change balances or accounting records.'
                : 'Preview example $kind to see how this screen will look. No sample data will be saved.',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed:
                  () => setState(() {
                    _showDemoFinancialPreview = !_showDemoFinancialPreview;
                    _tablePage = 0;
                  }),
              child: Text(
                _showDemoFinancialPreview
                    ? 'Hide sample data'
                    : 'Preview sample $kind',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _collectionToolbar(
    Set<String> statuses,
    String selectedStatus, {
    required bool canCreate,
  }) {
    final canManage = _hasConfigurableForm && _canManageRecordFields;
    final searchField = TextField(
      controller: _recordSearchController,
      onChanged: _searchRecords,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded, size: 20),
        hintText: 'Search records',
        isDense: true,
      ),
    );
    final statusField = DropdownButtonFormField<String>(
      value: selectedStatus,
      isDense: true,
      isExpanded: true,
      items:
          ['', ...statuses.toList()..sort()]
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(
                    value.isEmpty ? 'All statuses' : value,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
      onChanged:
          (value) => setState(() {
            status = value ?? '';
            _tablePage = 0;
          }),
    );
    final manageButton = OutlinedButton.icon(
      onPressed: _manageRecordFields,
      icon: const Icon(Icons.tune, size: 18),
      label: const Text('Manage form fields'),
    );
    final addButton = FilledButton.icon(
      onPressed: create,
      icon: const Icon(Icons.add_rounded, size: 19),
      label: const Text('Add Record'),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final requiredWidth =
                220.0 +
                (statuses.isNotEmpty ? 195 + gap : 0) +
                (canManage ? 228 + gap : 0) +
                (canCreate ? 162 + gap : 0);
            if (constraints.maxWidth >= requiredWidth) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: searchField),
                  if (statuses.isNotEmpty) ...[
                    const SizedBox(width: gap),
                    SizedBox(width: 195, child: statusField),
                  ],
                  if (canManage) ...[const SizedBox(width: gap), manageButton],
                  if (canCreate) ...[const SizedBox(width: gap), addButton],
                ],
              );
            }
            final searchWidth =
                constraints.maxWidth < 360 ? constraints.maxWidth : 360.0;
            final statusWidth =
                constraints.maxWidth < 195 ? constraints.maxWidth : 195.0;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: searchWidth, child: searchField),
                if (statuses.isNotEmpty)
                  SizedBox(width: statusWidth, child: statusField),
                if (canManage) manageButton,
                if (canCreate) addButton,
              ],
            );
          },
        ),
      ),
    );
  }

  String get _layoutPath {
    final platform = widget.grocery ? 'grocery' : 'airline';
    final collection = widget.module.path.split('/').last;
    return '/api/table-layouts/$platform/$collection';
  }

  Future<_RecordTableMeta> _loadTableMeta() async {
    List<FieldSpec> fields = widget.module.fields;
    if (_hasConfigurableForm) {
      try {
        fields = await loadRecordFields(widget.api, _formModule!);
      } catch (_) {
        // The record list still works if a legacy server lacks form settings.
      }
    }
    fields = fields.where((field) => field.key != 'password').toList();
    if (fields.isEmpty) {
      fields = [
        for (final key in widget.module.columns) FieldSpec(key, _label(key)),
      ];
    }
    try {
      final response = asMap(await widget.api.get(_layoutPath));
      return _RecordTableMeta(
        fields,
        (response['columns'] as List? ?? []).map((e) => e.toString()).toList(),
        (response['rows'] as List? ?? []).map((e) => e.toString()).toList(),
      );
    } catch (_) {
      return _RecordTableMeta(fields, [], []);
    }
  }

  List<FieldSpec> _orderedTableFields(_RecordTableMeta meta) {
    final fields = [...meta.fields];
    if (meta.columnOrder.isEmpty) return fields;
    final positions = <String, int>{
      for (var index = 0; index < meta.columnOrder.length; index++)
        meta.columnOrder[index]: index,
    };
    fields.sort((a, b) {
      final left =
          positions[a.key] ?? meta.columnOrder.length + meta.fields.indexOf(a);
      final right =
          positions[b.key] ?? meta.columnOrder.length + meta.fields.indexOf(b);
      return left.compareTo(right);
    });
    return fields;
  }

  List<Map<String, dynamic>> _orderedTableRows(
    _RecordTableMeta meta,
    List<Map<String, dynamic>> rows,
  ) {
    if (meta.rowOrder.isEmpty) return rows;
    final positions = <String, int>{
      for (var index = 0; index < meta.rowOrder.length; index++)
        meta.rowOrder[index]: index,
    };
    final ordered = [...rows];
    ordered.sort((a, b) {
      final left =
          positions[a['id']?.toString()] ??
          meta.rowOrder.length + rows.indexOf(a);
      final right =
          positions[b['id']?.toString()] ??
          meta.rowOrder.length + rows.indexOf(b);
      return left.compareTo(right);
    });
    return ordered;
  }

  bool _canEditTableField(FieldSpec field) {
    if (widget.module.editPath == null ||
        field.type == FieldType.password ||
        {
          'id',
          'createdAt',
          'updatedAt',
          'createdBy',
          'updatedBy',
        }.contains(field.key)) {
      return false;
    }
    if (!widget.grocery && widget.module.key == 'bookings') {
      return !{
        'paymentStatus',
        'paymentMethod',
        'paidAmount',
        'outstanding',
      }.contains(field.key);
    }
    if (!widget.grocery && widget.module.key == 'customers') {
      return field.key != 'trips';
    }
    if (!widget.grocery && widget.module.key == 'quotes') {
      return field.key != 'total';
    }
    if (!widget.grocery && widget.module.key == 'passports') {
      return field.key != 'paymentStatus';
    }
    if (widget.grocery && widget.module.key == 'customers') {
      return !{'points', 'spent', 'tier'}.contains(field.key);
    }
    return true;
  }

  Future<void> _saveTableCell(Map<String, dynamic> row, FieldSpec field) async {
    final content = _cellEditor.text;
    final raw = content.trim();
    if (field.required && raw.isEmpty) {
      widget.message('${field.label} is required');
      return;
    }
    if (field.type == FieldType.choice &&
        raw.isNotEmpty &&
        field.choices.isNotEmpty &&
        !field.choices.contains(raw)) {
      widget.message('Choose a valid ${field.label}');
      return;
    }
    dynamic value =
        field.type == FieldType.text || field.type == FieldType.paragraph
            ? content
            : raw;
    if (field.type == FieldType.number) {
      value = num.tryParse(raw);
      if (value == null) {
        widget.message('Enter a valid number');
        return;
      }
    } else if (field.type == FieldType.toggle) {
      value = raw == 'true';
    } else if (field.type == FieldType.date &&
        raw.isNotEmpty &&
        DateTime.tryParse(raw) == null) {
      widget.message('Enter a valid date');
      return;
    }
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    final oldValue = row[field.key];
    setState(() {
      row[field.key] = value;
      _editingRecordId = null;
      _editingFieldKey = null;
    });
    try {
      final updated = asMap(
        await widget.api
            .patch('${widget.module.editPath}/${Uri.encodeComponent(id)}', {
              field.key: value,
              if ((!widget.grocery && widget.module.key == 'bookings') ||
                  (widget.grocery && widget.module.key == 'products'))
                'tableEdit': true,
            }),
      );
      if (mounted) {
        setState(() {
          row.addAll(updated);
          future = widget.api.get(_collectionSearchPath);
        });
        widget.onUpdated();
        widget.message('Cell saved');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => row[field.key] = oldValue);
      widget.message('Could not save cell: $error');
    }
  }

  Widget _tableCell(
    Map<String, dynamic> row,
    FieldSpec field,
    double columnWidth,
  ) {
    final value = displayValue(row[field.key]);
    final choices =
        field.type == FieldType.toggle
            ? const ['true', 'false']
            : field.choices;
    final editing =
        _editingRecordId == row['id']?.toString() &&
        _editingFieldKey == field.key;
    final multiline =
        field.type == FieldType.text || field.type == FieldType.paragraph;
    return SizedBox(
      key: ValueKey('module-cell-${row['id']}-${field.key}'),
      width: columnWidth,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 180),
        child:
            editing
                ? Row(
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.escape) {
                            setState(() {
                              _editingRecordId = null;
                              _editingFieldKey = null;
                            });
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child:
                            field.type == FieldType.toggle ||
                                    (field.type == FieldType.choice &&
                                        choices.isNotEmpty)
                                ? DropdownButton<String>(
                                  value:
                                      choices.contains(_cellEditor.text)
                                          ? _cellEditor.text
                                          : null,
                                  isExpanded: true,
                                  items: [
                                    for (final option in choices)
                                      DropdownMenuItem(
                                        value: option,
                                        child: Text(
                                          option,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (choice) {
                                    if (choice != null) {
                                      setState(() => _cellEditor.text = choice);
                                    }
                                  },
                                )
                                : TextField(
                                  key: const ValueKey('module-cell-editor'),
                                  controller: _cellEditor,
                                  autofocus: true,
                                  minLines: 1,
                                  maxLines: multiline ? inlineCellMaxLines : 1,
                                  keyboardType:
                                      field.type == FieldType.number
                                          ? const TextInputType.numberWithOptions(
                                            decimal: true,
                                          )
                                          : field.type == FieldType.date
                                          ? TextInputType.datetime
                                          : TextInputType.multiline,
                                  textInputAction:
                                      multiline
                                          ? TextInputAction.newline
                                          : TextInputAction.done,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                  ),
                                  onChanged:
                                      multiline ? (_) => setState(() {}) : null,
                                  onSubmitted:
                                      multiline
                                          ? null
                                          : (_) => _saveTableCell(row, field),
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Save cell',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.check, size: 17),
                      onPressed: () => _saveTableCell(row, field),
                    ),
                    IconButton(
                      tooltip: 'Cancel edit',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, size: 17),
                      onPressed:
                          () => setState(() {
                            _editingRecordId = null;
                            _editingFieldKey = null;
                          }),
                    ),
                  ],
                )
                : InkWell(
                  onDoubleTap:
                      _canEditTableField(field)
                          ? () => setState(() {
                            _editingRecordId = row['id']?.toString();
                            _editingFieldKey = field.key;
                            _cellEditor.text = row[field.key]?.toString() ?? '';
                          })
                          : null,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    child: Tooltip(
                      message: value,
                      child: TableValueDisplay(
                        fieldKey: field.key,
                        value: value,
                      ),
                    ),
                  ),
                ),
      ),
    );
  }

  double _recordColumnWidth(FieldSpec field, bool structured) {
    final minimum =
        structured
            ? 400.0
            : field.type == FieldType.paragraph
            ? 300.0
            : 210.0;
    final labelWidth = field.label.length * 8.0 + 24;
    return (labelWidth > minimum ? labelWidth : minimum)
        .clamp(210.0, 420.0)
        .toDouble();
  }

  double _recordRowHeight(
    Map<String, dynamic> row,
    List<FieldSpec> fields,
    Map<String, double> columnWidths,
  ) {
    final style =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final direction = Directionality.of(context);
    var lines = 1;
    for (final field in fields) {
      final editing =
          _editingRecordId == row['id']?.toString() &&
          _editingFieldKey == field.key;
      final value = editing ? _cellEditor.text : displayValue(row[field.key]);
      final width = columnWidths[field.key] ?? 210;
      final count = inlineCellLineCount(
        value,
        width: editing ? width - 85 : width - 16,
        style: style,
        direction: direction,
      );
      if (count > lines) lines = count;
    }
    return inlineCellRowHeight(lines);
  }

  int _compareTableValues(dynamic left, dynamic right) {
    final a = left?.toString() ?? '';
    final b = right?.toString() ?? '';
    final aNumber = num.tryParse(a);
    final bNumber = num.tryParse(b);
    if (aNumber != null && bNumber != null) return aNumber.compareTo(bNumber);
    final aDate = DateTime.tryParse(a);
    final bDate = DateTime.tryParse(b);
    if (aDate != null && bDate != null) return aDate.compareTo(bDate);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  Widget _recordTable(List<Map<String, dynamic>> rows) {
    _tableMetaFuture ??= _loadTableMeta();
    return FutureBuilder<_RecordTableMeta>(
      future: _tableMetaFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final meta = snapshot.data!;
        final fields = _orderedTableFields(meta);
        final orderedRows = [..._orderedTableRows(meta, rows)];
        if (_tableSortKey != null) {
          orderedRows.sort((a, b) {
            final result = _compareTableValues(
              a[_tableSortKey],
              b[_tableSortKey],
            );
            return _tableSortAscending ? result : -result;
          });
        }
        final window = tablePageWindow(
          orderedRows.length,
          _tablePage,
          _tablePageSize,
        );
        final pageRows = orderedRows.sublist(window.start, window.end);
        final structuredKeys = <String>{};
        for (final row in orderedRows) {
          for (final entry in row.entries) {
            if (entry.value is Map || entry.value is List) {
              structuredKeys.add(entry.key);
            }
          }
        }
        final columnWidths = <String, double>{
          for (final field in fields)
            field.key: _recordColumnWidth(
              field,
              structuredKeys.contains(field.key),
            ),
        };
        final rowHeights = [
          for (final row in pageRows)
            _recordRowHeight(row, fields, columnWidths),
        ];
        final tableHeight =
            48 + rowHeights.fold<double>(0, (height, row) => height + row);
        final contentWidth =
            58.0 +
            columnWidths.values.fold<double>(0, (sum, width) => sum + width);
        final scheme = Theme.of(context).colorScheme;
        return Container(
          decoration: tablePanelDecoration(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                SizedBox(
                  height: tableHeight.clamp(120.0, 560.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder:
                              (context, constraints) => Scrollbar(
                                controller: _tableHorizontal,
                                thumbVisibility: true,
                                notificationPredicate:
                                    (notification) =>
                                        notification.metrics.axis ==
                                        Axis.horizontal,
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'record-table-horizontal-scroll',
                                  ),
                                  controller: _tableHorizontal,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width:
                                        contentWidth < constraints.maxWidth
                                            ? constraints.maxWidth
                                            : contentWidth,
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: tableHeaderColor(context),
                                            border: Border(
                                              bottom: BorderSide(
                                                color: scheme.outlineVariant,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 58,
                                                child: Center(
                                                  child: Text(
                                                    '#',
                                                    style: tableHeaderStyle(
                                                      context,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              for (final field in fields)
                                                SizedBox(
                                                  width:
                                                      columnWidths[field.key],
                                                  child: InkWell(
                                                    onTap:
                                                        () => setState(() {
                                                          if (_tableSortKey ==
                                                              field.key) {
                                                            _tableSortAscending =
                                                                !_tableSortAscending;
                                                          } else {
                                                            _tableSortKey =
                                                                field.key;
                                                            _tableSortAscending =
                                                                true;
                                                          }
                                                          _tablePage = 0;
                                                        }),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                          ),
                                                      child: Align(
                                                        alignment:
                                                            Alignment
                                                                .centerLeft,
                                                        child: Text(
                                                          field.label
                                                              .toUpperCase(),
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                          style:
                                                              tableHeaderStyle(
                                                                context,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              const Spacer(),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child:
                                              pageRows.isEmpty
                                                  ? Center(
                                                    child: Text(
                                                      'No matching records',
                                                      style: TextStyle(
                                                        color:
                                                            scheme
                                                                .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  )
                                                  : Scrollbar(
                                                    controller: _tableVertical,
                                                    thumbVisibility: true,
                                                    child: ListView.builder(
                                                      key: const ValueKey(
                                                        'record-table',
                                                      ),
                                                      controller:
                                                          _tableVertical,
                                                      itemCount:
                                                          pageRows.length,
                                                      itemExtentBuilder:
                                                          (index, _) =>
                                                              index <
                                                                      pageRows
                                                                          .length
                                                                  ? rowHeights[index]
                                                                  : null,
                                                      itemBuilder: (
                                                        context,
                                                        index,
                                                      ) {
                                                        final row =
                                                            pageRows[index];
                                                        final height =
                                                            rowHeights[index];
                                                        return Container(
                                                          key: ValueKey(
                                                            'record-data-row-$index',
                                                          ),
                                                          height: height,
                                                          decoration: BoxDecoration(
                                                            color:
                                                                index.isEven
                                                                    ? scheme
                                                                        .surface
                                                                    : scheme
                                                                        .surfaceContainerLowest,
                                                            border: Border(
                                                              bottom: BorderSide(
                                                                color: scheme
                                                                    .outlineVariant
                                                                    .withValues(
                                                                      alpha:
                                                                          .65,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              SizedBox(
                                                                width: 58,
                                                                child: Center(
                                                                  child: Text(
                                                                    '${window.start + index + 1}',
                                                                    style: TextStyle(
                                                                      color:
                                                                          scheme
                                                                              .onSurfaceVariant,
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              for (final field
                                                                  in fields)
                                                                _tableCell(
                                                                  row,
                                                                  field,
                                                                  columnWidths[field
                                                                      .key]!,
                                                                ),
                                                              const Spacer(),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: tableHeaderColor(context),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child:
                                    pageRows.isEmpty
                                        ? const SizedBox.shrink()
                                        : ListView.builder(
                                          key: const ValueKey('record-actions'),
                                          controller: _tableActionsVertical,
                                          itemCount: pageRows.length,
                                          itemExtentBuilder:
                                              (index, _) =>
                                                  index < pageRows.length
                                                      ? rowHeights[index]
                                                      : null,
                                          itemBuilder: (context, index) {
                                            final row = pageRows[index];
                                            return Container(
                                              decoration: BoxDecoration(
                                                color:
                                                    index.isEven
                                                        ? scheme.surface
                                                        : scheme
                                                            .surfaceContainerLowest,
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: scheme.outlineVariant
                                                        .withValues(alpha: .65),
                                                  ),
                                                ),
                                              ),
                                              child:
                                                  widget.module.key ==
                                                          'company_assets'
                                                      ? IconButton(
                                                        key: ValueKey(
                                                          'record-action-$index',
                                                        ),
                                                        tooltip: 'Delete row',
                                                        icon: const Icon(
                                                          Icons.delete_outline,
                                                          size: 18,
                                                        ),
                                                        onPressed:
                                                            () =>
                                                                _deleteCompanyAsset(
                                                                  row,
                                                                ),
                                                      )
                                                      : IconButton(
                                                        key: ValueKey(
                                                          'record-action-$index',
                                                        ),
                                                        tooltip: 'Details',
                                                        icon: const Icon(
                                                          Icons.chevron_right,
                                                          size: 18,
                                                        ),
                                                        onPressed:
                                                            () => _detail(row),
                                                      ),
                                            );
                                          },
                                        ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TablePagination(
                  total: orderedRows.length,
                  page: window.page,
                  pageSize: _tablePageSize,
                  onPageChanged:
                      (page) => setState(() {
                        _editingRecordId = null;
                        _editingFieldKey = null;
                        _tablePage = page;
                        if (_tableVertical.hasClients) _tableVertical.jumpTo(0);
                      }),
                  onPageSizeChanged:
                      (size) => setState(() {
                        _editingRecordId = null;
                        _editingFieldKey = null;
                        _tablePage = 0;
                        _tablePageSize = size;
                        if (_tableVertical.hasClients) _tableVertical.jumpTo(0);
                      }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rows, {
    bool expanded = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      child: ExpansionTile(
        key: ValueKey('record-section-$title'),
        initiallyExpanded: expanded,
        title: Text('$title (${rows.length})'),
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No records'),
            )
          else
            ...rows
                .take(100)
                .map(
                  (row) => ListTile(
                    title: Text(
                      displayValue(
                        row['reference'] ?? row['id'] ?? row['type'],
                      ),
                      maxLines: 1,
                    ),
                    subtitle: Text(
                      row.entries
                          .take(5)
                          .map(
                            (e) => '${_label(e.key)}: ${displayValue(e.value)}',
                          )
                          .join(' · '),
                      maxLines: 2,
                    ),
                    onTap: () => _detail(row),
                  ),
                ),
        ],
      ),
    ),
  );

  Widget _page({required List<Widget> ux}) => SingleChildScrollView(
    padding: EdgeInsets.all(widget.grocery ? 20 : 24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: ux,
        ),
      ),
    ),
  );

  Iterable<MapEntry<String, dynamic>> _detailEntries(
    Map<String, dynamic> row,
  ) => row.entries.where(
    (entry) =>
        !entry.key.toLowerCase().contains('data') &&
        entry.key != 'passwordHash',
  );

  Future<void> _printRecord(Map<String, dynamic> row) async {
    try {
      if (row['id']?.toString().startsWith('DEMO-') == true) {
        widget.message('Sample records cannot be printed');
        return;
      }
      if (widget.grocery &&
          (widget.module.key == 'sales' || row.containsKey('receipt'))) {
        await printRecord(freshMartSaleReceiptData(row));
        return;
      }
      await printRecord(
        RecordPrintData(
          brand: widget.grocery ? 'FreshMart' : 'AeroDesk',
          title:
              widget.module.key == 'bookings'
                  ? 'Booking summary'
                  : row.containsKey('payee')
                  ? 'Expense voucher'
                  : widget.module.key == 'sales' || row.containsKey('payments')
                  ? 'Sale receipt'
                  : '${widget.module.title} record',
          reference: displayValue(row['id'] ?? row['reference'] ?? row['name']),
          fields: [
            for (final entry in _detailEntries(row))
              if (!isSensitivePrintField(entry.key))
                RecordPrintField(_label(entry.key), displayValue(entry.value)),
          ],
        ),
      );
    } catch (error) {
      if (mounted) widget.message('Could not print record: $error');
    }
  }

  Future<void> _detail(Map<String, dynamic> row) async {
    final actions = recordActions(widget.module.key, widget.grocery, row);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: .86,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayValue(
                        row['name'] ??
                            row['employeeName'] ??
                            row['customerName'] ??
                            row['reference'] ??
                            row['poNumber'] ??
                            row['id'],
                      ),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.module.editPath != null ||
                            (!widget.grocery &&
                                ['users', 'roles'].contains(widget.module.key)))
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              edit(row);
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                        if (widget.module.key == 'company_assets')
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _deleteCompanyAsset(row);
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete record'),
                          ),
                        ...actions.map(
                          (action) => OutlinedButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _doAction(row, action);
                            },
                            child: Text(action.label),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _printRecord(row),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Print'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children:
                            _detailEntries(row)
                                .map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 145,
                                          child: Text(
                                            _label(entry.key),
                                            style:
                                                Theme.of(
                                                  context,
                                                ).textTheme.labelMedium,
                                          ),
                                        ),
                                        Expanded(
                                          child: SelectableText(
                                            displayValue(entry.value),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteCompanyAsset(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete asset record?'),
            content: const Text(
              'This removes the employee asset record permanently. '
              'It cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete record'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.request(
        'DELETE',
        '${widget.module.path}/${Uri.encodeComponent(row['id'].toString())}',
      );
      widget.message('Asset record deleted');
      reload();
    } catch (error) {
      widget.message(error.toString());
    }
  }

  Future<void> _doAction(Map<String, dynamic> row, RecordAction action) async {
    if (action.special == 'permissions') {
      final result = await showRecordForm(
        context,
        'Module access for ${displayValue(row['name'])}',
        [
          for (final module in permissionModules)
            FieldSpec(module, _label(module), type: FieldType.toggle),
        ],
        initial: asMap(row['permissions']),
      );
      if (result != null) {
        await request('PATCH', action.path(row), {
          'permissions': result,
        }, 'Permissions saved');
      }
      return;
    }
    if (action.special == 'view') {
      try {
        final result = await widget.api.get(action.path(row));
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(action.label),
                content: SizedBox(
                  width: 700,
                  height: 500,
                  child: ListView(
                    children: [
                      if (result is List)
                        ...asRows(result).map(
                          (item) => _infoCard(displayValue(item['id']), item),
                        )
                      else
                        ...asMap(result).entries.map(
                          (entry) =>
                              entry.value is List
                                  ? _section(
                                    _label(entry.key),
                                    asRows(entry.value),
                                  )
                                  : _infoCard(
                                    _label(entry.key),
                                    asMap(entry.value).isNotEmpty
                                        ? asMap(entry.value)
                                        : {'value': entry.value},
                                  ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
        );
      } catch (error) {
        widget.message(error.toString());
      }
      return;
    }
    if (action.special == 'pay') {
      final max =
          ((row['outstanding'] ??
                      ((row['total'] as num? ?? 0) -
                          (row['paidAmount'] as num? ?? 0)))
                  as num)
              .toDouble();
      final result = await showConfiguredSplitPayment(
        context,
        api: widget.api,
        max: max,
        exact: action.exactPayment,
      );
      if (result == null) return;
      await request('POST', action.path(row), result, 'Payment recorded');
      return;
    }
    if (action.special == 'receive') {
      final result = await showReceiveForm(context, row);
      if (result != null) {
        request('POST', action.path(row), result, 'Goods received');
      }
      return;
    }
    if (action.special == 'return') {
      final result = await showReturnForm(context, row);
      if (result != null) {
        request('POST', action.path(row), result, 'Return recorded');
      }
      return;
    }
    List<FieldSpec> fields = action.fields;
    if (action.formModule != null) {
      try {
        fields = await loadRecordFields(widget.api, action.formModule!);
        fields = _actionFormFields(action, fields);
      } catch (error) {
        widget.message(error.toString());
        return;
      }
    }
    if (!mounted) return;
    final body =
        fields.isEmpty
            ? action.body
            : await showRecordForm(
              context,
              action.label,
              fields,
              initial: action.body,
              onManageFields:
                  action.formModule != null && _canManageRecordFields
                      ? () async {
                        final changed = await showRecordFieldsManager(
                          context,
                          widget.api,
                          action.formModule!,
                        );
                        if (!changed || !mounted) return null;
                        reload();
                        final updated = await loadRecordFields(
                          widget.api,
                          action.formModule!,
                        );
                        return _actionFormFields(action, updated);
                      }
                      : null,
            );
    if (body == null) return;
    await request(
      action.method,
      action.path(row),
      action.formModule == null
          ? {...action.body, ...body}
          : action.formModule == 'refunds'
          ? {'bookingId': row['id'], ...body}
          : body,
      '${action.label} completed',
    );
  }

  List<FieldSpec> _actionFormFields(
    RecordAction action,
    List<FieldSpec> fields,
  ) {
    if (action.formModule == 'refunds') {
      return fields.where((field) => field.key != 'bookingId').toList();
    }
    if (action.formModule == 'cases') {
      return fields
          .where(
            (field) =>
                const {'status', 'assignee'}.contains(field.key) ||
                field.key.startsWith('custom_'),
          )
          .toList();
    }
    return fields;
  }
}

class _TableAlerts extends StatefulWidget {
  const _TableAlerts({
    required this.api,
    required this.grocery,
    required this.message,
    this.onOpenTable,
  });

  final ApiClient api;
  final bool grocery;
  final ValueChanged<String> message;
  final ValueChanged<String>? onOpenTable;

  @override
  State<_TableAlerts> createState() => _TableAlertsState();
}

class _TableAlertsState extends State<_TableAlerts> {
  List<TableReminder>? reminders;
  String? error;
  Timer? timer;
  int requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant _TableAlerts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.grocery != widget.grocery) {
      _load();
    }
  }

  @override
  void dispose() {
    requestSerial++;
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++requestSerial;
    try {
      final loaded = await NamedTableRepository(
        widget.api,
      ).dueReminders(widget.grocery);
      if (mounted && serial == requestSerial) {
        setState(() {
          reminders = loaded;
          error = null;
        });
      }
    } catch (exception) {
      if (mounted && serial == requestSerial) {
        setState(() => error = exception.toString());
      }
    }
  }

  Future<void> _dismiss(TableReminder reminder) async {
    setState(
      () =>
          reminders =
              (reminders ?? const <TableReminder>[])
                  .where(
                    (item) =>
                        item.tableId != reminder.tableId ||
                        item.rowId != reminder.rowId,
                  )
                  .toList(),
    );
    try {
      await NamedTableRepository(widget.api).dismissReminder(reminder);
      if (mounted) await _load();
    } catch (exception) {
      if (mounted) {
        widget.message('Could not dismiss alert: $exception');
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = reminders ?? const <TableReminder>[];
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: items.isEmpty ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Table alerts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (items.isNotEmpty)
                  Badge(
                    label: Text('${items.length}'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                IconButton(
                  tooltip: 'Refresh alerts',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (reminders == null && error == null)
              const LinearProgressIndicator()
            else if (error != null)
              Text('Could not load table alerts: $error')
            else if (items.isEmpty)
              const Text('No due table reminders.')
            else
              for (final reminder in items.take(20))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${reminder.tableName} · Row ${reminder.rowNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (reminder.preview.isNotEmpty)
                                Text(
                                  reminder.preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                'Due ${locale.formatShortDate(reminder.notifyAt)} '
                                '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(reminder.notifyAt))}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (widget.onOpenTable != null)
                          TextButton.icon(
                            onPressed:
                                () => widget.onOpenTable!(reminder.tableId),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open table'),
                          ),
                        TextButton(
                          onPressed: () => _dismiss(reminder),
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                ),
            if (items.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${items.length - 20} more alerts due'),
              ),
          ],
        ),
      ),
    );
  }
}

String _label(String key) => key
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    )
    .replaceAll('_', ' ')
    .replaceFirstMapped(RegExp(r'^.'), (match) => match[0]!.toUpperCase());
