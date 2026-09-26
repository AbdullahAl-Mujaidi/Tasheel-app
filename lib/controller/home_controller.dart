// ignore_for_file: avoid_print
// lib/controllers/home_controller.dart
import 'dart:async';
import 'package:fkra/model/home_model.dart';
import 'package:flutter/material.dart';

class HomeController extends ChangeNotifier {
  final String userId;
  final HomeModel _model;

  // الإحصائيات
  double totalExpenses = 0;
  double totalRevenues = 0;
  double netProfit = 0;
  int totalBusiness = 0;
  int totalWorkers = 0;

  // حالة الاتصال والتحميل
  bool isOffline = false;
  bool isLoading = true;

  // قوائم آخر العناصر
  List<Map<String, dynamic>> recentBusinesses = [];
  List<Map<String, dynamic>> recentExpenses = [];

  Timer? _syncTimer;
  Timer? _statsUpdateTimer;

  HomeController({required this.userId}) : _model = HomeModel(userId: userId) {
    _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    await _loadCachedStats();
    _updateRecentItems();
    await _checkConnectivity();
    _startPeriodicSync();
    _startPeriodicStatsUpdate();
    isLoading = false;
    notifyListeners();
  }

  // ========== تحميل الإحصائيات المخزنة ==========
  Future<void> _loadCachedStats() async {
    final stats = await _model.loadStatsLocally();
    if (stats.isNotEmpty) {
      totalExpenses = stats['totalExpenses'] ?? 0;
      totalRevenues = stats['totalRevenues'] ?? 0;
      netProfit = stats['netProfit'] ?? 0;
      totalBusiness = stats['totalBusiness'] ?? 0;
      totalWorkers = stats['totalWorkers'] ?? 0;
    } else {
      // حساب من البيانات المحلية
      final localStats = _model.calculateStatsFromLocal();
      totalExpenses = localStats['totalExpenses'];
      totalRevenues = localStats['totalRevenues'];
      netProfit = localStats['netProfit'];
      totalBusiness = localStats['totalBusiness'];
      totalWorkers = localStats['totalWorkers'];
      await _saveCurrentStats();
    }
  }

  Future<void> _saveCurrentStats() async {
    await _model.saveStatsLocally({
      'totalExpenses': totalExpenses,
      'totalRevenues': totalRevenues,
      'netProfit': netProfit,
      'totalBusiness': totalBusiness,
      'totalWorkers': totalWorkers,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  void _updateRecentItems() {
    recentBusinesses = _model.getRecentBusinesses(limit: 3);
    recentExpenses = _model.getRecentExpenses(limit: 3);
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

  // ========== المزامنة الدورية ==========
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        await refreshData();
      }
    });
  }

  void _startPeriodicStatsUpdate() {
    _statsUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      // إعادة قراءة الملفات المحلية ثم تحديث الإحصائيات من البيانات المحلية الحالية
      await _model.reloadLocalData();
      final localStats = _model.calculateStatsFromLocal();
      totalExpenses = localStats['totalExpenses'];
      totalRevenues = localStats['totalRevenues'];
      netProfit = localStats['netProfit'];
      totalBusiness = localStats['totalBusiness'];
      totalWorkers = localStats['totalWorkers'];
      _updateRecentItems();
      notifyListeners();
    });
  }

  // ========== تحديث البيانات (يدوي أو تلقائي) ==========
  Future<void> refreshData() async {
    final hasInternet = await _model.hasInternet();
    if (!hasInternet) {
      // استخدام البيانات المحلية (بعد إعادة قراءة الملفات)
      await _model.reloadLocalData();
      final localStats = _model.calculateStatsFromLocal();
      totalExpenses = localStats['totalExpenses'];
      totalRevenues = localStats['totalRevenues'];
      netProfit = localStats['netProfit'];
      totalBusiness = localStats['totalBusiness'];
      totalWorkers = localStats['totalWorkers'];
      _updateRecentItems();
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      final stats = await _model.fetchStatsFromFirestore();
      totalExpenses = stats['totalExpenses'];
      totalRevenues = stats['totalRevenues'];
      netProfit = stats['netProfit'];
      totalBusiness = stats['totalBusiness'];
      totalWorkers = stats['totalWorkers'];
      await _saveCurrentStats();
      // تحديث القوائم المحلية (سيتم تحديثها من النموذج)
      _updateRecentItems();
    } catch (e) {
      print('خطأ في تحديث البيانات: $e');
      // الرجوع إلى البيانات المحلية
      await _model.reloadLocalData();
      final localStats = _model.calculateStatsFromLocal();
      totalExpenses = localStats['totalExpenses'];
      totalRevenues = localStats['totalRevenues'];
      netProfit = localStats['netProfit'];
      totalBusiness = localStats['totalBusiness'];
      totalWorkers = localStats['totalWorkers'];
      _updateRecentItems();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ========== مزامنة يدوية (للزر) ==========
  Future<void> syncNow() async {
    await refreshData();
  }

  // ========== التنظيف ==========
  @override
  void dispose() {
    _syncTimer?.cancel();
    _statsUpdateTimer?.cancel();
    super.dispose();
  }
}