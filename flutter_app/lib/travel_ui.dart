import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Visual language for the AeroDesk travel experience. Grocery keeps its own
/// existing green styling and does not use this theme.
abstract final class TravelPalette {
  static const ink = Color(0xff1e2032);
  static const muted = Color(0xff818596);
  static const purple = Color(0xff6246e5);
  static const purpleSoft = Color(0xffefebff);
  static const canvas = Color(0xfff0f1f5);
  static const sidebar = Color(0xfff7f7fa);
  static const border = Color(0xffe6e7ee);
  static const green = Color(0xff25836c);
  static const amber = Color(0xffbd801c);
  static const red = Color(0xffc8555b);
}

ThemeData travelTheme(ThemeData base) => base.copyWith(
  colorScheme: ColorScheme.fromSeed(seedColor: TravelPalette.purple).copyWith(
    primary: TravelPalette.purple,
    secondary: const Color(0xff9b8bff),
    surface: Colors.white,
    onSurface: TravelPalette.ink,
  ),
  scaffoldBackgroundColor: TravelPalette.canvas,
  textTheme: base.textTheme.apply(
    bodyColor: TravelPalette.ink,
    displayColor: TravelPalette.ink,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: TravelPalette.border),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: TravelPalette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: TravelPalette.purple, width: 1.6),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: TravelPalette.purple,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: TravelPalette.ink,
      side: const BorderSide(color: TravelPalette.border),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  dividerTheme: const DividerThemeData(color: TravelPalette.border),
);

class TravelMetricCard extends StatelessWidget {
  const TravelMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.detail,
    this.accent = TravelPalette.purple,
  });

  final String label;
  final String value;
  final IconData icon;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: TravelPalette.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: TravelPalette.ink,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: TravelPalette.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class TravelStatusChip extends StatelessWidget {
  const TravelStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color =
        normalized.contains('ticket') ||
                normalized.contains('complete') ||
                normalized.contains('paid')
            ? TravelPalette.green
            : normalized.contains('cancel') || normalized.contains('reject')
            ? TravelPalette.red
            : normalized.contains('hold') || normalized.contains('pending')
            ? TravelPalette.amber
            : TravelPalette.purple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class TravelActivityChart extends StatelessWidget {
  const TravelActivityChart({super.key, required this.monthlyCounts});
  final List<int> monthlyCounts;
  static const monthLabels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final maximum = monthlyCounts.fold<int>(1, math.max);
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = math.max(32.0, (constraints.maxWidth - 22) / 12);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, barWidth * 12),
            height: 230,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(12, (month) {
                final count =
                    month < monthlyCounts.length ? monthlyCounts[month] : 0;
                final height = 12.0 + count / maximum * 162;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: '${monthLabels[month]}: $count bookings',
                          child: Container(
                            height: height,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color:
                                  count == maximum && count > 0
                                      ? TravelPalette.purple
                                      : const Color(0xffcbbfff),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          monthLabels[month],
                          style: const TextStyle(
                            color: TravelPalette.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

class TravelBookingDonut extends StatelessWidget {
  const TravelBookingDonut({
    super.key,
    required this.ticketed,
    required this.confirmed,
    required this.other,
  });
  final int ticketed;
  final int confirmed;
  final int other;

  @override
  Widget build(BuildContext context) {
    final total = ticketed + confirmed + other;
    final percent = total == 0 ? 0 : (ticketed / total * 100).round();
    return Column(
      children: [
        SizedBox(
          width: 185,
          height: 185,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(185),
                painter: _BookingDonutPainter(ticketed, confirmed, other),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: TravelPalette.ink,
                    ),
                  ),
                  const Text(
                    'Ticketed',
                    style: TextStyle(color: TravelPalette.muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 7,
          children: [
            _legend('Ticketed', TravelPalette.purple),
            _legend('Confirmed', const Color(0xffaa98ff)),
            _legend('Other', const Color(0xffdedfe5)),
          ],
        ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(radius: 5, backgroundColor: color),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: TravelPalette.muted),
      ),
    ],
  );
}

class _BookingDonutPainter extends CustomPainter {
  _BookingDonutPainter(this.ticketed, this.confirmed, this.other);
  final int ticketed;
  final int confirmed;
  final int other;

  @override
  void paint(Canvas canvas, Size size) {
    final total = ticketed + confirmed + other;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - 13);
    final base =
        Paint()
          ..color = const Color(0xffdedfe5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 19;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (final section in [
      (ticketed, TravelPalette.purple),
      (confirmed, const Color(0xffaa98ff)),
    ]) {
      if (section.$1 == 0) continue;
      final sweep = math.pi * 2 * section.$1 / total;
      final paint =
          Paint()
            ..color = section.$2
            ..style = PaintingStyle.stroke
            ..strokeWidth = 19
            ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _BookingDonutPainter oldDelegate) =>
      ticketed != oldDelegate.ticketed ||
      confirmed != oldDelegate.confirmed ||
      other != oldDelegate.other;
}
