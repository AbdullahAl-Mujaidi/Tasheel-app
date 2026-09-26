// ignore_for_file: avoid_print
// lib/model/home_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين (home_controller). بيتُّ الحسابات النقية هنا
// (calculateStatsFromLocal / getRecent...) والتنفيذ الفعلي للبيانات في
// features/dashboard/data (قراءة الجداول الموحدة، كاش الإحصائيات، السحاب).
import 'package:fkra/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:fkra/features/dashboard/domain/entities/local_dashboard_data.dart';
import 'package:fkra/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:fkra/core/network/connectivity_service.dart';

class HomeModel {
  final String userId;
  final DashboardRepository _repo = DashboardRepositoryImpl.instance;
  static const String _statsCacheKey = 'home_stats';

  List<Map<String, dynamic>> _localExpenses = [];
  List<Map<String, dynamic>> _localBusinesses = [];
  List<Map<String, dynamic>> _localWorkers = [];

  HomeModel({required this.userId});

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      await _repo.initHomeStorage(userId);
      await _reloadFromRepository();
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<void> _reloadFromRepository() async {
    final LocalDashboardData data = await _repo.loadLocalData(userId);
    _localExpenses = data.expenses;
    _localBusinesses = data.businesses;
    _localWorkers = data.workers;
  }

  Future<Map<String, dynamic>> loadStatsLocally() =>
      _repo.loadStats(userId, _statsCacheKey);

  Future<void> saveStatsLocally(Map<String, dynamic> stats) =>
      _repo.saveStats(userId, _statsCacheKey, stats);

  // إعادة قراءة البيانات المحلية (بعد إضافة مصروف جديد مثلاً)
  Future<void> reloadLocalData() async {
    try {
      await _reloadFromRepository();
    } catch (e) {
      print('خطأ في إعادة تحميل البيانات المحلية: $e');
    }
  }

  Map<String, dynamic> calculateStatsFromLocal() {
    double totalExpenses = _localExpenses.fold<double>(
      0.0,
      (acc, e) => acc + (e['amount'] ?? 0.0),
    );
    double totalRevenues = _localBusinesses.fold<double>(
      0.0,
      (acc, b) => acc + (b['amount'] ?? 0.0),
    );
    double netProfit = totalRevenues - totalExpenses;
    int totalBusiness = _localBusinesses.length;
    int totalWorkers = _localWorkers.length;
    return {
      'totalExpenses': totalExpenses,
      'totalRevenues': totalRevenues,
      'netProfit': netProfit,
      'totalBusiness': totalBusiness,
      'totalWorkers': totalWorkers,
    };
  }

  Future<Map<String, dynamic>> fetchStatsFromFirestore() =>
      _repo.fetchHomeStatsFromFirestore(userId);

  List<Map<String, dynamic>> getRecentBusinesses({int limit = 3}) {
    List<Map<String, dynamic>> list = List.from(_localBusinesses);
    list.sort((a, b) {
      try {
        DateTime dateA = DateTime.parse(a['date'] ?? DateTime.now().toIso8601String());
        DateTime dateB = DateTime.parse(b['date'] ?? DateTime.now().toIso8601String());
        return dateB.compareTo(dateA);
      } catch (_) {
        return 0;
      }
    });
    return list.take(limit).toList();
  }

  List<Map<String, dynamic>> getRecentExpenses({int limit = 3}) {
    List<Map<String, dynamic>> list = List.from(_localExpenses);
    list.sort((a, b) {
      try {
        DateTime dateA = DateTime.parse(a['date'] ?? DateTime.now().toIso8601String());
        DateTime dateB = DateTime.parse(b['date'] ?? DateTime.now().toIso8601String());
        return dateB.compareTo(dateA);
      } catch (_) {
        return 0;
      }
    });
    return list.take(limit).toList();
  }

  Future<bool> hasInternet() => ConnectivityService.hasInternet();
}