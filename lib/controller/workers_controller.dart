// ignore_for_file: avoid_print
import 'dart:async';
import 'package:fkra/admin/services/admin_session_service.dart';
import 'package:fkra/controller/team_members_controller.dart';
import 'package:fkra/model/workers_model.dart';
import 'package:fkra/model/expense_model.dart';
import 'package:fkra/model/login_model.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/activity_service.dart';
import 'package:fkra/services/analytics_service.dart';
import 'package:fkra/services/member_api.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:flutter/material.dart';

class WorkersController extends ChangeNotifier {
  final String userId;
  final WorkersModel _model;

  late final Future<void> ready;

  List<Map<String, dynamic>> workers = [];
  bool isOffline = false;
  bool isLoading = true;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController specializationController =
      TextEditingController();
  final TextEditingController salaryController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  String wageType = 'monthly';
  DateTime date = DateTime.now();

  String? _editingWorkerId;
  bool _isEditing = false;

  Timer? _syncTimer;

  WorkersController({required this.userId})
      : _model = WorkersModel(userId: userId) {
    ready = _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    await _applySessionScope();
    workers = List.from(_model.localWorkers);
    await _checkConnectivity();
    _startPeriodicSync();
    isLoading = false;
    notifyListeners();
  }

  /// نسخ نطاق المشاركة (عامل محدد) من جلسة المستخدم التابع الحالية إلى
  /// النموذج، حتى يُحمَّل من السحاب في حدود المفوَّض فقط. قبل القراءة يُحدَّث
  /// التفويض من الخادم ليمنع استعمال نطاق قديم (يُرفض استعلاماً عريضاً).
  Future<void> _applySessionScope() async {
    await MemberSessionService.instance.refreshMembershipBeforeScope();
    _model.setScopedWorkerIds(
      MemberSessionService.instance.scopedWorkerIdsFor(userId),
    );
  }

  /// تحديد معرّفات عمال النطاق المسموح به (فارغ = المالك/كل العمال).
  Set<String>? get _scopedAllowedWorkerIds {
    final ids = MemberSessionService.instance.scopedWorkerIdsFor(userId);
    return ids.isEmpty ? null : ids.toSet();
  }

  /// صحيح عند عرض حساب بنطاق تفويض مقيّد — لا نُحفظ القوائم المفلترة في
  /// التخزين المحلي (الكاش محفوظ باسم المالك ولا يجوز المساس به).
  bool get _isScopedMode => _scopedAllowedWorkerIds != null;

