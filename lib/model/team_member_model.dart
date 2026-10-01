// ignore_for_file: avoid_print
// lib/model/team_member_model.dart
// نموذج "المستخدم التابع" (Sub-user / Employee).
//
// المستخدم التابع:
//  - لديه حساب Firebase Authentication خاص (uid + email + كلمة مرور) للمصادقة فقط.
//  - بياناته الحقيقية (الأعمال/العمال/المصروفات...) تعود لصاحب الحساب (ownerUid).
//  - لا يحق له تعديل ownerUid أو permissions أو status في وثيقته (Rules تمنع ذلك).
//
// الصلاحيات صيغة قابلة للتوسع على مستوى العملية:
//   permissions[module][action] = bool
//   modules : businesses / workers / expenses / reports / settings
//   actions : read / create / update / delete
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/db/database_helper.dart';
import '../services/account_status_service.dart';

/// الوحدات المدعومة في التطبيق (نفس أسماء مسارات البيانات أو الصفحات).
class TeamPermissions {
  static const String businesses = 'businesses';
  static const String workers = 'workers';
  static const String expenses = 'expenses';
  static const String reports = 'reports';
  static const String settings = 'settings';

  static const List<String> modules = [
    businesses,
    workers,
    expenses,
    reports,
    settings,
  ];

  static const List<String> actions = ['read', 'create', 'update', 'delete'];
}

class TeamMember {
  final String uid;
  final String ownerUid;
  final String name;
  final String email;
  final String role;
  final Map<String, Map<String, bool>> permissions;
  final String status;
  final bool mustChangePassword;
  final String ownerName;

