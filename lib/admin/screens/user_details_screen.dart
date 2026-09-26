// lib/admin/screens/user_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../controllers/admin_users_controller.dart';
import '../models/admin_models.dart';
import '../models/admin_role.dart';
import '../services/admin_api.dart';
import '../services/admin_session_service.dart';
import '../widgets/common.dart';

class UserDetailsScreen extends StatefulWidget {
  final UserSnapshot user;
  final AdminUsersController controller;

  const UserDetailsScreen({
    super.key,
    required this.user,
    required this.controller,
  });

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  Map<String, dynamic>? _userStats;
  bool _loadingStats = true;
  late UserSnapshot _user;
  bool _acting = false;
  String? _actionError;

  bool get _isSuperAdmin {
    final role = AdminSessionService.instance.role;
    final currentEmail =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    return role == AdminRole.superAdmin ||
        currentEmail == 'abdullahalmjudi@gmail.com';
  }

  bool get _isSelf => FirebaseAuth.instance.currentUser?.uid == _user.uid;

  bool get _isTargetSuperAdmin =>
      _user.email.trim().toLowerCase() == 'abdullahalmjudi@gmail.com' ||
      _user.isSuperAdmin;

  bool get _canManageTarget {
    if (_isSelf) return false;
    if (_isTargetSuperAdmin) return false;
    if (_isSuperAdmin) return true;
    final role = AdminSessionService.instance.role;
    if (role == AdminRole.admin && _user.userType == 'user') return true;
    if (role == AdminRole.admin && _user.userType == 'admin') return true;
    return false;
  }

  // أي مدير يستطيع ترقية مستخدم عادي إلى مدير (الخطة المجانية بدون CF).
  bool get _canPromote {
    if (_isSelf || _isTargetSuperAdmin) return false;
    if (_user.userType != 'user') return false;
    final role = AdminSessionService.instance.role;
    return _isSuperAdmin || role == AdminRole.admin;
  }

