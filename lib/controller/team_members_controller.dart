// lib/controller/team_members_controller.dart
// التحكم في شاشة "المستخدمون" (إدارة المستخدمين التابعين) لصاحب الحساب.
// لا يملك التابعون أنفسهم صلاحية الوصول لهذه الشاشة (قواعد الأمان تمنع ذلك).
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../model/team_member_model.dart';
import '../services/member_api.dart';
import '../services/member_session_service.dart';

class TeamMembersController extends ChangeNotifier {
  /// معرف صاحب الحساب (المالك) — تُدار التابعون دائماً تحت حسابه.
  final String ownerUid;
  final TeamMemberRepository _repo = TeamMemberRepository();
  final MemberApi _api = MemberApi.instance;

  List<TeamMember> members = [];
  bool isLoading = true;
  bool isActing = false;
  String? error;
  String? success;

  // ========== نموذج الإضافة/التعديل ==========
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // الصلاحيات المختارة في النموذج (تُنسخ من القالب الفارغ عند الفتح).
  late Map<String, Map<String, bool>> selectedPermissions =
      _emptyPermissionMap();

  TeamMember? _editingMember;
  TeamMember? get editingMember => _editingMember;
  bool get isEditing => _editingMember != null;

  TeamMembersController({required this.ownerUid});

  static Map<String, Map<String, bool>> _emptyPermissionMap() {
    return TeamMember.permissionsForModules(const {});
  }

