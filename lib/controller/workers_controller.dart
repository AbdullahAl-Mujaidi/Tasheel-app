// lib/controllers/workers_controller.dart
import 'dart:async';
import 'package:fkra/model/workers_model.dart';
import 'package:flutter/material.dart';

class WorkersController extends ChangeNotifier {
  final String userId;
  final WorkersModel _model;

  // الحالة الأساسية
  List<Map<String, dynamic>> workers = [];
  bool isOffline = false;
  bool isLoading = true;

  // متغيرات النموذج (الحقول)
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController specializationController = TextEditingController();
  final TextEditingController salaryController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  DateTime date = DateTime.now();

  // حالة التعديل
  String? _editingWorkerId;
  bool _isEditing = false;

  Timer? _syncTimer;

  WorkersController({required this.userId})
      : _model = WorkersModel(userId: userId) {
    _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    workers = List.from(_model.localWorkers);
    await _checkConnectivity();
    _startPeriodicSync();
    isLoading = false;
    notifyListeners();
  }

  // ========== الاتصال ==========
  Future<void> _checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
    if (hasInternet) await _syncWithFirestore();
  }

  // ========== المزامنة ==========
  Future<void> _syncWithFirestore() async {
    try {
      await _model.syncWithFirestore(workers);
      workers = List.from(_model.localWorkers);
      notifyListeners();
    } catch (e) {
      print('فشل المزامنة: $e');
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) await _syncWithFirestore();
    });
  }

  // ========== عمليات العمال ==========
  Future<void> addWorker(BuildContext context) async {
    if (!formKey.currentState!.validate()) return;

    final workerId = DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = DateTime.now().toIso8601String();

    Map<String, dynamic> workerData = {
      'id': workerId,
      'name': nameController.text,
      'phone': phoneController.text,
      'specialization': specializationController.text,
      'salary': double.tryParse(salaryController.text) ?? 0,
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': createdAt,
    };

    workers.insert(0, workerData);
    await _model.saveWorkersToFile(workers);
    notifyListeners();

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.saveWorkerToFirestore(workerData, false);
        final index = workers.indexWhere((e) => e['id'] == workerId);
        if (index != -1) {
          workers[index]['synced'] = 1;
          await _model.saveWorkersToFile(workers);
        }
        notifyListeners();
      } catch (e) {
        print('فشل رفع العامل: $e');
      }
    }
    _resetForm();
  }

  Future<void> editWorker(BuildContext context) async {
    if (!formKey.currentState!.validate() || _editingWorkerId == null) return;

    final index = workers.indexWhere((e) => e['id'] == _editingWorkerId);
    if (index == -1) return;

    Map<String, dynamic> updatedData = {
      'id': _editingWorkerId,
      'name': nameController.text,
      'phone': phoneController.text,
      'specialization': specializationController.text,
      'salary': double.tryParse(salaryController.text) ?? 0,
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': workers[index]['createdAt'],
    };

    workers[index] = updatedData;
    await _model.saveWorkersToFile(workers);
    notifyListeners();

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.saveWorkerToFirestore(updatedData, true);
        workers[index]['synced'] = 1;
        await _model.saveWorkersToFile(workers);
        notifyListeners();
      } catch (e) {
        print('فشل تحديث العامل: $e');
      }
    }
    _resetForm();
  }

  Future<void> deleteWorker(String workerId) async {
    workers.removeWhere((e) => e['id'] == workerId);
    await _model.saveWorkersToFile(workers);
    notifyListeners();

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.deleteWorkerFromFirestore(workerId);
      } catch (e) {
        print('فشل حذف العامل من السحاب: $e');
      }
    }
  }

  // ========== تحميل بيانات العامل للتعديل ==========
  void loadWorkerForEditing(Map<String, dynamic> worker) {
    nameController.text = worker['name'] ?? '';
    phoneController.text = worker['phone'] ?? '';
    specializationController.text = worker['specialization'] ?? '';
    salaryController.text = worker['salary']?.toString() ?? '';
    try {
      date = DateTime.parse(worker['date']);
    } catch (_) {
      date = DateTime.now();
    }
    _editingWorkerId = worker['id'];
    _isEditing = true;
    notifyListeners();
  }

  void _resetForm() {
    nameController.clear();
    phoneController.clear();
    specializationController.clear();
    salaryController.clear();
    date = DateTime.now();
    _editingWorkerId = null;
    _isEditing = false;
    notifyListeners();
  }

  bool get isEditing => _isEditing;
  String? get editingWorkerId => _editingWorkerId;

  // ========== التصفية ==========
  List<Map<String, dynamic>> get filteredWorkers {
    final searchText = searchController.text.toLowerCase();
    return workers.where((worker) {
      final matchesSearch = searchText.isEmpty ||
          worker['name']?.toLowerCase().contains(searchText) == true;
      return matchesSearch;
    }).toList();
  }

  // ========== دوال مساعدة للعرض ==========
  void setDate(DateTime newDate) {
    date = newDate;
    notifyListeners();
  }

  void updateSearch(String value) {
    notifyListeners();
  }

  // ========== التنظيف ==========
  @override
  void dispose() {
    _syncTimer?.cancel();
    nameController.dispose();
    phoneController.dispose();
    specializationController.dispose();
    salaryController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // ========== المزامنة اليدوية (للزر) ==========
  Future<void> syncNow() async {
    await _syncWithFirestore();
  }

  void resetForm() {
    _resetForm();
  }
}