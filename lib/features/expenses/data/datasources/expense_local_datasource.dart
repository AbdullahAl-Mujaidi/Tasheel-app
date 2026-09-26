// lib/features/expenses/data/datasources/expense_local_datasource.dart
// المسؤول الوحيد عن التخزين المحلي لجدول المصروفات: ترحيل JSON القديمة
// وعمليات SQLite عبر DatabaseHelper. منقولة حرفياً من ExpenseModel القديم.
import 'dart:io';

import 'package:fkra/db/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ExpenseLocalDataSource {
  ExpenseLocalDataSource._();
  static final ExpenseLocalDataSource instance = ExpenseLocalDataSource._();

  /// ترحيل الملف القديم إلى SQLite إن وُجد (idempotent وآمن).
  Future<void> initStorage(String userId) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String expensesDirPath = path.join(appDir.path, 'expenses_data');
    await DatabaseHelper.instance.migrateJsonFile(
      'expenses',
      userId,
      path.join(expensesDirPath, 'expenses_$userId.json'),
    );
  }

  Future<List<Map<String, dynamic>>> loadLocalExpenses(String userId) async {
    try {
      return await DatabaseHelper.instance.loadAll('expenses', userId);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveExpensesToFile(
      String userId, List<Map<String, dynamic>> expenses) async {
    await DatabaseHelper.instance.saveAll('expenses', userId, expenses);
  }
}