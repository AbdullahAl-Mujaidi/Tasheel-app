// ignore_for_file: avoid_print
// lib/features/settings/data/datasources/settings_local_datasource.dart
// المسؤول الوحيد عن التخزين المحلي للإعدادات: ترحيل JSON القديمة، كاش
// بيانات المستخدم والحقول المخصصة (SQLite عبر DatabaseHelper)، وقوائم
// المعلّقات (SharedPreferences). منقولة حرفياً من SettingsModel القديم —
// بما في ذلك سلوك print والأسر try/catch كما هي تماماً.
import 'dart:convert';
import 'dart:io';

import 'package:fkra/core/constants/app_constants.dart';
import 'package:fkra/db/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_field_sanitizer.dart';

class SettingsLocalDataSource {
  SettingsLocalDataSource._();
  static final SettingsLocalDataSource instance = SettingsLocalDataSource._();

  /// تهيئة التخزين: ترحيل الملفات القديمة إلى SQLite إن وُجدت (idempotent وآمن).
  Future<void> initStorage(String userId) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String settingsDirPath = path.join(appDir.path, 'settings_data');
      await DatabaseHelper.instance.migrateCustomFieldsJsonFile(
        userId,
        path.join(settingsDirPath, 'custom_fields_$userId.json'),
      );
      await DatabaseHelper.instance.migrateJsonToCache(
        userId,
        CacheKeys.userProfile,
        path.join(settingsDirPath, 'user_$userId.json'),
      );
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  // ========== بيانات المستخدم ==========
  Future<Map<String, dynamic>?> loadCachedUserData(String userId) async {
    try {
      return await DatabaseHelper.instance
          .getCache(userId, CacheKeys.userProfile);
    } catch (e) {
      print('خطأ في تحميل بيانات المستخدم: $e');
    }
    return null;
  }

  Future<void> saveUserDataLocally(
      String userId, Map<String, dynamic> userData) async {
    try {
      await DatabaseHelper.instance
          .setCache(userId, CacheKeys.userProfile, userData);
    } catch (e) {
      print('خطأ في حفظ بيانات المستخدم: $e');
    }
  }

  /// نشر حقل مخصص جديد على كل الأعمال غير الحاملة له (جدول الأعمال).
  Future<void> propagateCustomFieldToBusinesses(
      String userId, String fieldName, dynamic defaultValue) async {
    try {
      final db = DatabaseHelper.instance;
      final businesses = await db.loadAll(LocalTables.businesses, userId);
      bool changed = false;
      for (final biz in businesses) {
        Map<String, dynamic> cf = {};
        if (biz['customFields'] != null && biz['customFields'] is Map) {
          cf = Map<String, dynamic>.from(biz['customFields'] as Map);
        }
        if (!cf.containsKey(fieldName)) {
          cf[fieldName] = defaultValue;
          biz['customFields'] = cf;
          changed = true;
        }
      }
      if (changed) {
        await db.saveAll(LocalTables.businesses, userId, businesses);
      }
    } catch (e) {
      print('خطأ في إضافة الحقل المخصص للأعمال: $e');
    }
  }

  // ========== الحقول المخصصة ==========
  Future<List<Map<String, dynamic>>> loadCachedCustomFields(
      String userId) async {
    try {
      final fields = await DatabaseHelper.instance.loadCustomFields(userId);
      return fields
          .map((f) => sanitizeCustomField(Map<String, dynamic>.from(f)))
          .toList();
    } catch (e) {
      print('خطأ في تحميل الحقول المخصصة: $e');
    }
    return [];
  }

  Future<void> saveCustomFieldsLocally(
      String userId, List<Map<String, dynamic>> fields) async {
    try {
      final List<Map<String, dynamic>> safeFields = fields
          .map((f) => sanitizeCustomField(Map<String, dynamic>.from(f)))
          .toList();
      await DatabaseHelper.instance.saveCustomFields(userId, safeFields);
    } catch (e) {
      print('خطأ في حفظ الحقول المخصصة: $e');
    }
  }

  // ========== التحديثات المعلقة ==========
  Future<List<Map<String, dynamic>>> loadPendingUpdates(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString(PrefKeys.pendingUpdates(userId));
      if (pendingJson != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(pendingJson));
      }
    } catch (e) {
      print('خطأ في تحميل التحديثات المعلقة: $e');
    }
    return [];
  }

  Future<void> savePendingUpdates(
      String userId, List<Map<String, dynamic>> pendingUpdates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          PrefKeys.pendingUpdates(userId), jsonEncode(pendingUpdates));
    } catch (e) {
      print('خطأ في حفظ التحديثات المعلقة: $e');
    }
  }

  // ========== عمليات الحقول المخصصة المعلقة (تعمل دون اتصال) ==========
  Future<List<Map<String, dynamic>>> loadPendingCustomFieldOps(
      String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? pendingJson =
          prefs.getString(PrefKeys.pendingCustomFieldOps(userId));
      if (pendingJson != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(pendingJson));
      }
    } catch (e) {
      print('خطأ في تحميل عمليات الحقول المعلقة: $e');
    }
    return [];
  }

  Future<void> savePendingCustomFieldOps(
      String userId, List<Map<String, dynamic>> ops) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          PrefKeys.pendingCustomFieldOps(userId), jsonEncode(ops));
    } catch (e) {
      print('خطأ في حفظ عمليات الحقول المعلقة: $e');
    }
  }

  // ========== تنظيف بيانات المستخدم ==========
  // يحذف كاش المستخدم والحقول المخصصة فقط (تعادل الملفات القديمة المحذوفة)،
  // مع إبقاء الأعمال/الحركات/المصروفات/العمال كما كان سلوك الملفات السابق.
  Future<void> clearAllLocalData(String userId) async {
    try {
      await DatabaseHelper.instance.clearUserData(userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefKeys.loggedInUser);
      await prefs.remove(PrefKeys.pendingLogins);
      await prefs.remove(PrefKeys.pendingUpdates(userId));
      await prefs.remove(PrefKeys.pendingCustomFieldOps(userId));
      await prefs.remove(PrefKeys.cachedStats(userId));
      await prefs.remove(PrefKeys.cachedTopExpenses(userId));
      await prefs.remove(PrefKeys.cachedBusinessStatus(userId));
      await prefs.remove(PrefKeys.pendingBusinesses(userId));
      await prefs.remove(PrefKeys.pendingExpenses(userId));
      await prefs.remove(PrefKeys.lastSyncBare(userId));
    } catch (e) {
      print('خطأ في تنظيف البيانات المحلية: $e');
    }
  }
}