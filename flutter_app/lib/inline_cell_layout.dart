import 'dart:math' as math;

import 'package:flutter/material.dart';

const inlineCellMaxLines = 6;

int inlineCellLineCount(
  String value, {
  required double width,
  required TextStyle style,
  required TextDirection direction,
}) {
  final painter = TextPainter(
    text: TextSpan(text: value.isEmpty ? ' ' : value, style: style),
    textDirection: direction,
    maxLines: inlineCellMaxLines,
  )..layout(maxWidth: math.max(1, width));
  final lines = math.max(
    value.split('\n').length,
    painter.computeLineMetrics().length,
  );
  painter.dispose();
  return lines.clamp(1, inlineCellMaxLines);
}

double inlineCellRowHeight(int lines, {double minimum = 52}) =>
    lines <= 1 ? minimum : math.max(minimum, 36.0 + 22.0 * lines);