  Future<void> _checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
    if (hasInternet) await _syncWithFirestore();
  }

  Future<void> _syncWithFirestore() async {
    try {
      // يُمكَّن النطاق منقّحاً (قد تُضاف مشاركات جديدة أثناء الجلسة).
      await _applySessionScope();
      await _model.syncWithFirestore(workers);
      if (_isScopedMode) {
        // الجلسة المقيّدة: النموذج دمج المفوَّضين في قائمة الذاكرة وسقَط
        // غيرهم — لا نعيد التحميل من القرص (قد يمسح التحميلات المقيّدة)،
        // والقرص باسم المالك لا يُكتب فيه في هذه الحالة.
        final allowed = _scopedAllowedWorkerIds;
        if (allowed != null) {
          workers = workers
              .where((w) => allowed.contains(w['id']?.toString()))
              .toList();
        }
      } else {
        await _model.loadLocalWorkers();
        workers = List.from(_model.localWorkers);
      }
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

  Future<void> syncNow() async {
    await _syncWithFirestore();
  }

  // ========== مشاركة عامل واحد ==========

  /// مشاركة عامل محدد مع مستخدم تابع (قراءة + تعديل على هذا العامل فقط):
  /// بحث عن عضو قائم بالبريد، وإلا إنشاء حساب جديد أو دعوة تفويض مقيّدة.
  Future<String> shareWorker(
      String workerId, String name, String email) async {
    final ownerUid = userId;
    final cleanEmail = email.trim().toLowerCase();
    final workerName = 'العامل (${_nameOf(workerId)})';

    final myEmail = LoginModel().currentUserEmail;
    if (cleanEmail == myEmail) {
      throw 'لا يمكن مشاركة $workerName مع بريدك أنت';
    }

    final repo = TeamMemberRepository();
    final member = await repo.findSubUserByEmail(ownerUid, cleanEmail);
    if (member != null) {
      if (member.isPending) {
        await repo.addScopedWorkerToInvite(
            ownerUid: ownerUid, email: cleanEmail, workerId: workerId);
        return 'تمت مشاركة $workerName مع $name — التفويض قيد التفعيل '
            'عند أول تسجيل دخول لصاحب البريد.';
      }
      if (member.canRead(TeamPermissions.workers) &&
          member.canUpdate(TeamPermissions.workers) &&
          !member.isScopedFor(TeamPermissions.workers)) {
        return '$name يملك أصلاً وصولاً كاملاً إلى جميع عمالك.';
      }
      await repo.grantScopedWorker(
          ownerUid: ownerUid, memberUid: member.uid, workerId: workerId);
      return 'تمت مشاركة $workerName مع $name.';
    }

    // لا يوجد عضو بهذا البريد: إنشاء حساب جديد (أو دعوة تفويض) مقيّد على العامل.
    // إن كانت توجد دعوة معلّقة من نفس المالك لهذا البريد نُلحِق العامل بدل
    // إنشاء دعوة جديدة كي لا تُضاعِف الإدخالات.
    final pending = await repo.findPendingInvite(ownerUid, cleanEmail);
    if (pending != null) {
      await repo.addScopedWorkerToInvite(
          ownerUid: ownerUid, email: cleanEmail, workerId: workerId);
      return 'تمت مشاركة $workerName مع $name — التفويض قيد التفعيل '
          'عند أول تسجيل دخول لصاحب البريد.';
    }

    final tempPassword = TeamMembersController.generateTemporaryPassword();
    final permissions = TeamMember.permissionsForModules(const {});
    permissions[TeamPermissions.workers] = {
      'read': true,
      'create': false,
      'update': true,
      'delete': false,
    };
    try {
      await MemberApi.instance.createSubUser(
        name: name,
        email: cleanEmail,
        temporaryPassword: tempPassword,
        permissions: permissions,
        scopedIds: {TeamPermissions.workers: [workerId]},
      );
      return 'تم إنشاء الحساب ومشاركة $workerName مع $name.\n'
          'كلمة المرور المؤقتة: $tempPassword (تُغيَّر عند أول دخول).';
    } on MemberInviteSentException catch (e) {
      return '${e.message}\nوسيُشارَك $workerName معه عند تفعيل التفويض.';
    }
  }

  String _nameOf(String workerId) {
    final w = getWorkerById(workerId);
    return w?['name']?.toString().trim().isNotEmpty == true
        ? w!['name'].toString()
        : 'بدون اسم';
  }

  // ========== عمليات العمال ==========
  Future<bool> addWorker(BuildContext context) async {
    if (AdminSessionService.instance.role != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حساب المدير مخصص للإدارة والإشراف فقط، ولا يمكنه إضافة عمال.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canCreate(TeamPermissions.workers)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا تملك صلاحية إضافة عمال.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (!formKey.currentState!.validate()) return false;

    final workerId = DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = DateTime.now().toIso8601String();
    final actor = MemberSessionService.instance.actor;

    Map<String, dynamic> workerData = {
      'id': workerId,
      'name': nameController.text,
      'phone': phoneController.text,
      'specialization': specializationController.text,
      'salary': double.tryParse(salaryController.text) ?? 0,
      'wageType': wageType,
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': createdAt,
      'status': 'active',
      'businessId': null,
      'workRecords': <Map<String, dynamic>>[],
      'payments': <Map<String, dynamic>>[],
      'advances': <Map<String, dynamic>>[],
      'workerExpenses': <Map<String, dynamic>>[],
      'createdByLabel': actor.label,
      'createdByRole': actor.role,
      'createdByUid': actor.uid,
    };

    workers.insert(0, workerData);
    await _model.saveWorkersToFile(workers);
    notifyListeners();

    unawaited(() async {
      await _syncSingleWorkerIfNeeded(workerData);
      await ActivityService.recordActivity(userId: userId);
      await AnalyticsService.instance.logWorkerAdded();
    }());
    _resetForm();
    return true;
  }

  Future<bool> editWorker(BuildContext context) async {
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canUpdate(TeamPermissions.workers)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا تملك صلاحية تعديل العمال.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (!formKey.currentState!.validate() || _editingWorkerId == null) return false;

    final index = workers.indexWhere((e) => e['id'] == _editingWorkerId);
    if (index == -1) return false;

    final existing = workers[index];
    final actor = MemberSessionService.instance.actor;
    Map<String, dynamic> updatedData = {
      'id': _editingWorkerId,
      'name': nameController.text,
      'phone': phoneController.text,
      'specialization': specializationController.text,
      'salary': double.tryParse(salaryController.text) ?? 0,
      'wageType': wageType,
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': existing['createdAt'],
      'status': existing['status'] ?? 'active',
      'businessId': existing['businessId'],
      'workRecords': existing['workRecords'] ?? [],
      'payments': existing['payments'] ?? [],
      'advances': existing['advances'] ?? [],
      'workerExpenses': existing['workerExpenses'] ?? [],
      'createdByLabel': existing['createdByLabel'],
      'createdByRole': existing['createdByRole'],
      'createdByUid': existing['createdByUid'],
      'lastModifiedByLabel': actor.label,
      'lastModifiedByRole': actor.role,
      'lastModifiedByUid': actor.uid,
    };

    workers[index] = updatedData;
    await _model.saveWorkersToFile(workers);
    notifyListeners();

    unawaited(_syncSingleWorkerIfNeeded(updatedData));
    _resetForm();
    return true;
  }

  Future<void> deleteWorker(String workerId) async {
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canDelete(TeamPermissions.workers)) {
      return;
    }

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

  void loadWorkerForEditing(Map<String, dynamic> worker) {
    nameController.text = worker['name'] ?? '';
    phoneController.text = worker['phone'] ?? '';
    specializationController.text = worker['specialization'] ?? '';
    salaryController.text = worker['salary']?.toString() ?? '';
    wageType = worker['wageType'] ?? 'monthly';
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
    wageType = 'monthly';
    date = DateTime.now();
    _editingWorkerId = null;
    _isEditing = false;
    notifyListeners();
  }

  bool get isEditing => _isEditing;
  String? get editingWorkerId => _editingWorkerId;

  // ========== سجل العمل ==========
  Future<void> addWorkRecord(String workerId,
      {required double quantity,
      required String unit,
      required double amount,
      String note = ''}) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    final record = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'date': DateTime.now().toIso8601String(),
      'quantity': quantity,
      'unit': unit,
      'amount': amount,
      'note': note,
      'createdByLabel': MemberSessionService.instance.actor.label,
      'createdByRole': MemberSessionService.instance.actor.role,
      'createdByUid': MemberSessionService.instance.actor.uid,
    };

    (worker['workRecords'] as List).add(record);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);
  }

  Future<void> deleteWorkRecord(String workerId, String recordId) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    (worker['workRecords'] as List).removeWhere((r) => r['id'] == recordId);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);
  }

  // ========== الدفعات ==========
  Future<void> addPayment(String workerId,
      {required double amount, String note = ''}) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    final payment = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'date': DateTime.now().toIso8601String(),
      'amount': amount,
      'note': note,
      'createdByLabel': MemberSessionService.instance.actor.label,
      'createdByRole': MemberSessionService.instance.actor.role,
      'createdByUid': MemberSessionService.instance.actor.uid,
    };

    (worker['payments'] as List).add(payment);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);

    final workerName = worker['name']?.toString();
    await _linkWorkerTxToGeneral(
      type: 'payment',
      tx: payment,
      workerId: workerId,
      workerName: workerName,
    );
  }

  Future<void> deletePayment(String workerId, String paymentId) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    (worker['payments'] as List).removeWhere((p) => p['id'] == paymentId);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);

    await _unlinkWorkerTxFromGeneral(paymentId);
  }

  // ========== السلف ==========
  Future<void> addAdvance(String workerId,
      {required double amount, String note = ''}) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    final advance = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'date': DateTime.now().toIso8601String(),
      'amount': amount,
      'note': note,
      'createdByLabel': MemberSessionService.instance.actor.label,
      'createdByRole': MemberSessionService.instance.actor.role,
      'createdByUid': MemberSessionService.instance.actor.uid,
    };

    (worker['advances'] as List).add(advance);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);

    final workerName = worker['name']?.toString();
    await _linkWorkerTxToGeneral(
      type: 'advance',
      tx: advance,
      workerId: workerId,
      workerName: workerName,
    );
  }

  Future<void> deleteAdvance(String workerId, String advanceId) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    (worker['advances'] as List).removeWhere((a) => a['id'] == advanceId);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);

    await _unlinkWorkerTxFromGeneral(advanceId);
  }

  // ========== مصروفات العامل ==========
  Future<void> addWorkerExpense(String workerId,
      {required double amount,
      String description = '',
      String? expenseId,
      bool linkToGeneral = true}) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    final expense = {
      'id': expenseId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'date': DateTime.now().toIso8601String(),
      'amount': amount,
      'description': description,
      'createdByLabel': MemberSessionService.instance.actor.label,
      'createdByRole': MemberSessionService.instance.actor.role,
      'createdByUid': MemberSessionService.instance.actor.uid,
    };

    (worker['workerExpenses'] as List).add(expense);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);

    if (!linkToGeneral) return;

    final workerName = worker['name']?.toString();
    await _linkWorkerTxToGeneral(
      type: 'expense',
      tx: expense,
      workerId: workerId,
      workerName: workerName,
    );
  }

  Future<void> deleteWorkerExpense(
      String workerId, String expenseId) async {
    final worker = getWorkerById(workerId);
    if (worker == null) return;

    (worker['workerExpenses'] as List)
        .removeWhere((e) => e['id'] == expenseId);
    worker['synced'] = 0;
    await _model.saveWorkersToFile(workers);
    notifyListeners();
    await _syncSingleWorkerIfNeeded(worker);

    await _unlinkWorkerTxFromGeneral(expenseId);
  }

  // حذف مصروف عامل بواسطة المعرّف (يُستخدم عند حذف مصروف عمل مرتبط بعامل)
  Future<void> deleteWorkerExpenseById(String expenseId) async {
    for (final worker in workers) {
      final list = (worker['workerExpenses'] as List);
      final int index = list.indexWhere((e) => e['id'] == expenseId);
      if (index == -1) continue;
      list.removeAt(index);
      worker['synced'] = 0;
      await _model.saveWorkersToFile(workers);
      notifyListeners();
      await _syncSingleWorkerIfNeeded(worker);
      return;
    }
  }

  // ========== الربط مع المصروفات العامة ==========
  Future<void> _linkWorkerTxToGeneral({
    required String type,
    required Map<String, dynamic> tx,
    required String workerId,
    required String? workerName,
  }) async {
    // في وضع التفويض المقيّد لا يُربَط أي مصروف عام (القواعد ترفض الرفع
    // ولا يجوز الكتابة في كاش المصروفات المحلي المحفوظ باسم المالك).
    if (_isScopedMode) return;
    try {
      final ExpenseModel model = ExpenseModel(userId: userId);
      await model.initStorage();

      final String category;
      final String source;
      final String desc;
      final String fallback = workerName ?? 'العامل';

      switch (type) {
        case 'payment':
          category = 'أجور';
          source = 'workerPayment';
          final String note =
              (tx['note'] ?? '').toString().trim();
          desc =
              note.isNotEmpty ? note : 'أجرة عامل: $fallback';
          break;
        case 'advance':
          category = 'سلف';
          source = 'workerAdvance';
          final String note =
              (tx['note'] ?? '').toString().trim();
          desc = note.isNotEmpty ? note : 'سلفة عامل: $fallback';
          break;
        case 'expense':
        default:
          category = 'اخرى';
          source = 'worker';
          final String d = (tx['description'] ?? '')
              .toString()
              .trim();
          desc = d.isNotEmpty ? d : 'مصروف عامل: $fallback';
          break;
      }

      final Map<String, dynamic> expenseData = {
        'id': tx['id'],
        'description': desc,
        'amount': (tx['amount'] as num?)?.toDouble() ?? 0,
        'category': category,
        'date': tx['date'],
        'synced': 0,
        'createdAt': DateTime.now().toIso8601String(),
        'source': source,
        'workerId': workerId,
        'workerName': workerName,
        'createdByLabel': tx['createdByLabel'],
        'createdByRole': tx['createdByRole'],
        'createdByUid': tx['createdByUid'],
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
          print('فشل رفع مصروف العامل إلى السحاب: $e');
        }
      }
    } catch (e) {
      print('فشل إضافة مصروف العامل إلى المصروفات العامة: $e');
    }
  }

  Future<void> _unlinkWorkerTxFromGeneral(String expenseId) async {
    if (_isScopedMode) return;
    try {
      final ExpenseModel model = ExpenseModel(userId: userId);
      await model.initStorage();
      final List<Map<String, dynamic>> list =
          List<Map<String, dynamic>>.from(model.localExpenses);
      final int index = list.indexWhere((e) => e['id'] == expenseId);
      if (index == -1) return;
      final String source =
          (list[index]['source'] ?? '').toString();
      list.removeAt(index);
      await model.saveExpensesToFile(list);

      if (source.startsWith('worker')) {
        final bool hasInternet = await model.hasInternet();
        if (hasInternet) {
          try {
            await model.deleteExpenseFromFirestore(expenseId);
          } catch (e) {
            print('فشل حذف مصروف العامل من السحاب: $e');
          }
        }
      }
    } catch (e) {
      print('فشل حذف مصروف العامل من المصروفات: $e');
    }
  }

  // ========== ربط العامل بعمل ==========
  void setWorkerBusiness(String workerId, String? businessId) {
    final worker = getWorkerById(workerId);
    if (worker == null) return;
    worker['businessId'] = businessId;
    worker['synced'] = 0;
    final actor = MemberSessionService.instance.actor;
    worker['lastModifiedByLabel'] = actor.label;
    worker['lastModifiedByRole'] = actor.role;
    worker['lastModifiedByUid'] = actor.uid;
    _model.saveWorkersToFile(workers);
    notifyListeners();
    _syncSingleWorkerIfNeeded(worker);
  }

  // ========== حساب الملخص ==========
  Map<String, dynamic> calculateWorkerSummary(String workerId) {
    final worker = getWorkerById(workerId);
    if (worker == null) {
      return {
        'totalEarned': 0,
        'totalPaid': 0,
        'totalAdvances': 0,
        'totalWorkerExpenses': 0,
        'totalWorkDays': 0,
        'remaining': 0,
      };
    }

    final totalEarned = (worker['workRecords'] as List).fold<double>(
        0,
        (sum, r) {
          final amt = ((r as Map<String, dynamic>?)?['amount'] as num?)?.toDouble() ?? 0;
          return sum + amt;
        });
    final totalWorkDays = (worker['workRecords'] as List).fold<double>(
        0,
        (sum, r) {
          final qty = ((r as Map<String, dynamic>?)?['quantity'] as num?)?.toDouble() ?? 0;
          return sum + qty;
        });
    final totalPaid = (worker['payments'] as List).fold<double>(
        0,
        (sum, p) {
          final amt = ((p as Map<String, dynamic>?)?['amount'] as num?)?.toDouble() ?? 0;
          return sum + amt;
        });
    final totalAdvances = (worker['advances'] as List).fold<double>(
        0,
        (sum, a) {
          final amt = ((a as Map<String, dynamic>?)?['amount'] as num?)?.toDouble() ?? 0;
          return sum + amt;
        });
    final totalWorkerExpenses = (worker['workerExpenses'] as List).fold<double>(
        0,
        (sum, e) {
          final amt = ((e as Map<String, dynamic>?)?['amount'] as num?)?.toDouble() ?? 0;
          return sum + amt;
        });
    final remaining = totalEarned - totalPaid - totalAdvances;

    return {
      'totalEarned': totalEarned.toInt(),
      'totalPaid': totalPaid.toInt(),
      'totalAdvances': totalAdvances.toInt(),
      'totalWorkerExpenses': totalWorkerExpenses.toInt(),
      'totalWorkDays': totalWorkDays.toInt(),
      'remaining': remaining.toInt(),
    };
  }

  // ========== صفوف كشف الحساب ==========
  List<Map<String, dynamic>> getStatementRows(String workerId) {
    final rows = <Map<String, dynamic>>[];
    final worker = getWorkerById(workerId);
    if (worker == null) return rows;

    for (var r in (worker['workRecords'] as List)) {
      final unitStr = unitLabel((r as Map<String, dynamic>)['unit'] ?? 'day');
      final qty = r['quantity'] ?? 0;
      rows.add({
        'id': r['id'],
        'type': 'work',
        'amount': (r['amount'] as num?)?.toInt() ?? 0,
        'description': 'سجل عمل: $qty $unitStr${(r['note'] ?? '').toString().isNotEmpty ? ' - ${r['note']}' : ''}',
        'date': r['date'],
        'sign': '+',
      });
    }

    for (var p in (worker['payments'] as List)) {
      rows.add({
        'id': (p as Map<String, dynamic>)['id'],
        'type': 'payment',
        'amount': (p['amount'] as num?)?.toInt() ?? 0,
        'description': 'دفعة${(p['note'] ?? '').toString().isNotEmpty ? ': ${p['note']}' : ''}',
        'date': p['date'],
        'sign': '+',
      });
    }

    for (var a in (worker['advances'] as List)) {
      rows.add({
        'id': (a as Map<String, dynamic>)['id'],
        'type': 'advance',
        'amount': (a['amount'] as num?)?.toInt() ?? 0,
        'description': 'سلفة${(a['note'] ?? '').toString().isNotEmpty ? ': ${a['note']}' : ''}',
        'date': a['date'],
        'sign': '-',
      });
    }

    for (var e in (worker['workerExpenses'] as List)) {
      rows.add({
        'id': (e as Map<String, dynamic>)['id'],
        'type': 'expense',
        'amount': (e['amount'] as num?)?.toInt() ?? 0,
        'description': 'مصروف${(e['description'] ?? '').toString().isNotEmpty ? ': ${e['description']}' : ''}',
        'date': e['date'],
        'sign': '-',
      });
    }

    rows.sort((a, b) {
      try {
        return DateTime.parse(b['date'].toString())
            .compareTo(DateTime.parse(a['date'].toString()));
      } catch (_) {
        return 0;
      }
    });

    return rows;
  }

  // ========== دوال مساعدة ==========
  Map<String, dynamic>? getWorkerById(String workerId) {
    for (final w in workers) {
      if (w['id'] != null && w['id'].toString() == workerId) return w;
    }
    return null;
  }

  String wageTypeLabel(String type) {
    switch (type) {
      case 'monthly':
        return 'شهري';
      case 'weekly':
        return 'أسبوعي';
      case 'daily':
        return 'يومي';
      case 'halfDay':
        return 'نصف يوم';
      case 'hourly':
        return 'بالساعة';
      default:
        return type;
    }
  }

  String unitLabel(String unit) {
    switch (unit) {
      case 'day':
        return 'يوم';
      case 'halfDay':
        return 'نصف يوم';
      case 'hour':
        return 'ساعة';
      case 'week':
        return 'أسبوع';
      case 'month':
        return 'شهر';
      default:
        return unit;
    }
  }

  void setWageType(String value) {
    wageType = value;
    notifyListeners();
  }

  void setDate(DateTime newDate) {
    date = newDate;
    notifyListeners();
  }

  void updateSearch(String value) {
    notifyListeners();
  }

  List<Map<String, dynamic>> get filteredWorkers {
    // تفويض على مستوى السجل: يعرض فقط العمال المفوَّضين (يشمل حالة عرض
    // القرص دون اتصال حيث تُقرأ القائمة الكاملة المخزنة باسم المالك).
    final scopedAllowed = _scopedAllowedWorkerIds;
    final searchText = searchController.text.toLowerCase();
    return workers.where((worker) {
      if (scopedAllowed != null &&
          !scopedAllowed.contains(worker['id']?.toString())) {
        return false;
      }
      final matchesSearch = searchText.isEmpty ||
          worker['name']?.toLowerCase().contains(searchText) == true;
      return matchesSearch;
    }).toList();
  }

  Future<void> _syncSingleWorkerIfNeeded(
      Map<String, dynamic> worker) async {
    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.saveWorkerToFirestore(worker, true);
        worker['synced'] = 1;
        await _model.saveWorkersToFile(workers);
        notifyListeners();
      } catch (e) {
        print('فشل مزامنة العامل: $e');
      }
    }
  }

  void resetForm() {
    _resetForm();
  }

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
}