  /// تفويض على مستوى السجل: لكل وحدة قائمة معرفات العناصر المسموح بها.
  /// غياب الوحدة أو قائمة فارغة = الوحدة كلها (تفويض كامل).
  final Map<String, List<String>> scopedIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TeamMember({
    required this.uid,
    required this.ownerUid,
    required this.name,
    required this.email,
    this.role = 'employee',
    required this.permissions,
    this.status = 'active',
    this.mustChangePassword = true,
    this.ownerName = '',
    this.scopedIds = const {},
    this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == 'active';

  /// تفويض قيد التفعيل: دعوة أنشأها المالك لبريد مسجّل مسبقاً، ولم يسجّل
  /// صاحب البريد دخوله بعد لتفعيل العضوية (لا وثيقة عضوية بعد بالمعرف
  /// الحقيقي — يكشفها العميل عند تسجيل الدخول فقط).
  bool get isPending => status == 'pending';

  static const Map<String, Map<String, bool>> emptyPermissions = {
    'businesses': {'read': false, 'create': false, 'update': false, 'delete': false},
    'workers': {'read': false, 'create': false, 'update': false, 'delete': false},
    'expenses': {'read': false, 'create': false, 'update': false, 'delete': false},
    'reports': {'read': false},
    'settings': {'read': false, 'update': false},
  };

  /// صلاحية عتد إلقاء نظرة على الوحدة (كل العمليات مفعلة للوحدات الكاملة،
  /// والتقارير والإعدادات قراءة فقط).
  static Map<String, Map<String, bool>> permissionsForModules(
      Set<String> modules) {
    final Map<String, Map<String, bool>> result = {};
    for (final m in TeamPermissions.modules) {
      final bool enabled = modules.contains(m);
      final actions = <String, bool>{
        'read': enabled,
        'create': enabled,
        'update': enabled,
        'delete': enabled,
      };
      if (m == TeamPermissions.reports || m == TeamPermissions.settings) {
        actions.remove('create');
        actions.remove('update');
        actions.remove('delete');
        actions['read'] = enabled;
      }
      result[m] = actions;
    }
    return result;
  }

  bool canAccess(String module, String action) {
    if (status != 'active') return false;
    final modulePerm = permissions[module];
    if (modulePerm == null) return false;
    return modulePerm[action] == true;
  }

  bool canRead(String module) => canAccess(module, 'read');
  bool canCreate(String module) => canAccess(module, 'create');
  bool canUpdate(String module) => canAccess(module, 'update');
  bool canDelete(String module) => canAccess(module, 'delete');

  /// معرفات العناصر المفوَّضة في وحدة معيّنة (فارغة = الوحدة كلها).
  List<String> scopedIdsFor(String module) => scopedIds[module] ?? const [];

  /// هل هذا التفويض مقصورٌ على عناصر محددة في هذه الوحدة؟
  bool isScopedFor(String module) => scopedIdsFor(module).isNotEmpty;

  /// صلاحية عملية على عنصر معيّن: يتحقق أولاً من الصلاحية العامة ثم من نطاق
  /// العناصر. قائمة scopedIds الفارغة (أو غياب الوحدة) تعني تفويضاً كاملاً.
  bool canAccessScoped(String module, String action, String docId) {
    if (!canAccess(module, action)) return false;
    final ids = scopedIdsFor(module);
    if (ids.isEmpty) return true;
    return ids.contains(docId);
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'uid': uid,
      'ownerUid': ownerUid,
      'name': name,
      'email': email,
      'role': role,
      'permissions': permissions,
      'status': status,
      'mustChangePassword': mustChangePassword,
      'ownerName': ownerName,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
    if (scopedIds.isNotEmpty) map['scopedIds'] = scopedIds;
    return map;
  }

  factory TeamMember.fromMap(Map<String, dynamic> data,
      {required String uid, String? ownerUid}) {
    final permRaw = data['permissions'];
    final permissions = <String, Map<String, bool>>{};
    if (permRaw is Map) {
      permRaw.forEach((module, actions) {
        final normalized = <String, bool>{};
        if (actions is Map) {
          actions.forEach((action, value) {
            normalized[action.toString()] = value == true;
          });
        }
        permissions[module.toString()] = normalized;
      });
    }
    // ملء الوحدات المفقودة بصفة "لا صلاحية" حتى لا يسقط أي مفتاح.
    for (final m in TeamPermissions.modules) {
      permissions.putIfAbsent(m, () => <String, bool>{});
    }

    // تفويض على مستوى السجل: خريطة وحدة ← قائمة معرفات عناصر (اختياري).
    final scopedRaw = data['scopedIds'];
    final scopedIds = <String, List<String>>{};
    if (scopedRaw is Map) {
      scopedRaw.forEach((module, ids) {
        final list = <String>[];
        if (ids is List) {
          for (final id in ids) {
            list.add(id.toString());
          }
        }
        scopedIds[module.toString()] = list;
      });
    }

    return TeamMember(
      uid: uid,
      ownerUid: (data['ownerUid'] ?? ownerUid ?? '').toString(),
      name: (data['name'] ?? data['fullName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      role: (data['role'] ?? 'employee').toString(),
      permissions: permissions,
      status: (data['status'] ?? 'active').toString(),
      mustChangePassword: data['mustChangePassword'] == true,
      ownerName: (data['ownerName'] ?? '').toString(),
      scopedIds: scopedIds,
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

/// أُرميت عندما يُنشئ المالك "تفويضاً عبر دعوة" لبريد مسجّل مسبقاً (حساب
/// خاص بالعضو) بدلاً من إنشاء حساب جديد. تُعالج كنجاح مع رسالة توضيحية:
/// تتفعّل العضوية عند أول تسجيل دخول لصاحب البريد بحسابه.
class MemberInviteSentException implements Exception {
  final String message;
  MemberInviteSentException(this.message);
  @override
  String toString() => message;
}

/// الوصول إلى وثائق المستخدمين التابعين في Firestore + الكاش المحلي في SQLite.
class TeamMemberRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference _ref(String ownerUid, String memberUid) =>
      _firestore.collection('users').doc(ownerUid).collection('team_members').doc(memberUid);

  /// يقرأ وثيقة عضوية المستخدم الحالي في حساب مالك معيّن.
  Future<TeamMember?> fetchMember(String ownerUid, String memberUid) async {
    final doc = await _ref(ownerUid, memberUid).get();
    if (!doc.exists) return null;
    return TeamMember.fromMap(doc.data() as Map<String, dynamic>,
        uid: memberUid, ownerUid: ownerUid);
  }

  /// البحث عن العضوية عبر 4 مسارات تدريجية مضمونة 100% لمعرفة صاحب الحساب.
  Future<TeamMember?> findMembershipByUid(String memberUid) async {
    // 1. فحص الوثيقة المباشرة للمستخدم users/{memberUid}
    try {
      final userDoc = await _firestore.collection('users').doc(memberUid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        final ownerUid = (userData?['ownerUid'] ?? '').toString();
        if (ownerUid.isNotEmpty && ownerUid != memberUid) {
          final member = await fetchMember(ownerUid, memberUid);
          if (member != null) return member;
        }
      }
    } catch (e) {
      print('تحذير: فشل فحص وثيقة users/$memberUid: $e');
    }

    // 2. فحص مجموعة السجل السريع member_lookups/{memberUid}
    try {
      final lookupDoc = await _firestore.collection('member_lookups').doc(memberUid).get();
      if (lookupDoc.exists) {
        final lookupData = lookupDoc.data();
        final ownerUid = (lookupData?['ownerUid'] ?? '').toString();
        if (ownerUid.isNotEmpty) {
          final member = await fetchMember(ownerUid, memberUid);
          if (member != null) return member;
        }
      }
    } catch (e) {
      print('تحذير: فشل فحص member_lookups/$memberUid: $e');
    }

    // 3. فحص الاستعلام المجمّع collectionGroup('team_members')
    try {
      final snap = await _firestore
          .collectionGroup('team_members')
          .where('uid', isEqualTo: memberUid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        final data = doc.data();
        final ownerUid = (data['ownerUid'] ?? doc.reference.parent.parent?.id ?? '').toString();
        if (ownerUid.isNotEmpty) {
          final member = TeamMember.fromMap(data, uid: memberUid, ownerUid: ownerUid);
          _saveLookupHelper(ownerUid, memberUid, member.email);
          return member;
        }
      }
    } catch (e) {
      print('تحذير: فشل البحث عبر collectionGroup: $e');
    }

    // 4. المسار الشامل للمستخدمين المنشئين سابقاً: المسح الفحصي لحسابات المالكين
    try {
      final ownersSnap = await _firestore
          .collection('users')
          .get();
      for (final ownerDoc in ownersSnap.docs) {
        final ownerUid = ownerDoc.id;
        if (ownerUid == memberUid) continue;
        final memberDoc = await fetchMember(ownerUid, memberUid);
        if (memberDoc != null) {
          _saveLookupHelper(ownerUid, memberUid, memberDoc.email);
          return memberDoc;
        }
      }
    } catch (e) {
      print('تحذير: فشل المسح الشامل لحسابات المالكين: $e');
    }

    return null;
  }

  static Future<void> _saveLookupHelper(String ownerUid, String memberUid, String email) async {
    try {
      await FirebaseFirestore.instance.collection('member_lookups').doc(memberUid).set({
        'uid': memberUid,
        'ownerUid': ownerUid,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('users').doc(memberUid).set({
        'uid': memberUid,
        'ownerUid': ownerUid,
        'userType': 'sub_user',
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// استرجاع كل الحسابات والتفويضات المتاحة للمستخدم الحالي.
  /// المستخدم الواحد قد يكون تابعاً لدى أكثر من مالك (تفويض لكل حسابٍ مستقل)،
  /// لذا يُجمع كل وثائق عضويته عبر collectionGroup بدل أول عضوية فقط.
  Future<List<TeamMember>> fetchDelegationsForUser(String memberUid) async {
    final list = <TeamMember>[];
    final seenOwners = <String>{};
    try {
      // كل وثائق العضوية التي يكون فيها المستخدم تابعاً لدى كل المالكين.
      final snap = await _firestore
          .collectionGroup('team_members')
          .where('uid', isEqualTo: memberUid)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final ownerUid = (data['ownerUid'] ?? doc.reference.parent.parent?.id ?? '')
            .toString();
        if (ownerUid.isEmpty || ownerUid == memberUid || !seenOwners.add(ownerUid)) {
          continue;
        }
        final member = TeamMember.fromMap(data, uid: memberUid, ownerUid: ownerUid);
        if (member.status == 'active') {
          // فحص حالة المالك (هل هو موقوف/محظور؟)
          final ownerStatus = await AccountStatusService.instance.checkUid(ownerUid);
          if (ownerStatus != AccountAccessState.suspended) {
            list.add(member);
            _saveLookupHelper(ownerUid, memberUid, member.email);
          } else {
            print('fetchDelegationsForUser: تجاهل المالك $ownerUid لأنه مقيد');
          }
        }
      }
      list.sort((a, b) => a.ownerName.compareTo(b.ownerName));
      if (list.isNotEmpty) {
        print('fetchDelegationsForUser: ${list.length} تفويض نشط لصاحب $memberUid');
        return list;
      }
      print('fetchDelegationsForUser: لا توجد عضوية نشطة لصاحب $memberUid');
    } catch (e) {
      print('تحذير: فشل جلب التفويضات عبر collectionGroup: $e');
    }

    // مسار احتياطي: إن فشل الاستعلام المجمّع (فهرس/وضع قديم) نُلقّي عضوية
    // واحدة عبر المسارات التدريجية المعروفة (الأولى فقط).
    try {
      final member = await findMembershipByUid(memberUid);
      if (member != null && member.status == 'active') {
        final ownerStatus = await AccountStatusService.instance.checkUid(member.ownerUid);
        if (ownerStatus != AccountAccessState.suspended) {
          list.add(member);
        }
      }
    } catch (e) {
      print('تحذير: فشل جلب التفويض الاحتياطي: $e');
    }
    return list;
  }

  /// البحث عن المالك بالبريد الإلكتروني وربط عضويته فوراً
  Future<TeamMember?> linkDelegatorByEmail(String memberUid, String ownerEmail) async {
    try {
      final cleanEmail = ownerEmail.trim().toLowerCase();
      final usersSnap = await _firestore
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();
      if (usersSnap.docs.isNotEmpty) {
        final ownerUid = usersSnap.docs.first.id;
        final member = await fetchMember(ownerUid, memberUid);
        if (member != null) {
          await _saveLookupHelper(ownerUid, memberUid, member.email);
          return member;
        }
      }
    } catch (e) {
      print('تحذير: فشل ربط المالك بالبريد: $e');
    }
    return null;
  }

  /// قائمة المستخدمين التابعين لصاحب حساب (لشاشة الإدارة).
  Future<List<TeamMember>> fetchMembers(String ownerUid) async {
    final snap = await _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('team_members')
        .get();
    final members = <TeamMember>[];
    for (final doc in snap.docs) {
      final member =
          TeamMember.fromMap(doc.data(), uid: doc.id, ownerUid: ownerUid);
      // المحذوف (وضع ناعم على الخطة المجانية) لا يظهر في قائمة الإدارة.
      if (member.status == 'deleted') continue;
      members.add(member);
    }
    // الدعوات المعلّقة لبريد مسجّل مسبقاً تظهر فوراً في القائمة كـ "قيد
    // التفعيل" حتى يرى المالك التفويض الذي أنشأه قبل تسجيل دخول العضو.
    members.addAll(await fetchPendingInvites(ownerUid));
    members.sort((a, b) {
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return members;
  }

  /// الدعوات المعلّقة التي أنشأها المالك لحسابات مسجّلة مسبقاً (بانتظار
  /// تسجيل دخول العضو لتفعيل العضوية). تُعرض في قائمة إدارة التابعين.
  Future<List<TeamMember>> fetchPendingInvites(String ownerUid) async {
    final list = <TeamMember>[];
    try {
      final snap = await _firestore
          .collection('member_invites')
          .where('ownerUid', isEqualTo: ownerUid)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if ((data['status'] ?? '').toString() != 'active') continue;
        final email = (data['email'] ?? doc.id).toString();
        // معرّف مؤقت للعرض فقط — لا يمكن إنشاء وثيقة العضوية قبل معرفة
        // UID الحساب الحقيقي (من جهة العميل لا يُكشف إلا عند تسجيل الدخول).
        final pendingId = 'pending:$email';
        list.add(TeamMember.fromMap(
          {
            ...data,
            'uid': pendingId,
            'ownerUid': ownerUid,
            'status': 'pending',
            'mustChangePassword': false,
          },
          uid: pendingId,
          ownerUid: ownerUid,
        ));
      }
      list.sort((a, b) {
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return da.compareTo(db);
      });
    } catch (e) {
      print('تحذير: فشل جلب الدعوات المعلّقة للمالك: $e');
    }
    return list;
  }

  /// إسقاط علم "يجب تغيير كلمة المرور" بعد أن يغيّر الموظف كلمة المرور المؤقتة.
  /// مسموح به فقط من قواعد الأمان لتحديث حقل mustChangePassword = false.
  Future<void> setMustChangePasswordFalse(String ownerUid, String memberUid) async {
    await _ref(ownerUid, memberUid).update({'mustChangePassword': false});
  }

  // ==================== التفويض لحساب مسجّل مسبقاً (دعوة) ====================
  // حين يكون بريد العضو مسجّلاً مسبقاً بحساب خاص به، لا يمكن إنشاء حساب جديد
  // (وإن إنشاؤه يفشل بـ EMAIL_EXISTS). يكتب المالك "دعوة تفويض" بمفتاح البريد،
  // وتُفعَّل العضوية تلقائياً عند أول تسجيل دخول لصاحب البريد بحسابه (يعرف
  // عندها UID حسابِه، وهو ما لا يستطيع العميل كشفه مسبقاً).
  // مفتاح الدعوة = "المالك_البريد" لا "البريد" فقط؛ حتى لا تتعارض دعوات
  // مالكين مختلفين لنفس البريد (كل مالك له دعوة مستقلة تخضع لأول دخول).
  DocumentReference inviteRef(String ownerUid, String email) =>
      _firestore.collection('member_invites').doc('${ownerUid}_${email.trim().toLowerCase()}');

  Future<void> createInvite({
    required String ownerUid,
    required String ownerName,
    required String name,
    required String email,
    required Map<String, Map<String, bool>> permissions,
    Map<String, List<String>>? scopedIds,
  }) async {
    await inviteRef(ownerUid, email).set({
      'ownerUid': ownerUid,
      'ownerName': ownerName,
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'permissions': permissions,
      if (scopedIds != null && scopedIds.isNotEmpty) 'scopedIds': scopedIds,
      'status': 'active',
      'mustChangePassword': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    print('createInvite: owner=$ownerUid email=${email.trim().toLowerCase()} '
        'scoped=${(scopedIds ?? {}).toString()}');
  }

  /// كل الدعوات النشطة الموجهة لبريد معين (قد تكون من مالكين مختلفين).
  Future<List<Map<String, dynamic>>> findInvitesByEmail(String email) async {
    try {
      final snap = await _firestore
          .collection('member_invites')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .get();
      return snap.docs
          .map((d) => Map<String, dynamic>.from(d.data() as Map)
            ..['inviteDocId'] = d.id)
          .toList()
        ..forEach((m) => print(
            'findInvitesByEmail: دعوة بمفتاح ["${m['inviteDocId']}"] لبريد "${m['email']}"'));
    } catch (e) {
      print('تحذير: فشل جلب دعوات البريد: $e');
      return const [];
    }
  }

  /// دعوة واحدة معلّقة لمالك + بريد محددين (مستخدمة عند إعادة المشاركة).
  Future<Map<String, dynamic>?> findPendingInvite(
      String ownerUid, String email) async {
    try {
      final doc = await inviteRef(ownerUid, email).get();
      if (!doc.exists) return null;
      final data = Map<String, dynamic>.from(doc.data() as Map);
      if ((data['status'] ?? '').toString() != 'active') return null;
      return data;
    } catch (e) {
      // قراءة دعوة غير موجودة قد ترفضها قواعد الأمان (get على وثيقة مفقودة).
      // لا يجب أن يوقف هذا مشاركة العمل: نعتبر أن لا دعوة معلّقة ونكمل
      // بإنشاء الحساب (أو دعوة جديدة) كسلوك طبيعي.
      print('findPendingInvite: لا توجد دعوة معلقة لـ $email ($e)');
      return null;
    }
  }

  Future<void> deleteInvite(String ownerUid, String email) async {
    try {
      await inviteRef(ownerUid, email).delete();
    } catch (_) {}
  }

  /// حذف الدعوة بمعرّف وثيقتها الحقيقي (لا يُعاد بناء المسار من البريد).
  Future<void> deleteInviteById(String inviteDocId) async {
    if (inviteDocId.isEmpty) return;
    try {
      await _firestore.collection('member_invites').doc(inviteDocId).delete();
    } catch (_) {}
  }

  /// تفعيل الدعوة بكتابة وثائق العضوية الثلاث بحساب المستخدم الحقيقي، ثم
  /// تُحذف الدعوة. يُستدعى من جلسة العضو نفسه عند أول دخول بحسابه.
  Future<void> activateInvite({
    required Map<String, dynamic> invite,
    required String ownerUid,
    required String memberUid,
    required String email,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final rawPerms = invite['permissions'];
    final permissions = <String, Map<String, bool>>{};
    if (rawPerms is Map) {
      rawPerms.forEach((module, actions) {
        final a = <String, bool>{};
        if (actions is Map) {
          actions.forEach((k, v) => a[k.toString()] = v == true);
        }
        permissions[module.toString()] = a;
      });
    }
    // ملء الوحدات المفقودة (نفس سلوك TeamMember.fromMap).
    for (final m in TeamPermissions.modules) {
      permissions.putIfAbsent(m, () => <String, bool>{});
    }

    // نضيف نطاق السجلات إن كانت الدعوة من نوع "مشاركة عمل واحد".
    final scopedRaw = invite['scopedIds'];
    final scopedIds = <String, List<String>>{};
    if (scopedRaw is Map) {
      scopedRaw.forEach((module, ids) {
        final list = <String>[];
        if (ids is List) {
          for (final id in ids) {
            list.add(id.toString());
          }
        }
        scopedIds[module.toString()] = list;
      });
    }

    final inviteDocId = (invite['inviteDocId'] ?? '').toString();
    print('activateInvite: إنشاء عضوية [$ownerUid/$memberUid] بـ inviteId="$inviteDocId" لبريد $cleanEmail');
    await _ref(ownerUid, memberUid).set({
      'uid': memberUid,
      'ownerUid': ownerUid,
      'name': (invite['name'] ?? '').toString(),
      'email': cleanEmail,
      'role': 'employee',
      'permissions': permissions,
      if (scopedIds.isNotEmpty) 'scopedIds': scopedIds,
      'status': 'active',
      'mustChangePassword': false,
      'ownerName': (invite['ownerName'] ?? '').toString(),
      'inviteId': (invite['inviteDocId'] ?? '').toString(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('member_lookups').doc(memberUid).set({
      'uid': memberUid,
      'ownerUid': ownerUid,
      'email': cleanEmail,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('users').doc(memberUid).set({
      'uid': memberUid,
      'ownerUid': ownerUid,
      'userType': 'sub_user',
      'email': cleanEmail,
      'fullName': (invite['name'] ?? '').toString(),
      'inviteId': (invite['inviteDocId'] ?? '').toString(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==================== مشاركة عمل واحد (تفويض على مستوى السجل) ====================
  // "المشاركة" = منح قراءة + تعديل على عمل واحد محدد لموظف قائم أو لبريد جديد.
  // تُخزَّن المعرفات في scopedIds[module]، وقواعد الأمان تربطها بـ docId.

  /// البحث عن عضو قائم لدى المالك بالبريد (مطابقة حرفية على الحقل email).
  Future<TeamMember?> findSubUserByEmail(String ownerUid, String email) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(ownerUid)
          .collection('team_members')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return TeamMember.fromMap(doc.data(), uid: doc.id, ownerUid: ownerUid);
    } catch (e) {
      print('تحذير: فشل البحث عن العضو بالبريد: $e');
      return null;
    }
  }

  /// منح قراءة + تعديل على عنصر محدد لعضو قائم. إذا كان العضو يملك أصلاً
  /// صلاحية كاملة على الوحدة (دون نطاق) لا يُقيَّد ولا يتغير شيء.
  Future<void> grantScopedRecord({
    required String ownerUid,
    required String memberUid,
    required String module,
    required String docId,
  }) async {
    final doc = await _ref(ownerUid, memberUid).get();
    if (!doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;

    final perms = <String, Map<String, bool>>{};
    final permRaw = data['permissions'];
    if (permRaw is Map) {
      permRaw.forEach((m, actions) {
        final a = <String, bool>{};
        if (actions is Map) {
          actions.forEach((k, v) => a[k.toString()] = v == true);
        }
        perms[m.toString()] = a;
      });
    }
    for (final m in TeamPermissions.modules) {
      perms.putIfAbsent(m, () => <String, bool>{});
    }

    final scoped = _parseScopedIds(data['scopedIds']);
    final ids = (scoped[module] ?? <String>[]).toSet();

    // العضو يملك أصلاً الوصول الكامل للوحدة: المشاركة بلا أثر.
    final fullAccess = perms[module]?['read'] == true &&
        perms[module]?['update'] == true &&
        (scoped[module]?.isEmpty ?? true);
    if (fullAccess) return;

    // وإلا مقيّد على العنصر: قراءة + تعديل دون إنشاء/حذف.
    final modulePerms = perms[module] ?? <String, bool>{};
    modulePerms['read'] = true;
    modulePerms['update'] = true;
    modulePerms['create'] = false;
    modulePerms['delete'] = false;
    perms[module] = modulePerms;

    ids.add(docId);
    scoped[module] = ids.toList();

    await _ref(ownerUid, memberUid).update({
      'permissions': perms,
      'scopedIds': scoped,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// منح قراءة + تعديل على عمل محدد لعضو قائم.
  Future<void> grantScopedBusiness({
    required String ownerUid,
    required String memberUid,
    required String workId,
  }) =>
      grantScopedRecord(
        ownerUid: ownerUid,
        memberUid: memberUid,
        module: TeamPermissions.businesses,
        docId: workId,
      );

  /// منح قراءة + تعديل على عامل محدد لعضو قائم.
  Future<void> grantScopedWorker({
    required String ownerUid,
    required String memberUid,
    required String workerId,
  }) =>
      grantScopedRecord(
        ownerUid: ownerUid,
        memberUid: memberUid,
        module: TeamPermissions.workers,
        docId: workerId,
      );

  /// إلحاق عنصر محدد بدعوة معلّقة (مشاركة لمستخدم مسجّل لم يُفَعِّل عضويته بعد).
  Future<void> addScopedIdToInviteForModule({
    required String ownerUid,
    required String email,
    required String module,
    required String docId,
  }) async {
    final ref = inviteRef(ownerUid, email);
    final doc = await ref.get();
    if (!doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;
    if ((data['ownerUid'] ?? '').toString() != ownerUid) return;

    final scoped = _parseScopedIds(data['scopedIds']);
    final ids = (scoped[module] ?? <String>[]).toSet();
    ids.add(docId);
    scoped[module] = ids.toList();

    // نفس صيغة المشاركة: قراءة + تعديل على العنصر المُشارَك فقط.
    final perms = <String, Map<String, bool>>{};
    final permRaw = data['permissions'];
    if (permRaw is Map) {
      permRaw.forEach((m, actions) {
        final a = <String, bool>{};
        if (actions is Map) {
          actions.forEach((k, v) => a[k.toString()] = v == true);
        }
        perms[m.toString()] = a;
      });
    }
    for (final m in TeamPermissions.modules) {
      perms.putIfAbsent(m, () => <String, bool>{});
    }
    final modulePerms = perms[module] ?? <String, bool>{};
    modulePerms['read'] = true;
    modulePerms['update'] = true;
    modulePerms['create'] = false;
    modulePerms['delete'] = false;
    perms[module] = modulePerms;

    await ref.update({
      'permissions': perms,
      'scopedIds': scoped,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// إلحاق عمل محدد بدعوة معلّقة (مشاركة لمستخدم مسجّل لم يُفَعِّل عضويته بعد).
  Future<void> addScopedIdToInvite({
    required String ownerUid,
    required String email,
    required String workId,
  }) =>
      addScopedIdToInviteForModule(
        ownerUid: ownerUid,
        email: email,
        module: TeamPermissions.businesses,
        docId: workId,
      );

  /// إلحاق عامل محدد بدعوة معلّقة (مشاركة لمستخدم مسجّل لم يُفَعِّل عضويته بعد).
  Future<void> addScopedWorkerToInvite({
    required String ownerUid,
    required String email,
    required String workerId,
  }) =>
      addScopedIdToInviteForModule(
        ownerUid: ownerUid,
        email: email,
        module: TeamPermissions.workers,
        docId: workerId,
      );

  static Map<String, List<String>> _parseScopedIds(dynamic raw) {
    final result = <String, List<String>>{};
    if (raw is Map) {
      raw.forEach((module, ids) {
        final list = <String>[];
        if (ids is List) {
          for (final id in ids) {
            list.add(id.toString());
          }
        }
        result[module.toString()] = list;
      });
    }
    return result;
  }

  // ==================== الكاش المحلي (Offline-First) ====================
  Future<TeamMember?> loadCachedMember(String memberUid) async {
    final data = await DatabaseHelper.instance.getCache(memberUid, 'member_profile');
    if (data == null) return null;
    return TeamMember.fromMap(data, uid: memberUid);
  }

  Future<void> saveMemberCached(TeamMember member) async {
    final data = Map<String, dynamic>.from(member.toMap());
    // سلسلة دوال القيم للتوافق مع jsonEncode في SQLite.
    await DatabaseHelper.instance.setCache(member.uid, 'member_profile', data);
  }

  Future<void> clearMemberCache(String memberUid) async {
    await DatabaseHelper.instance.removeCache(memberUid, 'member_profile');
  }

  Future<List<TeamMember>> loadCachedMembers(String ownerUid) async {
    final list = await DatabaseHelper.instance.getCacheList(ownerUid, 'team_members_cache');
    return list
        .map((e) => TeamMember.fromMap(Map<String, dynamic>.from(e), uid: e['uid']?.toString() ?? ''))
        .toList();
  }

  Future<void> saveMembersCached(String ownerUid, List<TeamMember> members) async {
    await DatabaseHelper.instance.setCacheList(
      ownerUid,
      'team_members_cache',
      members.map((m) => Map<String, dynamic>.from(m.toMap())).toList(),
    );
  }
}