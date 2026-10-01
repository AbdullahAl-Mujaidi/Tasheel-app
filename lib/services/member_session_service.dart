// ignore_for_file: avoid_print
// lib/services/member_session_service.dart
// إدارة جلسة "المستخدم التابع" (Sub-user) داخل التطبيق.
//
// الإجابة على سؤال: من أنا؟ وماذا يخصني؟
//  - بعد تسجيل الدخول يُحلّ المستخدم: إما مالك (owner) أو مستخدم تابع (member).
//  - المستخدم التابع تُكتشف وثيقة عضويته (collectionGroup) لمعرفة ownerUid
//    وصلاحياته، وتُخزَّن محلياً في SQLite حتى يعمل التطبيق دون اتصال.
//  - قاعدة "التخزين": كل بيانات الأعمال/العمال/المصروفات تُمرَّر للموديلات
//    بـ ownerUid كمعرّف البيانات — حتى يرى التابع بيانات المالك فقط.
//  - عند عودة الاتصال تُحدَّث العضوية من الخادم (الصلاحيات الأخيرة دائماً) ولا
//    يمنح الكاش المحلي صلاحيات أكثر من المسموح به (الخادم هو الحماية النهائية).
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/network/connectivity_service.dart';
import '../model/team_member_model.dart';
import 'account_status_service.dart';

class MemberSessionService extends ChangeNotifier {
  MemberSessionService._();
  static final MemberSessionService instance = MemberSessionService._();

  final TeamMemberRepository _repo = TeamMemberRepository();

  TeamMember? _member;
  String? _authUid;
  String _ownerUid = '';

  bool _resolving = false;
  Timer? _refreshTimer;

  /// معرف الحساب المصادق عليه (قد يكون مالكاً أو تابِعاً).
  String? get authUid => _authUid;

  /// معرف المُخزّن البيانات (صاحب الحساب). يستخدمه التابع للوصول لبيانات المالك.
  String get ownerUid => _ownerUid;

  /// وثيقة العضوية (تُملأ فقط إذا كان المستخدم تابِعاً).
  TeamMember? get member => _member;

  bool get isSubUser => _member != null;

  bool get isOwner => FirebaseAuth.instance.currentUser != null && !isSubUser;

  bool get mustChangePassword => _member?.mustChangePassword ?? false;

  bool get isSessionReady => _authUid != null;

  bool get _isActive => _member == null || _member!.isActive;

  List<TeamMember> _availableDelegations = [];
  List<TeamMember> get availableDelegations => _availableDelegations;

  bool get isDelegatedActive => _member != null && _ownerUid.isNotEmpty && _ownerUid != _authUid;
  String get activeDelegatedOwnerName =>
      (_member?.ownerName != null && _member!.ownerName.isNotEmpty) ? _member!.ownerName : 'مالك الحساب';

  /// وصف الفاعل الحالي (مَن أضاف/عدَّل سجلاً): المعرّف، الدور، والتسمية المعروضة.
  /// - المالك في حسابه: الدور 'owner' والتسمية "المالك".
  /// - تابع مفوَّض (محمد/علي نيابة عن مالك): الدور 'delegated' والتسمية
  ///   "{اسمه} (مفوض)" — لتُخزَّن مع كل إنشاء/تعديل ويُعرف لاحقاً الفاعل الحقيقي.
  ({String uid, String role, String label}) get actor {
    final uid = _authUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (isDelegatedActive) {
      final name = (_member?.name.trim().isNotEmpty ?? false)
          ? _member!.name.trim()
          : 'مفوض';
      return (uid: uid, role: 'delegated', label: '$name (مفوض)');
    }
    return (uid: uid, role: 'owner', label: 'المالك');
  }

  /// هل يمكن للمستخدم الحالي الوصول إلى (module/action)؟
  /// المالك يملك كل شيء ضمنياً؛ التابع حسب الصلاحيات المصرّح بها.
  bool canAccess(String module, String action) {
    if (!_isActive) return false;
    final m = _member;
    if (m == null) return true; // المالك
    return m.canAccess(module, action);
  }

  bool canRead(String module) => canAccess(module, 'read');
  bool canCreate(String module) => canAccess(module, 'create');
  bool canUpdate(String module) => canAccess(module, 'update');
  bool canDelete(String module) => canAccess(module, 'delete');

