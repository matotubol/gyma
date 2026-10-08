import 'dart:math';

import 'package:flutter/material.dart';

import 'format.dart';

/// Minimal line chart: evenly spaced points, three grid lines, soft fill.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _LineChartPainter(
        values: values,
        color: color,
        gridColor: theme.colorScheme.outlineVariant,
        dotFill: theme.colorScheme.surface,
        labelStyle: (theme.textTheme.labelSmall ?? const TextStyle())
            .copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.dotFill,
    required this.labelStyle,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;
  final Color dotFill;
  final TextStyle labelStyle;

  static const _left = 44.0;
  static const _top = 8.0;
  static const _bottom = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    var lo = values.reduce(min);
    var hi = values.reduce(max);
    if (hi == lo) {
      lo = max(0.0, lo - 5);
      hi = hi + 5;
    } else {
      final pad = (hi - lo) * 0.15;
      lo = max(0.0, lo - pad);
      hi += pad;
    }

    final w = size.width - _left - 8;
    final h = size.height - _top - _bottom;
    double y(double v) => _top + h * (1 - (v - lo) / (hi - lo));
    double x(int i) =>
        values.length == 1 ? _left + w / 2 : _left + w * i / (values.length - 1);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final v = lo + (hi - lo) * g / 3;
      final gy = y(v);
      canvas.drawLine(Offset(_left, gy), Offset(size.width, gy), grid);
      final tp = TextPainter(
        text: TextSpan(text: fmtKg(v.roundToDouble()), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_left - tp.width - 8, gy - tp.height / 2));
    }

    final points = [
      for (var i = 0; i < values.length; i++) Offset(x(i), y(values[i]))
    ];

    if (points.length > 1) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }
      final area = Path.from(line)
        ..lineTo(points.last.dx, _top + h)
        ..lineTo(points.first.dx, _top + h)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, _top, size.width, h)),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    final dot = Paint()..color = color;
    final hole = Paint()..color = dotFill;
    for (final p in points) {
      canvas.drawCircle(p, 5, dot);
      canvas.drawCircle(p, 2.2, hole);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values || old.color != color || old.gridColor != gridColor;
}
