// lib/views/report_view.dart
import 'package:fkra/controller/business_controller.dart';
import 'package:fkra/controller/expense_controller.dart';
import 'package:fkra/controller/report_controller.dart';
import 'package:fkra/controller/workers_controller.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/view/business_reports_view.dart';
import 'package:fkra/view/expense_reports_view.dart';
import 'package:fkra/view/worker_reports_view.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

class ReportsPage extends StatefulWidget {
  final String userId;
  const ReportsPage({super.key, required this.userId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  /// نوع التقرير الجاري تحميله — يمنع الضغط المتكرر أثناء التحميل.
  String? _opening;

  /// نفس منطق `home_page._canRead`: المالك يرى كل شيء، والمفوّض يرى ما
  /// مُنحت له صلاحية قراءته فقط. تقرير الأعمال يحوي أسماء وأرقاماً، فلا
  /// يُفتح لمن لا يملك صلاحية `businesses`.
  bool _canRead(String module) {
    if (!MemberSessionService.instance.isSubUser) return true;
    final member = MemberSessionService.instance.member;
    if (member == null) return false;
    return member.canRead(module);
  }

  /// ينتظر انتهاء تهيئة المتحكّم (تُستدعى في الـconstructor عبر `_init`).
  Future<void> _waitLoaded(ChangeNotifier c, bool Function() isLoading) async {
    var waited = 0;
    while (isLoading() && waited < 8000) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      waited += 80;
    }
  }

  Future<void> _openBusinessReports() async {
    if (_opening != null) return;
    setState(() => _opening = 'businesses');
    final c = BusinessController(userId: widget.userId);
    try {
      await _waitLoaded(c, () => c.isLoading);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BusinessReportsView(
            businesses: c.businesses,
            transactions: c.transactions,
          ),
        ),
      );
    } finally {
      c.dispose();
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _openWorkerReports() async {
    if (_opening != null) return;
    setState(() => _opening = 'workers');
    final c = WorkersController(userId: widget.userId);
    try {
      await _waitLoaded(c, () => c.isLoading);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkerReportsView(workers: c.workers),
        ),
      );
    } finally {
      c.dispose();
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _openExpenseReports() async {
    if (_opening != null) return;
    setState(() => _opening = 'expenses');
    final c = ExpenseController(userId: widget.userId);
    try {
      await _waitLoaded(c, () => c.isLoading);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExpenseReportsView(expenses: c.expenses),
        ),
      );
    } finally {
      c.dispose();
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReportController(userId: widget.userId),
      child: Consumer<ReportController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;

          if (controller.isLoading) {
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  "تسهيل",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                    fontSize: 25,
                  ),
                ),
                centerTitle: true,
                backgroundColor: colorScheme.surface,
                elevation: 0,
              ),
              body: Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(
                "تسهيل",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  fontSize: 25,
                ),
              ),
              centerTitle: true,
              backgroundColor: colorScheme.surface,
              elevation: 0,
              actions: [
                IconButton(
                  onPressed: () async {
                    await controller.refreshData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم تحديث البيانات'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: Icon(Icons.refresh, color: colorScheme.primary),
                  tooltip: 'تحديث البيانات',
                ),
                if (controller.isOffline)
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Tooltip(
                      message: 'وضع غير متصل - يتم عرض آخر البيانات المحفوظة',
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange, size: 18),
                            SizedBox(width: 4),
                            Text('غير متصل',
                                style: TextStyle(color: Colors.orange, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: controller.refreshData,
              child: SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    if (controller.isOffline)
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'وضع غير متصل. يتم عرض آخر البيانات المحفوظة. سيتم تحديث التقارير تلقائياً عند عودة الاتصال.',
                                style: TextStyle(color: Colors.orange[700], fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // عنوان التقارير
                    Container(
                      padding: EdgeInsets.all(10),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "التقارير المالية",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),

                    // اختصارات التقارير التفصيلية (نسخة من أزرار الأقسام)
                    _buildReportShortcuts(colorScheme),

                    // أداء اليوم
                    _buildTodayPerformanceCard(controller, colorScheme),

                    // البطاقات المالية
                    _buildFinancialCards(controller, colorScheme),
                    _buildNetProfitCard(controller, colorScheme),
                    _buildStatsCards(controller, colorScheme),

                    // الرسم البياني الشهري
                    _buildMonthlyChart(controller, colorScheme),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ========== قائمة التقارير التفصيلية ==========
  ///
  /// زر واحد يفتح قائمة منسدلة بالتقارير المتاحة، بدل ثلاثة أزرار عمودية
  /// تستهلك ارتفاع الشاشة وتلخّص عناوينها على الشاشات الضيقة.
  /// يُخفى ما لا يملك العضو صلاحية قراءته.
  Widget _buildReportShortcuts(ColorScheme colorScheme) {
    final items = <({String label, String key, IconData icon, VoidCallback onTap})>[
      if (_canRead(TeamPermissions.businesses))
        (
          label: 'تقارير الأعمال',
          key: 'businesses',
          icon: Icons.card_travel,
          onTap: _openBusinessReports,
        ),
      if (_canRead(TeamPermissions.workers))
        (
          label: 'تقارير العمال',
          key: 'workers',
          icon: Icons.groups_2,
          onTap: _openWorkerReports,
        ),
      if (_canRead(TeamPermissions.expenses))
        (
          label: 'تقارير المصروفات',
          key: 'expenses',
          icon: Icons.attach_money,
          onTap: _openExpenseReports,
        ),
    ];

    // لا صلاحية لأي تقرير ⇒ لا نعرض زراً بلا فائدة.
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: PopupMenuButton<String>(
        enabled: _opening == null,
        onSelected: (key) {
          for (final item in items) {
            if (item.key == key) {
              item.onTap();
              return;
            }
          }
        },
        color: colorScheme.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          for (final item in items)
            PopupMenuItem<String>(
              value: item.key,
              height: 48,
              child: Row(
                children: [
                  Icon(item.icon, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          width: double.infinity,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_opening != null)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.leaderboard, size: 18, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                _opening != null ? 'جارٍ فتح التقرير…' : 'التقارير',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_drop_down, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  // ========== بطاقة أداء اليوم ==========
  Widget _buildTodayPerformanceCard(ReportController controller, ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.all(10),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Container(
        padding: EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.today, color: colorScheme.primary, size: 24),
                ),
                Text(
                  'أداء اليوم',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Divider(color: colorScheme.outline),
            SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // صافي الربح
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: controller.todayProfit >= 0
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${controller.todayProfit.toStringAsFixed(2)} ريال',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: controller.todayProfit >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'صافي الربح',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Icon(
                          controller.todayProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                          size: 20,
                          color: controller.todayProfit >= 0 ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 10),
                // الإيرادات
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${controller.todayRevenues.toStringAsFixed(2)} ريال',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'الإيرادات',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Icon(Icons.arrow_upward, size: 20, color: Colors.green),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 10),
                // المصروفات
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${controller.todayExpenses.toStringAsFixed(2)} ريال',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'المصروفات',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Icon(Icons.arrow_downward, size: 20, color: Colors.red),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========== بطاقات الإحصائيات ==========
  Widget _buildFinancialCards(ReportController controller, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Flexible(
          child: _buildStatCard(
            icon: Icons.trending_down,
            iconColor: colorScheme.error,
            value: controller.totalExpenses.toStringAsFixed(2),
            label: "المصروفات الكلية",
            valueColor: colorScheme.error,
            colorScheme: colorScheme,
          ),
        ),
        Flexible(
          child: _buildStatCard(
            icon: Icons.moving,
            iconColor: colorScheme.primary,
            value: controller.totalRevenues.toStringAsFixed(2),
            label: "الإيرادات الكلية",
            valueColor: colorScheme.primary,
            colorScheme: colorScheme,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required Color valueColor,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 2,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        height: 100,
        margin: EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            SizedBox(height: 10),
            Text("$value ريال",
                style: TextStyle(
                    color: valueColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildNetProfitCard(ReportController controller, ColorScheme colorScheme) {
    bool isNegative = controller.netProfit < 0;
    Color profitColor = isNegative ? colorScheme.error : Colors.green;
    IconData profitIcon = isNegative ? Icons.south_east : Icons.north_east;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10),
      margin: EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: profitColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(profitIcon, color: Colors.white),
          Text("${controller.netProfit.toStringAsFixed(2)} ريال",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          Text("صافي الأرباح الكلي",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildStatsCards(ReportController controller, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Card(
          elevation: 2,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 150,
            height: 70,
            margin: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(controller.totalBusiness.toString(),
                    style: TextStyle(
                        color: Colors.brown,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text("عدد الأعمال",
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 14)),
              ],
            ),
          ),
        ),
        Card(
          elevation: 2,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 150,
            height: 70,
            margin: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(controller.totalWorkers.toString(),
                    style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text("عدد العمال",
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 14)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ========== الرسم البياني الشهري ==========
  Widget _buildMonthlyChart(ReportController controller, ColorScheme colorScheme) {
    if (controller.monthlyExpenses.isEmpty && controller.monthlyRevenues.isEmpty) {
      return Card(
        margin: EdgeInsets.all(10),
        child: Container(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('لا توجد بيانات كافية للرسم البياني'))),
      );
    }

    return Card(
      margin: EdgeInsets.all(10),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(15),
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 المصروفات والإيرادات الشهرية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('📌 الأخضر: الإيرادات | 🔴 الأحمر: المصروفات',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            SizedBox(height: 5),
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxY(controller),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 40)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < controller.monthlyExpenses.length) {
                            String month =
                                controller.monthlyExpenses[index]['month'].toString();
                            return Text(month.substring(5),
                                style: TextStyle(fontSize: 10));
                          }
                          return Text('');
                        },
                        reservedSize: 30,
                      ),
                    ),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _getBarGroups(controller),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxY(ReportController controller) {
    double max = 0;
    for (var expense in controller.monthlyExpenses) {
      if (expense['amount'] > max) max = expense['amount'];
    }
    for (var revenue in controller.monthlyRevenues) {
      if (revenue['amount'] > max) max = revenue['amount'];
    }
    return max * 1.1;
  }

  List<BarChartGroupData> _getBarGroups(ReportController controller) {
    List<BarChartGroupData> groups = [];
    int maxLength = controller.monthlyExpenses.length >
            controller.monthlyRevenues.length
        ? controller.monthlyExpenses.length
        : controller.monthlyRevenues.length;

    for (int i = 0; i < maxLength; i++) {
      double expenseAmount = i < controller.monthlyExpenses.length
          ? controller.monthlyExpenses[i]['amount']
          : 0;
      double revenueAmount = i < controller.monthlyRevenues.length
          ? controller.monthlyRevenues[i]['amount']
          : 0;

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
                toY: expenseAmount,
                color: Colors.red,
                width: 15,
                borderRadius: BorderRadius.circular(4)),
            BarChartRodData(
                toY: revenueAmount,
                color: Colors.green,
                width: 15,
                borderRadius: BorderRadius.circular(4)),
          ],
        ),
      );
    }
    return groups;
  }
}