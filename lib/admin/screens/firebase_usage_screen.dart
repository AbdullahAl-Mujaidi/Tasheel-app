// lib/admin/screens/firebase_usage_screen.dart
// صفحة "استهلاك Firebase" في لوحة المدير:
//  - البيانات الرسمية (Cloud Monitoring) مع الحصص والرسم اليومي.
//  - عمليات التطبيق المحلية (اختياري، على هذا الجهاز فقط).
import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../view/login_view.dart';
import '../controllers/firebase_usage_controller.dart';
import '../models/admin_role.dart';
import '../models/firebase_usage_model.dart';
import '../models/firebase_usage_quota.dart';
import '../services/admin_session_service.dart';
import '../widgets/common.dart';

/// نوع عرض الرسم اليومي: أعمدة مجمعة (أنواع) أو عمود واحد (الإجمالي).
enum _ChartMode { grouped, total }

class AdminFirebaseUsageScreen extends StatefulWidget {
  const AdminFirebaseUsageScreen({super.key});

  @override
  State<AdminFirebaseUsageScreen> createState() =>
      _AdminFirebaseUsageScreenState();
}

class _AdminFirebaseUsageScreenState extends State<AdminFirebaseUsageScreen> {
  static final NumberFormat _num = NumberFormat('#,##0');

  /// يُسند أثناء البناء للوصول للمتحكم من المؤقت (المؤقت خارج نطاق Provider).
  FirebaseUsageController? _autoRefreshController;
  Timer? _autoTimer;
  _ChartMode _chartMode = _ChartMode.grouped;

