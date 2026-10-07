import 'package:flutter/material.dart';
import 'api.dart';
import 'booking_form_fields.dart';
import 'form_sheet.dart';
import 'modules.dart';
import 'payment_dialog.dart';
import 'pos_pricing.dart';

class RecordAction {
  const RecordAction(
    this.label,
    this.method,
    this.path, {
    this.fields = const [],
    this.body = const {},
    this.special,
    this.formModule,
    this.exactPayment = false,
  });
  final String label, method;
  final String Function(Map<String, dynamic>) path;
  final List<FieldSpec> fields;
  final Map<String, dynamic> body;
  final String? special;
  final String? formModule;
  final bool exactPayment;
}

List<RecordAction> recordActions(
  String key,
  bool grocery,
  Map<String, dynamic> row,
) {
  final id = row['id'];
  if (grocery) {
    switch (key) {
      case 'purchases':
        return [
          if (row['status'] == 'Pending approval')
            RecordAction(
              'Approve',
              'POST',
              (_) => '/api/grocery/purchases/$id/approve',
              body: const {'approve': true},
            ),
          if (![
                'Draft',
                'Pending approval',
                'Rejected',
                'Cancelled',
              ].contains(row['status']) &&
              row['receivingStatus'] != 'Received')
            RecordAction(
              'Receive goods',
              'POST',
              (_) => '/api/grocery/purchases/$id/receive',
              special: 'receive',
            ),
          if ((row['outstanding'] ?? row['total'] ?? 0) > 0)
            RecordAction(
              'Pay supplier',
              'POST',
              (_) => '/api/grocery/purchases/$id/pay',
              special: 'pay',
            ),
          if (asRows(row['items']).any(
            (item) => (item['receivedQty'] ?? 0) > (item['returnedQty'] ?? 0),
          ))
            RecordAction(
              'Return goods',
              'POST',
              (_) => '/api/grocery/purchases/$id/return',
              special: 'return',
            ),
        ];
      case 'expenses':
        return [
          if (row['status'] == 'Pending approval')
            RecordAction(
              'Approve',
              'POST',
              (_) => '/api/grocery/expenses/$id/approve',
              body: const {'approve': true},
            ),
          if (row['status'] == 'Approved' && (row['outstanding'] ?? 0) > 0)
            RecordAction(
              'Pay expense',
              'POST',
              (_) => '/api/grocery/expenses/$id/pay',
              special: 'pay',
            ),
          if (row['reversed'] != true)
            RecordAction(
              'Reverse',
              'POST',
              (_) => '/api/grocery/expenses/$id/reverse',
              fields: const [
                FieldSpec(
                  'reason',
                  'Reason',
                  required: true,
                  type: FieldType.paragraph,
                ),
              ],
            ),
        ];
      case 'suppliers':
        return [
          RecordAction(
            'Statement',
            'GET',
            (_) => '/api/grocery/suppliers/$id/statement',
            special: 'view',
          ),
          if (row['archived'] != true)
            RecordAction(
              'Archive',
              'POST',
              (_) => '/api/grocery/suppliers/$id/archive',
            ),
        ];
    }
    return const [];
  }
  switch (key) {
    case 'finance':
      if (row['id']?.toString().startsWith('ADJ') == true &&
          row['status'] == 'Pending') {
        return [
          RecordAction(
            'Approve adjustment',
            'POST',
            (_) => '/api/wallet/adjustments/$id/approve',
            body: const {'approve': true},
          ),
          RecordAction(
            'Reject adjustment',
            'POST',
            (_) => '/api/wallet/adjustments/$id/approve',
            body: const {'approve': false},
          ),
        ];
      }
      if (row['id']?.toString().startsWith('PER') == true &&
          row['status'] == 'Locked') {
        return [
          RecordAction(
            'Unlock period',
            'POST',
            (_) => '/api/finance/periods/$id/unlock',
          ),
        ];
      }
      if (row['id']?.toString().startsWith('LE') == true &&
          row['status'] == 'Posted' &&
          row['reversedByJournalId'] == null) {
        return [
          RecordAction(
            'Reverse journal',
            'POST',
            (_) => '/api/ledger/$id/reverse',
            fields: const [
              FieldSpec('date', 'Reversal date', type: FieldType.date),
              FieldSpec('reason', 'Reason', required: true),
            ],
          ),
        ];
      }
      return const [];
    case 'bookings':
      return [
        if (row['paymentStatus'] != 'Paid')
          RecordAction(
            'Record payment',
            'POST',
            (_) => '/api/bookings/$id/pay',
            special: 'pay',
          ),
        if (row['status'] != 'Ticketed')
          RecordAction(
            'Issue ticket',
            'POST',
            (_) => '/api/bookings/$id/ticket',
          ),
        if (row['status'] == 'Ticketed')
          RecordAction(
            'Request refund',
            'POST',
            (_) => '/api/refunds',
            fields: const [
              FieldSpec(
                'amount',
                'Refund amount',
                type: FieldType.number,
                required: true,
              ),
              FieldSpec(
                'penalty',
                'Penalty',
                type: FieldType.number,
                initial: 0,
              ),
              FieldSpec('reason', 'Reason', required: true),
            ],
            formModule: 'refunds',
            body: {'bookingId': id, 'amount': row['total']},
          ),
      ];
    case 'refunds':
      return [
        RecordAction(
          'Update status',
          'PATCH',
          (_) => '/api/refunds/$id',
          fields: const [
            FieldSpec(
              'status',
              'Status',
              type: FieldType.choice,
              choices: [
                'Requested',
                'Under review',
                'Submitted to supplier',
                'Approved',
                'Rejected',
                'Awaiting airline payment',
                'Paid to agency',
                'Paid to customer',
              ],
            ),
          ],
          body: {'status': row['status']},
        ),
      ];
    case 'cases':
      return [
        RecordAction(
          'Update case',
          'PATCH',
          (_) => '/api/cases/$id',
          fields: const [
            FieldSpec(
              'status',
              'Status',
              type: FieldType.choice,
              choices: ['Open', 'In progress', 'Resolved'],
            ),
            FieldSpec('assignee', 'Assignee'),
          ],
          formModule: 'cases',
          body: row,
        ),
      ];
    case 'passports':
      return [
        RecordAction(
          'Update service / collection',
          'PATCH',
          (_) => '/api/passports/$id',
          fields: passportCollectionFields,
          formModule: 'passport_collection',
          body: row,
        ),
      ];
    case 'users':
      return [
        RecordAction(
          'Module permissions',
          'PATCH',
          (_) => '/api/users/$id',
          special: 'permissions',
        ),
        RecordAction(
          'Active sessions',
          'GET',
          (_) => '/api/users/$id/sessions',
          special: 'view',
        ),
        RecordAction(
          'Reset password',
          'POST',
          (_) => '/api/users/$id/reset-password',
          fields: const [
            FieldSpec(
              'password',
              'New password',
              required: true,
              type: FieldType.password,
            ),
            FieldSpec(
              'confirmPassword',
              'Confirm password',
              required: true,
              type: FieldType.password,
            ),
          ],
        ),
        RecordAction(
          'Sign out devices',
          'POST',
          (_) => '/api/users/$id/signout',
        ),
        RecordAction(
          'Archive employee',
          'POST',
          (_) => '/api/users/$id/archive',
        ),
      ];
  }
  return const [];
}