  // ========== تحميل القائمة ==========
  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      members = await _repo.fetchMembers(ownerUid);
      await _repo.saveMembersCached(ownerUid, members);
      isLoading = false;
      notifyListeners();
    } catch (e) {
      // دون اتصال: عرض الكاش المحلي مع تنبيه.
      try {
        members = await _repo.loadCachedMembers(ownerUid);
        error = members.isEmpty ? 'لا يوجد اتصال بالإنترنت' : null;
      } catch (_) {
        members = [];
      }
      isLoading = false;
      notifyListeners();
    }
  }

  // ========== توليد كلمة مرور مؤقتة قوية ==========
  static String generateTemporaryPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rand = Random.secure();
    // 12 حرفاً: أولها حرف كبير وآخرها رقم لضمان تلبية متطلبات القواعد
    // (حرف كبير + حرف صغير + رقم + طول >= 6).
    final buffer = StringBuffer();
    buffer.write(chars[rand.nextInt(24)]); // حرف كبير A-Z (24 حرفاً)
    for (var i = 0; i < 10; i++) {
      buffer.write(chars[rand.nextInt(57)]);
    }
    buffer.write(rand.nextInt(10)); // رقم أخير
    return buffer.toString();
  }

  // ========== إنشاء مستخدم تابع ==========
  Future<bool> createMember() async {
    if (!formKey.currentState!.validate()) return false;
    error = null;
    success = null;
    isActing = true;
    notifyListeners();
    try {
      await _api.createSubUser(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        temporaryPassword: passwordController.text.trim(),
        permissions: selectedPermissions,
      );
      await clearForm();
      await load();
      success = 'تم إنشاء المستخدم وإرسال كلمة المرور المؤقتة';
      isActing = false;
      notifyListeners();
      return true;
    } on MemberInviteSentException catch (e) {
      // بريد مسجّل مسبقاً: أُرسل تفويض وسيُفعَّل عند دخول العضو بحسابه.
      await clearForm();
      await load();
      success = e.message;
      isActing = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isActing = false;
      notifyListeners();
      return false;
    }
  }

  // ========== تعديل اسم/صلاحيات ==========
  Future<bool> updateMember() async {
    final target = _editingMember;
    if (target == null || !formKey.currentState!.validate()) return false;
    error = null;
    success = null;
    isActing = true;
    notifyListeners();
    try {
      await _api.updateSubUser(
        ownerUid: ownerUid,
        memberUid: target.uid,
        name: nameController.text.trim(),
        permissions: selectedPermissions,
      );
      await _refreshLocalMember(target.uid);
      await clearForm();
      await load();
      success = 'تم تعديل بيانات المستخدم';
      isActing = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isActing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _refreshLocalMember(String memberUid) async {
    // إن كان التعديل على العضو الحالي نفّذه من الخادم لتبديل الصلاحيات فوراً.
    final session = MemberSessionService.instance;
    if (session.authUid == memberUid) {
      await session.refreshMemberProfile();
    }
  }

  // ========== تعطيل/تفعيل ==========
  Future<bool> toggleStatus(TeamMember member) async {
    error = null;
    success = null;
    isActing = true;
    notifyListeners();
    try {
      await _api.setSubUserStatus(
        ownerUid: ownerUid,
        memberUid: member.uid,
        disabled: member.isActive,
      );
      await load();
      success = member.isActive ? 'تم تعطيل المستخدم' : 'تم تفعيل المستخدم';
      isActing = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isActing = false;
      notifyListeners();
      return false;
    }
  }

  // ========== إعادة تعيين كلمة المرور ==========
  Future<bool> resetPassword(TeamMember member) async {
    error = null;
    success = null;
    isActing = true;
    notifyListeners();
    try {
      // يعيد رسالة توضيحية: على الخطة المجانية تُرسل رسالة استعادة للبريد
      // وعند توفر الدوال تُعرض كلمة المرور المؤقتة الجديدة.
      final message = await _api.resetSubUserPassword(
        ownerUid: ownerUid,
        memberUid: member.uid,
        temporaryPassword: generateTemporaryPassword(),
      );
      await load();
      success = message;
      isActing = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isActing = false;
      notifyListeners();
      return false;
    }
  }

  // ========== حذف مستخدم تابع ==========
  Future<bool> deleteMember(TeamMember member) async {
    error = null;
    success = null;
    isActing = true;
    notifyListeners();
    try {
      await _api.deleteSubUser(ownerUid: ownerUid, memberUid: member.uid);
      // تنظيف كاش قائمة المستخدمين بعد الحذف.
      members.removeWhere((m) => m.uid == member.uid);
      await _repo.saveMembersCached(ownerUid, members);
      await load();
      success = 'تم حذف المستخدم نهائياً';
      isActing = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isActing = false;
      notifyListeners();
      return false;
    }
  }

  // ========== إدارة النموذج ==========
  void startCreate() {
    _editingMember = null;
    nameController.clear();
    emailController.clear();
    passwordController.text = generateTemporaryPassword();
    selectedPermissions = _emptyPermissionMap();
    error = null;
    notifyListeners();
  }

  void startEdit(TeamMember member) {
    _editingMember = member;
    nameController.text = member.name;
    emailController.text = member.email;
    passwordController.clear();
    selectedPermissions = Map<String, Map<String, bool>>.from(
      member.permissions.map((k, v) => MapEntry(k, Map<String, bool>.from(v))),
    );
    error = null;
    notifyListeners();
  }

  Future<void> clearForm() async {
    _editingMember = null;
    nameController.clear();
    emailController.clear();
    passwordController.clear();
    selectedPermissions = _emptyPermissionMap();
    error = null;
    notifyListeners();
  }

  void setPermission(String module, String action, bool value) {
    selectedPermissions[module]?[action] = value;
    // منح/سحب القراءة عند تفعيل الكتابة في الوحدات الكاملة (قراءة ملازمة).
    if (action != 'read' &&
        value &&
        module != TeamPermissions.reports &&
        module != TeamPermissions.settings) {
      selectedPermissions[module]?['read'] = true;
    }
    notifyListeners();
  }

  String? validateName(String? v) {
    if (v == null || v.trim().length < 3) return 'الاسم يجب أن يكون 3 أحرف على الأقل';
    return null;
  }

  String? validateEmail(String? v) {
    final value = v?.trim() ?? '';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(value)) {
      return 'أدخل بريداً إلكترونياً صحيحاً';
    }
    // منع التفويض الذاتي: لا يمكن لصاحب الحساب تفويض نفسه بنفس بريده.
    final selfEmail = FirebaseAuth.instance.currentUser
        ?.email
        ?.trim()
        .toLowerCase();
    if (selfEmail != null && value.toLowerCase() == selfEmail) {
      return 'لا يمكن تفويض نفسك بنفس بريدك';
    }
    return null;
  }

  String? validatePassword(String? v) {
    if (isEditing) return null; // التعديل لا يغيّر كلمة المرور
    final value = v ?? '';
    final hasUpper = RegExp(r'[A-Z]').hasMatch(value);
    final hasLower = RegExp(r'[a-z]').hasMatch(value);
    final hasDigit = RegExp(r'[0-9]').hasMatch(value);
    if (value.length < 6 || !hasUpper || !hasLower || !hasDigit) {
      return 'ضعيفة: 6+ أحرف مع حرف كبير ورقم';
    }
    return null;
  }

  // ========== الأسماء العربية للمساعدة في الرسائل ==========
  static String moduleLabel(String module) {
    switch (module) {
      case TeamPermissions.businesses:
        return 'الأعمال';
      case TeamPermissions.workers:
        return 'العمال';
      case TeamPermissions.expenses:
        return 'المصروفات';
      case TeamPermissions.reports:
        return 'التقارير';
      case TeamPermissions.settings:
        return 'الإعدادات';
      default:
        return module;
    }
  }

  static String actionLabel(String action) {
    switch (action) {
      case 'read':
        return 'عرض';
      case 'create':
        return 'إضافة';
      case 'update':
        return 'تعديل';
      case 'delete':
        return 'حذف';
      default:
        return action;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}