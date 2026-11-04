import 'package:flutter/material.dart';

import 'api.dart';

enum FinancialRecordKind { airlineSale, grocerySale, expense }

class FinancialRegister extends StatefulWidget {
  const FinancialRegister({
    super.key,
    required this.title,
    required this.rows,
    required this.kind,
    this.demo = false,
    this.onOpenRecord,
    this.onPrintRecord,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final FinancialRecordKind kind;
  final bool demo;
  final ValueChanged<Map<String, dynamic>>? onOpenRecord;
  final ValueChanged<Map<String, dynamic>>? onPrintRecord;

  @override
  State<FinancialRegister> createState() => _FinancialRegisterState();
}

class _FinancialRegisterState extends State<FinancialRegister> {
  static const _ink = Color(0xff17233d);
  static const _muted = Color(0xff718098);
  static const _line = Color(0xffe4eaf2);
  static const _green = Color(0xff128367);
  static const _blue = Color(0xff315da8);

  int selectedIndex = 0;
  int? expandedIndex;

  @override
  void didUpdateWidget(covariant FinancialRegister oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.rows.isEmpty != widget.rows.isEmpty) {
      selectedIndex = 0;
      expandedIndex = null;
    } else if (selectedIndex >= widget.rows.length) {
      selectedIndex = 0;
      expandedIndex = null;
    }
  }

  String _value(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return 'Not recorded';
    return displayValue(value);
  }

  String _amount(Object? value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (number == null) return 'Not recorded';
    final sign = number < 0 ? '-' : '';
    final fixed = number.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts.first;
    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(digits[index]);
    }
    return '$sign$grouped.${parts.last}';
  }

