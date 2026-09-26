// lib/features/workers/data/datasources/worker_local_datasource.dart
// المسؤول الوحيد عن التخزين المحلي لجدول العمال: ترحيل JSON القديمة
// وعمليات SQLite عبر DatabaseHelper وتطبيع الحقول الافتراضية.
// منقولة حرفياً من WorkersModel القديم.
import 'dart:io';

import 'package:fkra/db/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/worker_normalizer.dart';

class WorkerLocalDataSource {
  WorkerLocalDataSource._();
  static final WorkerLocalDataSource instance = WorkerLocalDataSource._();

  /// ترحيل الملف القديم إلى SQLite إن وُجد (idempotent وآمن).
  Future<void> initStorage(String userId) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String workersDirPath = path.join(appDir.path, 'workers_data');
    await DatabaseHelper.instance.migrateJsonFile(
      'workers',
      userId,
      path.join(workersDirPath, 'workers_$userId.json'),
    );
  }

  Future<List<Map<String, dynamic>>> loadLocalWorkers(String userId) async {
    final List<Map<String, dynamic>> workers = [];
    try {
      workers.addAll(
          await DatabaseHelper.instance.loadAll('workers', userId));
    } catch (_) {
      return [];
    }
    for (var w in workers) {
      applyWorkerDefaults(w);
    }
    return workers;
  }

  Future<void> saveWorkersToFile(
      String userId, List<Map<String, dynamic>> workers) async {
    await DatabaseHelper.instance.saveAll('workers', userId, workers);
  }
}