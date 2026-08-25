// lib/models/home_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class HomeModel {
  final String userId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  File? _statsFile;
  List<Map<String, dynamic>> _localExpenses = [];
  List<Map<String, dynamic>> _localBusinesses = [];
  List<Map<String, dynamic>> _localWorkers = [];

  HomeModel({required this.userId});

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String homeDirPath = path.join(appDir.path, 'home_data');
      final Directory homeDir = Directory(homeDirPath);
      if (!await homeDir.exists()) {
        await homeDir.create(recursive: true);
      }
      final String statsPath = path.join(homeDirPath, 'stats_$userId.json');
      _statsFile = File(statsPath);

      // تحميل البيانات من الملفات الأخرى
      final String expensesPath =
          path.join(appDir.path, 'expenses_data', 'expenses_$userId.json');
      final String businessesPath =
          path.join(appDir.path, 'businesses_data', 'businesses_$userId.json');
      final String workersPath =
          path.join(appDir.path, 'workers_data', 'workers_$userId.json');

      final File expensesFile = File(expensesPath);
      final File businessesFile = File(businessesPath);
      final File workersFile = File(workersPath);

      if (await expensesFile.exists()) {
        final String jsonString = await expensesFile.readAsString();
        final List<dynamic> list = json.decode(jsonString);
        _localExpenses = list.cast<Map<String, dynamic>>();
      }
      if (await businessesFile.exists()) {
        final String jsonString = await businessesFile.readAsString();
        final List<dynamic> list = json.decode(jsonString);
        _localBusinesses = list.cast<Map<String, dynamic>>();
      }
      if (await workersFile.exists()) {
        final String jsonString = await workersFile.readAsString();
        final List<dynamic> list = json.decode(jsonString);
        _localWorkers = list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadStatsLocally() async {
    if (_statsFile == null) return {};
    try {
      if (await _statsFile!.exists()) {
        final String jsonString = await _statsFile!.readAsString();
        final Map<String, dynamic> stats = jsonDecode(jsonString);
        return stats;
      }
    } catch (e) {
      print('خطأ في تحميل الإحصائيات: $e');
    }
    return {};
  }

  Future<void> saveStatsLocally(Map<String, dynamic> stats) async {
    if (_statsFile == null) return;
    try {
      await _statsFile!.writeAsString(jsonEncode(stats));
    } catch (e) {
      print('خطأ في حفظ الإحصائيات: $e');
    }
  }

  Map<String, dynamic> calculateStatsFromLocal() {
    double totalExpenses = _localExpenses.fold<double>(
      0.0,
      (sum, e) => sum + (e['amount'] ?? 0.0),
    );
    double totalRevenues = _localBusinesses.fold<double>(
      0.0,
      (sum, b) => sum + (b['amount'] ?? 0.0),
    );
    double netProfit = totalRevenues - totalExpenses;
    int totalBusiness = _localBusinesses.length;
    int totalWorkers = _localWorkers.length;
    return {
      'totalExpenses': totalExpenses,
      'totalRevenues': totalRevenues,
      'netProfit': netProfit,
      'totalBusiness': totalBusiness,
      'totalWorkers': totalWorkers,
    };
  }

  Future<Map<String, dynamic>> fetchStatsFromFirestore() async {
    final results = await Future.wait([
      firestore.collection('users').doc(userId).collection('expenses').get(),
      firestore.collection('users').doc(userId).collection('businesses').get(),
      firestore.collection('users').doc(userId).collection('workers').get(),
    ]);

    final expensesSnapshot = results[0];
    final businessSnapshot = results[1];
    final workersSnapshot = results[2];

    double totalExpenses = expensesSnapshot.docs.fold<double>(
      0.0,
      (sum, doc) => sum + (doc['amount'] ?? 0.0),
    );
    double totalRevenues = businessSnapshot.docs.fold<double>(
      0.0,
      (sum, doc) => sum + (doc['amount'] ?? 0.0),
    );
    double netProfit = totalRevenues - totalExpenses;
    int totalBusiness = businessSnapshot.docs.length;
    int totalWorkers = workersSnapshot.docs.length;

    return {
      'totalExpenses': totalExpenses,
      'totalRevenues': totalRevenues,
      'netProfit': netProfit,
      'totalBusiness': totalBusiness,
      'totalWorkers': totalWorkers,
    };
  }

  List<Map<String, dynamic>> getRecentBusinesses({int limit = 3}) {
    List<Map<String, dynamic>> list = List.from(_localBusinesses);
    list.sort((a, b) {
      try {
        DateTime dateA = DateTime.parse(a['date'] ?? DateTime.now().toIso8601String());
        DateTime dateB = DateTime.parse(b['date'] ?? DateTime.now().toIso8601String());
        return dateB.compareTo(dateA);
      } catch (_) {
        return 0;
      }
    });
    return list.take(limit).toList();
  }

  List<Map<String, dynamic>> getRecentExpenses({int limit = 3}) {
    List<Map<String, dynamic>> list = List.from(_localExpenses);
    list.sort((a, b) {
      try {
        DateTime dateA = DateTime.parse(a['date'] ?? DateTime.now().toIso8601String());
        DateTime dateB = DateTime.parse(b['date'] ?? DateTime.now().toIso8601String());
        return dateB.compareTo(dateA);
      } catch (_) {
        return 0;
      }
    });
    return list.take(limit).toList();
  }

  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}