class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    required this.api,
    required this.products,
    required this.onUpdated,
    required this.message,
  });
  final ApiClient api;
  final List<Map<String, dynamic>> products;
  final VoidCallback onUpdated;
  final void Function(String) message;
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final Map<String, int> cart = {};
  String search = '';
  String? scanFeedback;
  bool scanSucceeded = false;
  double defaultTaxRate = 5;
  String discountType = 'amount';
  String taxChoice = 'default';
  bool roundToWhole = true;
  final discountInput = TextEditingController(text: '0');
  final customTaxInput = TextEditingController(text: '5');
  final scanInput = TextEditingController();
  final scanFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/grocery/bootstrap').then((value) {
      if (mounted) {
        setState(
          () =>
              defaultTaxRate =
                  (asMap(asMap(value)['settings'])['taxRate'] as num?)
                      ?.toDouble() ??
                  5,
        );
      }
    });
  }

  @override
  void dispose() {
    discountInput.dispose();
    customTaxInput.dispose();
    scanInput.dispose();
    scanFocus.dispose();
    super.dispose();
  }

  void focusScanner() {
    if (mounted) scanFocus.requestFocus();
  }

  void addProduct(Map<String, dynamic> product) {
    final id = product['id']?.toString() ?? '';
    final stock = (product['stock'] as num?)?.toDouble() ?? 0;
    final nextQuantity = (cart[id] ?? 0) + 1;
    if (id.isEmpty || nextQuantity > stock) {
      setState(() {
        scanFeedback =
            '${displayValue(product['name'])} is out of stock or already fully in this sale.';
        scanSucceeded = false;
      });
      return;
    }
    setState(() {
      cart[id] = nextQuantity;
      scanFeedback =
          '${displayValue(product['name'])} added · $nextQuantity in sale';
      scanSucceeded = true;
    });
    if (MediaQuery.sizeOf(context).width >= 600) {
      WidgetsBinding.instance.addPostFrameCallback((_) => focusScanner());
    }
  }

  void scanBarcode(String raw) {
    final code = raw.trim();
    scanInput.clear();
    if (code.isEmpty) {
      focusScanner();
      return;
    }
    final matches =
        widget.products
            .where(
              (product) =>
                  product['barcode']?.toString().trim() == code &&
                  product['status'] != 'Inactive' &&
                  product['status'] != 'Discontinued',
            )
            .toList();
    if (matches.length == 1) {
      addProduct(matches.single);
    } else {
      setState(() {
        scanFeedback =
            matches.isEmpty
                ? 'Barcode $code not found. Check the product barcode in inventory.'
                : 'Barcode $code belongs to multiple products. Fix it in inventory before selling.';
        scanSucceeded = false;
      });
    }
    focusScanner();
  }

  void showScannerHelp() {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Connect a barcode scanner'),
            content: const Text(
              '1. Connect a USB scanner, or pair a Bluetooth scanner with this device.\n\n'
              '2. Set the scanner to USB/Bluetooth HID keyboard mode and add an Enter (Return) suffix using its setup guide.\n\n'
              '3. Give each product a unique barcode in Products & inventory. Keep leading zeros.\n\n'
              '4. Tap Scan barcode, then scan. A matching in-stock product is added immediately. You can also type a barcode and press Enter.\n\n'
              'If scanning types into another field, tap Scan barcode again before scanning. Serial-only scanners need keyboard/HID mode.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
    ).then((_) => focusScanner());
  }

  double get subtotal => widget.products.fold(
    0,
    (sum, product) =>
        sum +
        ((product['price'] as num?)?.toDouble() ?? 0) *
            (cart[product['id']] ?? 0),
  );
  double get chosenTaxRate => switch (taxChoice) {
    'none' => 0,
    'five' => 5,
    'thirteen' => 13,
    'custom' => double.tryParse(customTaxInput.text.trim()) ?? double.nan,
    _ => defaultTaxRate,
  };

  PosPricing get pricing => calculatePosPricing(
    subtotal: subtotal,
    discountType: discountType,
    discountValue: double.tryParse(discountInput.text.trim()) ?? double.nan,
    taxRate: chosenTaxRate,
    roundToWhole: roundToWhole,
  );

  void clearSale() => setState(() {
    cart.clear();
    scanFeedback = null;
    discountType = 'amount';
    discountInput.text = '0';
    taxChoice = 'default';
  });

  Future<void> checkout() async {
    if (cart.isEmpty) return;
    late final PosPricing salePricing;
    try {
      salePricing = pricing;
      if (salePricing.total <= 0) {
        throw const FormatException('Total must be greater than zero');
      }
    } on FormatException catch (error) {
      widget.message(error.message);
      return;
    }
    final payment = await showConfiguredSplitPayment(
      context,
      api: widget.api,
      max: salePricing.total,
      exact: true,
    );
    if (payment == null) return;
    try {
      final result = asMap(
        await widget.api.post('/api/grocery/sales', {
          'items':
              widget.products
                  .where((product) => cart.containsKey(product['id']))
                  .map(
                    (product) => {
                      'id': product['id'],
                      'name': product['name'],
                      'qty': cart[product['id']],
                      'price': product['price'],
                    },
                  )
                  .toList(),
          'payments': payment['payments'],
          'discountType': discountType,
          'discountValue': double.parse(discountInput.text.trim()),
          'taxRate': salePricing.taxRate,
          'roundToWhole': roundToWhole,
        }),
      );
      if (!mounted) return;
      clearSale();
      widget.message('Sale ${result['receipt']} completed');
      widget.onUpdated();
      if (MediaQuery.sizeOf(context).width >= 600) {
        WidgetsBinding.instance.addPostFrameCallback((_) => focusScanner());
      }
    } catch (error) {
      widget.message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    PosPricing? salePricing;
    String? pricingError;
    try {
      salePricing = pricing;
    } on FormatException catch (error) {
      pricingError = error.message;
    }
    InputDecoration compactInput(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: const OutlineInputBorder(),
    );
    Widget summaryRow(
      String label,
      String amount, {
      bool strong = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style:
                  strong ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          Text(
            amount,
            style: strong ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ],
      ),
    );
    final available =
        widget.products
            .where(
              (product) =>
                  product['status'] != 'Inactive' &&
                  product['status'] != 'Discontinued' &&
                  ((product['stock'] as num?)?.toDouble() ?? 0) > 0 &&
                  '${product['name']} ${product['barcode']} ${product['sku']}'
                      .toLowerCase()
                      .contains(search.toLowerCase()),
            )
            .toList();
    final wide = MediaQuery.sizeOf(context).width >= 950;
    final productsView = Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('pos-scan-barcode'),
                controller: scanInput,
                focusNode: scanFocus,
                autofocus: MediaQuery.sizeOf(context).width >= 600,
                textInputAction: TextInputAction.done,
                onSubmitted: scanBarcode,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.qr_code_scanner),
                  hintText: 'Scan barcode or type one and press Enter',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Barcode scanner setup',
              onPressed: showScannerHelp,
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
        if (scanFeedback != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                scanFeedback!,
                key: const ValueKey('pos-scan-feedback'),
                style: TextStyle(
                  color:
                      scanSucceeded
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          onChanged: (value) => setState(() => search = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search name, SKU or barcode',
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final maxTileWidth = wide ? 250.0 : 210.0;
              final columns = ((constraints.maxWidth + spacing) /
                      (maxTileWidth + spacing))
                  .ceil()
                  .clamp(1, 20);
              final rows = (available.length + columns - 1) ~/ columns;
              final tileHeight =
                  rows == 0
                      ? 145.0
                      : ((constraints.maxHeight - (rows - 1) * spacing) / rows)
                          .clamp(145.0, 260.0)
                          .toDouble();
              if (available.isEmpty) {
                return Center(
                  child: Text(
                    search.isEmpty
                        ? 'No in-stock products to sell. Add or restock products in inventory.'
                        : 'No products match your search.',
                  ),
                );
              }
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxTileWidth,
                  mainAxisExtent: tileHeight,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                ),
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final product = available[index],
                      stock = (product['stock'] as num?)?.toDouble() ?? 0;
                  return Card(
                    child: InkWell(
                      onTap:
                          stock > (cart[product['id'].toString()] ?? 0)
                              ? () => addProduct(product)
                              : null,
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.shopping_basket_outlined),
                            const Spacer(),
                            Text(
                              displayValue(product['name']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              stock <= 0
                                  ? '${product['price']} · Out of stock'
                                  : '${product['price']} · ${product['stock']} in stock',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
    final cartView = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Current sale',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (cart.isNotEmpty)
                  TextButton(onPressed: clearSale, child: const Text('Clear')),
              ],
            ),
            if (cart.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 46,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No items in this sale',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Scan a barcode or tap a product to begin.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: focusScanner,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Ready to scan'),
                      ),
                    ],
                  ),
                ),
              ),
            if (cart.isNotEmpty) ...[
              Expanded(
                child: ListView(
                  children:
                      widget.products
                          .where((product) => cart.containsKey(product['id']))
                          .map((product) {
                            final id = product['id'].toString(),
                                quantity = cart[id] ?? 0;
                            return ListTile(
                              title: Text(displayValue(product['name'])),
                              subtitle: Text('${product['price']} × $quantity'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed:
                                        () => setState(() {
                                          if (quantity <= 1) {
                                            cart.remove(id);
                                          } else {
                                            cart[id] = quantity - 1;
                                          }
                                        }),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text('$quantity'),
                                  IconButton(
                                    onPressed:
                                        quantity <
                                                ((product['stock'] as num?) ??
                                                    0)
                                            ? () => setState(
                                              () => cart[id] = quantity + 1,
                                            )
                                            : null,
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            );
                          })
                          .toList(),
                ),
              ),
              const Divider(),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: wide ? 240 : 180),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      summaryRow('Subtotal', subtotal.toStringAsFixed(2)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: const ValueKey('pos-discount-type'),
                              value: discountType,
                              isExpanded: true,
                              decoration: compactInput('Discount'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'amount',
                                  child: Text('Amount'),
                                ),
                                DropdownMenuItem(
                                  value: 'percent',
                                  child: Text('Percent'),
                                ),
                              ],
                              onChanged:
                                  (value) => setState(
                                    () => discountType = value ?? 'amount',
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('pos-discount-value'),
                              controller: discountInput,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: compactInput(
                                discountType == 'percent'
                                    ? 'Discount %'
                                    : 'Discount amount',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      summaryRow(
                        'Discount applied',
                        salePricing?.discount.toStringAsFixed(2) ?? '—',
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: const ValueKey('pos-tax-choice'),
                              value: taxChoice,
                              isExpanded: true,
                              decoration: compactInput('Tax'),
                              items: [
                                DropdownMenuItem(
                                  value: 'default',
                                  child: Text(
                                    'Store default (${defaultTaxRate.toStringAsFixed(2)}%)',
                                  ),
                                ),
                                const DropdownMenuItem(
                                  value: 'none',
                                  child: Text('No tax (0%)'),
                                ),
                                const DropdownMenuItem(
                                  value: 'five',
                                  child: Text('5%'),
                                ),
                                const DropdownMenuItem(
                                  value: 'thirteen',
                                  child: Text('13%'),
                                ),
                                const DropdownMenuItem(
                                  value: 'custom',
                                  child: Text('Custom rate'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == 'custom' &&
                                    taxChoice != 'custom') {
                                  customTaxInput.text =
                                      chosenTaxRate.toString();
                                }
                                setState(() => taxChoice = value ?? 'default');
                              },
                            ),
                          ),
                          if (taxChoice == 'custom') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                key: const ValueKey('pos-custom-tax-rate'),
                                controller: customTaxInput,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: compactInput('Rate %'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ],
                      ),
                      summaryRow(
                        'Tax (${chosenTaxRate.isFinite ? chosenTaxRate.toStringAsFixed(2) : '—'}%)',
                        salePricing?.tax.toStringAsFixed(2) ?? '—',
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Round-off to whole rupee')),
                  Switch.adaptive(
                    key: const ValueKey('pos-round-to-whole'),
                    value: roundToWhole,
                    onChanged: (value) => setState(() => roundToWhole = value),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    salePricing == null
                        ? '—'
                        : '${salePricing.roundingAdjustment > 0 ? '+' : ''}${salePricing.roundingAdjustment.toStringAsFixed(2)}',
                    key: const ValueKey('pos-rounding-adjustment'),
                  ),
                ],
              ),
              summaryRow(
                'Total',
                salePricing?.total.toStringAsFixed(2) ?? '—',
                strong: true,
              ),
              if (cart.isNotEmpty &&
                  (pricingError != null || (salePricing?.total ?? 0) <= 0))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    pricingError ?? 'Total must be greater than zero',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      cart.isEmpty ||
                              salePricing == null ||
                              salePricing.total <= 0
                          ? null
                          : checkout,
                  child: const Text('Choose payment & complete'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 3, child: productsView),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: cartView),
              ],
            );
          }
          if (constraints.maxHeight < 700) {
            return ListView(
              children: [
                SizedBox(height: 330, child: productsView),
                const SizedBox(height: 12),
                SizedBox(height: 450, child: cartView),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 3, child: productsView),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 450),
                child: cartView,
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<Map<String, dynamic>?> showPurchaseForm(
  BuildContext context,
  ApiClient api, {
  bool canManageFields = false,
}) async {
  final suppliers = asRows(await api.get('/api/grocery/suppliers'));
  final products = asRows(await api.get('/api/grocery/products'));
  final fields = await loadRecordFields(api, 'grocery_purchases');
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder:
        (_) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 850),
            child: _PurchaseForm(
              suppliers: suppliers,
              products: products,
              fields: fields,
              api: api,
              canManageFields: canManageFields,
            ),
          ),
        ),
  );
}

