import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'booking_form_fields.dart';
import 'form_sheet.dart';
import 'modules.dart';
import 'named_table_repository.dart';
import 'payment_dialog.dart';
import 'transactions.dart';
import 'travel_ui.dart';

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
  Future<dynamic>? recentBookingsFuture;
  String search = '';
  String status = '';
  DateTimeRange? financeRange;
  String financeType = '';
  String financeSearch = '';
  String financeSection = 'Wallet movements';

  Widget _tableAlerts() => _TableAlerts(
    api: widget.api,
    grocery: widget.grocery,
    message: widget.message,
    onOpenTable: widget.onOpenTable,
  );

  String get dataPath {
    if (widget.module.key != 'finance' || financeRange == null) {
      return widget.module.path;
    }
    String day(DateTime value) => value.toIso8601String().substring(0, 10);
    return '${widget.module.path}?from=${day(financeRange!.start)}&to=${day(financeRange!.end)}';
  }

  void reload() => setState(() {
    future = widget.api.get(dataPath);
    groceryReportsFuture = null;
    recentBookingsFuture = null;
  });

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
      if (widget.module.key == 'finance') return _finance(asMap(data));
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

  Widget _finance(Map<String, dynamic> data) {
    final wallet = asMap(data['wallet']);
    final sections = <String, dynamic>{
      'Wallet movements': data['walletRows'],
      'Ledger': data['ledgerRows'],
      'Receivables': data['receivables'],
      'Payables': data['payables'],
      'Adjustments': data['pendingAdjustments'],
      'Reconciliations': data['reconciliations'],
      'Locked periods': data['lockedPeriods'],
    };
    final movementTypes = <String>{
      ...asRows(data['walletRows']).map((row) => row['type'].toString()),
    };
    final selectedType = movementTypes.contains(financeType) ? financeType : '';
    const mainViews = <String>[
      'Wallet movements',
      'Ledger',
      'Receivables',
      'Payables',
    ];
    const otherViews = <String>[
      'Adjustments',
      'Reconciliations',
      'Locked periods',
    ];
    const descriptions = <String, String>{
      'Wallet movements': 'Money received and paid out of your wallet.',
      'Ledger': 'Accounting entries for each transaction.',
      'Receivables': 'Bookings with money still owed by customers.',
      'Payables': 'Purchases with money still owed to suppliers.',
      'Adjustments': 'Requests to correct a wallet balance.',
      'Reconciliations': 'Checks against bank or wallet statements.',
      'Locked periods': 'Accounting periods closed to new changes.',
    };
    final currentSection =
        sections.containsKey(financeSection)
            ? financeSection
            : 'Wallet movements';
    final visibleRows =
        asRows(sections[currentSection])
            .where(
              (row) =>
                  (currentSection != 'Wallet movements' ||
                      selectedType.isEmpty ||
                      row['type'] == selectedType) &&
                  (financeSearch.isEmpty ||
                      row.values.any(
                        (value) => displayValue(
                          value,
                        ).toLowerCase().contains(financeSearch),
                      )),
            )
            .toList();
    return _page(
      ux: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search wallet and ledger',
                  isDense: true,
                ),
                onChanged:
                    (value) =>
                        setState(() => financeSearch = value.toLowerCase()),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2150),
                  initialDateRange: financeRange,
                );
                if (range != null) {
                  financeRange = range;
                  reload();
                }
              },
              icon: const Icon(Icons.date_range),
              label: Text(
                financeRange == null
                    ? 'All dates'
                    : '${financeRange!.start.toIso8601String().substring(0, 10)} to ${financeRange!.end.toIso8601String().substring(0, 10)}',
              ),
            ),
            if (financeRange != null)
              TextButton(
                onPressed: () {
                  financeRange = null;
                  reload();
                },
                child: const Text('Clear dates'),
              ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Movement type',
                  isDense: true,
                ),
                items:
                    ['', ...movementTypes]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.isEmpty ? 'All types' : value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => financeType = value ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 30,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CURRENT WALLET BALANCE',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayValue(wallet['balance']),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
                Text('Opening: ${displayValue(data['openingBalance'])}'),
                Text('Closing: ${displayValue(data['closingBalance'])}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            title: const Text('More actions'),
            subtitle: const Text(
              'Adjustments, reconciliation, journals, reports and settings',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          () => _financeForm(
                            'Wallet adjustment',
                            '/api/wallet/adjustments',
                            [
                              const FieldSpec(
                                'date',
                                'Date',
                                type: FieldType.date,
                              ),
                              const FieldSpec(
                                'type',
                                'Type',
                                initial: 'Manual adjustment',
                              ),
                              const FieldSpec(
                                'reference',
                                'Reference',
                                required: true,
                              ),
                              const FieldSpec(
                                'amount',
                                'Amount (+ or −)',
                                type: FieldType.number,
                                required: true,
                              ),
                              const FieldSpec(
                                'account',
                                'Account',
                                initial: 'Agency wallet',
                              ),
                              const FieldSpec(
                                'category',
                                'Category',
                                initial: 'Other income',
                              ),
                              const FieldSpec(
                                'paymentMethod',
                                'Method',
                                type: FieldType.choice,
                                choices: paymentMethods,
                                initial: 'Cash',
                              ),
                              const FieldSpec('bankName', 'Bank name'),
                              const FieldSpec(
                                'note',
                                'Reason',
                                type: FieldType.paragraph,
                                required: true,
                              ),
                            ],
                          ),
                      icon: const Icon(Icons.add),
                      label: const Text('Request adjustment'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          () => _financeForm(
                            'Reconcile account',
                            '/api/finance/reconciliations',
                            [
                              const FieldSpec(
                                'date',
                                'Date',
                                type: FieldType.date,
                              ),
                              const FieldSpec(
                                'account',
                                'Account',
                                required: true,
                              ),
                              const FieldSpec(
                                'paymentMethod',
                                'Method',
                                type: FieldType.choice,
                                choices: paymentMethods,
                                initial: 'Bank',
                              ),
                              const FieldSpec(
                                'statementBalance',
                                'Statement balance',
                                type: FieldType.number,
                                required: true,
                              ),
                              const FieldSpec(
                                'systemBalance',
                                'System balance',
                                type: FieldType.number,
                                required: true,
                              ),
                              const FieldSpec(
                                'note',
                                'Notes',
                                type: FieldType.paragraph,
                              ),
                            ],
                          ),
                      icon: const Icon(Icons.balance),
                      label: const Text('Reconcile'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          () => _financeForm(
                            'Balanced journal',
                            '/api/ledger',
                            const [
                              FieldSpec('date', 'Date', type: FieldType.date),
                              FieldSpec(
                                'type',
                                'Type',
                                initial: 'Manual journal',
                              ),
                              FieldSpec(
                                'reference',
                                'Reference',
                                required: true,
                              ),
                              FieldSpec(
                                'debitAccount',
                                'Debit account',
                                required: true,
                              ),
                              FieldSpec(
                                'creditAccount',
                                'Credit account',
                                required: true,
                              ),
                              FieldSpec(
                                'amount',
                                'Amount',
                                type: FieldType.number,
                                required: true,
                              ),
                              FieldSpec('category', 'Category'),
                              FieldSpec('currency', 'Currency', initial: 'USD'),
                              FieldSpec(
                                'exchangeRate',
                                'Exchange rate',
                                type: FieldType.number,
                                initial: 1,
                              ),
                              FieldSpec('entityType', 'Linked record type'),
                              FieldSpec('entityId', 'Linked record ID'),
                              FieldSpec(
                                'note',
                                'Note',
                                type: FieldType.paragraph,
                              ),
                            ],
                          ),
                      icon: const Icon(Icons.add_card_outlined),
                      label: const Text('Post journal'),
                    ),
                    if (widget.user['role'] == 'Agency owner' ||
                        widget.user['role'] == 'Agency administrator')
                      OutlinedButton.icon(
                        onPressed:
                            () => _financeForm(
                              'Lock accounting period',
                              '/api/finance/periods',
                              const [
                                FieldSpec(
                                  'from',
                                  'From',
                                  type: FieldType.date,
                                  required: true,
                                ),
                                FieldSpec(
                                  'to',
                                  'To',
                                  type: FieldType.date,
                                  required: true,
                                ),
                              ],
                            ),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Lock period'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _showFinanceReports,
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Financial reports'),
                    ),
                    if (widget.user['role'] == 'Agency owner' ||
                        widget.user['role'] == 'Agency administrator')
                      OutlinedButton.icon(
                        onPressed:
                            () =>
                                _showCurrencySettings(asMap(data['settings'])),
                        icon: const Icon(Icons.currency_exchange),
                        label: const Text('Currencies & rates'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final view in mainViews)
              ChoiceChip(
                label: Text(
                  '${view == 'Wallet movements' ? 'Wallet' : view} (${asRows(sections[view]).length})',
                ),
                selected: currentSection == view,
                onSelected: (_) => setState(() => financeSection = view),
              ),
            PopupMenuButton<String>(
              tooltip: 'Other finance views',
              onSelected: (value) => setState(() => financeSection = value),
              itemBuilder:
                  (context) => [
                    for (final view in otherViews)
                      PopupMenuItem(
                        value: view,
                        child: Text('$view (${asRows(sections[view]).length})'),
                      ),
                  ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      otherViews.contains(currentSection)
                          ? currentSection
                          : 'Other views',
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          descriptions[currentSection] ?? '',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _section(currentSection, visibleRows, expanded: true),
      ],
    );
  }

  Future<void> _showCurrencySettings(Map<String, dynamic> settings) async {
    final currencies =
        settings['currencies'] is List
            ? (settings['currencies'] as List).join(', ')
            : '';
    final rates = asMap(
      settings['exchangeRates'],
    ).entries.map((entry) => '${entry.key}=${entry.value}').join('\n');
    final result = await showRecordForm(
      context,
      'Currencies and exchange rates',
      const [
        FieldSpec('baseCurrency', 'Base currency', required: true),
        FieldSpec('currencies', 'Currencies, comma separated', required: true),
        FieldSpec(
          'rates',
          'Exchange rates (CODE=rate per line)',
          type: FieldType.paragraph,
          required: true,
        ),
      ],
      initial: {
        'baseCurrency': settings['baseCurrency'],
        'currencies': currencies,
        'rates': rates,
      },
    );
    if (result == null) return;
    final codes =
        result['currencies']
            .toString()
            .split(',')
            .map((code) => code.trim().toUpperCase())
            .where((code) => code.isNotEmpty)
            .toList();
    final exchangeRates = <String, double>{};
    for (final line in result['rates'].toString().split(RegExp(r'[\n,]'))) {
      final parts = line.split('=');
      if (parts.length != 2) continue;
      final rate = double.tryParse(parts[1].trim());
      if (rate != null && rate > 0) {
        exchangeRates[parts[0].trim().toUpperCase()] = rate;
      }
    }
    await request('PATCH', '/api/finance/settings', {
      'baseCurrency': result['baseCurrency'].toString().toUpperCase(),
      'currencies': codes,
      'exchangeRates': exchangeRates,
    }, 'Currency settings saved');
  }

  Future<void> _financeForm(
    String title,
    String path,
    List<FieldSpec> fields,
  ) async {
    final result = await showRecordForm(
      context,
      title,
      fields,
      api: widget.api,
    );
    if (result != null) request('POST', path, result, 'Saved');
  }

  Future<void> _showFinanceReports() async {
    try {
      String day(DateTime value) => value.toIso8601String().substring(0, 10);
      final query =
          financeRange == null
              ? ''
              : '?from=${day(financeRange!.start)}&to=${day(financeRange!.end)}';
      final reports = asMap(await widget.api.get('/api/finance/reports$query'));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Financial reports'),
              content: SizedBox(
                width: 640,
                height: 520,
                child: ListView(
                  children: [
                    _infoCard('Profit and loss', asMap(reports['profitLoss'])),
                    _infoCard('Cash flow', asMap(reports['cashFlow'])),
                    _infoCard('Balance sheet', asMap(reports['balanceSheet'])),
                    _section('Daily summary', asRows(reports['daily'])),
                    _section('Monthly summary', asRows(reports['monthly'])),
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
  }

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
          ...asMap(data['stats']).entries.map(
            (entry) => _metric(_label(entry.key), displayValue(entry.value)),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<dynamic>>(
            future: groceryReportsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return snapshot.hasError
                    ? Text(snapshot.error.toString())
                    : const Center(child: CircularProgressIndicator());
              }
              final sales = asRows(snapshot.data![0]);
              final products = asRows(snapshot.data![1]);
              final expenses = asRows(snapshot.data![2]);
              double sum(List<Map<String, dynamic>> rows, String key) =>
                  rows.fold(
                    0,
                    (total, row) =>
                        total + ((row[key] as num?)?.toDouble() ?? 0),
                  );
              final grossProfit = sum(sales, 'profit');
              final expenseTotal = sum(expenses, 'amount');
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metric(
                        'Total sales',
                        sum(sales, 'total').toStringAsFixed(2),
                      ),
                      _metric('Gross profit', grossProfit.toStringAsFixed(2)),
                      _metric(
                        'Net after expenses',
                        (grossProfit - expenseTotal).toStringAsFixed(2),
                      ),
                      _metric('Stock at cost', stockCost.toStringAsFixed(2)),
                      _metric(
                        'Stock at retail',
                        stockRetail.toStringAsFixed(2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _section('Sales register', sales),
                ],
              );
            },
          ),
        ],
      );
    }
    final totals = asMap(data['totals']);
    return _page(
      ux: [
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
        _section('Sales', asRows(data['rows'])),
      ],
    );
  }

  Widget _collection(List<Map<String, dynamic>> rows) {
    final statuses = <String>{};
    for (final row in rows) {
      final value = row['status']?.toString();
      if (value != null && value.isNotEmpty) statuses.add(value);
    }
    final selectedStatus = statuses.contains(status) ? status : '';
    final filtered =
        rows.where((row) {
          final query = search.toLowerCase();
          return (selectedStatus.isEmpty || row['status'] == selectedStatus) &&
              row.values.any(
                (value) => displayValue(value).toLowerCase().contains(query),
              );
        }).toList();
    if (!widget.grocery) {
      return _travelCollection(filtered, statuses, selectedStatus);
    }
    return _page(
      ux: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Text(
              '${widget.module.title} (${filtered.length})',
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_hasConfigurableForm && _canManageRecordFields)
              OutlinedButton.icon(
                onPressed: _manageRecordFields,
                icon: const Icon(Icons.tune),
                label: const Text('Manage form fields'),
              ),
            if (widget.module.fields.isNotEmpty ||
                widget.module.key == 'purchases' ||
                widget.module.key == 'roles' ||
                (!widget.grocery && widget.module.key == 'sales'))
              FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add),
                label: Text(widget.module.createLabel ?? 'New purchase order'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 360,
              child: TextField(
                onChanged: (value) => setState(() => search = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search records',
                  isDense: true,
                ),
              ),
            ),
            if (statuses.isNotEmpty)
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
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
                  onChanged: (value) => setState(() => status = value ?? ''),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No matching records')),
            ),
          )
        else
          LayoutBuilder(
            builder:
                (context, constraints) =>
                    constraints.maxWidth < 700
                        ? Column(children: filtered.map(_recordCard).toList())
                        : _recordTable(filtered),
          ),
      ],
    );
  }

  Widget _travelCollection(
    List<Map<String, dynamic>> filtered,
    Set<String> statuses,
    String selectedStatus,
  ) {
    final canCreate =
        widget.module.fields.isNotEmpty ||
        widget.module.key == 'purchases' ||
        widget.module.key == 'roles' ||
        widget.module.key == 'sales';
    return _page(
      ux: [
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
                  if (_hasConfigurableForm && _canManageRecordFields)
                    OutlinedButton.icon(
                      onPressed: _manageRecordFields,
                      icon: const Icon(Icons.tune),
                      label: const Text('Manage form fields'),
                    ),
                  if (canCreate)
                    FilledButton.icon(
                      onPressed: create,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(widget.module.createLabel ?? 'New record'),
                    ),
                ],
              ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 345,
                  child: TextField(
                    onChanged: (value) => setState(() => search = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      hintText: 'Search records',
                      isDense: true,
                    ),
                  ),
                ),
                if (statuses.isNotEmpty)
                  SizedBox(
                    width: 195,
                    child: DropdownButtonFormField<String>(
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
                          (value) => setState(() => status = value ?? ''),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.travel_explore_outlined,
                      size: 35,
                      color: TravelPalette.purple,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No matching records',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Try a different search or status.',
                      style: TextStyle(color: TravelPalette.muted),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder:
                (context, constraints) =>
                    constraints.maxWidth < 700
                        ? Column(children: filtered.map(_recordCard).toList())
                        : _recordTable(filtered),
          ),
      ],
    );
  }

  Widget _recordCard(Map<String, dynamic> row) =>
      widget.grocery
          ? Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _detail(row),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayValue(row[widget.module.columns.first]),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...widget.module.columns
                        .skip(1)
                        .take(5)
                        .map(
                          (key) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${_label(key)}: ${displayValue(row[key])}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _detail(row),
                        child: const Text('Details & actions'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          : Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(17),
                onTap: () => _detail(row),
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 37,
                            height: 37,
                            decoration: BoxDecoration(
                              color: TravelPalette.purpleSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              widget.module.icon,
                              size: 18,
                              color: TravelPalette.purple,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              displayValue(row[widget.module.columns.first]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if ((row['status'] ?? '').toString().isNotEmpty)
                            TravelStatusChip(row['status'].toString()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...widget.module.columns
                          .skip(1)
                          .take(5)
                          .map(
                            (key) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      _label(key),
                                      style: const TextStyle(
                                        color: TravelPalette.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      displayValue(row[key]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _detail(row),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                          ),
                          label: const Text('Details & actions'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

  Widget _recordTable(List<Map<String, dynamic>> rows) => Card(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showBottomBorder: true,
        headingRowColor:
            widget.grocery
                ? null
                : const WidgetStatePropertyAll(Color(0xfff8f7fd)),
        headingTextStyle:
            widget.grocery
                ? null
                : const TextStyle(
                  color: TravelPalette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                ),
        dataRowMinHeight: widget.grocery ? null : 62,
        dataRowMaxHeight: widget.grocery ? null : 70,
        border: const TableBorder(
          verticalInside: BorderSide(color: Color(0xffdce5e9)),
          horizontalInside: BorderSide(color: Color(0xffedf1f3)),
        ),
        columns: [
          ...widget.module.columns.map(
            (key) => DataColumn(
              label: Text(
                widget.grocery ? _label(key) : _label(key).toUpperCase(),
              ),
            ),
          ),
          const DataColumn(label: Text('')),
        ],
        rows:
            rows
                .map(
                  (row) => DataRow(
                    cells: [
                      ...widget.module.columns.map(
                        (key) => DataCell(
                          SizedBox(
                            width: 130,
                            child:
                                !widget.grocery &&
                                        (key == 'status' ||
                                            key == 'paymentStatus') &&
                                        (row[key] ?? '').toString().isNotEmpty
                                    ? Align(
                                      alignment: Alignment.centerLeft,
                                      child: TravelStatusChip(
                                        row[key].toString(),
                                      ),
                                    )
                                    : Text(
                                      displayValue(row[key]),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                          ),
                          onTap: () => _detail(row),
                        ),
                      ),
                      DataCell(
                        IconButton(
                          tooltip: 'Details',
                          onPressed: () => _detail(row),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
      ),
    ),
  );

  Widget _section(
    String title,
    List<Map<String, dynamic>> rows, {
    bool expanded = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      child: ExpansionTile(
        key: ValueKey('finance-or-section-$title'),
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
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children:
                            row.entries
                                .where(
                                  (entry) =>
                                      !entry.key.toLowerCase().contains(
                                        'data',
                                      ) &&
                                      entry.key != 'passwordHash',
                                )
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
