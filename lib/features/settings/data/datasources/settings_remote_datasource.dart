// ignore_for_file: avoid_print
// lib/features/settings/data/datasources/settings_remote_datasource.dart
// المسؤول الوحيد عن الاتصال بـ Firebase لإعدادات المستخدم: بيانات المستخدم
// (users/{userId})، الحقول المخصصة (users/{userId}/custom_fields)، وتغيير
// كلمة المرور. منقولة حرفياً من SettingsModel القديم — بما في ذلك سلوك
// print والأسر try/catch كما هي تماماً.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/core/constants/app_constants.dart';

import '../models/custom_field_sanitizer.dart';

class SettingsRemoteDataSource {
  SettingsRemoteDataSource._();
  static final SettingsRemoteDataSource instance = SettingsRemoteDataSource._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ========== بيانات المستخدم ==========
  Future<Map<String, dynamic>?> fetchUserData(String userId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection(FirestoreCollections.users)
          .doc(userId)
          .get();
      FirebaseUsageTracker.instance.recordRead();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print('خطأ في جلب بيانات المستخدم: $e');
    }
    return null;
  }

  Future<void> updateUserData(
      String userId, Map<String, dynamic> updateData) async {
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .update(updateData);
    FirebaseUsageTracker.instance.recordWrite();
  }

  // ========== الحقول المخصصة ==========
  CollectionReference<Map<String, dynamic>> _customFieldsOf(String userId) =>
      _firestore
          .collection(FirestoreCollections.users)
          .doc(userId)
          .collection(FirestoreCollections.customFields);

  Future<List<Map<String, dynamic>>> fetchCustomFields(String userId) async {
    try {
      QuerySnapshot snapshot = await _customFieldsOf(userId)
          .orderBy(FirestoreFields.createdAt, descending: true)
          .get();
      FirebaseUsageTracker.instance.recordReads(snapshot.docs.length);
      return snapshot.docs.map((doc) {
        return sanitizeCustomField(
            {'id': doc.id, ...doc.data() as Map<String, dynamic>});
      }).toList();
    } catch (e) {
      print('خطأ في جلب الحقول المخصصة: $e');
      return [];
    }
  }

  Future<void> addCustomField(
      String userId, Map<String, dynamic> fieldData) async {
    await _customFieldsOf(userId).add(fieldData);
    FirebaseUsageTracker.instance.recordWrite();
  }

  Future<void> updateCustomField(
      String userId, String fieldId, Map<String, dynamic> updateData) async {
    await _customFieldsOf(userId).doc(fieldId).update(updateData);
    FirebaseUsageTracker.instance.recordWrite();
  }

  // إضافة/تحديث حقل مخصص بمعرّف محدد (يُستخدم عند الرفع لاحقاً بعد العمل
  // دون اتصال).
  Future<void> saveCustomField(
    String userId,
    String fieldId,
    Map<String, dynamic> fieldData, {
    bool isNew = false,
  }) async {
    final ref = _customFieldsOf(userId).doc(fieldId);
    final data = Map<String, dynamic>.from(fieldData)..remove('id');
    if (data['createdAt'] is String) {
      data['createdAt'] =
          Timestamp.fromDate(DateTime.parse(data['createdAt'] as String));
    }
    if (data['updatedAt'] is String) {
      data['updatedAt'] =
          Timestamp.fromDate(DateTime.parse(data['updatedAt'] as String));
    }
    if (isNew) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await ref.set(data);
    } else {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await ref.update(data);
    }
    FirebaseUsageTracker.instance.recordWrite();
  }

  Future<void> deleteCustomField(String userId, String fieldId) async {
    await _customFieldsOf(userId).doc(fieldId).delete();
    FirebaseUsageTracker.instance.recordDelete();
  }

  // ========== تغيير كلمة المرور ==========
  Future<void> changePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');
    await user.updatePassword(newPassword);
  }
}