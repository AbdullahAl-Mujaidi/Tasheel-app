// lib/features/account/data/datasources/account_local_datasource.dart
// التخزين المحلي للحسابات المعلقة (SharedPreferences: pending_accounts).
// منقول حرفياً من AccountModel القديم.
import 'dart:convert';

import 'package:fkra/core/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountLocalDataSource {
  AccountLocalDataSource._();
  static final AccountLocalDataSource instance = AccountLocalDataSource._();

  /// حفظ حساب محلياً عند عدم وجود إنترنت.
  Future<void> saveAccountLocally(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> pendingAccounts =
        prefs.getStringList(PrefKeys.pendingAccounts) ?? [];

    Map<String, dynamic> pendingData = {
      'userData': userData,
      'timestamp': DateTime.now().toIso8601String(),
      'email': userData['email'],
      'fullName': userData['fullName'],
    };

    pendingAccounts.add(jsonEncode(pendingData));
    await prefs.setStringList(PrefKeys.pendingAccounts, pendingAccounts);
  }

  /// تحميل قائمة الحسابات المعلقة (للاستخدام في التحقق).
  Future<List<String>> getPendingAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(PrefKeys.pendingAccounts) ?? [];
  }

  /// استبدال القائمة المعلقة (المتبقية الفاشلة بعد محاولة المزامنة).
  Future<void> setPendingAccounts(List<String> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(PrefKeys.pendingAccounts, accounts);
  }
}