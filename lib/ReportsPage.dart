import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:fl_chart/fl_chart.dart';

class ReportsPage extends StatefulWidget {
  final String userId;
  const ReportsPage({super.key, required this.userId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List<Map<String, dynamic>> topExpenses = [];
  double maxExpenseAmount = 0;
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  double totalExpenses = 0;
  double totalRevenues = 0;
  double netProfit = 0;
  int totalBusiness = 0;
  int totalWorkers = 0;
  bool isLoading = false;
  bool isOffline = false;

  // بيانات أداء اليوم
  double todayExpenses = 0;
  double todayRevenues = 0;
  double todayProfit = 0;

  // بيانات للرسوم البيانية
  List<Map<String, dynamic>> monthlyExpenses = [];
  List<Map<String, dynamic>> monthlyRevenues = [];

  // ملفات التخزين المحلية
  File? _statsFile;
  File? _topExpensesFile;
  File? _businessStatusFile;

  List<Map<String, dynamic>> _localExpenses = [];
  List<Map<String, dynamic>> _localBusinesses = [];
  List<Map<String, dynamic>> _localWorkers = [];

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📱 ReportsPage - Initialized');
    print('👤 UserId: ${widget.userId}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _initStorage();
    _checkConnectivity();
    _startPeriodicSync();
    _loadAllLocalData();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  // ==================== تهيئة التخزين في الملفات ====================
  Future<void> _initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String reportsDirPath = path.join(appDir.path, 'reports_data');

      final Directory reportsDir = Directory(reportsDirPath);
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
        print('📁 تم إنشاء مجلد التقارير: $reportsDirPath');
      }

      final String statsPath =
          path.join(reportsDirPath, 'stats_${widget.userId}.json');
      final String topExpensesPath =
          path.join(reportsDirPath, 'top_expenses_${widget.userId}.json');

      _statsFile = File(statsPath);
      _topExpensesFile = File(topExpensesPath);

      await _loadCachedData();
    } catch (e) {
      print('❌ خطأ في تهيئة التخزين: $e');
    }
  }

  // ==================== تحميل جميع البيانات المحلية ====================
  Future<void> _loadAllLocalData() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();

      final String expensesPath = path.join(
          appDir.path, 'expenses_data', 'expenses_${widget.userId}.json');
      final File expensesFile = File(expensesPath);
      if (await expensesFile.exists()) {
        final String expensesJson = await expensesFile.readAsString();
        final List<dynamic> expensesList = json.decode(expensesJson);
        _localExpenses = expensesList.cast<Map<String, dynamic>>();
        print('📊 تم تحميل ${_localExpenses.length} مصروف من الملف');
      }

      final String businessesPath = path.join(
          appDir.path, 'businesses_data', 'businesses_${widget.userId}.json');
      final File businessesFile = File(businessesPath);
      if (await businessesFile.exists()) {
        final String businessesJson = await businessesFile.readAsString();
        final List<dynamic> businessesList = json.decode(businessesJson);
        _localBusinesses = businessesList.cast<Map<String, dynamic>>();
        print('📊 تم تحميل ${_localBusinesses.length} عمل من الملف');
      }

      final String workersPath = path.join(
          appDir.path, 'workers_data', 'workers_${widget.userId}.json');
      final File workersFile = File(workersPath);
      if (await workersFile.exists()) {
        final String workersJson = await workersFile.readAsString();
        final List<dynamic> workersList = json.decode(workersJson);
        _localWorkers = workersList.cast<Map<String, dynamic>>();
        totalWorkers = _localWorkers.length;
        print('📊 تم تحميل ${_localWorkers.length} عامل من الملف');
      }