  /// هل يمثل المستخدم الحالي دور المالك لحساب معيّن (وليس تابعاً مفوَّضاً)؟
  bool isActiveOwnerOf(String ownerUid) => isOwner && _ownerUid == ownerUid;

  /// صلاحية عملية على عنصر معيّن (يدعم التفويض على مستوى السجل):
  /// المالك يملك كل شيء؛ التابع وفق الصلاحية والنطاق المصرّح بهما.
  bool canAccessWork(String workId, String action) {
    if (!_isActive) return false;
    final m = _member;
    if (m == null) return true; // المالك
    return m.canAccessScoped(TeamPermissions.businesses, action, workId);
  }

  /// قائمة الأعمال المفوَّضة في حساب {ownerUid} (لتفويض على مستوى السجل)؛
  /// تُرجع فارغة للمالك أو للتفويض الكامل (يُعالج كلا الحالتين كـ"كل الأعمال").
  List<String> scopedBusinessIdsFor(String ownerUid) {
    final m = _member;
    if (m == null || m.ownerUid != ownerUid || !m.isScopedFor(TeamPermissions.businesses)) {
      return const [];
    }
    return m.scopedIdsFor(TeamPermissions.businesses);
  }

  /// صلاحية عملية على عامل معيّن (يدعم التفويض على مستوى السجل للعمال):
  /// المالك يملك كل شيء؛ التابع وفق الصلاحية والنطاق المصرّح بهما.
  bool canAccessWorker(String workerId, String action) {
    if (!_isActive) return false;
    final m = _member;
    if (m == null) return true; // المالك
    return m.canAccessScoped(TeamPermissions.workers, action, workerId);
  }

  /// قائمة العمال المفوَّضين في حساب {ownerUid} (لتفويض على مستوى السجل)؛
  /// تُرجع فارغة للمالك أو للتفويض الكامل (يُعالج كلا الحالتين كـ"كل العمال").
  List<String> scopedWorkerIdsFor(String ownerUid) {
    final m = _member;
    if (m == null || m.ownerUid != ownerUid || !m.isScopedFor(TeamPermissions.workers)) {
      return const [];
    }
    return m.scopedIdsFor(TeamPermissions.workers);
  }

  // ==================== التبديل بين الحسابات المفوضة ====================

  /// جلب التفويضات المتاحة للحساب الحالي (بعد تفعيل أي دعوات معلّقة)
  Future<void> fetchDelegations() async {
    final uid = _authUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // تفعيل دعوات معلّقة من أي مالك أولاً حتى تظهر التفويضات الجديدة.
    await _activatePendingInvites();
    try {
      _availableDelegations = await _repo.fetchDelegationsForUser(uid);
      notifyListeners();
    } catch (_) {}
  }

  /// التبديل الفوري إلى حساب مالك مفوض
  Future<void> switchToOwner(TeamMember membership) async {
    _member = membership;
    _ownerUid = membership.ownerUid;
    await _repo.saveMemberCached(membership);
    await _persistSession();
    notifyListeners();
  }

  /// العودة الفورية إلى الحساب الشخصي المستقل
  Future<void> switchToPersonal() async {
    final uid = _authUid ?? FirebaseAuth.instance.currentUser?.uid;
    _member = null;
    _ownerUid = uid ?? '';
    // إيقاف المزامنة الخلفية ثم إعادة تشغيلها: على الحساب الشخصي لا تفعّل
    // عضويةً بل تُفعّل أي دعوات تفويض جديدة وتحدّث قائمة التبديل فقط.
    _refreshTimer?.cancel();
    _refreshTimer = null;
    // مسح كاش العضوية حتى يعيد هذا المستخدم دائماً إلى حسابه الشخصي
    // عند الإقلاع اللاحق (لا يبقى ما يعيده قسراً لحساب المفوَّض).
    if (uid != null) {
      try {
        await _repo.clearMemberCache(uid);
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PrefKeys.sessionOwnerUid, _ownerUid);
      await prefs.remove(PrefKeys.sessionMemberUid);
    } catch (_) {}
    _startPeriodicRefresh();
    notifyListeners();
  }

