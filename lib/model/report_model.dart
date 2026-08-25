// lib/models/report_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ReportModel {
  final String userId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  File? _statsFile;
  File? _topExpensesFile;

  List<Map<String, dynamic>> _localExpenses = [];
  List<Map<String, dynamic>> _localBusinesses = [];
  List<Map<String, dynamic>> _localWorkers = [];

  ReportModel({required this.userId});

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String reportsDirPath = path.join(appDir.path, 'reports_data');

      final Directory reportsDir = Directory(reportsDirPath);
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      _statsFile = File(path.join(reportsDirPath, 'stats_$userId.json'));
      _topExpensesFile =
          File(path.join(reportsDirPath, 'top_expenses_$userId.json'));
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  // تحميل جميع البيانات المحلية (المصروفات، الأعمال، العمال)
  Future<void> loadAllLocalData() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();

      // تحميل المصروفات
      final String expensesPath =
          path.join(appDir.path, 'expenses_data', 'expenses_$userId.json');
      final File expensesFile = File(expensesPath);
      if (await expensesFile.exists()) {
        final String jsonString = await expensesFile.readAsString();
        final List<dynamic> list = json.decode(jsonString);
        _localExpenses = list.cast<Map<String, dynamic>>();
      }

      // تحميل الأعمال
      final String businessesPath =
          path.join(appDir.path, 'businesses_data', 'businesses_$userId.json');
      final File businessesFile = File(businessesPath);
      if (await businessesFile.exists()) {
        final String jsonString = await businessesFile.readAsString();
        final List<dynamic> list = json.decode(jsonString);
        _localBusinesses = list.cast<Map<String, dynamic>>();
      }

      // تحميل العمال
      final String workersPath =
          path.join(appDir.path, 'workers_data', 'workers_$userId.json');
      final File workersFile = File(workersPath);
      if (await workersFile.exists()) {
        final String jsonString = await workersFile.readAsString();
        final List<dynamic> list = json.decode(jsonString);
        _localWorkers = list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('خطأ في تحميل البيانات المحلية: $e');
      rethrow;
    }
  }

  // حفظ الإحصائيات محلياً
  Future<void> saveStatsLocally(Map<String, dynamic> stats) async {
    if (_statsFile == null) return;
    try {
      await _statsFile!.writeAsString(jsonEncode(stats));
    } catch (e) {
      print('خطأ في حفظ الإحصائيات: $e');
    }
  }

  // حفظ أعلى المصروفات محلياً
  Future<void> saveTopExpensesLocally(List<Map<String, dynamic>> topExpenses) async {
    if (_topExpensesFile == null) return;
    try {
      await _topExpensesFile!.writeAsString(jsonEncode(topExpenses));
    } catch (e) {
      print('خطأ في حفظ أعلى المصروفات: $e');
    }
  }

  // تحميل البيانات المخزنة مؤقتاً
  Future<Map<String, dynamic>> loadCachedStats() async {
    try {
      if (_statsFile != null && await _statsFile!.exists()) {
        final String jsonString = await _statsFile!.readAsString();
        return jsonDecode(jsonString);
      }
    } catch (e) {
      print('خطأ في تحميل الإحصائيات المخزنة: $e');
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> loadCachedTopExpenses() async {
    try {
      if (_topExpensesFile != null && await _topExpensesFile!.exists()) {
        final String jsonString = await _topExpensesFile!.readAsString();
        final List<dynamic> list = jsonDecode(jsonString);
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('خطأ في تحميل أعلى المصروفات المخزنة: $e');
    }
    return [];
  }

  // ========== جلب البيانات من Firebase ==========
  Future<void> fetchAllDataFromFirestore() async {
    try {
      final results = await Future.wait([
        firestore
            .collection('users')
            .doc(userId)
            .collection('expenses')
            .get(),
        firestore
            .collection('users')
            .doc(userId)
            .collection('businesses')
            .get(),
        firestore
            .collection('users')
            .doc(userId)
            .collection('workers')
            .get(),
      ]);

      final expensesSnapshot = results[0];
      final businessSnapshot = results[1];
      final workersSnapshot = results[2];

      _localExpenses = expensesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'description': data['description'],
          'amount': data['amount'],
          'category': data['category'],
          'date': (data['date'] as Timestamp).toDate().toIso8601String(),
          'synced': 1,
        };
      }).toList();

      _localBusinesses = businessSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'],
          'description': data['description'],
          'amount': data['amount'],
          'status': data['status'],
          'date': (data['date'] as Timestamp).toDate().toIso8601String(),
          'synced': 1,
        };
      }).toList();

      _localWorkers = workersSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'],
          'phone': data['phone'],
          'specialization': data['specialization'],
          'salary': data['salary'],
          'date': (data['date'] as Timestamp).toDate().toIso8601String(),
          'synced': 1,
        };
      }).toList();

      // حفظ البيانات محلياً بعد الجلب (سيتم بواسطة المتحكم)
    } catch (e) {
      print('خطأ في جلب البيانات من Firestore: $e');
      rethrow;
    }
  }

  // ========== دوال مساعدة ==========
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ========== Getters للبيانات المحلية ==========
  List<Map<String, dynamic>> get localExpenses => _localExpenses;
  List<Map<String, dynamic>> get localBusinesses => _localBusinesses;
  List<Map<String, dynamic>> get localWorkers => _localWorkers;
}