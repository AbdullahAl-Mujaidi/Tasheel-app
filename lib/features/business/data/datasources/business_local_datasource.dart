// lib/features/business/data/datasources/business_local_datasource.dart
// المسؤول الوحيد عن التخزين المحلي لمثلث البيانات: ترحيل JSON القديمة،
// عمليات SQLite عبر DatabaseHelper، وكاش الحقول المخصصة في SharedPreferences.
// منقولة حرفياً من BusinessModel القديم بنفس السلوك.
import 'dart:convert';
import 'dart:io';

import 'package:fkra/db/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_field_codec.dart';

class BusinessLocalDataSource {
  BusinessLocalDataSource._();
  static final BusinessLocalDataSource instance =
      BusinessLocalDataSource._();

  // ========== تهيئة وترحيل الملفات القديمة إلى SQLite (idempotent وآمن) ==========
  Future<void> initStorage(String userId) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String businessesDirPath = path.join(appDir.path, 'businesses_data');
    await DatabaseHelper.instance.migrateJsonFile(
      'businesses',
      userId,
      path.join(businessesDirPath, 'businesses_$userId.json'),
    );
    await DatabaseHelper.instance.migrateJsonFile(
      'transactions',
      userId,
      path.join(businessesDirPath, 'transactions_$userId.json'),
    );
    await DatabaseHelper.instance.migrateCustomFieldsJsonFile(
      userId,
      path.join(appDir.path, 'settings_data', 'custom_fields_$userId.json'),
    );
  }

  // ========== الأعمال ==========
  Future<List<Map<String, dynamic>>> loadLocalBusinesses(String userId) async {
    try {
      return await DatabaseHelper.instance.loadAll('businesses', userId);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveBusinessesToFile(
      String userId, List<Map<String, dynamic>> businesses) async {
    await DatabaseHelper.instance.saveAll('businesses', userId, businesses);
  }

  // ========== الحركات المالية ==========
  Future<List<Map<String, dynamic>>> loadLocalTransactions(
      String userId) async {
    try {
      return await DatabaseHelper.instance.loadAll('transactions', userId);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTransactionsToFile(
      String userId, List<Map<String, dynamic>> transactions) async {
    await DatabaseHelper.instance.saveAll('transactions', userId, transactions);
  }

  // ========== الحقول المخصصة ==========
  Future<void> saveCustomFields(
      String userId, List<Map<String, dynamic>> fields) async {
    final safeFields = fields
        .map((f) => sanitizeCustomField(Map<String, dynamic>.from(f)))
        .toList();
    await DatabaseHelper.instance.saveCustomFields(userId, safeFields);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_fields_$userId', jsonEncode(safeFields));
  }

  Future<List<Map<String, dynamic>>> loadCustomFields(String userId) async {
    try {
      final fields = await DatabaseHelper.instance.loadCustomFields(userId);
      if (fields.isNotEmpty) {
        return fields
            .map((f) => sanitizeCustomField(Map<String, dynamic>.from(f)))
            .toList();
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('custom_fields_$userId');
      if (cached != null) {
        final List<dynamic> list = jsonDecode(cached);
        return list
            .map<Map<String, dynamic>>((e) =>
                sanitizeCustomField(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}