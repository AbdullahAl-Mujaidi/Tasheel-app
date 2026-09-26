// ignore_for_file: avoid_print
import 'dart:async';
import 'package:fkra/admin/services/admin_session_service.dart';
import 'package:fkra/model/business_model.dart';
import 'package:fkra/model/expense_model.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/activity_service.dart';
import 'package:fkra/services/analytics_service.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:flutter/material.dart';

class BusinessController extends ChangeNotifier {
  final String userId;
  final BusinessModel _model;

  // الحالة الأساسية
  List<Map<String, dynamic>> businesses = [];
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> customFieldsList = [];
  bool isOffline = false;
  bool isLoading = true;
  String selectedCategory = "الكل";

  // متغيرات النافذة المنبثقة (الإضافة/التعديل)
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  String businessName = '';
  String businessDescription = '';
  String businessAmount = '';
  String businessInitialPaid = '';
  String businessClientPhone = '';
  String? selectedStatus;
  DateTime date = DateTime.now();

  // الحقول المخصصة - قيمها
  Map<String, dynamic> customFieldsValues = {};
  Map<String, TextEditingController> textControllers = {};
  Map<String, DateTime> dateValues = {};
  Map<String, String?> dropdownValues = {};

  // حالة التعديل
  String? _editingBusinessId;
  bool _isEditing = false;

  Timer? _syncTimer;

  BusinessController({required this.userId})
      : _model = BusinessModel(userId: userId) {
    _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    await _applySessionScope();
    businesses = List.from(_model.localBusinesses);
    transactions = List.from(_model.localTransactions);
    // تصفية العرض فوراً حسب النطاق (حركات الأعمال غير المفوَّضة فقط لا تظهر).
    _applyScopedDisplay();
    await _checkConnectivity();
    await _fetchCustomFields();
    _startPeriodicSync();
    isLoading = false;
    notifyListeners();
  }

  /// نسخ نطاق المشاركة (أعمال محددة) من جلسة المستخدم التابع الحالية إلى
  /// النموذج، حتى يُحمَّل من السحاب في حدود المفوَّض فقط. قبل القراءة يُحدَّث
  /// التفويض من الخادم ليمنع استعمال نطاق قديم (يُرفض استعلاماً عريضاً).
  Future<void> _applySessionScope() async {
    await MemberSessionService.instance.refreshMembershipBeforeScope();
    _model.setScopedBusinessIds(
      MemberSessionService.instance.scopedBusinessIdsFor(userId),
    );
  }

  /// تحديد معرّفات أعمال النطاق المسموح به (فارغ = المالك/كل الأعمال).
  Set<String>? get _scopedAllowedWorkIds {
    final ids = MemberSessionService.instance.scopedBusinessIdsFor(userId);
    return ids.isEmpty ? null : ids.toSet();
  }

  /// صحيح عند عرض حساب بنطاق تفويض مقيّد — لا نُحفظ الحركات المفلترة في
  /// التخزين المحلي (إعدادات الكاش محفوظة باسم المالك ولا يجوز المساس بها).
  bool get _isScopedMode => _scopedAllowedWorkIds != null;

  /// تصفية عرض الحركات إلى نطاق الأعمال المسموح بها فقط. قائمة الأعمال نفسها
  /// تبقى كاملة في الذاكرة والتخزين (لا تُنقَّص)، والتصفية تتم في
  /// filteredBusinesses عند العرض — فلا يضيع من كاش صاحب الحساب شيء.
  void _applyScopedDisplay() {
    final allowed = _scopedAllowedWorkIds;
    if (allowed == null) return;
    transactions = transactions
        .where((t) => allowed.contains(t['workId']?.toString()))
        .toList();
  }

