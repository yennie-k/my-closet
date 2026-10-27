import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/garment.dart';

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

class FitSilhouettePainter extends CustomPainter {
  const FitSilhouettePainter(this.fit, this.category, this.color);
  final String fit;
  final GarmentCategory? category;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 110);
    final path = Path();
    final width = switch (fit) {
      '스키니핏' => 15.0,
      '슬림핏' => 21.0,
      '오버핏' => 38.0,
      '루즈핏' => 33.0,
      '와이드핏' => 39.0,
      _ => 27.0,
    };
    if (category == GarmentCategory.bottoms && (fit == 'A라인' || fit == 'H라인')) {
      final hem = fit == 'A라인' ? 45.0 : 30.0;
      path.moveTo(23, 8);
      path.lineTo(77, 8);
      path.lineTo(50 + hem, 102);
      path.lineTo(50 - hem, 102);
      path.close();
    } else if (category == GarmentCategory.bottoms) {
      final hem = switch (fit) {
        '테이퍼드핏' => 10.0,
        '스키니핏' => 7.0,
        '슬림핏' => 12.0,
        '와이드핏' || 'A라인' => 31.0,
        '오버핏' => 28.0,
        '루즈핏' => 25.0,
        '레귤러핏' => 18.0,
        _ => 21.0,
      };
      path.moveTo(18, 8);
      path.lineTo(82, 8);
      path.lineTo(82 + (hem - 21) / 2, 101);
      path.lineTo(52, 101);
      path.lineTo(50, 43);
      path.lineTo(48, 101);
      path.lineTo(18 - (hem - 21) / 2, 101);
      path.close();
      if (fit == '스키니핏' || fit == '슬림핏' || fit == '테이퍼드핏') {
        path.reset();
        path.moveTo(20, 8);
        path.lineTo(80, 8);
        path.lineTo(68 + hem / 2, 101);
        path.lineTo(68 - hem / 2, 101);
        path.lineTo(50, 38);
        path.lineTo(32 + hem / 2, 101);
        path.lineTo(32 - hem / 2, 101);
        path.close();
      }
    } else if (category == GarmentCategory.dresses ||
        fit == 'A라인' ||
        fit == 'H라인') {
      final hem = fit == 'A라인'
          ? 44.0
          : fit == 'H라인'
          ? 27.0
          : width;
      path.moveTo(33, 9);
      path.quadraticBezierTo(50, 23, 67, 9);
      path.lineTo(75, 34);
      path.lineTo(65, 42);
      path.lineTo(50 + hem, 102);
      path.lineTo(50 - hem, 102);
      path.lineTo(35, 42);
      path.lineTo(25, 34);
      path.close();
    } else {
      final shoulder = fit == '오버핏' ? 37.0 : width;
      path.moveTo(38, 12);
      path.quadraticBezierTo(50, 25, 62, 12);
      path.lineTo(50 + shoulder, 24);
      path.lineTo(97, 51);
      path.lineTo(81, 61);
      path.lineTo(50 + width, 48);
      path.lineTo(50 + width, 100);
      path.lineTo(50 - width, 100);
      path.lineTo(50 - width, 48);
      path.lineTo(19, 61);
      path.lineTo(3, 51);
      path.lineTo(50 - shoulder, 24);
      path.close();
    }
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FitSilhouettePainter oldDelegate) =>
      fit != oldDelegate.fit ||
      category != oldDelegate.category ||
      color != oldDelegate.color;
}
