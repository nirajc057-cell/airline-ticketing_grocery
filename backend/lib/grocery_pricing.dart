class GrocerySaleTotals {
  const GrocerySaleTotals({
    required this.subtotal,
    required this.discountType,
    required this.discountValue,
    required this.discount,
    required this.taxableSubtotal,
    required this.taxRate,
    required this.tax,
    required this.beforeRounding,
    required this.roundingAdjustment,
    required this.total,
  });

  final double subtotal;
  final String discountType;
  final double discountValue;
  final double discount;
  final double taxableSubtotal;
  final double taxRate;
  final double tax;
  final double beforeRounding;
  final double roundingAdjustment;
  final double total;
}

double _money(double value) => (value * 100).round() / 100;

GrocerySaleTotals calculateGrocerySaleTotals({
  required double subtotal,
  required String discountType,
  required double discountValue,
  required double taxRate,
  bool roundToWhole = false,
}) {
  if (!subtotal.isFinite ||
      subtotal < 0 ||
      !discountValue.isFinite ||
      discountValue < 0 ||
      !taxRate.isFinite ||
      taxRate < 0 ||
      taxRate > 100 ||
      !{'amount', 'percent'}.contains(discountType) ||
      (discountType == 'percent' && discountValue > 100)) {
    throw const FormatException('Invalid discount or tax rate');
  }
  final gross = _money(subtotal);
  final discount = _money(
      discountType == 'percent' ? gross * discountValue / 100 : discountValue);
  if (discount > gross) {
    throw const FormatException('Discount cannot exceed the subtotal');
  }
  final taxableSubtotal = _money(gross - discount);
  final tax = _money(taxableSubtotal * taxRate / 100);
  final beforeRounding = _money(taxableSubtotal + tax);
  final cents = (beforeRounding * 100).round();
  final roundedCents = roundToWhole ? ((cents + 50) ~/ 100) * 100 : cents;
  return GrocerySaleTotals(
    subtotal: gross,
    discountType: discountType,
    discountValue: discountValue,
    discount: discount,
    taxableSubtotal: taxableSubtotal,
    taxRate: taxRate,
    tax: tax,
    beforeRounding: beforeRounding,
    roundingAdjustment: (roundedCents - cents) / 100,
    total: roundedCents / 100,
  );
}
