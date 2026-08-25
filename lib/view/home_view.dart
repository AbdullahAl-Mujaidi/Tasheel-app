// lib/views/home_view.dart
import 'package:fkra/controller/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePage extends StatelessWidget {
  final Function(int)? changePage;
  final String userId;

  const HomePage({super.key, this.changePage, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeController(userId: userId),
      child: Consumer<HomeController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;

          if (controller.isLoading) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    SizedBox(height: 16),
                    Text('جاري تحميل البيانات...',
                        style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(
                "تساهيل",
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
                          content: Text('تم تحديث الإحصائيات'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 1),
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
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange, size: 18),
                            SizedBox(width: 4),
                            Text(
                              'غير متصل',
                              style: TextStyle(color: Colors.orange, fontSize: 11),
                            ),
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
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'وضع غير متصل. يتم عرض آخر البيانات المحفوظة. سيتم تحديث الإحصائيات تلقائياً عند عودة الاتصال.',
                                style: TextStyle(color: Colors.orange[700], fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // صف الكروت العلوي (المصروفات والإيرادات)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildStatCard(
                          icon: Icons.trending_down,
                          iconColor: colorScheme.error,
                          value: controller.totalExpenses.toStringAsFixed(2),
                          label: "المصروفات",
                          valueColor: colorScheme.error,
                          context: context,
                        ),
                        _buildStatCard(
                          icon: Icons.moving,
                          iconColor: colorScheme.primary,
                          value: controller.totalRevenues.toStringAsFixed(2),
                          label: "الايرادات",
                          valueColor: colorScheme.primary,
                          context: context,
                        ),
                      ],
                    ),
                    // صف الكروت السفلي
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildStatCard(
                          icon: Icons.leaderboard,
                          iconColor: Colors.orange,
                          value: controller.netProfit.toStringAsFixed(0),
                          label: "صافي الارباح",
                          valueColor: Colors.orange,
                          context: context,
                        ),
                        _buildStatCard(
                          icon: Icons.card_travel,
                          iconColor: Colors.brown,
                          value: controller.totalBusiness.toString(),
                          label: "اجمالي الاعمال",
                          valueColor: Colors.brown,
                          context: context,
                        ),
                        _buildStatCard(
                          icon: Icons.groups_2,
                          iconColor: colorScheme.primary,
                          value: controller.totalWorkers.toString(),
                          label: "العمال",
                          valueColor: colorScheme.primary,
                          context: context,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // قسم الأعمال الأخيرة
                    _buildBusinessSection(controller, colorScheme, context),
                    // قسم المصروفات الأخيرة
                    _buildExpensesSection(controller, colorScheme, context),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required Color valueColor,
    required BuildContext context,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: label == "المصروفات" || label == "الايرادات" ? 160 : 100,
        height: 100,
        margin: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              "$value ريال",
              style: TextStyle(
                color: valueColor,
                fontSize: label == "المصروفات" || label == "الايرادات" ? 18 : 15,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessSection(
    HomeController controller,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  // الانتقال إلى صفحة الأعمال (index 3)
                  // نفترض أن changePage موجود
                  if (controller.changePage != null) {
                    // نحتاج إلى تمرير changePage من الخارج
                    // ولكننا في هذه الحالة يمكننا استخدام context للوصول إلى الـ Scaffold أو الـ Navigator
                    // أفضل طريقة هي تمرير changePage عبر الـ constructor
                  }
                },
                child: Text(
                  "عرض الكل",
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                "الاعمال الاخيره",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          _buildRecentBusinesses(controller, colorScheme),
        ],
      ),
    );
  }

  Widget _buildRecentBusinesses(HomeController controller, ColorScheme colorScheme) {
    final businesses = controller.recentBusinesses;
    if (businesses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.business_center, size: 50, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              "لا توجد اعمال حالياً",
              style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: businesses.length,
      itemBuilder: (context, index) {
        final data = businesses[index];
        String name = data['name'] ?? 'بدون اسم';
        double amount = (data['amount'] ?? 0).toDouble();
        String status = data['status'] ?? 'قيد الانتظار';
        String description = data['description'] ?? 'بدون وصف';
        bool isSynced = data['synced'] == 1;
        String date = '';
        try {
          DateTime dateTime = DateTime.parse(data['date']);
          date =
              "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}";
        } catch (_) {
          date = 'بدون تاريخ';
        }
        Color statusColor = colorScheme.primary;
        if (status == 'مكتمل') statusColor = Colors.green;
        else if (status == 'ملغي') statusColor = colorScheme.error;
        else if (status == 'جاري التنفيذ') statusColor = Colors.orange;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Card(
            elevation: 2,
            color: !isSynced ? Colors.orange.withOpacity(0.05) : colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: !isSynced ? BorderSide(color: Colors.orange, width: 1) : BorderSide.none,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          if (!isSynced)
                            Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.sync_problem, color: Colors.orange, size: 16),
                            ),
                          Text(
                            "$amount ريال",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: amount >= 0 ? Colors.green : colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        date,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                        textAlign: TextAlign.right,
                      ),
                      if (description.length > 15)
                        Text(
                          "${description.substring(0, 15)}...",
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        )
                      else
                        Text(
                          description,
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpensesSection(
    HomeController controller,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    final expenses = controller.recentExpenses;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  // الانتقال إلى صفحة المصروفات
                },
                child: Text(
                  "عرض الكل",
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                "المصروفات الاخيره",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        expenses.isEmpty
            ? Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.receipt, size: 50, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text(
                      "لا توجد مصروفات حالياً",
                      style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: expenses.length,
                itemBuilder: (context, index) {
                  final expense = expenses[index];
                  double amount = (expense['amount'] ?? 0).toDouble();
                  String description = expense['description'] ?? "بدون وصف";
                  bool isSynced = expense['synced'] == 1;
                  String date = '';
                  try {
                    DateTime dateTime = DateTime.parse(expense['date']);
                    date =
                        "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}";
                  } catch (_) {
                    date = 'بدون تاريخ';
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    child: Card(
                      elevation: 2,
                      color: !isSynced ? Colors.orange.withOpacity(0.05) : colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: !isSynced ? BorderSide(color: Colors.orange, width: 1) : BorderSide.none,
                      ),
                      child: Container(
                        width: double.infinity,
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    if (!isSynced)
                                      Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Icon(Icons.sync_problem, color: Colors.orange, size: 16),
                                      ),
                                    Text(
                                      "$amount ريال",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  date,
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            Expanded(
                              child: Text(
                                description,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }
}