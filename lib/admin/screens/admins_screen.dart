// lib/admin/screens/admins_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_admins_controller.dart';
import '../models/admin_models.dart';
import '../models/admin_role.dart';
import '../widgets/common.dart';

class AdminAdminsScreen extends StatelessWidget {
  const AdminAdminsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminAdminsController()..load(),
      child: Consumer<AdminAdminsController>(
        builder: (context, c, _) {
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('المديرون والصلاحيات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('الأدوار: مدير عام (كامل) • مدير (المستخدمون/الإشعارات/التحليلات/المزامنة/الإصدارات) • محلل (التحليلات فقط).',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              const _AddAdminCard(),
              const SizedBox(height: 24),
              sectionTitle(context, 'قائمة المديرين الحالية'),
              if (c.isLoading)
                loadingWidget()
              else if (c.admins.isEmpty)
                emptyState(context, 'لا يوجد مديرون بعد')
              else
                Column(
                  children: [
                    for (final a in c.admins)
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: scheme.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
                        child: ListTile(
                          title: Row(
                            children: [
                              Text(a.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (a.protected) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.lock, size: 16, color: Colors.orange),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text('محمي', style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text('${a.email}\n${a.role?.label ?? '-'} • ${a.status} • منذ ${formatTodayOnly(a.createdAt)}'),
                          isThreeLine: true,
                          // لا يسمح لأي مدير بإدارة نفسه (تغيير دوره/إزالته)
                          trailing: _isSelf(a.uid)
                              ? Text('أنت', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600))
                              : a.protected && a.role == AdminRole.superAdmin
                                  ? null
                                  : PopupMenuButton<String>(
                                      onSelected: (action) {
                                        if (action == 'remove') {
                                          _confirmRemove(context, c, a);
                                        } else {
                                          _confirmSetRole(context, c, a, action);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        for (final r in AdminRole.values)
                                          PopupMenuItem(value: r.key, child: Text('تغيير: ${r.label}')),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(value: 'remove', child: Text('إزالة المدير', style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  bool _isSelf(String uid) =>
      FirebaseAuth.instance.currentUser?.uid == uid;

  Future<void> _confirmSetRole(BuildContext context, AdminAdminsController c, Object target, String role) async {
    final String label = AdminRole.tryParse(role)?.label ?? role;
    final String name = target is UserSnapshot ? target.fullName : (target as AdminMember).displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد تغيير الدور'),
        content: Text('تعيين "$name" بدور: $label\nسيتم تسجيل العملية في سجل العمليات.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final bool ok;
    if (target is UserSnapshot) {
      ok = await c.setRole(uid: target.uid, role: role, email: target.email, displayName: target.fullName, user: target);
    } else {
      final a = target as AdminMember;
      ok = await c.setRole(uid: a.uid, role: role, email: a.email, displayName: a.displayName);
    }
    if (context.mounted) {
      showSnack(context, ok ? (c.success ?? 'تم تحديث الدور') : (c.error ?? 'فشل التحديث'), ok ? SnackKind.success : SnackKind.error);
    }
  }

  Future<void> _confirmRemove(BuildContext context, AdminAdminsController c, AdminMember a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إزالة مدير'),
        content: Text('سيتم إزالة صلاحيات المدير من "${a.displayName}" نهائياً. هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('إزالة', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await c.removeRole(a);
    if (context.mounted) {
      showSnack(context, ok ? (c.success ?? 'تمت الإزالة') : (c.error ?? 'فشل الإزالة'), ok ? SnackKind.success : SnackKind.error);
    }
  }
}

// ===================== بطاقة إضافة/تعديل مدير =====================
class _AddAdminCard extends StatefulWidget {
  const _AddAdminCard();

  @override
  _AddAdminCardState createState() => _AddAdminCardState();
}

class _AddAdminCardState extends State<_AddAdminCard> {
  final TextEditingController _searchCtrl = TextEditingController();
  UserSnapshot? _selected;
  AdminRole? _role;

  String? _roleLabelOf(AdminAdminsController c, UserSnapshot u) {
    for (final a in c.admins) {
      if (a.uid == u.uid && a.status == 'active' && a.role != null) return a.role!.label;
    }
    return AdminRole.tryParse(u.userType)?.label;
  }

  void _pickResult(AdminAdminsController c, UserSnapshot u) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null && u.uid == myUid) {
      showSnack(context, 'لا يمكنك تعديل صلاحياتك الخاصة', SnackKind.error);
      return;
    }
    if (u.email.trim().toLowerCase() == kProtectedAdminEmail) {
      showSnack(context, 'هذا الحساب محمي ولا يمكن تعديله', SnackKind.error);
      return;
    }
    setState(() => _selected = u);
  }

  Future<void> _submit(AdminAdminsController c) async {
    final u = _selected;
    final r = _role;
    if (u == null || r == null || c.isActing) return;
    final ok = await c.setRole(
      uid: u.uid,
      role: r.key,
      email: u.email,
      displayName: u.fullName,
      user: u,
    );
    if (!mounted) return;
    showSnack(context, ok ? (c.success ?? 'تم تحديث الدور') : (c.error ?? 'فشل التحديث'), ok ? SnackKind.success : SnackKind.error);
    if (ok) {
      _searchCtrl.clear();
      c.searchUsers('');
      setState(() {
        _selected = null;
        _role = null;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<AdminAdminsController>(
      builder: (context, c, _) => Card(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionTitle(context, 'إضافة/تعديل مدير'),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'البحث عن مستخدم ليصبح مدير',
                  suffixIcon: c.isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
                onChanged: (q) => c.searchUsers(q),
              ),
              const SizedBox(height: 8),
              if (c.isSearching) ...[
                loadingWidget(),
              ] else if (c.searchResults.isNotEmpty) ...[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      for (final u in c.searchResults.take(5))
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(child: Text(u.fullName.isNotEmpty ? u.fullName.substring(0, 1) : '؟')),
                          title: Text(u.fullName),
                          subtitle: Text(_roleLabelOf(c, u) == null
                              ? u.email
                              : '${u.email}\nالدور الحالي: ${_roleLabelOf(c, u)}'),
                          isThreeLine: _roleLabelOf(c, u) != null,
                          selected: _selected?.uid == u.uid,
                          selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
                          onTap: () => _pickResult(c, u),
                        ),
                    ],
                  ),
                ),
              ] else if (c.searchResults.isEmpty && _searchCtrl.text.trim().isNotEmpty && !c.isSearching) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('لا توجد نتائج', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ],
              const SizedBox(height: 8),
              if (_selected != null)
                Card(
                  elevation: 0,
                  color: scheme.primaryContainer.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.person),
                    title: Text(_selected!.fullName),
                    subtitle: Text(_selected!.email),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _selected = null),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AdminRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'الدور المراد تعيينه'),
                hint: const Text('اختر الدور'),
                items: [
                  for (final r in AdminRole.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: c.isActing ? null : (r) => setState(() => _role = r),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_selected != null && _role != null && !c.isActing) ? () => _submit(c) : null,
                child: c.isActing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('تعيين الدور'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}