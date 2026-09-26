// lib/features/dashboard/data/repositories/dashboard_repository_impl.dart
// تنفيذ عقد DashboardRepository بتنسيق المصدر البعيد والمحلي.
// سلوك كل طريقة منقول حرفياً من HomeModel/ReportModel القديمين مع
// إزالة تكرار قراءة الجداول الموحدة (كانت تتكرر في 6 مواضع).
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/local_dashboard_data.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_local_datasource.dart';
import '../datasources/dashboard_remote_datasource.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl._();
  static final DashboardRepositoryImpl instance = DashboardRepositoryImpl._();

  final DashboardLocalDataSource _local = DashboardLocalDataSource.instance;
  final DashboardRemoteDataSource _remote = DashboardRemoteDataSource.instance;

  // ========== ترحيل الكاش القديم ==========

  @override
  Future<void> initHomeStorage(String userId) =>
      _local.initHomeStorage(userId);

  @override
  Future<void> initReportStorage(String userId) =>
      _local.initReportStorage(userId);

  // ========== قراءة الجداول الموحدة ==========

  @override
  Future<LocalDashboardData> loadLocalData(String userId) =>
      _local.loadLocalData(userId);

  // ========== كاش الإحصائيات ==========

  @override
  Future<Map<String, dynamic>> loadStats(String userId, String cacheKey) =>
      _local.loadStats(userId, cacheKey);

  @override
  Future<void> saveStats(
          String userId, String cacheKey, Map<String, dynamic> stats) =>
      _local.saveStats(userId, cacheKey, stats);

  @override
  Future<List<Map<String, dynamic>>> loadCacheList(
          String userId, String cacheKey) =>
      _local.loadCacheList(userId, cacheKey);

  @override
  Future<void> saveCacheList(String userId, String cacheKey,
          List<Map<String, dynamic>> list) =>
      _local.saveCacheList(userId, cacheKey, list);

  // ========== الجلب من السحاب ==========

  @override
  Future<Map<String, dynamic>> fetchHomeStatsFromFirestore(
      String userId) async {
    // جلب كل مجموعة على حدة: إن رُفضت قراءة مجموعة (مثل المصروفات/العمال
    // لتابع لا يملك صلاحية قراءتهما) تُستثنى دون أن تُسقط بقية الإحصائيات.
    double totalExpenses = 0;
    double totalRevenues = 0;
    int totalBusiness = 0;
    int totalWorkers = 0;

    try {
      final expensesDocs = await _remote.fetchCollection(userId, 'expenses');
      totalExpenses = expensesDocs.fold<double>(
        0.0,
        (acc, doc) => acc + (doc['amount'] ?? 0.0),
      );
    } catch (_) {
      // لا صلاحية لقراءة المصروفات: تبقى صفراً دون إفشال الباقي.
    }

    try {
      final businessDocs = await _remote.fetchCollection(userId, 'businesses');
      totalRevenues = businessDocs.fold<double>(
        0.0,
        (acc, doc) => acc + (doc['amount'] ?? 0.0),
      );
      totalBusiness = businessDocs.length;
    } catch (_) {
      // لا صلاحية لقراءة الأعمال.
    }

    try {
      final workersDocs = await _remote.fetchCollection(userId, 'workers');
      totalWorkers = workersDocs.length;
    } catch (_) {
      // لا صلاحية لقراءة العمال.
    }

    double netProfit = totalRevenues - totalExpenses;

    return {
      'totalExpenses': totalExpenses,
      'totalRevenues': totalRevenues,
      'netProfit': netProfit,
      'totalBusiness': totalBusiness,
      'totalWorkers': totalWorkers,
    };
  }

  @override
  Future<LocalDashboardData> fetchReportDataFromFirestore(
      String userId) async {
    final results = await Future.wait([
      _remote.fetchCollection(userId, 'expenses'),
      _remote.fetchCollection(userId, 'businesses'),
      _remote.fetchCollection(userId, 'workers'),
    ]);

    final expensesSnapshot = results[0];
    final businessSnapshot = results[1];
    final workersSnapshot = results[2];

    final expenses = expensesSnapshot.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'description': data['description'],
        'amount': data['amount'],
        'category': data['category'],
        'date': (data['date'] as Timestamp).toDate().toIso8601String(),
        'synced': 1,
      };
    }).toList();

    final businesses = businessSnapshot.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'],
        'description': data['description'],
        'amount': data['amount'],
        'status': data['status'],
        'date': (data['date'] as Timestamp).toDate().toIso8601String(),
        'synced': 1,
      };
    }).toList();

    final workers = workersSnapshot.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'],
        'phone': data['phone'],
        'specialization': data['specialization'],
        'salary': data['salary'],
        'date': (data['date'] as Timestamp).toDate().toIso8601String(),
        'synced': 1,
      };
    }).toList();

    return (expenses: expenses, businesses: businesses, workers: workers);
  }
}