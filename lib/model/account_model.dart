// lib/models/account_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountModel {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // التحقق من وجود اتصال بالإنترنت
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // حفظ البيانات محلياً عند عدم وجود إنترنت
  Future<void> saveAccountLocally(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> pendingAccounts = prefs.getStringList('pending_accounts') ?? [];

    Map<String, dynamic> pendingData = {
      'userData': userData,
      'timestamp': DateTime.now().toIso8601String(),
      'email': userData['email'],
      'fullName': userData['fullName'],
    };

    pendingAccounts.add(jsonEncode(pendingData));
    await prefs.setStringList('pending_accounts', pendingAccounts);
  }

  // مزامنة الحسابات المعلقة (تستدعى عند توفر الإنترنت)
  Future<int> syncPendingAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingAccounts = prefs.getStringList('pending_accounts') ?? [];
    if (pendingAccounts.isEmpty) return 0;

    List<String> syncedAccounts = [];
    List<String> failedAccounts = [];

    for (String accountJson in pendingAccounts) {
      try {
        Map<String, dynamic> account = jsonDecode(accountJson);
        Map<String, dynamic> userData = account['userData'];

        UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: userData['email'],
          password: userData['password'],
        );

        final String userId = userCredential.user!.uid;
        await userCredential.user?.updateDisplayName(userData['fullName']);

        Map<String, dynamic> firestoreData = {
          'userId': userId,
          'fullName': userData['fullName'],
          'businessName': userData['businessName'],
          'phoneNumber': userData['phoneNumber'],
          'email': userData['email'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await _firestore.collection('users').doc(userId).set(firestoreData);

        syncedAccounts.add(accountJson);
      } catch (e) {
        failedAccounts.add(accountJson);
      }
    }

    // تحديث القائمة المعلقة
    await prefs.setStringList('pending_accounts', failedAccounts);
    return syncedAccounts.length;
  }

  // إنشاء حساب جديد في Firebase
  Future<UserCredential> createAccountWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // حفظ بيانات المستخدم في Firestore
  Future<void> saveUserDataToFirestore({
    required String userId,
    required Map<String, dynamic> userData,
  }) async {
    Map<String, dynamic> firestoreData = {
      'userId': userId,
      'fullName': userData['fullName'],
      'businessName': userData['businessName'],
      'phoneNumber': userData['phoneNumber'],
      'email': userData['email'],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _firestore.collection('users').doc(userId).set(firestoreData);
  }

  // تحميل قائمة الحسابات المعلقة (للاستخدام في التحقق)
  Future<List<String>> getPendingAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('pending_accounts') ?? [];
  }
}