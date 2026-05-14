import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class HomePage extends StatefulWidget {
  final Function(int)? changePage;
  final String userId;

  const HomePage({super.key, this.changePage, required this.userId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  double totalExpenses = 0;
  double totalRevenues = 0;
  double netProfit = 0;
  int totalBusiness = 0;
  int totalWorkers = 0;

  bool isLoading = true;
  bool isOffline = false;

  // ملفات التخزين المحلية
  File? _statsFile;
  List<Map<String, dynamic>> _localExpenses = [];
  List<Map<String, dynamic>> _localBusinesses = [];

  Timer? _syncTimer;
  Timer? _statsUpdateTimer;

  @override
  void initState() {
    super.initState();
    _initStorage();
    _checkConnectivity();
    _startPeriodicSync();
    _startPeriodicStatsUpdate();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _statsUpdateTimer?.cancel();
    super.dispose();
  }

  // ==================== تهيئة التخزين في الملفات ====================
  Future<void> _initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String homeDirPath = path.join(appDir.path, 'home_data');

      // إنشاء المجلد إذا لم يكن موجوداً
      final Directory homeDir = Directory(homeDirPath);
      if (!await homeDir.exists()) {
        await homeDir.create(recursive: true);
      }

      // مسار ملف الإحصائيات
      final String statsPath =
          path.join(homeDirPath, 'stats_${widget.userId}.json');
      _statsFile = File(statsPath);

      // مسارات الملفات الأخرى للمزامنة
      final String expensesPath = path.join(
          appDir.path, 'expenses_data', 'expenses_${widget.userId}.json');
      final String businessesPath = path.join(
          appDir.path, 'businesses_data', 'businesses_${widget.userId}.json');
      final String workersPath = path.join(
          appDir.path, 'workers_data', 'workers_${widget.userId}.json');

      final File expensesFile = File(expensesPath);
      final File businessesFile = File(businessesPath);
      final File workersFile = File(workersPath);

      print('📁 مسار ملف الإحصائيات: $statsPath');

      // تحميل البيانات من الملفات
      await _loadLocalStats();

      // تحميل البيانات من المصادر الأخرى
      if (await expensesFile.exists()) {
        final String expensesJson = await expensesFile.readAsString();
        final List<dynamic> expensesList = json.decode(expensesJson);
        _localExpenses = expensesList.cast<Map<String, dynamic>>();
        print('📊 تم تحميل ${_localExpenses.length} مصروف من الملف');
      }

      if (await businessesFile.exists()) {
        final String businessesJson = await businessesFile.readAsString();
        final List<dynamic> businessesList = json.decode(businessesJson);
        _localBusinesses = businessesList.cast<Map<String, dynamic>>();
        print('📊 تم تحميل ${_localBusinesses.length} عمل من الملف');
      }

      if (await workersFile.exists()) {
        final String workersJson = await workersFile.readAsString();
        final List<dynamic> workersList = json.decode(workersJson);
        print('📊 تم تحميل ${workersList.length} عامل من الملف');
      }

      // تحديث الإحصائيات من البيانات المحلية
      _updateStatsFromLocalData();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ خطأ في تهيئة التخزين: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ==================== تحديث الإحصائيات من البيانات المحلية ====================
  void _updateStatsFromLocalData() {
    try {
      // حساب إجمالي المصروفات
      totalExpenses = _localExpenses.fold(
        0,
        (sum, expense) => sum + (expense['amount'] ?? 0),
      );

      // حساب إجمالي الإيرادات (من الأعمال)
      totalRevenues = _localBusinesses.fold(
        0,
        (sum, business) => sum + (business['amount'] ?? 0),
      );

      // حساب صافي الأرباح
      netProfit = totalRevenues - totalExpenses;

      // حساب عدد الأعمال
      totalBusiness = _localBusinesses.length;

      // عدد العمال (سنقوم بتحميله لاحقاً)
      // totalWorkers سيتم تحديثه عند تحميل بيانات العمال

      print('📊 إحصائيات محدثة من البيانات المحلية:');
      print('  - المصروفات: $totalExpenses');
      print('  - الإيرادات: $totalRevenues');
      print('  - الأرباح: $netProfit');
      print('  - عدد الأعمال: $totalBusiness');

      _saveStatsLocally();
    } catch (e) {
      print('❌ خطأ في تحديث الإحصائيات: $e');
    }
  }

  // ==================== تحميل الإحصائيات من الملف ====================
  Future<void> _loadLocalStats() async {
    if (_statsFile == null) return;

    try {
      if (await _statsFile!.exists()) {
        final String jsonString = await _statsFile!.readAsString();
        final Map<String, dynamic> stats = jsonDecode(jsonString);

        setState(() {
          totalExpenses = stats['totalExpenses'] ?? 0;
          totalRevenues = stats['totalRevenues'] ?? 0;
          netProfit = stats['netProfit'] ?? 0;
          totalBusiness = stats['totalBusiness'] ?? 0;
          totalWorkers = stats['totalWorkers'] ?? 0;
        });

        print('📱 تم تحميل الإحصائيات من الملف المحلي');
      }
    } catch (e) {
      print('❌ خطأ في تحميل الإحصائيات من الملف: $e');
    }
  }

  // ==================== حفظ الإحصائيات في الملف ====================
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
      print('💾 تم حفظ الإحصائيات في الملف');
    } catch (e) {
      print('❌ خطأ في حفظ الإحصائيات في الملف: $e');
    }
  }

  // ==================== التحقق من الاتصال بالإنترنت ====================
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(Duration(seconds: 5));
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
    }

    if (hasInternet) {
      await _refreshData();
    }
  }

  // ==================== المزامنة الدورية ====================
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _hasInternet();
      if (hasInternet) {
        await _refreshData();
      }
    });
  }

  // ==================== تحديث الإحصائيات الدوري ====================
  void _startPeriodicStatsUpdate() {
    _statsUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      // تحديث الإحصائيات من البيانات المحلية الحالية
      _updateStatsFromLocalData();
      if (mounted) {
        setState(() {});
      }
    });
  }

  // ==================== تحديث البيانات ====================
  Future<void> _refreshData() async {
    final bool hasInternet = await _hasInternet();

    if (!hasInternet) {
      // إذا لا يوجد إنترنت، اعرض البيانات المحلية فقط
      _updateStatsFromLocalData();
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
      // جلب البيانات من Firestore
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

      // تحديث الإحصائيات
      setState(() {
        totalExpenses = expensesSnapshot.docs.fold(
          0,
          (sum, doc) => sum + (doc['amount'] ?? 0),
        );
        totalRevenues = businessSnapshot.docs.fold(
          0,
          (sum, doc) => sum + (doc['amount'] ?? 0),
        );
        netProfit = totalRevenues - totalExpenses;
        totalBusiness = businessSnapshot.docs.length;
        totalWorkers = workersSnapshot.docs.length;
      });

      // حفظ الإحصائيات محلياً
      await _saveStatsLocally();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم تحديث الإحصائيات'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (error) {
      print("خطأ في جلب البيانات: $error");
      // في حالة الخطأ، استخدم البيانات المحلية
      _updateStatsFromLocalData();

      if (mounted && !isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ حدث خطأ، يتم عرض البيانات المحفوظة'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
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

  // ==================== تحميل بيانات العمال من الملف المحلي ====================
  Future<void> _loadWorkersCount() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String workersPath = path.join(
          appDir.path, 'workers_data', 'workers_${widget.userId}.json');
      final File workersFile = File(workersPath);

      if (await workersFile.exists()) {
        final String workersJson = await workersFile.readAsString();
        final List<dynamic> workersList = json.decode(workersJson);
        setState(() {
          totalWorkers = workersList.length;
        });
        await _saveStatsLocally();
      }
    } catch (e) {
      print('❌ خطأ في تحميل عدد العمال: $e');
    }
  }

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // عرض مؤشر تحميل أثناء تحميل البيانات
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: Icon(Icons.notifications),
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
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              SizedBox(height: 16),
              Text(
                'جاري تحميل البيانات...',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
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
          // زر تحديث يدوي
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
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // إشعار وضع عدم الاتصال
              if (isOffline)
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'وضع غير متصل. يتم عرض آخر البيانات المحفوظة. سيتم تحديث الإحصائيات تلقائياً عند عودة الاتصال.',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 12,
                          ),
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
                    value: totalExpenses.toStringAsFixed(2),
                    label: "المصروفات",
                    valueColor: colorScheme.error,
                    context: context,
                  ),
                  _buildStatCard(
                    icon: Icons.moving,
                    iconColor: colorScheme.primary,
                    value: totalRevenues.toStringAsFixed(2),
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
                    value: netProfit.toStringAsFixed(0),
                    label: "صافي الارباح",
                    valueColor: Colors.orange,
                    context: context,
                  ),
                  _buildStatCard(
                    icon: Icons.card_travel,
                    iconColor: Colors.brown,
                    value: totalBusiness.toString(),
                    label: "اجمالي الاعمال",
                    valueColor: Colors.brown,
                    context: context,
                  ),
                  _buildStatCard(
                    icon: Icons.groups_2,
                    iconColor: colorScheme.primary,
                    value: totalWorkers.toString(),
                    label: "العمال",
                    valueColor: colorScheme.primary,
                    context: context,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // قسم عرض آخر 3 أعمال
              _buildBusinessSection(colorScheme),

              // قسم المصروفات الأخيرة
              _buildExpensesSection(colorScheme),
            ],
          ),
        ),
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
                fontSize:
                    label == "المصروفات" || label == "الايرادات" ? 18 : 15,
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

  // قسم عرض الأعمال (يعمل مع وضع عدم الاتصال)
  Widget _buildBusinessSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  widget.changePage?.call(3);
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
          // عرض الأعمال من البيانات المحلية
          _buildRecentBusinesses(colorScheme),
        ],
      ),
    );
  }

  Widget _buildRecentBusinesses(ColorScheme colorScheme) {
    // ترتيب الأعمال حسب التاريخ وتحديد آخر 3
    List<Map<String, dynamic>> recentBusinesses = List.from(_localBusinesses);
    recentBusinesses.sort((a, b) {
      try {
        DateTime dateA =
            DateTime.parse(a['date'] ?? DateTime.now().toIso8601String());
        DateTime dateB =
            DateTime.parse(b['date'] ?? DateTime.now().toIso8601String());
        return dateB.compareTo(dateA);
      } catch (e) {
        return 0;
      }
    });
    recentBusinesses = recentBusinesses.take(3).toList();

    if (recentBusinesses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.business_center,
              size: 50,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              "لا توجد اعمال حالياً",
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              "اضغط على زر 'اضافة عمل' لإضافة عمل جديد",
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recentBusinesses.length,
      itemBuilder: (context, index) {
        final data = recentBusinesses[index];

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
        } catch (e) {
          date = 'بدون تاريخ';
        }

        Color statusColor = colorScheme.primary;
        if (status == 'مكتمل') {
          statusColor = Colors.green;
        } else if (status == 'ملغي') {
          statusColor = colorScheme.error;
        } else if (status == 'جاري التنفيذ') {
          statusColor = Colors.orange;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Card(
            elevation: 2,
            color: !isSynced
                ? Colors.orange.withOpacity(0.05)
                : colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: !isSynced
                  ? BorderSide(color: Colors.orange, width: 1)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(12),
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
                                child: Icon(
                                  Icons.sync_problem,
                                  color: Colors.orange,
                                  size: 16,
                                ),
                              ),
                            Text(
                              "$amount ريال",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: amount >= 0
                                    ? Colors.green
                                    : colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.right,
                        ),
                        if (description.length > 15)
                          Text(
                            "${description.substring(0, 15)}...",
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // قسم عرض المصروفات (يعمل مع وضع عدم الاتصال)
  Widget _buildExpensesSection(ColorScheme colorScheme) {
    // ترتيب المصروفات حسب التاريخ وتحديد آخر 3
    List<Map<String, dynamic>> recentExpenses = List.from(_localExpenses);
    recentExpenses.sort((a, b) {
      try {
        DateTime dateA =
            DateTime.parse(a['date'] ?? DateTime.now().toIso8601String());
        DateTime dateB =
            DateTime.parse(b['date'] ?? DateTime.now().toIso8601String());
        return dateB.compareTo(dateA);
      } catch (e) {
        return 0;
      }
    });
    recentExpenses = recentExpenses.take(3).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  widget.changePage?.call(2);
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
        recentExpenses.isEmpty
            ? Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt,
                      size: 50,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "لا توجد مصروفات حالياً",
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentExpenses.length,
                itemBuilder: (context, index) {
                  final expense = recentExpenses[index];

                  double amount = (expense['amount'] ?? 0).toDouble();
                  String description = expense['description'] ?? "بدون وصف";
                  bool isSynced = expense['synced'] == 1;

                  String date = '';
                  try {
                    DateTime dateTime = DateTime.parse(expense['date']);
                    date =
                        "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}";
                  } catch (e) {
                    date = 'بدون تاريخ';
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    child: Card(
                      elevation: 2,
                      color: !isSynced
                          ? Colors.orange.withOpacity(0.05)
                          : colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: !isSynced
                            ? BorderSide(color: Colors.orange, width: 1)
                            : BorderSide.none,
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
                                        child: Icon(
                                          Icons.sync_problem,
                                          color: Colors.orange,
                                          size: 16,
                                        ),
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
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
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
