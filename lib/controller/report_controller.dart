// ignore_for_file: avoid_print
// lib/controllers/report_controller.dart
import 'dart:async';
import 'package:fkra/model/report_model.dart';
import 'package:fkra/services/analytics_service.dart';
import 'package:flutter/material.dart';

class ReportController extends ChangeNotifier {
  final String userId;
  final ReportModel _model;

  // الحالة الأساسية
  bool isLoading = false;
  bool isOffline = false;

  // الإحصائيات العامة
  double totalExpenses = 0;
  double totalRevenues = 0;
  double netProfit = 0;
  int totalBusiness = 0;
  int totalWorkers = 0;

  // أداء اليوم
  double todayExpenses = 0;
  double todayRevenues = 0;
  double todayProfit = 0;

  // أعلى المصروفات
  List<Map<String, dynamic>> topExpenses = [];
  double maxExpenseAmount = 0;

  // بيانات المخططات الشهرية
  List<Map<String, dynamic>> monthlyExpenses = [];
  List<Map<String, dynamic>> monthlyRevenues = [];

  Timer? _syncTimer;

  ReportController({required this.userId}) : _model = ReportModel(userId: userId) {
    _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    await _checkConnectivity();
    await _loadAllData();
    _startPeriodicSync();
  }

  // ========== الاتصال ==========
  Future<void> _checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
    if (hasInternet) {
      await refreshData();
    }
  }

  // ========== تحميل جميع البيانات ==========
  Future<void> _loadAllData() async {
    isLoading = true;
    notifyListeners();

    try {
      await _model.loadAllLocalData();
      _updateStatsFromLocalData();
      _calculateMonthlyStats();
      _calculateTodayPerformance();
      await AnalyticsService.instance.logReportGenerated(type: 'general');

      // تحميل البيانات المخزنة مؤقتاً إذا لم توجد محلية
      if (totalExpenses == 0 && totalRevenues == 0) {
        final cachedStats = await _model.loadCachedStats();
        if (cachedStats.isNotEmpty) {
          totalExpenses = cachedStats['totalExpenses'] ?? 0;
          totalRevenues = cachedStats['totalRevenues'] ?? 0;
          netProfit = cachedStats['netProfit'] ?? 0;
          totalBusiness = cachedStats['totalBusiness'] ?? 0;
          totalWorkers = cachedStats['totalWorkers'] ?? 0;
        }

        final cachedTop = await _model.loadCachedTopExpenses();
        if (cachedTop.isNotEmpty) {
          topExpenses = cachedTop;
          maxExpenseAmount = topExpenses.isNotEmpty ? topExpenses.first['amount'] : 0;
        }
      }
    } catch (e) {
      print('خطأ في تحميل البيانات: $e');
    }

    isLoading = false;
    notifyListeners();
  }

  // ========== تحديث الإحصائيات من البيانات المحلية ==========
  void _updateStatsFromLocalData() {
    final expenses = _model.localExpenses;
    final businesses = _model.localBusinesses;
    final workers = _model.localWorkers;

    totalExpenses = expenses.fold(
        0, (sum, e) => sum + (e['amount'] ?? 0));
    totalRevenues = businesses.fold(
        0, (sum, b) => sum + (b['amount'] ?? 0));
    netProfit = totalRevenues - totalExpenses;
    totalBusiness = businesses.length;
    totalWorkers = workers.length;

    // أعلى المصروفات
    List<Map<String, dynamic>> sorted = List.from(expenses);
    sorted.sort((a, b) => (b['amount'] ?? 0).compareTo(a['amount'] ?? 0));
    topExpenses = sorted.take(5).map((expense) {
      return {
        'id': expense['id'],
        'name': expense['description'] ?? 'بدون اسم',
        'amount': (expense['amount'] ?? 0).toDouble(),
        'category': expense['category'] ?? 'أخرى',
        'date': expense['date'],
      };
    }).toList();

    maxExpenseAmount = topExpenses.isNotEmpty ? topExpenses.first['amount'] : 0;

    // حفظ البيانات محلياً
    _saveStatsLocally();
    _saveTopExpensesLocally();
  }

  // ========== حساب أداء اليوم ==========
  void _calculateTodayPerformance() {
    final today = DateTime.now();

    todayExpenses = _model.localExpenses.where((expense) {
      try {
        DateTime d = DateTime.parse(expense['date']);
        return d.year == today.year &&
            d.month == today.month &&
            d.day == today.day;
      } catch (_) {
        return false;
      }
    }).fold<double>(0.0, (sum, e) => sum + (e['amount'] ?? 0.0));

    todayRevenues = _model.localBusinesses.where((business) {
      try {
        DateTime d = DateTime.parse(business['date']);
        return d.year == today.year &&
            d.month == today.month &&
            d.day == today.day;
      } catch (_) {
        return false;
      }
    }).fold<double>(0.0, (sum, b) => sum + (b['amount'] ?? 0.0));

    todayProfit = todayRevenues - todayExpenses;
  }

  // ========== حساب الإحصائيات الشهرية ==========
  void _calculateMonthlyStats() {
    Map<String, double> expensesByMonth = {};
    Map<String, double> revenuesByMonth = {};

    for (var expense in _model.localExpenses) {
      try {
        DateTime d = DateTime.parse(expense['date']);
        String key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        expensesByMonth[key] = (expensesByMonth[key] ?? 0) + (expense['amount'] ?? 0);
      } catch (_) {}
    }

    for (var business in _model.localBusinesses) {
      try {
        DateTime d = DateTime.parse(business['date']);
        String key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        revenuesByMonth[key] = (revenuesByMonth[key] ?? 0) + (business['amount'] ?? 0);
      } catch (_) {}
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

  // ========== حفظ البيانات محلياً ==========
  Future<void> _saveStatsLocally() async {
    final stats = {
      'totalExpenses': totalExpenses,
      'totalRevenues': totalRevenues,
      'netProfit': netProfit,
      'totalBusiness': totalBusiness,
      'totalWorkers': totalWorkers,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    await _model.saveStatsLocally(stats);
  }

  Future<void> _saveTopExpensesLocally() async {
    await _model.saveTopExpensesLocally(topExpenses);
  }

  // ========== المزامنة الدورية ==========
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        await refreshData();
      }
    });
  }

  // ========== تحديث البيانات (للزر أو السحب للأسفل) ==========
  Future<void> refreshData() async {
    final hasInternet = await _model.hasInternet();

    if (!hasInternet) {
      await _loadAllData();
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      await _model.fetchAllDataFromFirestore();
      await _model.loadAllLocalData();
      _updateStatsFromLocalData();
      _calculateMonthlyStats();
      _calculateTodayPerformance();
      notifyListeners();
    } catch (e) {
      print('خطأ في تحديث البيانات: $e');
      await _loadAllData();
      notifyListeners();
    }

    isLoading = false;
    notifyListeners();
  }

  // ========== التنظيف ==========
  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}