      _updateStatsFromLocalData();
      _calculateMonthlyStats();
      _calculateTodayPerformance();
    } catch (e) {
      print('❌ خطأ في تحميل البيانات المحلية: $e');
    }
  }

  // ==================== حساب أداء اليوم ====================
  void _calculateTodayPerformance() {
    final today = DateTime.now();

    todayExpenses = _localExpenses.where((expense) {
      try {
        DateTime expenseDate = DateTime.parse(expense['date']);
        return expenseDate.year == today.year &&
            expenseDate.month == today.month &&
            expenseDate.day == today.day;
      } catch (e) {
        return false;
      }
    }).fold<double>(0.0, (sum, e) => sum + (e['amount'] ?? 0.0));

    todayRevenues = _localBusinesses.where((business) {
      try {
        DateTime businessDate = DateTime.parse(business['date']);
        return businessDate.year == today.year &&
            businessDate.month == today.month &&
            businessDate.day == today.day;
      } catch (e) {
        return false;
      }
    }).fold<double>(0.0, (sum, b) => sum + (b['amount'] ?? 0.0));

    todayProfit = todayRevenues - todayExpenses;
  }

  // ==================== حساب الإحصائيات الشهرية ====================
  void _calculateMonthlyStats() {
    Map<String, double> expensesByMonth = {};
    Map<String, double> revenuesByMonth = {};

    for (var expense in _localExpenses) {
      try {
        DateTime date = DateTime.parse(expense['date']);
        String monthKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}';
        expensesByMonth[monthKey] =
            (expensesByMonth[monthKey] ?? 0) + (expense['amount'] ?? 0);
      } catch (e) {}
    }

    for (var business in _localBusinesses) {
      try {
        DateTime date = DateTime.parse(business['date']);
        String monthKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}';
        revenuesByMonth[monthKey] =
            (revenuesByMonth[monthKey] ?? 0) + (business['amount'] ?? 0);
      } catch (e) {}
    }

    monthlyExpenses = expensesByMonth.entries
        .map((e) => {'month': e.key, 'amount': e.value})
        .toList();
    monthlyRevenues = revenuesByMonth.entries
        .map((e) => {'month': e.key, 'amount': e.value})
        .toList();

    monthlyExpenses.sort((a, b) => a['month'].compareTo(b['month']));
    monthlyRevenues.sort((a, b) => a['month'].compareTo(b['month']));
  }

  // ==================== تحديث الإحصائيات ====================
  void _updateStatsFromLocalData() {
    try {
      totalExpenses = _localExpenses.fold(
        0,
        (sum, expense) => sum + (expense['amount'] ?? 0),
      );

      totalRevenues = _localBusinesses.fold(
        0,
        (sum, business) => sum + (business['amount'] ?? 0),
      );

      netProfit = totalRevenues - totalExpenses;
      totalBusiness = _localBusinesses.length;
      totalWorkers = _localWorkers.length;

      List<Map<String, dynamic>> sortedExpenses = List.from(_localExpenses);
      sortedExpenses
          .sort((a, b) => (b['amount'] ?? 0).compareTo(a['amount'] ?? 0));
      topExpenses = sortedExpenses.take(5).map((expense) {
        return {
          'id': expense['id'],
          'name': expense['description'] ?? 'بدون اسم',
          'amount': (expense['amount'] ?? 0).toDouble(),
          'category': expense['category'] ?? 'أخرى',
          'date': expense['date'],
        };
      }).toList();

      if (topExpenses.isNotEmpty) {
        maxExpenseAmount = topExpenses.first['amount'];
      } else {
        maxExpenseAmount = 0;
      }

      _saveStatsLocally();
      _saveTopExpensesLocally();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ خطأ في تحديث الإحصائيات: $e');
    }
  }

  // ==================== حفظ البيانات في الملفات ====================
  Future<void> _saveStatsLocally() async {
    if (_statsFile == null) return;
    try {
      final statsData = {
        'totalExpenses': totalExpenses,
        'totalRevenues': totalRevenues,
        'netProfit': netProfit,
        'totalBusiness': totalBusiness,
        'totalWorkers': totalWorkers,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      await _statsFile!.writeAsString(jsonEncode(statsData));
    } catch (e) {
      print('❌ خطأ في حفظ الإحصائيات: $e');
    }
  }

  Future<void> _saveTopExpensesLocally() async {
    if (_topExpensesFile == null) return;
    try {
      await _topExpensesFile!.writeAsString(jsonEncode(topExpenses));
    } catch (e) {
      print('❌ خطأ في حفظ أعلى المصروفات: $e');
    }
  }

  // ==================== تحميل البيانات المخزنة ====================
  Future<void> _loadCachedData() async {
    try {
      if (_statsFile != null && await _statsFile!.exists()) {
        final String jsonString = await _statsFile!.readAsString();
        final Map<String, dynamic> stats = jsonDecode(jsonString);
        setState(() {
          totalExpenses = stats['totalExpenses'] ?? 0;
          totalRevenues = stats['totalRevenues'] ?? 0;
          netProfit = stats['netProfit'] ?? 0;
          totalBusiness = stats['totalBusiness'] ?? 0;
          totalWorkers = stats['totalWorkers'] ?? 0;
        });
      }

      if (_topExpensesFile != null && await _topExpensesFile!.exists()) {
        final String jsonString = await _topExpensesFile!.readAsString();
        final List<dynamic> expensesList = jsonDecode(jsonString);
        setState(() {
          topExpenses = expensesList.cast<Map<String, dynamic>>();
          if (topExpenses.isNotEmpty) {
            maxExpenseAmount = topExpenses.first['amount'];
          }
        });
      }
    } catch (e) {
      print('❌ خطأ في تحميل البيانات المخزنة: $e');
    }
  }

  // ==================== التحقق من الاتصال ====================
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkConnectivity() async {
    final hasInternet = await _hasInternet();
    if (mounted) {
      setState(() {
        isOffline = !hasInternet;
      });
      if (hasInternet) {
        await _refreshData();
      }
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _hasInternet();
      if (hasInternet) {
        await _refreshData();
      }
    });
  }

  // ==================== تحديث البيانات ====================
  Future<void> _refreshData() async {
    final bool hasInternet = await _hasInternet();

    if (!hasInternet) {
      await _loadAllLocalData();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 وضع غير متصل - عرض البيانات المحلية'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await fetchStatistics(showLoading: false);
      await _loadAllLocalData();
    } catch (error) {
      print("خطأ: $error");
      if (mounted && !isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ حدث خطأ، يتم عرض البيانات المحفوظة'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ==================== جلب الإحصائيات من Firebase ====================
  Future<void> fetchStatistics({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => isLoading = true);
    }

    try {
      final results = await Future.wait([
        firestore
            .collection('users')
            .doc(widget.userId)
            .collection("expenses")
            .get(),
        firestore
            .collection('users')
            .doc(widget.userId)
            .collection("businesses")
            .get(),
        firestore
            .collection('users')
            .doc(widget.userId)
            .collection("workers")
            .get(),
      ]);

      final expensesSnapshot = results[0];
      final businessSnapshot = results[1];
      final workersSnapshot = results[2];

      _localExpenses = expensesSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'description': doc['description'],
          'amount': doc['amount'],
          'category': doc['category'],
          'date': (doc['date'] as Timestamp).toDate().toIso8601String(),
          'synced': 1,
        };
      }).toList();

      _localBusinesses = businessSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc['name'],
          'description': doc['description'],
          'amount': doc['amount'],
          'status': doc['status'],
          'date': (doc['date'] as Timestamp).toDate().toIso8601String(),
          'synced': 1,
        };
      }).toList();

      _localWorkers = workersSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc['name'],
          'phone': doc['phone'],
          'specialization': doc['specialization'],
          'salary': doc['salary'],
          'date': (doc['date'] as Timestamp).toDate().toIso8601String(),
          'synced': 1,
        };
      }).toList();

      totalWorkers = _localWorkers.length;

      _updateStatsFromLocalData();
      _calculateMonthlyStats();
      _calculateTodayPerformance();
    } catch (error) {
      print("خطأ: $error");
      await _loadAllLocalData();
      _updateStatsFromLocalData();
    }

    if (showLoading && mounted) {
      setState(() => isLoading = false);
    }
  }

  // ==================== دوال الرسم البياني ====================
  double _getMaxY() {
    double max = 0;
    for (var expense in monthlyExpenses) {
      if (expense['amount'] > max) max = expense['amount'];
    }
    for (var revenue in monthlyRevenues) {
      if (revenue['amount'] > max) max = revenue['amount'];
    }
    return max * 1.1;
  }

  List<BarChartGroupData> _getBarGroups() {
    List<BarChartGroupData> groups = [];
    int maxLength = monthlyExpenses.length > monthlyRevenues.length
        ? monthlyExpenses.length
        : monthlyRevenues.length;

    for (int i = 0; i < maxLength; i++) {
      double expenseAmount =
          i < monthlyExpenses.length ? monthlyExpenses[i]['amount'] : 0;
      double revenueAmount =
          i < monthlyRevenues.length ? monthlyRevenues[i]['amount'] : 0;

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

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
              await _refreshData();
            },
            icon: Icon(Icons.refresh, color: colorScheme.primary),
            tooltip: 'تحديث البيانات',
          ),
          if (isOffline)
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
        onRefresh: _refreshData,
        child: isLoading
            ? Center(
                child: CircularProgressIndicator(color: colorScheme.primary))
            : SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    if (isOffline)
                      Container(
                        margin:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'وضع غير متصل. يتم عرض آخر البيانات المحفوظة. سيتم تحديث التقارير تلقائياً عند عودة الاتصال.',
                                style: TextStyle(
                                    color: Colors.orange[700], fontSize: 12),
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

                    // أداء اليوم
                    _buildTodayPerformanceCard(colorScheme),

                    // البطاقات المالية
                    _buildFinancialCards(colorScheme),
                    _buildNetProfitCard(colorScheme),
                    _buildStatsCards(colorScheme),

                    // الرسم البياني الشهري
                    _buildMonthlyChart(colorScheme),
                  ],
                ),
              ),
      ),
    );
  }

  // ==================== بطاقة أداء اليوم ====================
  Widget _buildTodayPerformanceCard(ColorScheme colorScheme) {
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
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.today, color: colorScheme.primary, size: 24),
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
                      color: todayProfit >= 0
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${todayProfit.toStringAsFixed(2)} ريال',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: todayProfit >= 0 ? Colors.green : Colors.red,
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
                          todayProfit >= 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 20,
                          color: todayProfit >= 0 ? Colors.green : Colors.red,
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
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${todayRevenues.toStringAsFixed(2)} ريال',
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
                        Icon(
                          Icons.arrow_upward,
                          size: 20,
                          color: Colors.green,
                        ),
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
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${todayExpenses.toStringAsFixed(2)} ريال',
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
                        Icon(
                          Icons.arrow_downward,
                          size: 20,
                          color: Colors.red,
                        ),
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

  // ==================== واجهات العرض الأخرى ====================

  Widget _buildFinancialCards(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatCard(
          icon: Icons.trending_down,
          iconColor: colorScheme.error,
          value: totalExpenses.toStringAsFixed(2),
          label: "المصروفات الكلية",
          valueColor: colorScheme.error,
          colorScheme: colorScheme,
        ),
        _buildStatCard(
          icon: Icons.moving,
          iconColor: colorScheme.primary,
          value: totalRevenues.toStringAsFixed(2),
          label: "الإيرادات الكلية",
          valueColor: colorScheme.primary,
          colorScheme: colorScheme,
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
        width: 160,
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
                color: iconColor.withOpacity(0.1),
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

  Widget _buildNetProfitCard(ColorScheme colorScheme) {
    bool isNegative = netProfit < 0;
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
          Text("${netProfit.toStringAsFixed(2)} ريال",
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

  Widget _buildStatsCards(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Card(
          elevation: 2,
          color: colorScheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 150,
            height: 70,
            margin: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(totalBusiness.toString(),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 150,
            height: 70,
            margin: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(totalWorkers.toString(),
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

  Widget _buildMonthlyChart(ColorScheme colorScheme) {
    if (monthlyExpenses.isEmpty && monthlyRevenues.isEmpty) {
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
                  maxY: _getMaxY(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 40)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < monthlyExpenses.length) {
                            String month =
                                monthlyExpenses[index]['month'].toString();
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
                  barGroups: _getBarGroups(),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