  @override
  void initState() {
    super.initState();
    // تحديث تلقائي هادئ كل 5 دقائق: يعرض كاش سليم فوراً، ويجلب من الشبكة
    // فقط عندما يصبح الكاش قديماً (أكثر من 15 دقيقة).
    _autoTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _autoRefreshController?.loadIfNeeded();
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  String _f(int? n) => _num.format(n ?? 0);
  String _pct(double x) => '${(x * 100).toStringAsFixed(1)}%';

  void _redirectToLogin(BuildContext context) {
    AdminSessionService.instance.clearCache();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _refresh(BuildContext context) async {
    final c = context.read<FirebaseUsageController>();
    if (!c.canRefresh) {
      showSnack(context, 'يُسمح بتحديث البيانات مرة كل دقيقة فقط', SnackKind.info);
      return;
    }
    await c.refresh();
    if (context.mounted) showSnack(context, 'تم تحديث بيانات الاستخدام');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAnalyst = AdminSessionService.instance.role == AdminRole.analyst;

    return ChangeNotifierProvider(
      create: (_) => FirebaseUsageController()
        ..onSessionExpired = () {
          _redirectToLogin(context);
        }
        ..load(),
      child: Consumer<FirebaseUsageController>(
        builder: (context, c, _) {
          _autoRefreshController = c;
          if (c.isLoading) return loadingWidget();

          final content = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('استهلاك Firebase',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  // المحلل قراءة فقط — لا زر تحديث.
                  if (!isAnalyst)
                    IconButton(
                      onPressed:
                          c.isRefreshing ? null : () => _refresh(context),
                      icon: c.isRefreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      tooltip: 'تحديث البيانات الرسمية',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (c.error != null) ...[
                errorBanner(context, c.error!, onRetry: () => c.load()),
                const SizedBox(height: 16),
              ],
              _firestoreDbSection(context, c),
              _officialSection(context, c),
              const SizedBox(height: 24),
              sectionTitle(context, 'عمليات التطبيق (محلي)'),
              _appOpsSection(context, c.snapshot),
              const SizedBox(height: 24),
              _infoSection(context, scheme),
            ],
          );

          if (isAnalyst) return content;
          return RefreshIndicator(onRefresh: () => _refresh(context),
            child: content);
        },
      ),
    );
  }

  // ======================= قسم إحصائيات قاعدة البيانات =======================
  Widget _firestoreDbSection(BuildContext context, FirebaseUsageController c) {
    final scheme = Theme.of(context).colorScheme;
    final dbTotals = c.dbTotals;
    final authTotals = c.dbAuthTotals;
    final reads = c.dbReadsStatus;
    final writes = c.dbWritesStatus;
    final deletes = c.dbDeletesStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle(context, 'إحصائيات قاعدة البيانات (Firestore Database)'),
        const SizedBox(height: 4),
        Text(
          'جدول الإحصائيات الفوري المسجل في قاعدة البيانات لجميع عمليات ومستخدمي التطبيق:',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final cross = constraints.maxWidth >= 700 ? 3 : 1;
          return GridView.count(
            crossAxisCount: cross,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cross == 1 ? 2.6 : 1.5,
            children: [
              _quotaCard(context,
                  label: 'قراءات اليوم',
                  st: reads,
                  color: scheme.primary),
              _quotaCard(context,
                  label: 'كتابات اليوم',
                  st: writes,
                  color: Colors.teal.shade600),
              _quotaCard(context,
                  label: 'حذف اليوم',
                  st: deletes,
                  color: scheme.error),
            ],
          );
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'إجمالي القراءات',
                value: _f(dbTotals.reads),
                icon: Icons.auto_graph_outlined,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'إجمالي الكتابات',
                value: _f(dbTotals.writes),
                icon: Icons.edit_note_outlined,
                color: Colors.teal.shade600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'إجمالي الحذف',
                value: _f(dbTotals.deletes),
                icon: Icons.delete_outline,
                color: scheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        sectionTitle(context, 'إحصائيات تسجيل الدخول والحسابات'),
        const SizedBox(height: 4),
        Text(
          'أعداد عمليات التسجيل والتوثيق المنفذة عبر التطبيق:',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'دخول بريد إلكتروني',
                value: _f(authTotals.emailLogins),
                icon: Icons.email_outlined,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'تسجيل دخول Google',
                value: _f(authTotals.googleLogins),
                icon: Icons.g_mobiledata,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'حسابات منشأة جديدة',
                value: _f(authTotals.signups),
                icon: Icons.person_add_outlined,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'حسابات موثقة',
                value: _f(authTotals.verifications),
                icon: Icons.verified_outlined,
                color: Colors.amber.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _storageCard(context, c),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _storageCard(BuildContext context, FirebaseUsageController c) {
    final scheme = Theme.of(context).colorScheme;
    final sizeFormatted = c.dbStorageSizeFormatted;

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.storage_outlined, color: scheme.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حجم التخزين الفعلي في Firestore',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    'الحجم الإجمالي التقريبي للبيانات الحالية: $sizeFormatted من أصل الحد المجاني (1 GiB)',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(
              sizeFormatted,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================= القسم الرسمي =======================
  Widget _officialSection(BuildContext context, FirebaseUsageController c) {
    if (!c.hasOfficialData) return _unavailableCard(context, c);

    final official = c.snapshot!.official!;
    final scheme = Theme.of(context).colorScheme;
    final reads = c.readsStatus;
    final writes = c.writesStatus;
    final deletes = c.deletesStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.officialFromCache || c.isOfficialStale) ...[
          _cacheBanner(context, c.isOfficialStale),
          const SizedBox(height: 12),
        ],
        sectionTitle(context, 'البيانات الرسمية (Cloud Monitoring)'),
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'آخر مزامنة: ${formatDate(official.fetchedAt.toLocal())} — أرقام تقديرية قد تتأخر حتى 4 دقائق',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (c.hasActiveAlerts) ...[
          _alertsBanner(context, c.activeAlerts),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(builder: (context, constraints) {
          final cross = constraints.maxWidth >= 700 ? 3 : 1;
          return GridView.count(
            crossAxisCount: cross,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cross == 1 ? 2.6 : 1.5,
            children: [
              if (reads != null)
                _quotaCard(context,
                    label: 'قراءات اليوم',
                    st: reads,
                    color: scheme.primary),
              if (writes != null)
                _quotaCard(context,
                    label: 'كتابات اليوم',
                    st: writes,
                    color: Colors.teal.shade600),
              if (deletes != null)
                _quotaCard(context,
                    label: 'حذف اليوم',
                    st: deletes,
                    color: scheme.error),
            ],
          );
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'مستخدمو Authentication',
                value: _f(official.authUsers),
                icon: Icons.verified_user_outlined,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'إجمالي عمليات الشهر',
                value: _f(official.month?.total),
                icon: Icons.calendar_month_outlined,
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: sectionTitle(context, 'الاستخدام اليومي (آخر ${c.days} يوم)'),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                children: [
                  _modeSelector(context),
                  const SizedBox(width: 8),
                  _daysSelector(context, c),
                ],
              ),
            ),
          ],
        ),
        _officialChartArea(context, official, c.days),
        const SizedBox(height: 16),
        _storageCard(context, c),
      ],
    );
  }

  Widget _daysSelector(BuildContext context, FirebaseUsageController c) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 7, label: Text('7')),
        ButtonSegment(value: 14, label: Text('14')),
        ButtonSegment(value: 30, label: Text('30')),
      ],
      selected: {c.days},
      onSelectionChanged: (s) => c.setDays(s.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _modeSelector(BuildContext context) {
    return SegmentedButton<_ChartMode>(
      segments: const [
        ButtonSegment(value: _ChartMode.grouped, label: Text('أنواع')),
        ButtonSegment(value: _ChartMode.total, label: Text('الإجمالي')),
      ],
      selected: {_chartMode},
      onSelectionChanged: (s) => setState(() => _chartMode = s.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// بطاقة الحصة الواحدة مع شريط نسبة ملوّن حسب مستوى التحذير.
  Widget _quotaCard(BuildContext context,
      {required String label, required QuotaStatus st, required Color color}) {
    final scheme = Theme.of(context).colorScheme;
    final levelColor = _levelColor(context, st.level);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(Icons.speed, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${_f(st.used)} / ${_f(st.limit)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: st.ratio.clamp(0.0, 1.0),
              minHeight: 8,
              color: levelColor,
              backgroundColor: scheme.outlineVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(_pct(st.ratio.clamp(0.0, 1.0)),
                    style: TextStyle(fontSize: 12, color: levelColor)),
              ),
              Text(
                st.overQuota
                    ? 'تجاوز الحصة بـ ${_f(-st.remaining)}'
                    : 'متبقٍ ${_f(st.remaining)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// الرسم اليومي الرسمي + دليل الألوان عند العرض "أنواع".
  Widget _officialChartArea(
      BuildContext context, OfficialFirebaseUsage official, int days) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _officialChart(context, official, days),
        if (_chartMode == _ChartMode.grouped) ...[
          const SizedBox(height: 10),
          _chartLegend(context),
        ],
      ],
    );
  }

  Widget _chartLegend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsetsDirectional.only(end: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(scheme.primary, 'قراءات'),
        item(Colors.teal.shade600, 'كتابات'),
        item(scheme.error, 'حذف'),
      ],
    );
  }

  Widget _officialChart(
      BuildContext context, OfficialFirebaseUsage official, int days) {
    final scheme = Theme.of(context).colorScheme;
    final list = official.daily;
    final keep =
        list.length > days ? list.sublist(list.length - days) : list;
    if (keep.isEmpty) {
      return emptyState(context, 'لا توجد نقاط يومية بعد', icon: Icons.bar_chart);
    }
    final maxV = keep.fold<double>(
        0, (a, e) => a > e.ops.total ? a : e.ops.total.toDouble());

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxV * 1.25,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: scheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (v, meta) => Text(
                      _f(v.toInt()),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= keep.length) {
                        return const SizedBox.shrink();
                      }
                      if (keep.length > 12 && i % 2 != 0) {
                        return const SizedBox.shrink();
                      }
                      final d = keep[i].date.toLocal();
                      final label = keep.length > 10
                          ? '${d.day}/${d.month}'
                          : '${d.day}/${d.month}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child:
                            Text(label, style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => scheme.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final p = keep[group.x];
                    final d = p.date.toLocal();
                    final title =
                        '${d.day}/${d.month}/${d.year}\n';
                    final color = rod.color!;
                    final value = rod.toY.toInt();
                    return BarTooltipItem(
                      title,
                      TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.bold),
                      children: [
                        TextSpan(
                          text: '${_f(value)} عملية',
                          style: TextStyle(color: color, fontWeight: FontWeight.bold),
                        ),
                      ],
                    );
                  },
                ),
              ),
              barGroups: [
                for (int i = 0; i < keep.length; i++)
                  if (_chartMode == _ChartMode.grouped)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: keep[i].ops.reads.toDouble(),
                          color: scheme.primary,
                          width: 7,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                        BarChartRodData(
                          toY: keep[i].ops.writes.toDouble(),
                          color: Colors.teal.shade600,
                          width: 7,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                        BarChartRodData(
                          toY: keep[i].ops.deletes.toDouble(),
                          color: scheme.error,
                          width: 7,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ],
                    )
                  else
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: keep[i].ops.total.toDouble(),
                          color: scheme.primary,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
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

  Widget _unavailableCard(BuildContext context, FirebaseUsageController c) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('البيانات الرسمية غير متاحة حالياً',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              c.snapshot?.officialError ??
                  'يتعذر الوصول لبيانات الاستخدام الرسمية من Google.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              'يظهر قسم الاستهلاك تلقائياً فور توفّر الخادم:',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            const _Bullet(
                'نشر Cloud Function «getFirebaseUsage» (يتطلب خطة Blaze).'),
            const _Bullet(
                'تفعيل Cloud Monitoring API ومنح «Monitoring Viewer» لحساب الخدمة.'),
            const _Bullet('التفاصيل في functions/FIREBASE_USAGE_BACKEND.md.'),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: c.isRefreshing ? null : () => c.refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// شريط تنبيه صريح عند اقتراب/تجاوز حصة اليوم (90% فأكثر).
  Widget _alertsBanner(BuildContext context, List<QuotaAlert> alerts) {
    final scheme = Theme.of(context).colorScheme;
    final anyCritical = alerts.any((a) => a.isCritical);
    final bg = anyCritical ? scheme.errorContainer : scheme.tertiaryContainer;
    final fg =
        anyCritical ? scheme.onErrorContainer : scheme.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                anyCritical ? Icons.warning_amber_rounded : Icons.error_outline,
                size: 20,
                color: fg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  anyCritical
                      ? 'تنبيه: تم تجاوز حصة اليوم'
                      : 'تنبيه: اقترب الاستهلاك اليومي من الحد',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: fg, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final a in alerts)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 5, color: fg),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(a.summary,
                        style: TextStyle(color: fg, fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cacheBanner(BuildContext context, bool stale) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stale
                  ? 'تعرض أحدث بيانات رسمية من الكاش المحلي، والمزامنة الأخيرة أقدم من 15 دقيقة.'
                  : 'تعرض بيانات رسمية محفوظة محلياً (آخر تحديث ناجح) — دون اتصال بالشبكة هذه اللحظة.',
              style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  // ======================= قسم عمليات التطبيق =======================
  Widget _appOpsSection(BuildContext context, UsageSnapshot? snap) {
    final scheme = Theme.of(context).colorScheme;
    final ops = snap?.appOps ?? const FirestoreOps.empty();
    final history = snap?.appHistory ?? const <FirestoreOps>[];

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('عمليات التطبيق على هذا الجهاز (اليوم)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'عداد محلي اختياري — يُسجَّل في SQLite فقط، دون أي اتصال بالشبكة أو استهلاك Firestore.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _opsMini(context, 'قراءات', ops.reads,
                      color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _opsMini(context, 'كتابات', ops.writes,
                      color: Colors.teal.shade600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _opsMini(context, 'حذف', ops.deletes,
                      color: scheme.error),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (history.isNotEmpty) _appOpsChart(context, history),
          ],
        ),
      ),
    );
  }

  Widget _opsMini(
      BuildContext context, String label, int value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(_f(value),
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// رسم أعمدة بسيط لإجمالي آخر 7 أيام (اليوم أولاً).
  Widget _appOpsChart(BuildContext context, List<FirestoreOps> history) {
    final scheme = Theme.of(context).colorScheme;
    final asc = history.reversed.toList();
    final maxV = asc.fold<double>(
        0, (a, e) => a > e.total ? a : e.total.toDouble());

    return SizedBox(
      height: 130,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (maxV > 0 ? maxV * 1.3 : 1),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= asc.length) return const SizedBox.shrink();
                  if (asc.length > 8 && i % 2 != 0) return const SizedBox.shrink();
                  final d = DateTime.now()
                      .subtract(Duration(days: asc.length - 1 - i));
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
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
                return BarTooltipItem(
                  '${d.day}/${d.month}/${d.year}\nعمليات: ${_f(p.total)}',
                  TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.bold),
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
                    toY: asc[i].total.toDouble(),
                    color: scheme.primary,
                    width: 14,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ======================= معلومة الضبط =======================
  Widget _infoSection(BuildContext context, ColorScheme scheme) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معلومات الضبط',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const _Bullet(
                'الأرقام الرسمية تقديرية من Google Cloud Monitoring وقد تتأخر حتى 4 دقائق.'),
            const _Bullet(
                'يُحسب "اليوم" الشهري بتوقيت UTC — عند مقارنته بمنتصف ليل المنطقة قد ترى فارقاً زمنياً (ليس خطأ).'),
            const _Bullet(
                'عند أي اختلاف، تُعتمد فاتورة Google (Billing Report) وليست لوحة الاستخدام.'),
            const _Bullet(
                'التخزين والإنترنت غير متاحين عبر Monitoring لخطة Native — لا يتم اختلاق أرقام.'),
            const _Bullet(
                'الحصص المجانية قابلة للتعديل من مكان واحد: QuotaLimits في نماذج الاستخدام.'),
          ],
        ),
      ),
    );
  }

  Color _levelColor(BuildContext context, UsageAlertLevel level) {
    switch (level) {
      case UsageAlertLevel.normal:
        return Colors.green.shade600;
      case UsageAlertLevel.warning:
        return Colors.orange.shade700;
      case UsageAlertLevel.danger:
        return Colors.deepOrange.shade500;
      case UsageAlertLevel.critical:
        return Colors.red.shade700;
    }
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}