import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;

    final days = isAr ? ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'] : ['S', 'S', 'M', 'T', 'W', 'T', 'F'];
    const heights = [38, 64, 52, 80, 46, 70, 58];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Text(t.progress, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 4),
        Text(t.progressSub, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.green.withOpacity(0.4), radius: QRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.thisWeek, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.green, letterSpacing: 0.4)),
              const SizedBox(height: 4),
              Text(
                isAr ? '٤ أيام نشاط · ١٠ وجبات مسجلة · ٧١٪ داخل النطاق' : '4 active days · 10 meals logged · 71% in target range',
                style: QText.body(size: 14, height: 22, color: QColors.textHigh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.activeDays, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: heights[i] / 100,
                                  widthFactor: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [QColors.cyan, QColors.blue]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(days[i], style: QText.number(size: 10, color: QColors.textFaint)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), radius: QRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.weightTrend, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, height: 90, child: CustomPaint(painter: _WeightTrendPainter())),
              const SizedBox(height: 10),
              Text(
                isAr ? 'اتجاه هادي لأسبوعين. قياس واحد مش دليل.' : 'A calm trend over two weeks. A single reading is not evidence.',
                style: QText.body(size: 13, color: QColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: QColors.blue.withOpacity(0.1), border: Border.all(color: QColors.blue.withOpacity(0.4)), borderRadius: BorderRadius.circular(QRadii.xl)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.weeklyInsight, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.skyBlue, letterSpacing: 0.4)),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'أقوى أيامك كان فيها غدا متخطط. المهمة الجاية: جهّز الغدا مرتين الأسبوع ده.'
                    : 'Your strongest days followed a planned lunch. Next quest: prepare lunch twice this week.',
                style: QText.body(size: 14, height: 22, color: QColors.textHigh),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeightTrendPainter extends CustomPainter {
  static const _points = [
    Offset(8, 64),
    Offset(56, 58),
    Offset(104, 60),
    Offset(152, 48),
    Offset(200, 42),
    Offset(248, 38),
    Offset(292, 34),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 300;
    final sy = size.height / 90;
    final path = Path();
    for (var i = 0; i < _points.length; i++) {
      final p = Offset(_points[i].dx * sx, _points[i].dy * sy);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final linePaint = Paint()
      ..color = QColors.violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final last = Offset(_points.last.dx * sx, _points.last.dy * sy);
    canvas.drawCircle(last, 5, Paint()..color = QColors.cyan);
  }

  @override
  bool shouldRepaint(covariant _WeightTrendPainter oldDelegate) => false;
}
