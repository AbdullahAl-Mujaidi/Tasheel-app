// lib/admin/screens/analytics_screen.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_analytics_controller.dart';
import '../models/admin_models.dart';
import '../models/admin_role.dart';
import '../services/admin_session_service.dart';
import '../widgets/common.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  Future<void> _refresh(BuildContext context) async {
    final c = context.read<AdminAnalyticsController>();
    await c.refresh();
    if (context.mounted && c.error == null) showSnack(context, 'تم تحديث التحليلات');
  }

  @override
  Widget build(BuildContext context) {
    final isAnalyst = AdminSessionService.instance.role == AdminRole.analyst;

    return ChangeNotifierProvider(
      create: (_) => AdminAnalyticsController()..load(),
      child: Consumer<AdminAnalyticsController>(
        builder: (context, c, _) {
          if (c.isLoading) return loadingWidget();

          final content = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('التحليلات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  // المحلل قراءة فقط — لا يظهر له زر تحديث أو أي إجراء تعديل.
                  if (!isAnalyst)
                    IconButton(
                      onPressed: c.isRefreshing ? null : () => _refresh(context),
                      icon: c.isRefreshing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      tooltip: 'تحديث',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (c.error != null) ...[
                errorBanner(context, c.error!, onRetry: c.load),
                const SizedBox(height: 16),
              ],
              if (c.stats == null && c.error == null) ...[
                const SizedBox(height: 24),
                emptyState(context, 'لا توجد بيانات كافية للعرض', icon: Icons.insights_outlined),
                if (!isAnalyst) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'تُحسب الإحصاءات تلقائياً كل 6 ساعات، أو حدّثها الآن يدوياً من زر التحديث أعلى الصفحة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
              if (c.stats != null) ...[
                _grid(context, c.stats!),
                const SizedBox(height: 24),
                sectionTitle(context, 'توزيع المستخدمين حسب إصدار التطبيق'),
                _versions(context, c.stats!),
              ],
            ],
          );

          if (isAnalyst) return content;

          return RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: content,
          );
        },
      ),
    );
  }

  Widget _grid(BuildContext context, DashboardStats s) {
    return LayoutBuilder(builder: (context, constraints) {
      final cross = constraints.maxWidth > 900 ? 4 : 2;
      return GridView.count(
        crossAxisCount: cross,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: [
          StatCard(label: 'إجمالي الأعمال', value: s.totalBusinesses.toString(), icon: Icons.business_center_outlined),
          StatCard(label: 'أُضيفت اليوم', value: s.businessesToday.toString(), icon: Icons.today_outlined, color: Colors.indigo),
          StatCard(label: 'مكتملة', value: s.completedBusinesses.toString(), icon: Icons.check_circle, color: Colors.green.shade700),
          StatCard(label: 'المتبقية (غير مكتملة)', value: s.remainingBusinesses.toString(), icon: Icons.hourglass_top, color: Colors.orange),
          StatCard(label: 'إجمالي العمال', value: s.totalWorkers.toString(), icon: Icons.groups_outlined, color: Colors.teal),
          StatCard(label: 'إجمالي المستخدمين', value: s.totalUsers.toString(), icon: Icons.people_alt_outlined),
        ],
      );
    });
  }

  Widget _versions(BuildContext context, DashboardStats s) {
    final entries = s.versionDistribution.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return emptyState(context, 'لا توجد بيانات كافية للعرض');
    }
    final total = entries.fold<int>(0, (a, e) => a + e.value);
    final maxVal = entries.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 800;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide) ...[
            _barChart(context, entries, total),
            const SizedBox(height: 16),
          ],
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const SizedBox(width: 90, child: Text('الإصدار', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Expanded(child: Text('الانتشار', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 90, child: Text('المستخدمون', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 60, child: Text('النسبة', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                  ),
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (e.value / (maxVal <= 0 ? 1 : maxVal)).clamp(0.0, 1.0),
                                minHeight: 8,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text('${e.value} مستخدم', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12)),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text('${_percent(e.value, total)}%', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _barChart(BuildContext context, List<MapEntry<String, int>> entries, int total) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (entries.map((e) => e.value).fold(0, (a, b) => a > b ? a : b) * 1.2).toDouble(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(entries[i].key, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => scheme.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final e = entries[group.x];
                    return BarTooltipItem(
                      '${e.key}\n${e.value} مستخدم (${_percent(e.value, total)}%)',
                      TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              barGroups: [
                for (int i = 0; i < entries.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: entries[i].value.toDouble(),
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _percent(int part, int total) {
    if (total <= 0) return '0';
    return ((part * 100) / total).toStringAsFixed(1);
  }
}