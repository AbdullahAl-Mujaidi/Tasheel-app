// lib/models/business_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class BusinessModel {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final String userId;

  File? _businessesFile;
  List<Map<String, dynamic>> _localBusinesses = [];

  BusinessModel({required this.userId});

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String businessesDirPath = path.join(appDir.path, 'businesses_data');
      final Directory businessesDir = Directory(businessesDirPath);
      if (!await businessesDir.exists()) {
        await businessesDir.create(recursive: true);
      }
      final String filePath = path.join(businessesDirPath, 'businesses_$userId.json');
      _businessesFile = File(filePath);
      await loadLocalBusinesses();
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<void> loadLocalBusinesses() async {
    if (_businessesFile == null) return;
    try {
      if (await _businessesFile!.exists()) {
        final String jsonString = await _businessesFile!.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        _localBusinesses = jsonList.cast<Map<String, dynamic>>();
      } else {
        _localBusinesses = [];
      }
    } catch (e) {
      print('خطأ في تحميل الأعمال: $e');
      _localBusinesses = [];
    }
  }

  Future<void> saveBusinessesToFile(List<Map<String, dynamic>> businesses) async {
    if (_businessesFile == null) return;
    try {
      final String jsonString = json.encode(businesses);
      await _businessesFile!.writeAsString(jsonString);
    } catch (e) {
      print('خطأ في حفظ الأعمال: $e');
      rethrow;
    }
  }

  List<Map<String, dynamic>> get localBusinesses => _localBusinesses;

  // ========== الاتصال بالإنترنت ==========
   Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> businesses) async {
    if (_businessesFile == null) return;
    final bool internetAvailable = await hasInternet();
    if (!internetAvailable) return;

    try {
      // 1. رفع الأعمال غير المتزامنة
      final List<Map<String, dynamic>> unsynced =
          businesses.where((b) => b['synced'] == 0).toList();
      for (var business in unsynced) {
        await _uploadBusiness(business);
        // تحديث حالة المزامنة
        final index = businesses.indexWhere((e) => e['id'] == business['id']);
        if (index != -1) businesses[index]['synced'] = 1;
      }
      if (unsynced.isNotEmpty) await saveBusinessesToFile(businesses);

      // 2. تحميل الأعمال الجديدة من السحاب
      final lastSyncTime = await _getLastSyncTime();
      final QuerySnapshot cloudBusinesses = await firestore
          .collection('users')
          .doc(userId)
          .collection('businesses')
          .where('createdAt', isGreaterThan: lastSyncTime)
          .get();

      int addedCount = 0;
      for (var doc in cloudBusinesses.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final id = doc.id;
        if (!businesses.any((e) => e['id'] == id)) {
          final newBusiness = {
            'id': id,
            'name': data['name'],
            'description': data['description'],
            'amount': data['amount'],
            'status': data['status'],
            'date': data['date'] is Timestamp
                ? (data['date'] as Timestamp).toDate().toIso8601String()
                : data['date'].toString(),
            'customFields': data['customFields'] ?? {},
            'synced': 1,
            'createdAt': data['createdAt'] != null && data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate().toIso8601String()
                : DateTime.now().toIso8601String(),
          };
          businesses.add(newBusiness);
          addedCount++;
        }
      }

      // ترتيب حسب التاريخ
      businesses.sort((a, b) {
        try {
          DateTime dateA = DateTime.parse(a['date']);
          DateTime dateB = DateTime.parse(b['date']);
          return dateB.compareTo(dateA);
        } catch (_) {
          return 0;
        }
      });

      if (addedCount > 0) await saveBusinessesToFile(businesses);
      await _saveLastSyncTime(DateTime.now().toIso8601String());

      return;
    } catch (e) {
      print('خطأ في المزامنة: $e');
      rethrow;
    }
  }

  Future<void> _uploadBusiness(Map<String, dynamic> business) async {
    final id = business['id'];
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('businesses')
        .doc(id);

    Map<String, dynamic> firestoreData = Map.from(business);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    firestoreData.remove('localId');

    if (firestoreData['date'] is String) {
      firestoreData['date'] = Timestamp.fromDate(DateTime.parse(firestoreData['date']));
    }

    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) {
      await docRef.set(firestoreData);
    } else {
      await docRef.update({
        ...firestoreData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<String> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_sync_businesses_$userId') ?? '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_businesses_$userId', time);
  }

  // ========== الحقول المخصصة ==========
  Future<List<Map<String, dynamic>>> fetchCustomFields() async {
    final bool internetAvailable = await hasInternet();
    List<Map<String, dynamic>> fields = [];

    if (internetAvailable) {
      try {
        QuerySnapshot snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('custom_fields')
            .orderBy('createdAt', descending: false)
            .get();
        fields = snapshot.docs.map((doc) {
          return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
        }).toList();
        await _saveCustomFieldsLocally(fields);
      } catch (e) {
        print('خطأ في جلب الحقول: $e');
        fields = await _loadCustomFieldsLocally();
      }
    } else {
      fields = await _loadCustomFieldsLocally();
    }
    return fields;
  }

  Future<void> _saveCustomFieldsLocally(List<Map<String, dynamic>> fields) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_fields_$userId', jsonEncode(fields));
    } catch (e) {
      print('خطأ في حفظ الحقول محلياً: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadCustomFieldsLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('custom_fields_$userId');
      if (cached != null) {
        final List<dynamic> list = jsonDecode(cached);
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('خطأ في تحميل الحقول من الملف: $e');
    }
    return [];
  }

  // ========== حذف من السحاب ==========
  Future<void> deleteBusinessFromFirestore(String businessId) async {
    await firestore
        .collection('users')
        .doc(userId)
        .collection('businesses')
        .doc(businessId)
        .delete();
  }

  // ========== حفظ أو تحديث في السحاب ==========
  Future<void> saveBusinessToFirestore(Map<String, dynamic> business, bool isEditing) async {
    final id = business['id'];
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('businesses')
        .doc(id);

    Map<String, dynamic> firestoreData = Map.from(business);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    if (firestoreData['date'] is String) {
      firestoreData['date'] = Timestamp.fromDate(DateTime.parse(firestoreData['date']));
    }

    if (isEditing) {
      await docRef.update({
        ...firestoreData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.set({
        ...firestoreData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
}