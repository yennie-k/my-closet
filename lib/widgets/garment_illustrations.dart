import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../models/garment_options.dart';

/// Original schematic patterns. These are not photos or physical simulations.
class FabricPatternPainter extends CustomPainter {
  const FabricPatternPainter(this.pattern, this.color);
  final int pattern;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
    );
    canvas.drawColor(color.withValues(alpha: 0.08), BlendMode.srcOver);
    final pen = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    switch (pattern) {
      case 0:
        for (double n = 2; n < size.width + size.height; n += 6) {
          canvas.drawLine(Offset(n, 0), Offset(n, size.height), pen);
          canvas.drawLine(Offset(0, n), Offset(size.width, n), pen);
        }
      case 1:
        pen.strokeWidth = 2;
        for (double n = -size.height; n < size.width; n += 6) {
          canvas.drawLine(
            Offset(n, size.height),
            Offset(n + size.height, 0),
            pen,
          );
        }
      case 2:
        for (double y = 5; y < size.height; y += 10) {
          final path = Path()
            ..moveTo(0, y)
            ..cubicTo(
              size.width / 3,
              y - 6,
              size.width * 2 / 3,
              y + 6,
              size.width,
              y,
            );
          canvas.drawPath(path, pen);
        }
      case 3:
        for (double y = 3; y < size.height; y += 7) {
          for (double x = 3; x < size.width; x += 7) {
            canvas.drawArc(
              Rect.fromLTWH(x, y, 5, 5),
              0,
              math.pi * 1.6,
              false,
              pen,
            );
          }
        }
      case 4:
        for (double y = 4; y < size.height; y += 10) {
          for (double x = 4; x < size.width; x += 9) {
            canvas.drawOval(Rect.fromLTWH(x, y, 6, 4), pen);
          }
        }
      case 5:
        for (double y = 2; y < size.height; y += 9) {
          for (double x = 4; x < size.width; x += 9) {
            canvas.drawPath(
              Path()
                ..moveTo(x, y)
                ..quadraticBezierTo(x - 5, y + 5, x, y + 8)
                ..quadraticBezierTo(x + 5, y + 5, x, y),
              pen,
            );
          }
        }
      case 6:
        pen.strokeWidth = 3;
        for (double x = 3; x < size.width; x += 7) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
        }
      default:
        for (double y = 0; y < size.height; y += 8) {
          for (double x = 2; x < size.width; x += 6) {
            canvas.drawLine(Offset(x, y), Offset(x + 4, y + 11), pen);
          }
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FabricPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.color != color;
}

/// Original garment outlines; proportions compare fits, not garment length.
class FitSilhouettePainter extends CustomPainter {
  const FitSilhouettePainter(
    this.fit,
    this.category,
    this.color, {
    this.subtype = '',
  });
  final String fit, subtype;
  final GarmentCategory? category;
  final Color color;

  double get _width => switch (fit) {
    '스키니핏' => 16,
    '슬림핏' => 21,
    '오버핏' => 34,
    '루즈핏' => 30,
    '와이드핏' => 34,
    _ => 26,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final context = fitContextFor(category, subtype);
    if (context == FitContext.optional) return;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 110);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    void draw(Path path) {
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawPath(path, pen);
    }