  /// البحث عن حساب المالك بالبريد الإلكتروني وتفعيل التفويض فوراً
  Future<TeamMember?> linkDelegatorByEmail(String ownerEmail) async {
    final uid = _authUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final found = await _repo.linkDelegatorByEmail(uid, ownerEmail);
    if (found != null) {
      await fetchDelegations();
      await switchToOwner(found);
    }
    return found;
  }

  // ==================== حلّ الجلسة ====================

  /// يحلّ جلسة المستخدم الحالي: يقرأ الكاش المحلي أولاً (سريع/دون اتصال)
  /// ثم يحدّثه من الخادم عند توفر الاتصال.
  Future<void> resolveForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await clearSession();
      return;
    }
    if (_resolving) return;
    _resolving = true;
    try {
      _authUid = user.uid;

      // 0) تفضيل العرض المحفوظ: إذا اختار المستخدم سابقاً "حسابي الشخصي"
      //    (جلسة دون session_member_uid) نبقيه عليه عند كل إقلاع حتى لا
      //    يُعاد قسرياً إلى حساب مفوّض. غياب جلسة محفوظة = السلوك التلقائي
      //    القديم (تفعيل التفويض إن وُجد).
      final persisted = await loadPersistedSession();
      final wantPersonal = persisted != null &&
          persisted.memberUid == null &&
          persisted.ownerUid.isNotEmpty &&
          persisted.ownerUid == user.uid;

      // 1) محاولة العثور على عضوية من الكاش المحلي أولاً (فقط عند عدم
      //    التفضيل الشخصي؛ الشخصي يبدأ دائماً من بياناته هو بلا كاش عضوية).
      if (!wantPersonal) {
        final cached = await _repo.loadCachedMember(user.uid);
        if (cached != null && cached.ownerUid.isNotEmpty) {
          _member = cached;
          _ownerUid = cached.ownerUid;
          notifyListeners();
        }
      } else {
        _member = null;
        _ownerUid = user.uid;
      }

      // 2) الجلب من الخادم (إن أمكن) للحصول على أحدث صلاحيات.
      //    true → عضوية مؤكدة؛ false → تأكد أن المستخدم ليس تابعاً؛
      //    null → فشل الجلب (دون اتصال) فنستمر بالكاش المحلي.
      //    عند وجود تفويض محفوظ سلفاً نفضّل المالك نفسه لضمان الاستمرارية
      //    حتى لو كان المستخدم تابعاً لدى أكثر من مالك.
      final preferredOwner = persisted != null && persisted.memberUid != null
          ? persisted.ownerUid
          : null;
      final serverResult = await _tryFetchFromServer(user.uid,
          preferredOwner: preferredOwner);

      // 2.5) تفعيل الدعوات المعلّقة من *أي* مالك وتحديث قائمة التفويضات —
      //      دائماً، حتى لو كان المستخدم على حسابه الشخصي أو رغم وجود عضوية
      //      أخرى مفعّلة سلفاً. هذا يضمن وصول تفويض المالك الثاني (مثل علي)
      //      فورَ وصوله حتى مع بقاء المستخدم على حسابه الشخصي؛ لو لم يُنفَّذ
      //      هنا لبقيت الدعوات الجديدة علّقة ولن تظهر أبداً في قائمة التبديل.
      //      fetchDelegations لا يبدّل الحساب المعروض أبداً — الخطوتان 3.5/3.6
      //      هما اللتان تحفظان تفضيل "الحساب الشخصي" وتمنعان القفز التلقائي.
      await fetchDelegations();

      // 3) لا عضوية → هذا المستخدم مالك لبياناته (وحذف أي كاش قديم).
      if (serverResult == false || (serverResult == null && _member == null)) {
        if (serverResult == false) {
          await _repo.clearMemberCache(user.uid);
          _member = null;
        }
        _ownerUid = user.uid;
      }

      // 3.5) تفضيل شخصي رغم وجود عضوية فعّالة: نبقى على حسابنا الشخصي ولا
      //      نفعل التفويض؛ ويُنظَّف كاش العضوية حتى لا يعيده قسراً لاحقاً.
      if (wantPersonal && serverResult == true) {
        _member = null;
        _ownerUid = user.uid;
        await _repo.clearMemberCache(user.uid);
      }

      // 3.6) بعد تفعيل دعوة من مالك جديد ولم يكن للمستخدم أي تفويض معروض
      //      (سجّل دخولاً أول مرة): يظهر أول تفويض نشط كحسابٍ حالي.
      if (!wantPersonal && _member == null && _availableDelegations.isNotEmpty) {
        final first = _availableDelegations.firstWhere(
          (m) => m.status == 'active',
          orElse: () => _availableDelegations.first,
        );
        _member = first;
        _ownerUid = first.ownerUid;
        await _repo.saveMemberCached(first);
      }

      await _persistSession();
      // النافذة الدورية تعمل في الحالتين: للتابع (تحديث صلاحية العضوية) ولصاحب
      // الحساب الشخصي (تفعيل أي دعوات تفويض جديدة من أي مالك) — وإلا بقيت
      // الدعوات عالقة ما دام المستخدم على حسابه الشخصي دون إعادة فتح التطبيق.
      _startPeriodicRefresh();
      notifyListeners();
    } finally {
      _resolving = false;
    }
  }

  /// مزامنة خلفية خفيفة: يومِّن التطبيق دون اتصال بالكاش المحلي، وعند عودة
  /// الاتصال يُنزل أحدث الصلاحيات من الخادم ويحدّث التبويبات تلقائياً.
  /// تعمل حتى على الحساب الشخصي: تُفعّل دعوات التفويض الجديدة وتحدّث قائمة
  /// التبديل (دون تغيير الحساب المعروض أبداً).
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (FirebaseAuth.instance.currentUser == null) {
        timer.cancel();
        return;
      }
      try {
        await ConnectivityService.hasQuickInternet();
        if (isSubUser) {
          await refreshMemberProfile();
        } else {
          // تابع من أي مالك؟ لا — حسابه الشخصي: ننشّط الدعوات المعلّقة
          // ونتحقق من وصول تفويض جديد دون الخروج من الحساب الشخصي.
          await fetchDelegations();
        }
      } catch (_) {
        // دون اتصال: يبقى الكاش المحلي.
      }
    });
  }

  /// تفعيل كل "دعوات التفويض" المعلّقة لبريد الحساب الحالي (قد تكون من عدة
  /// مالكين مختلفين): يكتب وثائق العضوية بحساب المستخدم الحقيقي ثم يمسح
  /// الدعوات. تعمل دائماً — حتى لو كانت للمستخدم عضوية أخرى مفعّلة — حتى
  /// يصل تفويض كل مالك دون الحاجة لأول تسجيل دخول.
  Future<void> _activatePendingInvites() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final email = user.email?.trim().toLowerCase() ?? '';
    if (email.isEmpty) {
      print('تفعيل الدعوات: الحساب الحالي لا يحمل بريداً إلكترونياً');
      return;
    }
    final invites = await _repo.findInvitesByEmail(email);
    if (invites.isEmpty) {
      print('تفعيل الدعوات: لا توجد دعوات لبريد $email');
      return;
    }
    for (final invite in invites) {
      final status = (invite['status'] ?? '').toString();
      final ownerUid = (invite['ownerUid'] ?? '').toString();
      final inviteDocId = (invite['inviteDocId'] ?? '').toString();
      if (ownerUid.isEmpty || ownerUid == user.uid) continue;
      print('تفعيل الدعوات: وجدت دعوة للمالك $ownerUid (status=$status) للبريد $email');
      print('تفعيل الدعوات: وثيقة الدعوة ["$inviteDocId"] — بناء جديد مبني على inviteDocId الحقيقي');
      if (status != 'active') continue;
      try {
        // العضوية لهذا المالك مفعّلة سلفاً → تنظيف الدعوة فقط.
        final existing = await _repo.fetchMember(ownerUid, user.uid);
        if (existing != null) {
          await _repo.deleteInviteById(inviteDocId);
          print('تفعيل الدعوات: عضوية $ownerUid قائمة سلفاً — حُذفت دعوته فقط');
          continue;
        }
      } catch (_) {}
      try {
        await _repo.activateInvite(
          invite: invite,
          ownerUid: ownerUid,
          memberUid: user.uid,
          email: email,
        );
        await _repo.deleteInviteById(inviteDocId);
        print('تفعيل الدعوات: تم تفعيل العضوية للمالك $ownerUid');
      } catch (e) {
        // فشل التفعيل (اتصال/قواعد): لا نوقف حلّ الجلسة كاملاً، نُسجّل ونكمل.
        print('تفعيل الدعوات: فشل تفعيل العضوية لـ $ownerUid: $e');
      }
    }
  }

  /// الجلب من الخادم. يعيد:
  ///  - true: عُثر على عضوية.
  ///  - false: تأكد من عدم وجود عضوية (لا يقبل كاش قديم بعدها).
  ///  - null: فشل الاتصال بالخادم (يبقى الكاش المحلي سارياً دون اتصال).
  Future<bool?> _tryFetchFromServer(String uid, {String? preferredOwner}) async {
    try {
      // تفضيل المالك المحفوظ (استمرارية الحساب المعروض عند أكثر من تفويض).
      if (preferredOwner != null && preferredOwner.isNotEmpty && preferredOwner != uid) {
        try {
          final m = await _repo.fetchMember(preferredOwner, uid);
          if (m != null && m.isActive) {
            _member = m;
            _ownerUid = m.ownerUid;
            await _repo.saveMemberCached(m);
            return true;
          }
        } catch (_) {}
      }
      final found = await _repo.findMembershipByUid(uid);
      if (found != null && found.isActive) {
        _member = found;
        _ownerUid = found.ownerUid;
        await _repo.saveMemberCached(found);
        return true;
      }
      return false;
    } catch (_) {
      // دون اتصال أو خطأ: لا يمكن الجزم.
      return null;
    }
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_authUid != null) {
        await prefs.setString(PrefKeys.sessionOwnerUid, _ownerUid);
        if (isSubUser) {
          await prefs.setString(PrefKeys.sessionMemberUid, _authUid!);
        } else {
          await prefs.remove(PrefKeys.sessionMemberUid);
        }
      }
    } catch (_) {}
  }

  /// جلب آخر تحديثات الصلاحيات من الخادم وتطبيقها محلياً (تستدعى عند المزامنة).
  /// يُحدَّث تفويض المالك المعروض حاليّاً فقط — لا يعيد البحث عن "أول" عضوية
  /// كي لا يقفز المستخدم إلى حساب مالك آخر دون قصد.
  Future<void> refreshMemberProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isSubUser || _ownerUid.isEmpty) return;
    // تفعيل الدعوات المعلّقة من أي مالك أولاً (تفويض جديد يصل حتى دون
    // إعادة فتح التطبيق أو نافذة المفوضين) وتحديث قائمة التفويضات.
    await fetchDelegations();
    try {
      // فحص حالة المالك (هل أصبح موقوفاً؟)
      final ownerStatus = await AccountStatusService.instance.checkUid(_ownerUid);
      if (ownerStatus == AccountAccessState.suspended) {
        // ⭐ المالك موقوف وحسابي أنا نشط ⇒ ألغِ التفويض وارجعني لحسابي
        // الشخصي. (كان `switchToPersonal()` هنا أيضاً صحيحاً، لكن كان الحارس
        // afterwards يخرج المستخدم من حسابه بالكامل فينكبه.)
        print('refreshMemberProfile: المالك موقوف — يُلغى التفويض للحساب الشخصي');
        await switchToPersonal();
        return;
      }

      final fresh = await _repo.fetchMember(_ownerUid, user.uid);
      if (fresh != null) {
        if (!fresh.isActive) {
          print('refreshMemberProfile: تم تعطيل عضوية التابع، جارٍ الخروج');
          await switchToPersonal();
          return;
        }
        _member = fresh;
        _ownerUid = fresh.ownerUid;
        await _repo.saveMemberCached(fresh);
        notifyListeners();
        return;
      }
      // وثيقة العضوية لم تعد موجودة (حُذف الحساب): لا تبقى أي عضوية مخزنة.
      await _repo.clearMemberCache(user.uid);
      _member = null;
      _ownerUid = user.uid;
      _refreshTimer?.cancel();
      await _persistSession();
      notifyListeners();
    } catch (_) {
      // تحتفظ الجلسة بالكاش المحلي حتى عودة الاتصال.
    }
  }

  /// تحديث العضوية الحالية من الخادم قبل تطبيق نطاق التفويض/المزامنة حتى
  /// تعكس أحدث صلاحيات ونطاقات المالك المعروض (لا كاش قديم). إذا زالت عضوية
  /// المالك المعروض أو عُطِّلت (حُذف التفويض)، يُعاد المستخدم تلقائياً إلى
  /// حسابه الشخصي بدل الاستمرار بمزامنة مرفوضة (PERMISSION_DENIED) من قواعد
  /// الأمان على بيانات مالك لم يعد مفوَّضاً عليه.
  Future<void> refreshMembershipBeforeScope() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!isSubUser || _ownerUid.isEmpty || _ownerUid == user.uid) return;
    final ownerNow = _ownerUid;
    try {
      // ⚠️ فحص حالة المالك أولاً: قراءة وثيقة العضوية ستُرفض بالقواعد
      // (memberDocActive) بعد إيقاف المالك، فيرمي الاستثناء ويُبتلع في
      // `catch` أدناه — فتُحفظ الجلسة والكاش وكأن شيئاً لم يحدث. الفحص
      // الصريح يجعل الإيقاف ظاهراً بدل الاعتماد على استثناء.
      final ownerState = await AccountStatusService.instance.checkUid(ownerNow);
      if (ownerState == AccountAccessState.suspended) {
        // ⭐ المالك موقوف ⇒ يُلغى نطاق التفويض ويُعاد للحساب الشخصي بدل
        // ترك الجلسة تشير إلى مالك موقوف (فيُبتلع PERMISSION_DENIED في catch).
        print(
            'refreshMembershipBeforeScope: المالك موقوف — يُلغى التفويض للحساب الشخصي');
        await switchToPersonal();
        return;
      }

      final fresh = await _repo.fetchMember(ownerNow, user.uid);
      if (fresh != null && fresh.isActive) {
        _member = fresh;
        _ownerUid = fresh.ownerUid;
        await _repo.saveMemberCached(fresh);
        return;
      }
      // العضوية غير موجودة أو غير نشطة → الحساب الشخصي (دون notify تكرار).
      await switchToPersonal();
    } catch (_) {
      // دون اتصال أو فشل الجلب: تُحتفظ الجلسة والكاش الحاليين.
    }
  }

  /// توثيق تغيير كلمة المرور المؤقتة محلياً (يُستدعى بعد نجاح التغيير:
  /// updatePassword + إسقاط mustChangePassword من Firestore).
  Future<void> markPasswordChanged() async {
    final m = _member;
    if (m == null) return;
    _member = TeamMember(
      uid: m.uid,
      ownerUid: m.ownerUid,
      name: m.name,
      email: m.email,
      role: m.role,
      permissions: m.permissions,
      status: m.status,
      mustChangePassword: false,
      ownerName: m.ownerName,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
    );
    await _repo.saveMemberCached(_member!);
    _repo.setMustChangePasswordFalse(_ownerUid, m.uid).catchError((_) {});
    notifyListeners();
  }

  /// مسح الجلسة عند تسجيل الخروج.
  Future<void> clearSession() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _resolving = false;
    if (_member != null) {
      try {
        await _repo.clearMemberCache(_authUid!);
      } catch (_) {}
    }
    _member = null;
    _authUid = null;
    _ownerUid = '';
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefKeys.sessionOwnerUid);
      await prefs.remove(PrefKeys.sessionMemberUid);
    } catch (_) {}
  }

  /// قراءة جلسة محفوظة (للمرور السريع من Splash دون انتظار الشبكة).
  Future<({String ownerUid, String? memberUid})?> loadPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(PrefKeys.sessionOwnerUid);
      if (owner == null) return null;
      final memberUid = prefs.getString(PrefKeys.sessionMemberUid);
      return (ownerUid: owner, memberUid: memberUid);
    } catch (_) {
      return null;
    }
  }

  /// إعادة بناء الجلسة دون اتصال (المرور السريع من Splash مع غياب الشبكة):
  /// التابع يُعيد بناء عضويته من الكاش المحلي حتى لا يُعامل كمالك أبداً.
  Future<void> resolvePersistedSessionOffline(
      String ownerUid, String? memberUid) async {
    _authUid = memberUid ?? ownerUid;
    _ownerUid = ownerUid;
    _member = memberUid != null ? await _repo.loadCachedMember(memberUid) : null;
    notifyListeners();
  }
}