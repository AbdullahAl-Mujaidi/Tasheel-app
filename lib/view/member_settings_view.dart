// lib/view/member_settings_view.dart
// صفحة الإعدادات المبسطة للمستخدم التابع: يعرض معلوماته وصلاحياته الدنيا فقط
// (تغيير كلمة المرور الخاصة به + تسجيل الخروج). كل ما يخص المالك
// (تعديل البروفايل/الحقول المخصصة/المستخدمون) لا يظهر للتابع أصلاً.
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/model/login_model.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/view/login_view.dart';
import 'package:flutter/material.dart';

class MemberSettingsPage extends StatelessWidget {
  final String userId; // ownerUid دائمًا
  final String memberUid;
  const MemberSettingsPage({super.key, required this.userId, required this.memberUid});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final session = MemberSessionService.instance;
    final member = session.member;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "تسهيل",
          style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 25),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(Icons.person, size: 32, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    member?.name ?? 'مستخدم',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(member?.email ?? ''),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('مستخدم تابع',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'هذه البيانات تعود لصاحب الحساب',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'صلاحياتي'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _PermissionsList(session: session),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'حسابي'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.password, color: colorScheme.primary),
                  title: const Text('تغيير كلمة المرور'),
                  subtitle: const Text('الخاصة بحسابك فقط'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _changePassword(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => _confirmLogout(context, colorScheme),
            icon: Icon(Icons.logout, color: colorScheme.error),
            label: Text(
              'تسجيل الخروج',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final newPassword = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;
    var saving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('تغيير كلمة المرور'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: newPassword,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور الجديدة',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => obscure = !obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 6) return '6 أحرف على الأقل';
                        if (v != confirm.text) return 'كلمتا المرور غير متطابقتين';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'تأكيد كلمة المرور',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'أعد إدخال كلمة المرور';
                        if (v != newPassword.text) return 'كلمتا المرور غير متطابقتين';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          setState(() => saving = true);
                          final user = FirebaseAuth.instance.currentUser;
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            if (user != null) {
                              await user.updatePassword(newPassword.text.trim());
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
                              );
                            }
                          } on FirebaseAuthException catch (e) {
                            setState(() => saving = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.code == 'requires-recent-login'
                                      ? 'نفدت الجلسة، سجّل الخروج ثم الدخول مجدداً'
                                      : 'فشل تغيير كلمة المرور: ${e.message ?? ''}',
                                ),
                              ),
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmLogout(BuildContext context, ColorScheme colorScheme) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      title: 'تسجيل الخروج',
      desc: 'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
      btnOkText: 'نعم',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        await MemberSessionService.instance.clearSession();
        await LoginModel.signOutPlatform();
        await LoginModel.clearSessionPrefs();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      },
    ).show();
  }
}

class _PermissionsList extends StatelessWidget {
  final MemberSessionService session;
  const _PermissionsList({required this.session});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final member = session.member;
    if (member == null) return const SizedBox.shrink();

    final granted = <String>[];
    for (final module in TeamPermissions.modules) {
      final labels = <String>[];
      if (member.canRead(module)) labels.add('عرض');
      if (member.canCreate(module)) labels.add('إضافة');
      if (member.canUpdate(module)) labels.add('تعديل');
      if (member.canDelete(module)) labels.add('حذف');
      if (labels.isEmpty) continue;
      final name = switch (module) {
        TeamPermissions.businesses => 'الأعمال',
        TeamPermissions.workers => 'العمال',
        TeamPermissions.expenses => 'المصروفات',
        TeamPermissions.reports => 'التقارير',
        TeamPermissions.settings => 'الإعدادات',
        _ => module,
      };
      // مشاركة على مستوى السجل: عناصر محددة فقط مشاركةً من المالك.
      final scopedIds = member.scopedIdsFor(module);
      final scopedNote = scopedIds.isEmpty
          ? ''
          : ' (${scopedIds.length} '
              '${_scopedItemLabel(module, scopedIds.length)})';
      granted.add('$name: ${labels.join('، ')}$scopedNote');
    }
    if (granted.isEmpty) {
      return Text('لا توجد صلاحيات متاحة حالياً',
          style: TextStyle(color: colorScheme.onSurfaceVariant));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in granted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
                const SizedBox(width: 8),
                Expanded(child: Text(line)),
              ],
            ),
          ),
      ],
    );
  }

  static String _scopedItemLabel(String module, int count) {
    if (module == TeamPermissions.workers) {
      return count == 1 ? 'عامل مشترك' : 'عمال مشتركون';
    }
    return count == 1 ? 'عمل مشترك' : 'أعمال مشتركة';
  }
}