// lib/models/settings_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class SettingsModel {
  final String userId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  File? _userDataFile;
  File? _customFieldsFile;

  SettingsModel({required this.userId});

  // ========== تهيئة التخزين ==========
  Future<void> initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String settingsDirPath = path.join(appDir.path, 'settings_data');
      final Directory settingsDir = Directory(settingsDirPath);
      if (!await settingsDir.exists()) {
        await settingsDir.create(recursive: true);
      }
      _userDataFile = File(path.join(settingsDirPath, 'user_$userId.json'));
      _customFieldsFile = File(path.join(settingsDirPath, 'custom_fields_$userId.json'));
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  // ========== بيانات المستخدم ==========
  Future<Map<String, dynamic>?> loadCachedUserData() async {
    if (_userDataFile == null) return null;
    try {
      if (await _userDataFile!.exists()) {
        final String jsonString = await _userDataFile!.readAsString();
        return jsonDecode(jsonString);
      }
    } catch (e) {
      print('خطأ في تحميل بيانات المستخدم: $e');
    }
    return null;
  }

  Future<void> saveUserDataLocally(Map<String, dynamic> userData) async {
    if (_userDataFile == null) return;
    try {
      await _userDataFile!.writeAsString(jsonEncode(userData));
    } catch (e) {
      print('خطأ في حفظ بيانات المستخدم: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchUserDataFromFirestore() async {
    try {
      DocumentSnapshot doc = await firestore
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print('خطأ في جلب بيانات المستخدم: $e');
    }
    return null;
  }

  Future<void> updateUserDataInFirestore(Map<String, dynamic> updateData) async {
    await firestore.collection('users').doc(userId).update(updateData);
  }

  // ========== الحقول المخصصة ==========
  Future<List<Map<String, dynamic>>> loadCachedCustomFields() async {
    if (_customFieldsFile == null) return [];
    try {
      if (await _customFieldsFile!.exists()) {
        final String jsonString = await _customFieldsFile!.readAsString();
        final List<dynamic> list = jsonDecode(jsonString);
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('خطأ في تحميل الحقول المخصصة: $e');
    }
    return [];
  }

  Future<void> saveCustomFieldsLocally(List<Map<String, dynamic>> fields) async {
    if (_customFieldsFile == null) return;
    try {
      await _customFieldsFile!.writeAsString(jsonEncode(fields));
    } catch (e) {
      print('خطأ في حفظ الحقول المخصصة: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCustomFieldsFromFirestore() async {
    try {
      QuerySnapshot snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('custom_fields')
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
      }).toList();
    } catch (e) {
      print('خطأ في جلب الحقول المخصصة: $e');
      return [];
    }
  }

  Future<void> addCustomFieldToFirestore(Map<String, dynamic> fieldData) async {
    await firestore
        .collection('users')
        .doc(userId)
        .collection('custom_fields')
        .add(fieldData);
  }

  Future<void> updateCustomFieldInFirestore(String fieldId, Map<String, dynamic> updateData) async {
    await firestore
        .collection('users')
        .doc(userId)
        .collection('custom_fields')
        .doc(fieldId)
        .update(updateData);
  }

  Future<void> deleteCustomFieldFromFirestore(String fieldId) async {
    await firestore
        .collection('users')
        .doc(userId)
        .collection('custom_fields')
        .doc(fieldId)
        .delete();
  }

  // ========== تغيير كلمة المرور ==========
  Future<void> changePassword(String newPassword) async {
    final user = auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');
    await user.updatePassword(newPassword);
  }

  // ========== التحديثات المعلقة ==========
  Future<List<Map<String, dynamic>>> loadPendingUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('pending_updates_$userId');
      if (pendingJson != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(pendingJson));
      }
    } catch (e) {
      print('خطأ في تحميل التحديثات المعلقة: $e');
    }
    return [];
  }

  Future<void> savePendingUpdates(List<Map<String, dynamic>> pendingUpdates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_updates_$userId', jsonEncode(pendingUpdates));
    } catch (e) {
      print('خطأ في حفظ التحديثات المعلقة: $e');
    }
  }

  // ========== تسجيل الخروج ==========
  Future<void> clearAllLocalData() async {
    try {
      if (_userDataFile != null && await _userDataFile!.exists()) {
        await _userDataFile!.delete();
      }
      if (_customFieldsFile != null && await _customFieldsFile!.exists()) {
        await _customFieldsFile!.delete();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('logged_in_user');
      await prefs.remove('pending_logins');
      await prefs.remove('pending_updates_$userId');
      await prefs.remove('cached_stats_$userId');
      await prefs.remove('cached_top_expenses_$userId');
      await prefs.remove('cached_business_status_$userId');
      await prefs.remove('pending_businesses_$userId');
      await prefs.remove('pending_expenses_$userId');
      await prefs.remove('last_sync_$userId');
    } catch (e) {
      print('خطأ في تنظيف البيانات المحلية: $e');
    }
  }

  Future<void> signOut() async {
    await auth.signOut();
  }

  // ========== الاتصال بالإنترنت ==========
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
}