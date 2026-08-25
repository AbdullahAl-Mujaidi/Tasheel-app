// lib/models/workers_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkersModel {
  final String userId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  File? _workersFile;
  List<Map<String, dynamic>> _localWorkers = [];

  WorkersModel({required this.userId});

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String workersDirPath = '${appDir.path}/workers_data';
      final Directory workersDir = Directory(workersDirPath);
      if (!await workersDir.exists()) {
        await workersDir.create(recursive: true);
      }
      final String filePath = '$workersDirPath/workers_$userId.json';
      _workersFile = File(filePath);
      await loadLocalWorkers();
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<void> loadLocalWorkers() async {
    if (_workersFile == null) return;
    try {
      if (await _workersFile!.exists()) {
        final String jsonString = await _workersFile!.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        _localWorkers = jsonList.cast<Map<String, dynamic>>();
      } else {
        _localWorkers = [];
      }
    } catch (e) {
      print('خطأ في تحميل العمال: $e');
      _localWorkers = [];
    }
  }

  Future<void> saveWorkersToFile(List<Map<String, dynamic>> workers) async {
    if (_workersFile == null) return;
    try {
      final String jsonString = json.encode(workers);
      await _workersFile!.writeAsString(jsonString);
    } catch (e) {
      print('خطأ في حفظ العمال: $e');
      rethrow;
    }
  }

  List<Map<String, dynamic>> get localWorkers => _localWorkers;

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
  Future<void> syncWithFirestore(List<Map<String, dynamic>> workers) async {
    if (_workersFile == null) return;
    final bool internetAvailable = await hasInternet();
    if (!internetAvailable) return;

    try {
      // رفع العمال غير المتزامنين
      final List<Map<String, dynamic>> unsynced =
          workers.where((w) => w['synced'] == 0).toList();
      for (var worker in unsynced) {
        await _uploadWorker(worker);
        final index = workers.indexWhere((e) => e['id'] == worker['id']);
        if (index != -1) workers[index]['synced'] = 1;
      }
      if (unsynced.isNotEmpty) await saveWorkersToFile(workers);

      // تحميل العمال الجدد من السحاب
      final lastSyncTime = await _getLastSyncTime();
      final QuerySnapshot cloudWorkers = await firestore
          .collection('users')
          .doc(userId)
          .collection('workers')
          .where('createdAt', isGreaterThan: lastSyncTime)
          .get();

      int addedCount = 0;
      for (var doc in cloudWorkers.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final id = doc.id;
        if (!workers.any((e) => e['id'] == id)) {
          workers.add({
            'id': id,
            'name': data['name'],
            'phone': data['phone'],
            'specialization': data['specialization'],
            'salary': data['salary'],
            'date': (data['date'] as Timestamp).toDate().toIso8601String(),
            'synced': 1,
            'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
          });
          addedCount++;
        }
      }

      workers.sort((a, b) => b['date'].compareTo(a['date']));
      if (addedCount > 0) await saveWorkersToFile(workers);
      await _saveLastSyncTime(DateTime.now().toIso8601String());
    } catch (e) {
      print('خطأ في المزامنة: $e');
      rethrow;
    }
  }

  Future<void> _uploadWorker(Map<String, dynamic> worker) async {
    final id = worker['id'];
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('workers')
        .doc(id);

    Map<String, dynamic> firestoreData = Map.from(worker);
    firestoreData.remove('id');
    firestoreData.remove('synced');
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
    return prefs.getString('last_sync_workers_$userId') ?? '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_workers_$userId', time);
  }

  // حفظ أو تحديث عامل في السحاب
  Future<void> saveWorkerToFirestore(Map<String, dynamic> worker, bool isEditing) async {
    final id = worker['id'];
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('workers')
        .doc(id);

    Map<String, dynamic> firestoreData = Map.from(worker);
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

  // حذف من السحاب
  Future<void> deleteWorkerFromFirestore(String workerId) async {
    await firestore
        .collection('users')
        .doc(userId)
        .collection('workers')
        .doc(workerId)
        .delete();
  }
}