  // ========== الاتصال ==========
  Future<void> _checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
    if (hasInternet) await syncWithFirestore();
  }

  // ========== المزامنة ==========
  Future<void> syncWithFirestore() async {
    try {
      // يُمكَّن النطاق منقّحاً (قد تُضاف مشاركات جديدة أثناء الجلسة).
      await _applySessionScope();
      await _model.syncWithFirestore(businesses);
      // تحميل/دفع الحركات للأعمال النشطة (في وضع المشاركة المقيّد تكون
      // قائمة الأعمال قد سُقِطت من غير المفوَّض، فلا تُقرأ حركاتها المحظورة).
      await _model.syncTransactionsWithFirestore(transactions, businesses);
      if (_isScopedMode) {
        // الجلسة المقيّدة: النموذج دمج الأعمال المفوَّضة في قائمة الذاكرة
        // وأسقط غيرها — لا نعيد التحميل من القرص (يمسح تحميلات النطاق)،
        // والقرص باسم المالك لا يُكتب فيه في هذه الحالة.
        final allowed = _scopedAllowedWorkIds;
        if (allowed != null) {
          businesses =
              businesses.where((b) => allowed.contains(b['id']?.toString())).toList();
          transactions = transactions
              .where((t) => allowed.contains(t['workId']?.toString()))
              .toList();
        }
      } else {
        await _model.loadLocalBusinesses();
        businesses = List.from(_model.localBusinesses);
        await _model.loadLocalTransactions();
        transactions = List.from(_model.localTransactions);
      }
      await _fetchCustomFields();
      notifyListeners();
      await ActivityService.record(userId: userId, isSync: true);
      await AnalyticsService.instance.logDataSynced();
    } catch (e) {
      print('فشل المزامنة: $e');
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) await syncWithFirestore();
    });
  }

  // ========== الحقول المخصصة ==========
  Future<void> _fetchCustomFields() async {
    customFieldsList = await _model.fetchCustomFields();
    _initializeCustomFieldsControllers();
    notifyListeners();
  }

  void _initializeCustomFieldsControllers() {
    for (var field in customFieldsList) {
      String fieldName = field['fieldName'];
      switch (field['fieldType']) {
        case 'نص':
          if (!textControllers.containsKey(fieldName)) {
            textControllers[fieldName] = TextEditingController();
          }
          break;
        case 'رقم':
          if (!textControllers.containsKey(fieldName)) {
            textControllers[fieldName] = TextEditingController();
          }
          break;
        case 'تاريخ':
          if (!dateValues.containsKey(fieldName)) {
            dateValues[fieldName] = DateTime.now();
          }
          break;
        case 'قائمة منسدلة':
          if (!dropdownValues.containsKey(fieldName)) {
            dropdownValues[fieldName] = null;
          }
          break;
      }
    }
  }

  // ========== عمليات الأعمال ==========
  Future<bool> addBusiness(BuildContext context) async {
    if (AdminSessionService.instance.role != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حساب المدير مخصص للإدارة والإشراف فقط، ولا يمكنه إضافة أعمال جديدة.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    // حماية صلاحيات التابع: منع الإضافة دون إذن create (بالإضافة لإخفاء الزر).
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canCreate(TeamPermissions.businesses)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا تملك صلاحية إضافة أعمال جديدة.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    // التحقق من صحة النموذج
    if (!formKey.currentState!.validate()) return false;

    final businessId = DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = DateTime.now().toIso8601String();
    final actor = MemberSessionService.instance.actor;

    Map<String, dynamic> businessData = {
      'id': businessId,
      'name': businessName,
      'description': businessDescription,
      'amount': int.tryParse(businessAmount) ?? 0,
      'initialPaid': int.tryParse(businessInitialPaid) ?? 0,
      'clientPhone': businessClientPhone,
      'totalPaid': 0,
      'totalExpenses': 0,
      'remaining': int.tryParse(businessAmount) ?? 0,
      'date': date.toIso8601String(),
      'status': selectedStatus ?? 'قيد الانتظار',
      'customFields': Map.from(customFieldsValues),
      'synced': 0,
      'createdAt': createdAt,
      'createdByLabel': actor.label,
      'createdByRole': actor.role,
      'createdByUid': actor.uid,
    };

    // إضافة محلياً
    businesses.insert(0, businessData);
    await _saveSummaryToBusiness(businessId, calculateSummary(businessId));

    // محاولة الرفع للسحاب وتسجيل النشاط في الخلفية: لا ننتظر الشبكة قبل
    // إظهار التأكيد، فتظهر رسالة نجاح الحفظ فوراً (حتى دون اتصال).
    unawaited(() async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        try {
          await _model.saveBusinessToFirestore(businessData, false);
          // تحديث حالة المزامنة
          final index = businesses.indexWhere((e) => e['id'] == businessId);
          if (index != -1) {
            businesses[index]['synced'] = 1;
            if (!_isScopedMode) {
              await _model.saveBusinessesToFile(businesses);
            }
          }
          notifyListeners();
        } catch (e) {
          // فشل الرفع - يبقى محلياً
          print('فشل رفع العمل: $e');
        }
      }
      await ActivityService.recordActivity(userId: userId);
      await AnalyticsService.instance.logBusinessCreated();
    }());
    resetForm();
    return true;
  }

  Future<bool> editBusiness(BuildContext context, String businessId) async {
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canUpdate(TeamPermissions.businesses)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا تملك صلاحية تعديل الأعمال.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (!formKey.currentState!.validate()) return false;

    final index = businesses.indexWhere((e) => e['id'] == businessId);
    if (index == -1) return false;

    // الملخص يُحسب من الحركات القائمة ليرفع صحيحاً للسحاب — لا يُصفَّر أبداً
    // وإلا وصلت أصفار للمالك عبر المزامنة وطمست أرقامه.
    final summary = calculateSummary(businessId);
    final actor = MemberSessionService.instance.actor;
    final existing = businesses[index];

    Map<String, dynamic> updatedData = {
      'id': businessId,
      'name': businessName,
      'description': businessDescription,
      'amount': int.tryParse(businessAmount) ?? 0,
      'initialPaid': int.tryParse(businessInitialPaid) ?? 0,
      'clientPhone': businessClientPhone,
      'totalPaid': summary['totalPaid'],
      'totalExpenses': summary['totalExpenses'],
      'remaining': summary['remaining'],
      'date': date.toIso8601String(),
      'status': selectedStatus ?? 'قيد الانتظار',
      'customFields': Map.from(customFieldsValues),
      'synced': 0,
      'createdAt': businesses[index]['createdAt'],
      'createdByLabel': existing['createdByLabel'],
      'createdByRole': existing['createdByRole'],
      'createdByUid': existing['createdByUid'],
      'lastModifiedByLabel': actor.label,
      'lastModifiedByRole': actor.role,
      'lastModifiedByUid': actor.uid,
    };

    businesses[index] = updatedData;
    await _saveSummaryToBusiness(businessId, summary);

    unawaited(() async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        try {
          await _model.saveBusinessToFirestore(updatedData, true);
          businesses[index]['synced'] = 1;
          if (!_isScopedMode) {
            await _model.saveBusinessesToFile(businesses);
          }
          notifyListeners();
        } catch (e) {
          print('فشل تحديث العمل: $e');
        }
      }
      await ActivityService.recordActivity(userId: userId);
      await AnalyticsService.instance.logBusinessUpdated();
    }());
    resetForm();
    return true;
  }

  Future<void> markBusinessCompleted(BuildContext context, String businessId) async {
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canUpdate(TeamPermissions.businesses)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا تملك صلاحية تعديل الأعمال.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final index = businesses.indexWhere((e) => e['id'] == businessId);
    if (index == -1) return;

    businesses[index]['status'] = 'مكتمل';
    businesses[index]['synced'] = 0;
    businesses[index]['updatedAt'] = DateTime.now().toIso8601String();
    final actor = MemberSessionService.instance.actor;
    businesses[index]['lastModifiedByLabel'] = actor.label;
    businesses[index]['lastModifiedByRole'] = actor.role;
    businesses[index]['lastModifiedByUid'] = actor.uid;
    if (!_isScopedMode) await _model.saveBusinessesToFile(businesses);
    notifyListeners();

    unawaited(() async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        try {
          await _model.saveBusinessToFirestore(
              Map<String, dynamic>.from(businesses[index]), true);
          final idx = businesses.indexWhere((e) => e['id'] == businessId);
          if (idx != -1) {
            businesses[idx]['synced'] = 1;
            if (!_isScopedMode) await _model.saveBusinessesToFile(businesses);
          }
          notifyListeners();
        } catch (e) {
          print('فشل رفع تحديث حالة العمل: $e');
        }
      }
      await ActivityService.recordActivity(userId: userId);
      await AnalyticsService.instance.logBusinessUpdated();
    }());
  }

  Future<void> deleteBusiness(String businessId) async {
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canDelete(TeamPermissions.businesses)) {
      return;
    }

    businesses.removeWhere((e) => e['id'] == businessId);
    transactions.removeWhere((e) => e['workId'] == businessId);
    if (!_isScopedMode) await _model.saveBusinessesToFile(businesses);
    if (!_isScopedMode) await _model.saveTransactionsToFile(transactions);
    notifyListeners();

    await ActivityService.recordActivity(userId: userId);
    await AnalyticsService.instance.logBusinessDeleted();

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.deleteBusinessTransactionsFromFirestore(businessId);
        await _model.deleteBusinessFromFirestore(businessId);
      } catch (e) {
        print('فشل حذف العمل من السحاب: $e');
      }
    }
  }

  // ========== الحركات المالية ==========
  List<Map<String, dynamic>> getTransactionsForWork(String workId) {
    final list = transactions
        .where((t) => t['workId'] == workId)
        .toList();
    list.sort((a, b) {
      try {
        DateTime dateA = DateTime.parse(a['date']);
        DateTime dateB = DateTime.parse(b['date']);
        return dateB.compareTo(dateA);
      } catch (_) {
        return 0;
      }
    });
    return list;
  }

  Map<String, int> calculateSummary(String workId) {
    final work = businesses.where((e) => e['id'] == workId).toList();
    final int amount = work.isNotEmpty && work.first['amount'] != null
        ? (work.first['amount'] as num).toInt()
        : 0;

    int totalPaid = work.isNotEmpty
        ? ((work.first['initialPaid'] as num?)?.toInt() ?? 0)
        : 0;
    int totalExpenses = 0;
    for (var t in transactions) {
      if (t['workId'] != workId) continue;
      final int tAmount = (t['amount'] as num?)?.toInt() ?? 0;
      if (t['type'] == 'payment') {
        totalPaid += tAmount;
      } else if (t['type'] == 'expense') {
        totalExpenses += tAmount;
      }
    }

    return {
      'totalPaid': totalPaid,
      'totalExpenses': totalExpenses,
      'remaining': amount - totalPaid,
    };
  }

  Future<void> _saveSummaryToBusiness(String workId, Map<String, int> summary) async {
    final index = businesses.indexWhere((e) => e['id'] == workId);
    if (index == -1) return;
    businesses[index]['totalPaid'] = summary['totalPaid'];
    businesses[index]['totalExpenses'] = summary['totalExpenses'];
    businesses[index]['remaining'] = summary['remaining'];
    if (!_isScopedMode) await _model.saveBusinessesToFile(businesses);
    notifyListeners();
  }

  Future<void> addTransaction({
    required String workId,
    required String type,
    required int amount,
    required String description,
    required DateTime date,
    String category = 'اخرى',
    String? workerId,
    String? workerName,
    String? transactionId,
  }) async {
    final id = transactionId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final tx = {
      'id': id,
      'workId': workId,
      'type': type,
      'amount': amount,
      'description': description,
      'category': category,
      'date': date.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'synced': 0,
      if (workerId != null) 'workerId': workerId,
      if (workerName != null) 'workerName': workerName,
      'createdByLabel': MemberSessionService.instance.actor.label,
      'createdByRole': MemberSessionService.instance.actor.role,
      'createdByUid': MemberSessionService.instance.actor.uid,
    };

    transactions.insert(0, tx);
    if (!_isScopedMode) await _model.saveTransactionsToFile(transactions);
    final summary = calculateSummary(workId);
    await _saveSummaryToBusiness(workId, summary);

    // مصروف العمل يُسجَّل تلقائياً في قائمة المصروفات العامة للإحصائيات
    if (type == 'expense') {
      final work = businesses.where((e) => e['id'] == workId).toList();
      final workName = work.isNotEmpty ? work.first['name']?.toString() : null;
      await _linkExpenseToGeneral(tx, workName);
    }

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.uploadTransactionToFirestore(tx);
        final index = transactions.indexWhere((e) => e['id'] == id);
        if (index != -1) transactions[index]['synced'] = 1;
        if (!_isScopedMode) await _model.saveTransactionsToFile(transactions);
        await _model.updateBusinessSummaryFirestore(
          workId,
          totalPaid: summary['totalPaid']!,
          totalExpenses: summary['totalExpenses']!,
          remaining: summary['remaining']!,
        );
      } catch (e) {
        // فشل الرفع - يعيد وضع العمل كغير متزامن لرفعه كاملاً لاحقاً
        final bIndex = businesses.indexWhere((e) => e['id'] == workId);
        if (bIndex != -1) {
          businesses[bIndex]['synced'] = 0;
          if (!_isScopedMode) {
            await _model.saveBusinessesToFile(businesses);
          }
        }
        print('فشل رفع الحركة: $e');
      }
    }
  }

  Future<void> deleteTransaction(String workId, String transactionId) async {
    final tx = transactions.where((e) => e['id'] == transactionId).toList();
    final bool isExpense = tx.isNotEmpty && tx.first['type'] == 'expense';

    transactions.removeWhere((e) => e['id'] == transactionId);
    if (!_isScopedMode) await _model.saveTransactionsToFile(transactions);
    final summary = calculateSummary(workId);
    await _saveSummaryToBusiness(workId, summary);

    // حذف المطابق من قائمة المصروفات العامة إن كان مصروفاً
    if (isExpense) {
      await _unlinkExpenseFromGeneral(transactionId);
    }

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.deleteTransactionFromFirestore(workId, transactionId);
        // إعادة دفع الملخص بعد الحذف حتى يبقى المجموع سحابياً متسقاً
        // مع ما يراه صاحب الحساب بعد المزامنة (دون مسحات تصل كأصفار).
        await _model.updateBusinessSummaryFirestore(
          workId,
          totalPaid: summary['totalPaid']!,
          totalExpenses: summary['totalExpenses']!,
          remaining: summary['remaining']!,
        );
      } catch (e) {
        print('فشل حذف الحركة من السحاب: $e');
      }
    }
  }

  // ========== تحميل بيانات العمل للتعديل ==========
  void loadBusinessForEditing(Map<String, dynamic> business) {
    businessName = business['name'] ?? '';
    businessDescription = business['description'] ?? '';
    businessAmount = business['amount']?.toString() ?? '0';
    businessInitialPaid = business['initialPaid']?.toString() ?? '0';
    businessClientPhone = business['clientPhone']?.toString() ?? '';
    selectedStatus = business['status'] ?? 'قيد الانتظار';
    try {
      date = DateTime.parse(business['date']);
    } catch (_) {
      date = DateTime.now();
    }

    // تعبئة الحقول المخصصة
    if (business['customFields'] != null) {
      final Map<String, dynamic> saved = Map<String, dynamic>.from(
        business['customFields'] as Map);
      for (var field in customFieldsList) {
        String fieldName = field['fieldName'];
        String fieldType = field['fieldType'];
        if (saved.containsKey(fieldName)) {
          dynamic value = saved[fieldName];
          switch (fieldType) {
            case 'نص':
              if (textControllers.containsKey(fieldName)) {
                textControllers[fieldName]?.text = value?.toString() ?? '';
              }
              customFieldsValues[fieldName] = value;
              break;
            case 'رقم':
              if (textControllers.containsKey(fieldName)) {
                textControllers[fieldName]?.text = value?.toString() ?? '0';
              }
              customFieldsValues[fieldName] = value ?? 0;
              break;
            case 'تاريخ':
              if (value is String) {
                try {
                  dateValues[fieldName] = DateTime.parse(value);
                  customFieldsValues[fieldName] = DateTime.parse(value);
                } catch (_) {
                  dateValues[fieldName] = DateTime.now();
                  customFieldsValues[fieldName] = DateTime.now();
                }
              } else if (value is DateTime) {
                dateValues[fieldName] = value;
                customFieldsValues[fieldName] = value;
              }
              break;
            case 'قائمة منسدلة':
              dropdownValues[fieldName] = value?.toString();
              customFieldsValues[fieldName] = value?.toString();
              break;
          }
        }
      }
    }
    _editingBusinessId = business['id'];
    _isEditing = true;
    notifyListeners();
  }

  void resetForm() {
    businessName = '';
    businessDescription = '';
    businessAmount = '';
    businessInitialPaid = '';
    businessClientPhone = '';
    selectedStatus = null;
    date = DateTime.now();
    _editingBusinessId = null;
    _isEditing = false;
    // مسح الحقول المخصصة
    for (var controller in textControllers.values) {
      controller.clear();
    }
    for (var key in dateValues.keys) {
      dateValues[key] = DateTime.now();
    }
    for (var key in dropdownValues.keys) {
      dropdownValues[key] = null;
    }
    customFieldsValues.clear();
    notifyListeners();
  }

  bool get isEditing => _isEditing;
  String? get editingBusinessId => _editingBusinessId;

  // ========== التصفية ==========
  List<Map<String, dynamic>> get filteredBusinesses {
    // تفويض على مستوى السجل: يعرض فقط الأعمال المفوَّضة (قائمة الأعمال في
    // الذاكرة تبقى كاملة؛ الترشيح للعرض فقط حتى لا تتأثر بيانات المالك).
    final scopedAllowed = _scopedAllowedWorkIds;
    return businesses.where((business) {
      if (scopedAllowed != null &&
          !scopedAllowed.contains(business['id']?.toString())) {
        return false;
      }
      final matchesCategory =
          selectedCategory == "الكل" || business['status'] == selectedCategory;
      return matchesCategory;
    }).toList();
  }

  // ========== التنظيف ==========
  @override
  void dispose() {
    _syncTimer?.cancel();
    for (var controller in textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ========== دوال مساعدة للعرض ==========
  void toggleCategory(String category) {
    selectedCategory = category;
    notifyListeners();
  }

  void setDate(DateTime newDate) {
    date = newDate;
    notifyListeners();
  }

  void setStatus(String? status) {
    selectedStatus = status;
    notifyListeners();
  }

  void setCustomFieldValue(String fieldName, dynamic value) {
    customFieldsValues[fieldName] = value;
    notifyListeners();
  }

  // ========== دوال مساعدة لعرض كشف الحساب ==========
  Map<String, dynamic>? getBusinessById(String workId) {
    for (final b in businesses) {
      if (b['id'] != null && b['id'].toString() == workId) return b;
    }
    return null;
  }

  // ========== صفوف كشف الحساب ==========
  // يعيد الحركات مع إضافة "الدفعة الأولى" (المبلغ المدفوع عند الإنشاء)
  // كأول صف حتى تظهر في الكشف ولا تبدو الأرقام غير متسقة
  List<Map<String, dynamic>> getStatementRows(String workId,
      {bool paymentsOnly = false}) {
    final rows = <Map<String, dynamic>>[];
    final business = getBusinessById(workId);
    if (business != null) {
      final int initialPaid = (business['initialPaid'] as num?)?.toInt() ?? 0;
      if (initialPaid > 0) {
        rows.add({
          'id': 'initialPaid_$workId',
          'type': 'payment',
          'amount': initialPaid,
          'description': 'دفعة أولى (المبلغ المدفوع عند الإنشاء)',
          'date': business['date'] ?? DateTime.now().toIso8601String(),
          'isInitial': true,
          'createdByLabel': business['createdByLabel'],
        });
      }
    }
    final all = getTransactionsForWork(workId);
    rows.addAll(
        paymentsOnly ? all.where((t) => t['type'] == 'payment') : all);
    return rows;
  }

  // ========== الربط مع المصروفات العامة (يعمل دون اتصال) ==========
  // يقرأ ملف المصروفات ويحدّثه مباشرة، ويرفع للسحاب فقط عند توفر اتصال
  Future<void> _linkExpenseToGeneral(
      Map<String, dynamic> tx, String? workName) async {
    try {
      final ExpenseModel model = ExpenseModel(userId: userId);
      await model.initStorage();
      final String description =
          (tx['description'] ?? '').toString().trim().isEmpty
              ? (workName ?? 'مصروف عمل')
              : tx['description'].toString();
      final Map<String, dynamic> expenseData = {
        'id': tx['id'],
        'description': description,
        'amount': (tx['amount'] as num?)?.toDouble() ?? 0,
        'category': (tx['category'] ?? 'اخرى').toString(),
        'date': tx['date'],
        'synced': 0,
        'createdAt': tx['createdAt'],
        'source': 'business',
        'workId': tx['workId'],
        'workName': workName,
        'createdByLabel': tx['createdByLabel'],
        'createdByRole': tx['createdByRole'],
        'createdByUid': tx['createdByUid'],
        if (tx['workerId'] != null) 'workerId': tx['workerId'],
        if (tx['workerName'] != null) 'workerName': tx['workerName'],
      };
      final List<Map<String, dynamic>> list =
          List<Map<String, dynamic>>.from(model.localExpenses);
      if (!list.any((e) => e['id'] == expenseData['id'])) {
        list.insert(0, expenseData);
      }
      await model.saveExpensesToFile(list);

      final bool hasInternet = await model.hasInternet();
      if (hasInternet) {
        try {
          await model.saveExpenseToFirestore(expenseData, false);
        } catch (e) {
          print('فشل رفع المصروف المرتبط إلى سحاب المصروفات: $e');
        }
      }
    } catch (e) {
      print('فشل إضافة المصروف إلى قائمة المصروفات: $e');
    }
  }

  // يزيل المصروف المرتبط (نفس المعرّف) من الملف والسحاب إن وُجد
  Future<void> _unlinkExpenseFromGeneral(String expenseId) async {
    try {
      final ExpenseModel model = ExpenseModel(userId: userId);
      await model.initStorage();
      final List<Map<String, dynamic>> list =
          List<Map<String, dynamic>>.from(model.localExpenses);
      final int index = list.indexWhere((e) => e['id'] == expenseId);
      if (index == -1) return;
      final bool wasLinked = list[index]['source'] == 'business';
      list.removeAt(index);
      await model.saveExpensesToFile(list);

      if (wasLinked) {
        final bool hasInternet = await model.hasInternet();
        if (hasInternet) {
          try {
            await model.deleteExpenseFromFirestore(expenseId);
          } catch (e) {
            print('فشل حذف المصروف المرتبط من سحاب المصروفات: $e');
          }
        }
      }
    } catch (e) {
      print('فشل حذف المصروف من قائمة المصروفات: $e');
    }
  }
}