  // إلغاء صلاحية المدير: للمدير العام فقط — القواعد تمنع ديموتيون بمدير عادي.
  bool get _canChangeRole =>
      _isSuperAdmin && !_isSelf && !_isTargetSuperAdmin;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final s = await AdminApi.instance.getUserStats(uid: _user.uid);
      if (mounted &&
          s.isNotEmpty &&
          ((s['businessCount'] as num?)?.toInt() ?? 0) > 0) {
        setState(() {
          _userStats = s;
          _loadingStats = false;
        });
        return;
      }
    } catch (_) {}

    // استعلام مباشر من قاعدة البيانات لمستندات هذا المستخدم تحديدا (Spark Plan Fallback)
    try {
      final bizSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .collection('businesses')
          .get();

      final bCount = bizSnap.docs.length;
      int cCount = 0;
      int pCount = 0;
      for (final doc in bizSnap.docs) {
        final st = doc.data()['status']?.toString();
        if (st == 'completed' || st == 'مكتمل') {
          cCount++;
        } else {
          pCount++;
        }
      }

      int wCount = 0;
      try {
        final workerSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(_user.uid)
            .collection('workers')
            .get();
        wCount = workerSnap.docs.length;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _userStats = {
            'businessCount': bCount,
            'completedCount': cCount,
            'inProgressCount': pCount,
            'workerCount': wCount,
          };
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _loadingStats = false);
  }

  Future<void> _executeAction({
    required Future<String?> Function() action,
    required UserSnapshot updatedSnapshot,
    required String successMessage,
    bool isDelete = false,
  }) async {
    setState(() {
      _acting = true;
      _actionError = null;
    });

    final error = await action();
    if (!mounted) return;

    if (error == null) {
      if (isDelete) {
        Navigator.of(context).pop('deleted');
      } else {
        setState(() {
          _user = updatedSnapshot;
          _acting = false;
        });
        showSnack(context, successMessage);
      }
    } else {
      setState(() {
        _acting = false;
        _actionError = error;
      });
      showSnack(context, 'فشلت العملية: $error', SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final scheme = Theme.of(context).colorScheme;
    final accountAge = u.createdAt == null ? '-' : _accountAge(u.createdAt!);
    final counts = widget.controller.countsByUser[u.uid];

    final totalBusinessCount =
        _userStats?['businessCount'] ?? counts?.businessCount ?? 0;
    final completedCount =
        _userStats?['completedCount'] ?? counts?.completedCount ?? 0;
    final inProgressCount =
        _userStats?['inProgressCount'] ?? counts?.inProgressCount ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل وإدارة المستخدم'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===================== بطاقة المستخدم الرئيسية =====================
          Card(
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      u.fullName.isNotEmpty ? u.fullName.substring(0, 1) : '؟',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.fullName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(u.email,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _buildStatusBadge(u.isBlocked),
                            _buildRoleBadge(u),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ===================== 👤 معلومات الحساب =====================
          Card(
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle(context, '👤 معلومات الحساب'),
                  const SizedBox(height: 8),
                  InfoRow(label: 'الاسم', value: u.fullName),
                  InfoRow(label: 'البريد الإلكتروني', value: u.email),
                  InfoRow(label: 'معرف المستخدم (UID)', value: u.uid),
                  InfoRow(
                      label: 'رقم الهاتف',
                      value: u.phoneNumber.isNotEmpty ? u.phoneNumber : '-'),
                  InfoRow(
                      label: 'اسم النشاط التجاري',
                      value: u.businessName.isNotEmpty ? u.businessName : '-'),
                  InfoRow(label: 'الدور', value: u.roleLabel),
                  InfoRow(
                      label: 'الحالة', value: u.isBlocked ? 'موقوف' : 'نشط'),
                  InfoRow(
                      label: 'تاريخ التسجيل', value: formatDate(u.createdAt)),
                  InfoRow(label: 'مدة الاستخدام', value: accountAge),
                  InfoRow(
                      label: 'آخر تسجيل دخول',
                      value: formatDate(u.lastLoginAt)),
                  InfoRow(
                    label: 'آخر استخدام',
                    value: u.lastActivityAt != null
                        ? '${formatDate(u.lastActivityAt)} (${daysAgo(u.lastActivityAt)})'
                        : '-',
                  ),
                  InfoRow(
                      label: 'طريقة الدخول',
                      value: u.lastLoginMethod.isNotEmpty
                          ? u.lastLoginMethod
                          : '-'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ===================== 📊 استخدام التطبيق =====================
          Card(
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle(context, '📊 استخدام التطبيق'),
                  const SizedBox(height: 8),
                  if (_loadingStats)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else ...[
                    InfoRow(
                        label: 'عدد الأعمال الإجمالي',
                        value: '$totalBusinessCount'),
                    InfoRow(
                        label: 'الأعمال المكتملة', value: '$completedCount'),
                    InfoRow(
                        label: 'الأعمال قيد التنفيذ',
                        value: '$inProgressCount'),
                    InfoRow(
                        label: 'عدد العمال المسجلين',
                        value: '${_userStats?['workerCount'] ?? 0}'),
                    InfoRow(
                        label: 'آخر مزامنة', value: formatDate(u.lastSyncAt)),
                    InfoRow(
                        label: 'إصدار التطبيق الحالي',
                        value: u.appVersion.isNotEmpty ? u.appVersion : '-'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ===================== 🔐 إدارة الحساب =====================
          Card(
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sectionTitle(context, '🔐 إدارة الحساب'),
                  const SizedBox(height: 12),

                  if (_isSelf) ...[
                    _buildAlertBox(
                      context,
                      'لا يمكنك تعديل أو إيقاف أو حذف حسابك الشخصي من لوحة إدارة المستخدمين.',
                      Icons.info_outline,
                      Colors.blue,
                    ),
                    const SizedBox(height: 12),
                  ] else if (_isTargetSuperAdmin) ...[
                    _buildAlertBox(
                      context,
                      'هذا الحساب ينتمي لمدير عام (Super Admin) وهو محمي ضد التعديل والإيقاف.',
                      Icons.shield,
                      Colors.amber.shade900,
                    ),
                    const SizedBox(height: 12),
                  ] else if (!_canManageTarget) ...[
                    _buildAlertBox(
                      context,
                      'ليس لديك صلاحية كافية لتعديل حساب هذا المدير.',
                      Icons.lock_outline,
                      Colors.orange,
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_actionError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _actionError!,
                        style: TextStyle(color: scheme.error, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // --- 1. زر التحكم بالدور ---
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('الدور الحالي',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(u.roleLabel),
                    trailing: u.userType == 'user' && _canPromote
                        ? FilledButton.icon(
                            onPressed: _acting
                                ? null
                                : () => _confirmPromoteToAdmin(context),
                            icon: const Icon(Icons.admin_panel_settings,
                                size: 18),
                            label: const Text('تحويل إلى مدير'),
                          )
                        : (u.userType == 'admin' && _canChangeRole)
                            ? OutlinedButton.icon(
                                onPressed: _acting || !_canManageTarget
                                    ? null
                                    : () => _confirmDemoteToUser(context),
                                icon:
                                    const Icon(Icons.person_outline, size: 18),
                                label: const Text('إلغاء صلاحية المدير'),
                              )
                            : null,
                  ),
                  const Divider(height: 24),

                  // --- 2. زر التحكم بحالة الحساب ---
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('حالة الحساب',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(u.isBlocked ? 'موقوف' : 'نشط'),
                    trailing: u.isBlocked
                        ? FilledButton.icon(
                            onPressed: _acting || !_canManageTarget
                                ? null
                                : () => _confirmReactivateAccount(context),
                            icon: const Icon(Icons.lock_open, size: 18),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.green),
                            label: const Text('إعادة تفعيل الحساب'),
                          )
                        : OutlinedButton.icon(
                            onPressed: _acting || !_canManageTarget
                                ? null
                                : () => _confirmSuspendAccount(context),
                            icon: const Icon(Icons.block, size: 18),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange.shade900),
                            label: const Text('إيقاف الحساب'),
                          ),
                  ),
                  const Divider(height: 24),

                  // --- 3. زر حذف الحساب النهائي ---
                  OutlinedButton.icon(
                    onPressed: _acting || !_canManageTarget
                        ? null
                        : () => _confirmDeleteAccount(context),
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text('حذف الحساب نهائياً'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                  ),

                  if (_acting) ...[
                    const SizedBox(height: 16),
                    const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== إجراءات الحوار والتأكيد =====================

  /// تحويل مستخدم إلى مدير
  Future<void> _confirmPromoteToAdmin(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل إلى مدير'),
        content: Text(
            'هل أنت متأكد من تحويل ${_user.fullName} إلى مدير؟\n\nسيتم منحه صلاحيات الدخول للوحة الإدارة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _executeAction(
      action: () => widget.controller.promoteToAdmin(_user),
      updatedSnapshot: _user.copyWith(userType: 'admin'),
      successMessage: 'تم تحويل ${_user.fullName} إلى مدير بنجاح',
    );
  }

  /// إلغاء صلاحية مدير
  Future<void> _confirmDemoteToUser(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء صلاحية المدير'),
        content: Text(
            'هل أنت متأكد من تحويل ${_user.fullName} إلى مستخدم عادي وإزالة صلاحيات الإدارة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _executeAction(
      action: () => widget.controller.demoteToUser(_user),
      updatedSnapshot: _user.copyWith(userType: 'user'),
      successMessage: 'تم تحويل ${_user.fullName} إلى مستخدم عادي',
    );
  }

  /// إيقاف الحساب
  Future<void> _confirmSuspendAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إيقاف الحساب'),
        content: Text(
          'هل أنت متأكد من إيقاف حساب ${_user.fullName}؟\n\nلن يتم حذف بيانات الحساب، وسيتم منع المستخدم من استخدام التطبيق.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            child: const Text('إيقاف الحساب',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _executeAction(
      action: () => widget.controller.setBlocked(_user, true),
      updatedSnapshot: _user.copyWith(status: 'suspended'),
      successMessage: 'تم إيقاف حساب ${_user.fullName} بنجاح',
    );
  }

  /// إعادة تفعيل الحساب
  Future<void> _confirmReactivateAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تفعيل الحساب'),
        content: Text(
            'هل تريد إعادة تفعيل هذا الحساب؟\n\nسيتمكن ${_user.fullName} من استخدام التطبيق بشكل طبيعي مرة أخرى.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('تأكيد التفعيل',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _executeAction(
      action: () => widget.controller.setBlocked(_user, false),
      updatedSnapshot: _user.copyWith(status: 'active'),
      successMessage: 'تم إعادة تفعيل حساب ${_user.fullName} بنجاح',
    );
  }

  /// حذف الحساب نهائياً
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب نهائياً'),
        content: Text(
          'تنبيه: هل أنت متأكد من رغبتك في حذف حساب ${_user.fullName}؟ هذا الإجراء لا يمكن التراجع عنه.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('متابعة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final emailMatches = await _confirmEmailMatch(this.context);
    if (emailMatches != true || !mounted) return;

    await _executeAction(
      action: () => widget.controller.deleteUser(_user),
      updatedSnapshot: _user,
      successMessage: 'تم حذف الحساب بنجاح',
      isDelete: true,
    );
  }

  Future<bool?> _confirmEmailMatch(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final targetEmail = _user.email.toLowerCase();
          final match = controller.text.trim().toLowerCase() == targetEmail;
          return AlertDialog(
            title: const Text('تأكيد البريد الإلكتروني للحذف'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'اكتب البريد الإلكتروني (${_user.email}) لتأكيد الحذف النهائي:'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: _user.email,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setLocalState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                onPressed: match ? () => Navigator.pop(ctx, true) : null,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('حذف نهائي',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===================== أدوات مساعدة للواجهة =====================

  String _accountAge(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt.toLocal());
    if (diff.inDays < 1) return 'أقل من يوم';
    return '${diff.inDays} يوم';
  }

  Widget _buildStatusBadge(bool blocked) {
    final color = blocked ? Colors.red.shade700 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 4),
          Text(
            blocked ? 'موقوف' : 'نشط',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(UserSnapshot u) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        u.roleLabel,
        style: TextStyle(
            fontSize: 12, color: scheme.primary, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildAlertBox(
      BuildContext context, String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