class _PurchaseLine {
  String? productId;
  final quantity = TextEditingController(text: '1');
  final unitCost = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0');
  final taxRate = TextEditingController(text: '0');
  final batch = TextEditingController();
  final expiry = TextEditingController();
  void dispose() {
    quantity.dispose();
    unitCost.dispose();
    discount.dispose();
    taxRate.dispose();
    batch.dispose();
    expiry.dispose();
  }
}

class _PurchaseForm extends StatefulWidget {
  const _PurchaseForm({
    required this.suppliers,
    required this.products,
    required this.fields,
    required this.api,
    required this.canManageFields,
  });
  final List<Map<String, dynamic>> suppliers, products;
  final List<FieldSpec> fields;
  final ApiClient api;
  final bool canManageFields;
  @override
  State<_PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<_PurchaseForm> {
  late List<FieldSpec> headerFields = widget.fields;
  final Map<String, TextEditingController> extraControllers = {};
  final Map<String, String> extraChoices = {};
  final po = TextEditingController(), invoice = TextEditingController();
  final shipping = TextEditingController(text: '0'),
      otherCosts = TextEditingController(text: '0');
  final expected = TextEditingController(),
      due = TextEditingController(),
      notes = TextEditingController();
  final lines = <_PurchaseLine>[_PurchaseLine()];
  String? supplierId;
  String status = 'Ordered';

  bool hasHeader(String key) => headerFields.any((field) => field.key == key);

  @override
  void initState() {
    super.initState();
    _syncExtraFields();
  }

  void _syncExtraFields() {
    final active = headerFields.where(
      (field) => field.key.startsWith('custom_'),
    );
    final keys = active.map((field) => field.key).toSet();
    for (final key in extraControllers.keys.toList()) {
      if (!keys.contains(key)) extraControllers.remove(key)?.dispose();
    }
    extraChoices.removeWhere((key, _) => !keys.contains(key));
    for (final spec in active) {
      if (spec.type == FieldType.choice) {
        extraChoices.putIfAbsent(
          spec.key,
          () => spec.choices.firstOrNull ?? '',
        );
      } else {
        extraControllers.putIfAbsent(spec.key, TextEditingController.new);
      }
    }
  }

  Future<void> _manageHeaders() async {
    final changed = await showRecordFieldsManager(
      context,
      widget.api,
      'grocery_purchases',
    );
    if (!changed || !mounted) return;
    final updated = await loadRecordFields(widget.api, 'grocery_purchases');
    if (!mounted) return;
    setState(() {
      headerFields = updated;
      _syncExtraFields();
    });
  }

  @override
  void dispose() {
    po.dispose();
    invoice.dispose();
    shipping.dispose();
    otherCosts.dispose();
    expected.dispose();
    due.dispose();
    notes.dispose();
    for (final line in lines) {
      line.dispose();
    }
    for (final controller in extraControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get total {
    var value =
        hasHeader('shipping') ? double.tryParse(shipping.text) ?? 0 : 0.0;
    value +=
        hasHeader('otherCosts') ? double.tryParse(otherCosts.text) ?? 0 : 0.0;
    for (final line in lines) {
      final sub =
          (double.tryParse(line.quantity.text) ?? 0) *
          (double.tryParse(line.unitCost.text) ?? 0);
      final afterDiscount = sub - (double.tryParse(line.discount.text) ?? 0);
      value +=
          afterDiscount * (1 + (double.tryParse(line.taxRate.text) ?? 0) / 100);
    }
    return value;
  }

  void submit() {
    if (supplierId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a supplier')));
      return;
    }
    if (lines.any(
      (line) =>
          line.productId == null ||
          (double.tryParse(line.quantity.text) ?? 0) <= 0,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a product and quantity for every line'),
        ),
      );
      return;
    }
    for (final field in headerFields) {
      if (!field.required || !field.key.startsWith('custom_')) continue;
      final value =
          field.type == FieldType.choice
              ? extraChoices[field.key] ?? ''
              : extraControllers[field.key]?.text.trim() ?? '';
      if (value.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${field.label} is required')));
        return;
      }
    }
    final payload = <String, dynamic>{
      'supplierId': supplierId,
      'poNumber': po.text.trim(),
      'supplierInvoice': invoice.text.trim(),
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'expectedDate': expected.text.trim(),
      'dueDate': due.text.trim(),
      'shipping': double.tryParse(shipping.text) ?? 0,
      'otherCosts': double.tryParse(otherCosts.text) ?? 0,
      'status': status,
      'notes': notes.text.trim(),
      'items':
          lines
              .map(
                (line) => {
                  'productId': line.productId,
                  'quantity': double.tryParse(line.quantity.text) ?? 0,
                  'unitCost': double.tryParse(line.unitCost.text) ?? 0,
                  'discount': double.tryParse(line.discount.text) ?? 0,
                  'taxRate': double.tryParse(line.taxRate.text) ?? 0,
                  'batchNumber': line.batch.text.trim(),
                  'expiry': line.expiry.text.trim(),
                },
              )
              .toList(),
    };
    final activeKeys = headerFields.map((field) => field.key).toSet();
    for (final field in purchaseHeaderFields) {
      if (!activeKeys.contains(field.key)) payload.remove(field.key);
    }
    for (final field in headerFields.where(
      (field) => field.key.startsWith('custom_'),
    )) {
      final value =
          field.type == FieldType.choice
              ? extraChoices[field.key] ?? ''
              : extraControllers[field.key]?.text.trim() ?? '';
      payload[field.key] =
          field.type == FieldType.number ? num.tryParse(value) ?? 0 : value;
    }
    Navigator.pop(context, payload);
  }

  Widget headerField(FieldSpec spec) {
    if (spec.key == 'supplierId') {
      return DropdownButtonFormField<String>(
        value: supplierId,
        decoration: InputDecoration(labelText: spec.label),
        items:
            widget.suppliers
                .where((supplier) => supplier['archived'] != true)
                .map(
                  (supplier) => DropdownMenuItem(
                    value: supplier['id'].toString(),
                    child: Text(displayValue(supplier['name'])),
                  ),
                )
                .toList(),
        onChanged: (value) => setState(() => supplierId = value),
      );
    }
    if (spec.key == 'status') {
      return DropdownButtonFormField<String>(
        value: status,
        decoration: InputDecoration(labelText: spec.label),
        items:
            ['Draft', 'Ordered']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
        onChanged: (value) => setState(() => status = value ?? 'Ordered'),
      );
    }
    final builtIn = <String, TextEditingController>{
      'poNumber': po,
      'supplierInvoice': invoice,
      'expectedDate': expected,
      'dueDate': due,
      'shipping': shipping,
      'otherCosts': otherCosts,
      'notes': notes,
    };
    final controller = builtIn[spec.key] ?? extraControllers[spec.key];
    if (controller == null && spec.type == FieldType.choice) {
      return DropdownButtonFormField<String>(
        value: extraChoices[spec.key],
        decoration: InputDecoration(labelText: spec.label),
        items:
            spec.choices
                .map(
                  (choice) =>
                      DropdownMenuItem(value: choice, child: Text(choice)),
                )
                .toList(),
        onChanged:
            (value) => setState(() => extraChoices[spec.key] = value ?? ''),
      );
    }
    if (controller == null) return const SizedBox.shrink();
    return field(controller, spec.label, number: spec.type == FieldType.number);
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    keyboardType:
        number ? const TextInputType.numberWithOptions(decimal: true) : null,
    onChanged: (_) => setState(() {}),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'New purchase order',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (widget.canManageFields)
              IconButton(
                tooltip: 'Manage form fields',
                onPressed: _manageHeaders,
                icon: const Icon(Icons.tune),
              ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final spec in headerFields)
                    SizedBox(
                      width: spec.type == FieldType.paragraph ? 500 : 220,
                      child: headerField(spec),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Products', style: Theme.of(context).textTheme.titleLarge),
              ...lines.map(
                (line) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: line.productId,
                                decoration: const InputDecoration(
                                  labelText: 'Product',
                                ),
                                items:
                                    widget.products
                                        .map(
                                          (product) => DropdownMenuItem(
                                            value: product['id'].toString(),
                                            child: Text(
                                              displayValue(product['name']),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged:
                                    (value) => setState(() {
                                      line.productId = value;
                                      final product = widget.products
                                          .firstWhere(
                                            (product) => product['id'] == value,
                                          );
                                      line.unitCost.text = displayValue(
                                        product['cost'],
                                      );
                                      line.taxRate.text = displayValue(
                                        product['taxRate'] ?? 0,
                                      );
                                    }),
                              ),
                            ),
                            IconButton(
                              onPressed:
                                  lines.length == 1
                                      ? null
                                      : () => setState(() {
                                        lines.remove(line);
                                        line.dispose();
                                      }),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: 130,
                              child: field(
                                line.quantity,
                                'Quantity',
                                number: true,
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: field(
                                line.unitCost,
                                'Unit cost',
                                number: true,
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: field(
                                line.discount,
                                'Discount',
                                number: true,
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: field(line.taxRate, 'Tax %', number: true),
                            ),
                            SizedBox(
                              width: 150,
                              child: field(line.batch, 'Batch'),
                            ),
                            SizedBox(
                              width: 180,
                              child: field(line.expiry, 'Expiry YYYY-MM-DD'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => lines.add(_PurchaseLine())),
                icon: const Icon(Icons.add),
                label: const Text('Add product line'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Total ${total.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            FilledButton(
              onPressed: submit,
              child: const Text('Create purchase order'),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<Map<String, dynamic>?> showReceiveForm(
  BuildContext context,
  Map<String, dynamic> purchase,
) async {
  final items = asRows(purchase['items']);
  final fields = <FieldSpec>[];
  for (var i = 0; i < items.length; i++) {
    fields.add(
      FieldSpec(
        'receive_$i',
        'Receive ${items[i]['productName']} (ordered ${items[i]['orderedQty']})',
        type: FieldType.number,
        initial: 0,
      ),
    );
    fields.add(
      FieldSpec(
        'reject_$i',
        'Reject ${items[i]['productName']}',
        type: FieldType.number,
        initial: 0,
      ),
    );
    fields.add(
      FieldSpec(
        'batch_$i',
        'Batch ${items[i]['productName']}',
        initial: items[i]['batchNumber'],
      ),
    );
    fields.add(
      FieldSpec(
        'expiry_$i',
        'Expiry ${items[i]['productName']}',
        type: FieldType.date,
        initial: items[i]['expiry'],
      ),
    );
  }
  final result = await showRecordForm(context, 'Receive goods', fields);
  if (result == null) return null;
  return {
    'items': [
      for (var i = 0; i < items.length; i++)
        {
          'itemId': items[i]['id'],
          'quantity': result['receive_$i'],
          'rejected': result['reject_$i'],
          'batchNumber': result['batch_$i'],
          'expiry': result['expiry_$i'],
        },
    ],
  };
}

Future<Map<String, dynamic>?> showReturnForm(
  BuildContext context,
  Map<String, dynamic> purchase,
) async {
  final items =
      asRows(purchase['items'])
          .where(
            (item) => (item['receivedQty'] ?? 0) > (item['returnedQty'] ?? 0),
          )
          .toList();
  if (items.isEmpty) return null;
  return showRecordForm(context, 'Return goods', [
    FieldSpec(
      'itemId',
      'Product',
      type: FieldType.choice,
      choices: items.map((item) => item['id'].toString()).toList(),
      initial: items.first['id'],
    ),
    const FieldSpec(
      'quantity',
      'Quantity',
      type: FieldType.number,
      required: true,
    ),
    const FieldSpec('reason', 'Reason', required: true),
  ]);
}

Future<Map<String, dynamic>?> showRoleForm(
  BuildContext context, {
  Map<String, dynamic>? row,
}) async {
  final name = TextEditingController(text: row?['name']?.toString() ?? '');
  final permissions = <String, bool>{
    for (final module in permissionModules)
      module: asMap(row?['permissions'])[module] == true,
  };
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, update) => AlertDialog(
                title: Text(row == null ? 'Create role' : 'Edit role'),
                content: SizedBox(
                  width: 470,
                  height: 540,
                  child: Column(
                    children: [
                      TextField(
                        controller: name,
                        enabled: row?['system'] != true,
                        decoration: const InputDecoration(
                          labelText: 'Role name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Module permissions'),
                      Expanded(
                        child: ListView(
                          children:
                              permissionModules
                                  .map(
                                    (module) => SwitchListTile(
                                      title: Text(module),
                                      value: permissions[module] ?? false,
                                      onChanged:
                                          (value) => update(
                                            () => permissions[module] = value,
                                          ),
                                    ),
                                  )
                                  .toList(),
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
                    onPressed: () {
                      if (name.text.trim().isEmpty) return;
                      Navigator.pop(context, {
                        'name': name.text.trim(),
                        'permissions': permissions,
                      });
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
        ),
  );
  name.dispose();
  return result;
}
