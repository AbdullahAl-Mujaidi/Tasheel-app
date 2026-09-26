// lib/features/dashboard/data/datasources/dashboard_local_datasource.dart
// المسؤول الوحيد عن التخزين المحلي للوحة البداية والتقارير: ترحيل كاش
// JSON القديم، قراءة الجداول الموحدة (مصروفات/أعمال/عمال)، وعمليات كاش
// الإحصائيات في SQLite. منقول حرفياً من HomeModel/ReportModel القديمين.
import 'dart:io';

import 'package:fkra/core/constants/app_constants.dart';
import 'package:fkra/db/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/local_dashboard_data.dart';

class DashboardLocalDataSource {
  DashboardLocalDataSource._();
  static final DashboardLocalDataSource instance =
      DashboardLocalDataSource._();

  /// كاش الصفحة الرئيسية: ترحيل ملف `stats_<uid>.json` القديم إن وُجد.
  Future<void> initHomeStorage(String userId) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String homeDirPath = path.join(appDir.path, 'home_data');
    await DatabaseHelper.instance.migrateJsonToCache(
      userId,
      'home_stats',
      path.join(homeDirPath, 'stats_$userId.json'),
    );
  }

  /// كاش التقارير: ترحيل ملفي stats وtop_expenses القديمين إن وُجدا.
  Future<void> initReportStorage(String userId) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String reportsDirPath = path.join(appDir.path, 'reports_data');
    await DatabaseHelper.instance.migrateJsonToCache(
      userId,
      'report_stats',
      path.join(reportsDirPath, 'stats_$userId.json'),
    );
    await DatabaseHelper.instance.migrateJsonToCache(
      userId,
      'top_expenses',
      path.join(reportsDirPath, 'top_expenses_$userId.json'),
    );
  }

  /// قراءة الجداول الموحدة الثلاثة في عملية واحدة.
  Future<LocalDashboardData> loadLocalData(String userId) async {
    final db = DatabaseHelper.instance;
    final expenses = await db.loadAll(LocalTables.expenses, userId);
    final businesses = await db.loadAll(LocalTables.businesses, userId);
    final workers = await db.loadAll(LocalTables.workers, userId);
    return (expenses: expenses, businesses: businesses, workers: workers);
  }

  // ========== كاش الإحصائيات ==========

  Future<Map<String, dynamic>> loadStats(String userId, String cacheKey) async {
    try {
      final stats = await DatabaseHelper.instance.getCache(userId, cacheKey);
      if (stats != null) return stats;
    } catch (_) {}
    return {};
  }

  Future<void> saveStats(
      String userId, String cacheKey, Map<String, dynamic> stats) async {
    try {
      await DatabaseHelper.instance.setCache(userId, cacheKey, stats);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadCacheList(
      String userId, String cacheKey) async {
    try {
      return await DatabaseHelper.instance.getCacheList(userId, cacheKey);
    } catch (_) {}
    return [];
  }

  Future<void> saveCacheList(
      String userId, String cacheKey, List<Map<String, dynamic>> list) async {
    try {
      await DatabaseHelper.instance.setCacheList(userId, cacheKey, list);
    } catch (_) {}
  }
}