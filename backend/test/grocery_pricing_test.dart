import 'package:aerodesk_backend/grocery_pricing.dart';
import 'package:test/test.dart';

void main() {
  test('fixed discount is applied before manually chosen tax', () {
    final result = calculateGrocerySaleTotals(
      subtotal: 100,
      discountType: 'amount',
      discountValue: 25,
      taxRate: 13,
    );
    expect(result.discount, 25);
    expect(result.taxableSubtotal, 75);
    expect(result.tax, 9.75);
    expect(result.total, 84.75);
  });

  test('percentage discount and no tax use cent rounding', () {
    final result = calculateGrocerySaleTotals(
      subtotal: 19.99,
      discountType: 'percent',
      discountValue: 10,
      taxRate: 0,
    );
    expect(result.discount, 2);
    expect(result.total, 17.99);
  });

  test('whole-rupee round-off is explicit and reports its adjustment', () {
    final down = calculateGrocerySaleTotals(
      subtotal: 16.32,
      discountType: 'amount',
      discountValue: 0,
      taxRate: 0,
      roundToWhole: true,
    );
    expect(down.beforeRounding, 16.32);
    expect(down.roundingAdjustment, -0.32);
    expect(down.total, 16);

    final up = calculateGrocerySaleTotals(
      subtotal: 16.50,
      discountType: 'amount',
      discountValue: 0,
      taxRate: 0,
      roundToWhole: true,
    );
    expect(up.roundingAdjustment, 0.50);
    expect(up.total, 17);
  });

  test('invalid discounts and tax rates are rejected', () {
    expect(
        () => calculateGrocerySaleTotals(
              subtotal: 10,
              discountType: 'amount',
              discountValue: 11,
              taxRate: 5,
            ),
        throwsFormatException);
    expect(
        () => calculateGrocerySaleTotals(
              subtotal: 10,
              discountType: 'percent',
              discountValue: 101,
              taxRate: 5,
            ),
        throwsFormatException);
    expect(
        () => calculateGrocerySaleTotals(
              subtotal: 10,
              discountType: 'amount',
              discountValue: 0,
              taxRate: -1,
            ),
        throwsFormatException);
  });
}