    switch (context) {
      case FitContext.coat ||
          FitContext.puffer ||
          FitContext.jacket ||
          FitContext.outerwear:
        final coat = context == FitContext.coat;
        final puffer = context == FitContext.puffer;
        final bottom = coat ? 104.0 : 82.0;
        final shoulder = fit == '오버핏' ? 32.0 : 26.0;
        final hem = fit == 'A라인' ? 37.0 : _width;
        final waist = fit == '슬림핏' ? 19.0 : _width;
        final path = Path()
          ..moveTo(40, 9)
          ..lineTo(60, 9)
          ..lineTo(50 + shoulder, 20)
          ..lineTo(96, 73)
          ..lineTo(83, 79)
          ..lineTo(50 + shoulder, 43)
          ..lineTo(50 + waist, 58)
          ..lineTo(50 + hem, bottom)
          ..lineTo(50 - hem, bottom)
          ..lineTo(50 - waist, 58)
          ..lineTo(50 - shoulder, 43)
          ..lineTo(17, 79)
          ..lineTo(4, 73)
          ..lineTo(50 - shoulder, 20)
          ..close();
        draw(path);
        // Lapels and buttons distinguish coats/blazers from a T-shirt.
        final lapels =
            coat ||
            subtype.contains('블레이저') ||
            subtype.contains('재킷') ||
            subtype.contains('자켓');
        if (lapels) {
          canvas.drawPath(
            Path()
              ..moveTo(40, 9)
              ..lineTo(35, 26)
              ..lineTo(45, 36)
              ..lineTo(50, 49)
              ..lineTo(55, 36)
              ..lineTo(65, 26)
              ..lineTo(60, 9),
            pen,
          );
          canvas.drawLine(const Offset(50, 49), Offset(50, bottom), pen);
          for (double y = 57; y < bottom - 6; y += 15) {
            canvas.drawCircle(Offset(55, y), 1.5, pen);
          }
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(40, 5, 20, 13),
              const Radius.circular(4),
            ),
            pen,
          );
          canvas.drawLine(const Offset(50, 18), Offset(50, bottom), pen);
        }
        if (puffer) {
          canvas.save();
          canvas.clipPath(path);
          for (double y = 27; y < bottom; y += 12) {
            canvas.drawLine(Offset(5, y), Offset(95, y), pen);
          }
          canvas.restore();
        } else {
          canvas.drawLine(const Offset(26, 65), const Offset(37, 61), pen);
          canvas.drawLine(const Offset(63, 61), const Offset(74, 65), pen);
        }
        if (coat && subtype.contains('트렌치')) {
          canvas.drawLine(const Offset(27, 58), const Offset(73, 58), pen);
          canvas.drawRect(const Rect.fromLTWH(46, 55, 8, 6), pen);
        }
      case FitContext.pants || FitContext.shorts || FitContext.leggings:
        final bottom = context == FitContext.shorts ? 67.0 : 103.0;
        draw(_pants(bottom));
        canvas.drawLine(const Offset(21, 15), const Offset(79, 15), pen);
        canvas.drawLine(const Offset(50, 15), const Offset(50, 35), pen);
      case FitContext.skirt:
        final hem = fit == 'A라인' ? 44.0 : 29.0;
        draw(
          Path()
            ..moveTo(23, 9)
            ..lineTo(77, 9)
            ..lineTo(50 + hem, 103)
            ..lineTo(50 - hem, 103)
            ..close(),
        );
        canvas.drawLine(const Offset(23, 17), const Offset(77, 17), pen);
      case FitContext.dress:
        final hem = fit == 'A라인'
            ? 44.0
            : fit == 'H라인'
            ? 27.0
            : _width;
        final waist = fit == '슬림핏' || fit == 'A라인' ? 17.0 : _width;
        draw(
          Path()
            ..moveTo(34, 9)
            ..quadraticBezierTo(50, 23, 66, 9)
            ..lineTo(77, 31)
            ..lineTo(66, 39)
            ..lineTo(50 + waist, 45)
            ..lineTo(50 + hem, 103)
            ..lineTo(50 - hem, 103)
            ..lineTo(50 - waist, 45)
            ..lineTo(34, 39)
            ..lineTo(23, 31)
            ..close(),
        );
      case FitContext.jumpsuit:
        final body = _width;
        draw(
          Path()
            ..moveTo(35, 8)
            ..quadraticBezierTo(50, 23, 65, 8)
            ..lineTo(83, 24)
            ..lineTo(73, 36)
            ..lineTo(50 + body, 32)
            ..lineTo(50 + body, 103)
            ..lineTo(55, 103)
            ..lineTo(50, 62)
            ..lineTo(45, 103)
            ..lineTo(50 - body, 103)
            ..lineTo(50 - body, 32)
            ..lineTo(27, 36)
            ..lineTo(17, 24)
            ..close(),
        );
        canvas.drawLine(Offset(50 - body, 48), Offset(50 + body, 48), pen);
      case FitContext.set:
        // Two separated pieces: illustrative composition, not a stored set type.
        canvas.save();
        canvas.scale(0.72, 0.43);
        canvas.translate(19.5, 0);
        draw(_top());
        canvas.restore();
        canvas.save();
        canvas.translate(14, 54);
        canvas.scale(0.72, 0.49);
        draw(_pants(103));
        canvas.restore();
      case FitContext.tops:
        draw(_top());
      case FitContext.optional:
        break;
    }
    canvas.restore();
  }

  Path _top() {
    final shoulder = fit == '오버핏' ? 36.0 : _width;
    final sleeveless = subtype.contains('민소매');
    final longSleeves =
        ['긴팔', '셔츠', '니트', '맨투맨', '후드', '가디건'].any(subtype.contains) &&
        !subtype.contains('반팔') &&
        !subtype.contains('폴로');
    return Path()
      ..moveTo(38, 10)
      ..quadraticBezierTo(50, 24, 62, 10)
      ..lineTo(50 + shoulder, 22)
      ..lineTo(
        sleeveless ? 50 + _width : 97,
        sleeveless
            ? 44
            : longSleeves
            ? 78
            : 48,
      )
      ..lineTo(
        sleeveless ? 50 + _width : 82,
        sleeveless
            ? 44
            : longSleeves
            ? 84
            : 58,
      )
      ..lineTo(50 + _width, 45)
      ..lineTo(50 + _width, 101)
      ..lineTo(50 - _width, 101)
      ..lineTo(50 - _width, 45)
      ..lineTo(
        sleeveless ? 50 - _width : 18,
        sleeveless
            ? 44
            : longSleeves
            ? 84
            : 58,
      )
      ..lineTo(
        sleeveless ? 50 - _width : 3,
        sleeveless
            ? 44
            : longSleeves
            ? 78
            : 48,
      )
      ..lineTo(50 - shoulder, 22)
      ..close();
  }

  Path _pants(double bottom) {
    final hem = switch (fit) {
      '테이퍼드핏' => 7.0,
      '스키니핏' => 6.0,
      '슬림핏' => 9.0,
      '와이드핏' => 17.0,
      '루즈핏' => 15.0,
      _ => 12.0,
    };
    return Path()
      ..moveTo(21, 9)
      ..lineTo(79, 9)
      ..lineTo(68 + hem, bottom)
      ..lineTo(68 - hem, bottom)
      ..lineTo(50, 37)
      ..lineTo(32 + hem, bottom)
      ..lineTo(32 - hem, bottom)
      ..close();
  }

  @override
  bool shouldRepaint(FitSilhouettePainter oldDelegate) =>
      fit != oldDelegate.fit ||
      category != oldDelegate.category ||
      subtype != oldDelegate.subtype ||
      color != oldDelegate.color;
}
