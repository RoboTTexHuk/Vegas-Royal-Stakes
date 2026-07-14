import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Виджет лоадера: фон assets/loader.png + анимированная звуковая волна
/// (эквалайзер из вертикальных полосок, как на референсе) по центру.
///
/// Использование:
/// ```dart
/// const AppLoader()
/// ```
/// или на весь экран, например как splash / loading screen:
/// ```dart
/// Scaffold(body: AppLoader())
/// ```
class AppLoader extends StatefulWidget {
  const AppLoader({
    super.key,
    this.backgroundAsset = 'assets/loader.png',
    this.barColor = const Color(0x99FFFFFF),
    this.barsPerGroup = 6,
    this.groupCount = 2,
    this.barWidth = 6,
    this.barSpacing = 8,
    this.groupSpacing = 28,
    this.minBarHeight = 10,
    this.maxBarHeight = 46,
    this.animationSpeed = const Duration(milliseconds: 900),
  });

  /// Путь к фоновому изображению.
  final String backgroundAsset;

  /// Цвет полосок волны.
  final Color barColor;

  /// Количество полосок в одной группе.
  final int barsPerGroup;

  /// Количество групп полосок (на референсе — 2, с промежутком между ними).
  final int groupCount;

  /// Ширина одной полоски.
  final double barWidth;

  /// Расстояние между полосками внутри группы.
  final double barSpacing;

  /// Расстояние между группами.
  final double groupSpacing;

  /// Минимальная высота полоски.
  final double minBarHeight;

  /// Максимальная высота полоски.
  final double maxBarHeight;

  /// Скорость анимации пульсации полосок.
  final Duration animationSpeed;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationSpeed)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Фоновая картинка
        Image.asset(
          widget.backgroundAsset,
          fit: BoxFit.cover,
        ),
        // Анимированная волна (эквалайзер) по центру
        Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _WaveBarsPainter(
                  progress: _controller.value,
                  color: widget.barColor,
                  barsPerGroup: widget.barsPerGroup,
                  groupCount: widget.groupCount,
                  barWidth: widget.barWidth,
                  barSpacing: widget.barSpacing,
                  groupSpacing: widget.groupSpacing,
                  minBarHeight: widget.minBarHeight,
                  maxBarHeight: widget.maxBarHeight,
                ),
                size: Size(
                  widget.groupCount * widget.barsPerGroup * (widget.barWidth + widget.barSpacing) +
                      (widget.groupCount - 1) * widget.groupSpacing,
                  widget.maxBarHeight,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Отдельный класс-painter для отрисовки анимированной звуковой волны
/// в виде вертикальных полосок (эквалайзер), сгруппированных с промежутками.
class _WaveBarsPainter extends CustomPainter {
  _WaveBarsPainter({
    required this.progress,
    required this.color,
    required this.barsPerGroup,
    required this.groupCount,
    required this.barWidth,
    required this.barSpacing,
    required this.groupSpacing,
    required this.minBarHeight,
    required this.maxBarHeight,
  });

  /// Значение от 0.0 до 1.0 — фаза анимации.
  final double progress;

  final Color color;
  final int barsPerGroup;
  final int groupCount;
  final double barWidth;
  final double barSpacing;
  final double groupSpacing;
  final double minBarHeight;
  final double maxBarHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final midY = size.height / 2;
    final phase = progress * 2 * math.pi;

    double x = 0;
    var globalIndex = 0;

    for (var g = 0; g < groupCount; g++) {
      for (var i = 0; i < barsPerGroup; i++) {
        // У каждой полоски своя фаза колебания — создаёт эффект живой волны.
        final barPhase = phase + globalIndex * 0.9;
        final t = (math.sin(barPhase) + 1) / 2; // 0..1
        final height = minBarHeight + (maxBarHeight - minBarHeight) * t;

        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, midY),
            width: barWidth,
            height: height,
          ),
          Radius.circular(barWidth / 2),
        );
        canvas.drawRRect(rect, paint);

        x += barWidth + barSpacing;
        globalIndex++;
      }
      x += groupSpacing - barSpacing;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveBarsPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
