// lib/view/app_usage_view.dart
// صفحة "الإعدادات ← استهلاك التطبيق":
// عداد محلي لعمليات Firestore التي نفذها التطبيق على هذا الجهاز فقط.
// ملاحظة مهمة: هذه الأرقام ليست الاستهلاك الرسمي لـ Firebase.
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../admin/models/firebase_usage_model.dart';
import '../controller/app_usage_controller.dart';

class AppUsageView extends StatelessWidget {
  const AppUsageView({super.key});

  static final NumberFormat _num = NumberFormat('#,##0');

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppUsageController()..load(),
      child: Consumer<AppUsageController>(
        builder: (context, controller, _) {
          final colorScheme = Theme.of(context).colorScheme;
          final hasHistory = controller.last7Days.any((o) => o.total > 0);

          return Scaffold(
            appBar: AppBar(
              title: const Text('استهلاك التطبيق'),
              backgroundColor: colorScheme.surface,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoBanner(context),
                      const SizedBox(height: 20),
                      _sectionTitle(context, 'إحصائيات اليوم'),
                      const SizedBox(height: 10),
                      _todaySection(context, controller.today),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'آخر 7 أيام'),
                      const SizedBox(height: 10),
                      if (hasHistory)
                        _chartCard(context, controller.last7Days)
                      else
                        _emptyChart(context),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'الإجمالي'),
                      const SizedBox(height: 10),
                      _totalsCard(context, controller.totals),
                      const SizedBox(height: 28),
                      _resetButton(context, controller),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ======================= التنويه =======================
  Widget _infoBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'هذه الإحصائيات تمثل عمليات Firestore التي سجلها التطبيق على هذا '
              'الجهاز، وقد تختلف عن أرقام Firebase الرسمية بسبب طريقة احتساب '
              'Firebase وبعض العمليات التي قد تتم خارج التطبيق.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  // ======================= اليوم =======================
  Widget _todaySection(BuildContext context, FirestoreOps today) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _opsMini(context, 'قراءات Firestore', today.reads,
                  Icons.import_contacts, Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _opsMini(context, 'كتابات Firestore', today.writes,
                  Icons.edit_note, Colors.teal.shade600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _opsMini(context, 'حذف Firestore', today.deletes,
                  Icons.delete_outline, Theme.of(context).colorScheme.error),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _totalMini(context, today.total),
      ],
    );
  }

  Widget _opsMini(
      BuildContext context, String label, int value, IconData icon, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_num.format(value),
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _totalMini(BuildContext context, int total) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('إجمالي العمليات',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.onPrimary)),
          Text(_num.format(total),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: scheme.onPrimary)),
        ],
      ),
    );
  }

  // ======================= آخر 7 أيام =======================
  Widget _chartCard(BuildContext context, List<FirestoreOps> history) {
    final scheme = Theme.of(context).colorScheme;
    final asc = history.reversed.toList();
    final maxV = asc.fold<double>(
        0, (a, e) => a > e.total ? a : e.total.toDouble());

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 210,
              width: double.infinity,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxV > 0 ? maxV * 1.35 : 1),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, meta) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(_num.format(v.toInt()),
                              style: const TextStyle(fontSize: 9)),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= asc.length) {
                            return const SizedBox.shrink();
                          }
                          final d = DateTime.now()
                              .subtract(Duration(days: asc.length - 1 - i));
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('${d.day}/${d.month}',
                                style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => scheme.inverseSurface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final p = asc[group.x];
                        final d = DateTime.now()
                            .subtract(Duration(days: asc.length - 1 - group.x));
                        final color = rod.color ?? scheme.primary;
                        final label = rodIndex == 0
                            ? 'قراءات'
                            : rodIndex == 1
                                ? 'كتابات'
                                : 'حذف';
                        return BarTooltipItem(
                          '${d.day}/${d.month}/${d.year}\n$label: ${_num.format(rod.toY.toInt())}',
                          TextStyle(
                              color: scheme.onInverseSurface,
                              fontWeight: FontWeight.bold),
                          children: [
                            TextSpan(
                              text: '\nإجمالي: ${_num.format(p.total)}',
                              style: TextStyle(
                                  color: color, fontWeight: FontWeight.bold),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (int i = 0; i < asc.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: asc[i].reads.toDouble(),
                            color: scheme.primary,
                            width: 6,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                          ),
                          BarChartRodData(
                            toY: asc[i].writes.toDouble(),
                            color: Colors.teal.shade600,
                            width: 6,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                          ),
                          BarChartRodData(
                            toY: asc[i].deletes.toDouble(),
                            color: scheme.error,
                            width: 6,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _legend(context),
          ],
        ),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsetsDirectional.only(end: 4),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            Text(label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item(scheme.primary, 'قراءات'),
        item(Colors.teal.shade600, 'كتابات'),
        item(scheme.error, 'حذف'),
      ],
    );
  }

  Widget _emptyChart(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bar_chart, color: scheme.onSurfaceVariant, size: 40),
              const SizedBox(height: 8),
              Text('لا توجد عمليات مسجلة بعد',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  // ======================= الإجمالي =======================
  Widget _totalsCard(BuildContext context, FirestoreOps totals) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, String label, int value, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(_num.format(value),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row(Icons.import_contacts, 'قراءات Firestore', totals.reads,
                scheme.primary),
            row(Icons.edit_note, 'كتابات Firestore', totals.writes,
                Colors.teal.shade600),
            row(Icons.delete_outline, 'حذف Firestore', totals.deletes,
                scheme.error),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.speed),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('إجمالي العمليات',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(_num.format(totals.total),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ======================= إعادة الضبط =======================
  Widget _resetButton(BuildContext context, AppUsageController controller) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          AwesomeDialog(
            context: context,
            dialogType: DialogType.warning,
            title: 'إعادة ضبط الإحصائيات',
            desc: 'هل أنت متأكد من حذف إحصائيات الاستخدام المحلية؟',
            btnOkText: 'نعم، احذف',
            btnCancelText: 'إلغاء',
            btnOkOnPress: () async {
              await controller.reset();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('تمت إعادة ضبط الإحصائيات المحلية'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ).show();
        },
        icon: Icon(Icons.delete_sweep_outlined, color: scheme.error),
        label: Text('إعادة ضبط الإحصائيات',
            style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.error,
          side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}