  String _reference(Map<String, dynamic> row, int index) {
    for (final candidate in [row['receipt'], row['reference'], row['id']]) {
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        return candidate.toString();
      }
    }
    return 'Record ${index + 1}';
  }

  String _date(Map<String, dynamic> row) {
    final raw = row['createdAt'] ?? row['date'];
    if (raw == null) return 'Date not recorded';
    return raw.toString().replaceFirst('T', ' ').replaceFirst('Z', '');
  }

  String _status(Map<String, dynamic> row) {
    if (widget.kind == FinancialRecordKind.expense) {
      return _value(row['paymentStatus'] ?? row['status']);
    }
    return _value(
      row['paymentStatus'] ??
          (widget.kind == FinancialRecordKind.grocerySale ? 'Paid' : null),
    );
  }

  String _person(Map<String, dynamic> row) => switch (widget.kind) {
    FinancialRecordKind.expense => _value(row['payee']),
    _ => _value(row['customerName'] ?? row['customer']),
  };

  String _paymentMethod(Map<String, dynamic> row) {
    if (row['payment'] != null) return _value(row['payment']);
    final methods =
        asRows(row['payments'])
            .map((payment) => payment['method'] ?? payment['methodName'])
            .where((method) => method != null)
            .map((method) => method.toString())
            .toList();
    return methods.isEmpty ? 'Not recorded' : methods.join(' + ');
  }

  bool _isDemo(Map<String, dynamic> row) =>
      widget.demo || row['id']?.toString().startsWith('DEMO-') == true;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${widget.title} (${rows.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _pill(
                widget.demo ? 'Demo preview' : 'Recorded data',
                widget.demo ? _blue : _green,
              ),
              if (rows.isNotEmpty)
                TextButton(
                  onPressed:
                      () => setState(() {
                        expandedIndex =
                            expandedIndex == null ? selectedIndex : null;
                      }),
                  child: Text(
                    expandedIndex == null ? 'Expand selected' : 'Collapse all',
                  ),
                ),
            ],
          ),
        ),
        if (rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: _panelDecoration(),
            child: Column(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  color: _muted,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.kind == FinancialRecordKind.expense
                      ? 'No expenses recorded'
                      : 'No sales recorded',
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 850;
              final list = Column(
                children: [
                  for (
                    var index = 0;
                    index < rows.length && index < 100;
                    index++
                  ) ...[
                    _recordCard(
                      rows[index],
                      index,
                      showAirlineActions: compact,
                    ),
                    const SizedBox(height: 9),
                  ],
                  if (rows.length > 100)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Showing the first 100 of ${rows.length} records',
                      ),
                    ),
                ],
              );
              final preview = _previewPanel(
                rows[selectedIndex],
                showAirlineActions: !compact,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [list, const SizedBox(height: 10), preview],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: list),
                  const SizedBox(width: 14),
                  Expanded(flex: 4, child: preview),
                ],
              );
            },
          ),
      ],
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
    color: Colors.white,
    border: Border.all(color: _line),
    borderRadius: BorderRadius.circular(13),
  );

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );

  Widget _recordCard(
    Map<String, dynamic> row,
    int index, {
    required bool showAirlineActions,
  }) {
    final expanded = expandedIndex == index;
    final selected = selectedIndex == index;
    final items = asRows(row['items']);
    final total = row['total'] ?? row['amount'];
    final status = _status(row);
    return Container(
      key: ValueKey('financial-record-$index'),
      decoration: _panelDecoration().copyWith(
        border: Border.all(color: selected ? const Color(0xffcbd9f0) : _line),
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey('financial-record-select-$index'),
            borderRadius: BorderRadius.circular(13),
            onTap: () => setState(() => selectedIndex = index),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final reference = Text(
                        _reference(row, index),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      );
                      final amount = Text(
                        _amount(total),
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      );
                      final arrow = IconButton(
                        key: ValueKey('financial-record-expand-$index'),
                        tooltip:
                            expanded ? 'Collapse details' : 'Expand details',
                        onPressed:
                            () => setState(
                              () => expandedIndex = expanded ? null : index,
                            ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        icon: Icon(
                          expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: _muted,
                          size: 19,
                        ),
                      );
                      if (constraints.maxWidth < 380) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: reference),
                                const SizedBox(width: 8),
                                amount,
                                const SizedBox(width: 4),
                                arrow,
                              ],
                            ),
                            if (status != 'Not recorded' || _isDemo(row))
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Wrap(
                                  spacing: 6,
                                  children: [
                                    if (status != 'Not recorded')
                                      _pill(status, _green),
                                    if (_isDemo(row)) _pill('SAMPLE', _blue),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Flexible(child: reference),
                          const SizedBox(width: 7),
                          if (status != 'Not recorded') _pill(status, _green),
                          if (_isDemo(row)) ...[
                            const SizedBox(width: 6),
                            _pill('SAMPLE', _blue),
                          ],
                          const Spacer(),
                          amount,
                          const SizedBox(width: 4),
                          arrow,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _date(row),
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    switch (widget.kind) {
                      FinancialRecordKind.grocerySale =>
                        'Items: ${items.length}  ·  Tax: ${_amount(row['tax'])}  ·  Profit: ${_amount(row['profit'])}',
                      FinancialRecordKind.airlineSale =>
                        'Customer: ${_person(row)}  ·  ${_value(row['description'])}',
                      FinancialRecordKind.expense =>
                        'Payee: ${_person(row)}  ·  Category: ${_value(row['category'])}  ·  Outstanding: ${_amount(row['outstanding'])}',
                    },
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: _line),
            _expandedDetails(row, showAirlineActions: showAirlineActions),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, Object? value, {bool amount = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 115,
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            amount ? _amount(value) : _value(value),
            style: const TextStyle(color: _ink, fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget _expandedDetails(
    Map<String, dynamic> row, {
    required bool showAirlineActions,
  }) {
    final items = asRows(row['items']);
    final payments = asRows(row['payments']);
    final expense = widget.kind == FinancialRecordKind.expense;
    final grocery = widget.kind == FinancialRecordKind.grocerySale;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (grocery) ...[
            const Text(
              'ITEM DETAILS',
              style: TextStyle(
                color: _blue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('Items not recorded', style: TextStyle(color: _muted))
            else
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(_value(item['name']))),
                      Expanded(child: Text('× ${_value(item['qty'])}')),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _amount(item['total']),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
            const Divider(color: _line),
          ],
          if (expense) ...[
            _detail('Payee', row['payee']),
            _detail('Category', row['category']),
            _detail('Description', row['description']),
            _detail('Quantity', row['quantity']),
            _detail('Unit rate', row['unitRate'], amount: true),
          ] else ...[
            _detail('Customer', row['customerName'] ?? row['customer']),
            if (!grocery) _detail('What was sold', row['description']),
            _detail('Cashier', row['cashier'] ?? row['createdBy']),
          ],
          _detail('Subtotal', row['subtotal'], amount: true),
          _detail('Discount', row['discount'], amount: true),
          _detail('Tax', row['tax'], amount: true),
          _detail('Total', row['total'] ?? row['amount'], amount: true),
          if (grocery) ...[
            _detail('Cost of goods', row['cost'], amount: true),
            _detail('Profit', row['profit'], amount: true),
          ],
          if (expense) ...[
            _detail('Paid', row['paidAmount'], amount: true),
            _detail('Outstanding', row['outstanding'], amount: true),
          ],
          _detail('Payment method', _paymentMethod(row)),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 3),
            for (final payment in payments)
              _detail(
                'Payment',
                '${_value(payment['method'] ?? payment['methodName'])}: ${_amount(payment['amount'])}',
              ),
          ],
          if ((widget.kind == FinancialRecordKind.airlineSale
                  ? showAirlineActions
                  : !_isDemo(row)) &&
              (widget.onOpenRecord != null ||
                  widget.onPrintRecord != null)) ...[
            const SizedBox(height: 8),
            _recordActionButtons(row, expense: expense),
          ],
        ],
      ),
    );
  }

  Widget _recordActionButtons(
    Map<String, dynamic> row, {
    required bool expense,
  }) {
    final demo = _isDemo(row);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (demo) ...[
          const Text(
            'Actions are available for saved sales only.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 6),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.onOpenRecord != null)
              OutlinedButton.icon(
                onPressed: demo ? null : () => widget.onOpenRecord!(row),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Open full record'),
              ),
            if (widget.onPrintRecord != null)
              OutlinedButton.icon(
                onPressed: demo ? null : () => widget.onPrintRecord!(row),
                icon: const Icon(Icons.print_outlined, size: 15),
                label: Text(expense ? 'Print voucher' : 'Print receipt'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _previewPanel(
    Map<String, dynamic> row, {
    required bool showAirlineActions,
  }) {
    final expense = widget.kind == FinancialRecordKind.expense;
    final grocery = widget.kind == FinancialRecordKind.grocerySale;
    final items = asRows(row['items']);
    final reference = _reference(row, selectedIndex);
    final total = row['total'] ?? row['amount'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: _panelDecoration(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense ? 'EXPENSE PREVIEW' : 'RECEIPT PREVIEW',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                expense ? 'Expense voucher' : 'Sales slip',
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xfff7f9fc),
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(13),
                child: Column(
                  children: [
                    Text(
                      grocery ? 'FRESHMART' : 'AERODESK',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _ink,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reference,
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                    if (_isDemo(row))
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text(
                          'SAMPLE ONLY · NOT A REAL TRANSACTION',
                          style: TextStyle(
                            color: _blue,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const Divider(height: 24, color: _line),
                    if (grocery && items.isNotEmpty)
                      for (final item in items)
                        _slipLine(
                          '${_value(item['qty'])}× ${_value(item['name'])}',
                          _amount(item['total']),
                        )
                    else
                      _slipLine(
                        expense
                            ? _value(row['description'] ?? row['category'])
                            : _value(row['description']),
                        _amount(total),
                      ),
                    const Divider(height: 20, color: _line),
                    if (row['subtotal'] != null)
                      _slipLine('Subtotal', _amount(row['subtotal'])),
                    if (row['discount'] != null)
                      _slipLine('Discount', _amount(row['discount'])),
                    if (row['tax'] != null)
                      _slipLine('Tax', _amount(row['tax'])),
                    _slipLine('TOTAL', _amount(total), bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _detail(expense ? 'Payee' : 'Customer', _person(row)),
              if (widget.kind == FinancialRecordKind.airlineSale &&
                  asRows(row['payments']).isNotEmpty)
                for (final payment in asRows(row['payments']))
                  _detail(
                    'Payment',
                    '${_value(payment['method'] ?? payment['methodName'])}: ${_amount(payment['amount'])}',
                  )
              else
                _detail('Payment', _paymentMethod(row)),
              _detail('Date', _date(row)),
              if (showAirlineActions &&
                  widget.kind == FinancialRecordKind.airlineSale &&
                  (widget.onOpenRecord != null ||
                      widget.onPrintRecord != null)) ...[
                const SizedBox(height: 8),
                _recordActionButtons(row, expense: false),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: _panelDecoration(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense
                    ? 'PAYMENT POSITION'
                    : grocery
                    ? 'PROFIT & MARGIN'
                    : 'SALE SUMMARY',
                style: const TextStyle(
                  color: _blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (grocery) ...[
                _detail('Cost', row['cost'], amount: true),
                _detail('Net profit', row['profit'], amount: true),
              ] else if (expense) ...[
                _detail('Paid', row['paidAmount'], amount: true),
                _detail('Outstanding', row['outstanding'], amount: true),
              ] else ...[
                _detail('Total', total, amount: true),
                _detail('Status', _status(row)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _slipLine(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink,
              fontSize: 10,
              fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: _ink,
            fontSize: 10,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}
