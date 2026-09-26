// ignore_for_file: avoid_print
// lib/model/report_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين (report_controller). التنفيذ الفعلي للبيانات في
// features/dashboard/data (قراءة الجداول الموحدة، كاش الإحصائيات، السحاب).
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:fkra/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:fkra/features/dashboard/domain/entities/local_dashboard_data.dart';
import 'package:fkra/features/dashboard/domain/repositories/dashboard_repository.dart';

class ReportModel {
  final String userId;
  final DashboardRepository _repo = DashboardRepositoryImpl.instance;
  static const String _statsCacheKey = 'report_stats';
  static const String _topExpensesCacheKey = 'top_expenses';

  List<Map<String, dynamic>> _localExpenses = [];
  List<Map<String, dynamic>> _localBusinesses = [];
  List<Map<String, dynamic>> _localWorkers = [];

  ReportModel({required this.userId});

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      await _repo.initReportStorage(userId);
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  // تحميل جميع البيانات المحلية (المصروفات، الأعمال، العمال) من القاعدة
  Future<void> loadAllLocalData() async {
    try {
      await _loadFromRepository();
    } catch (e) {
      print('خطأ في تحميل البيانات المحلية: $e');
      rethrow;
    }
  }

  Future<void> _loadFromRepository() async {
    final LocalDashboardData data = await _repo.loadLocalData(userId);
    _localExpenses = data.expenses;
    _localBusinesses = data.businesses;
    _localWorkers = data.workers;
  }

  // حفظ الإحصائيات محلياً
  Future<void> saveStatsLocally(Map<String, dynamic> stats) =>
      _repo.saveStats(userId, _statsCacheKey, stats);

  // حفظ أعلى المصروفات محلياً
  Future<void> saveTopExpensesLocally(
          List<Map<String, dynamic>> topExpenses) =>
      _repo.saveCacheList(userId, _topExpensesCacheKey, topExpenses);

  // تحميل البيانات المخزنة مؤقتاً
  Future<Map<String, dynamic>> loadCachedStats() =>
      _repo.loadStats(userId, _statsCacheKey);

  Future<List<Map<String, dynamic>>> loadCachedTopExpenses() =>
      _repo.loadCacheList(userId, _topExpensesCacheKey);

  // ========== جلب البيانات من Firebase ==========
  Future<void> fetchAllDataFromFirestore() async {
    try {
      final LocalDashboardData data =
          await _repo.fetchReportDataFromFirestore(userId);
      _localExpenses = data.expenses;
      _localBusinesses = data.businesses;
      _localWorkers = data.workers;
    } catch (e) {
      print('خطأ في جلب البيانات من Firestore: $e');
      rethrow;
    }
  }

  // ========== دوال مساعدة ==========
  Future<bool> hasInternet() => ConnectivityService.hasInternet();

  // ========== Getters للبيانات المحلية ==========
  List<Map<String, dynamic>> get localExpenses => _localExpenses;
  List<Map<String, dynamic>> get localBusinesses => _localBusinesses;
  List<Map<String, dynamic>> get localWorkers => _localWorkers;
}