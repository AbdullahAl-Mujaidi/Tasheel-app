// lib/view/member_settings_view.dart
// صفحة الإعدادات المبسطة للمستخدم التابع: يعرض معلوماته وصلاحياته الدنيا فقط
// (تغيير كلمة المرور الخاصة به + تسجيل الخروج). كل ما يخص المالك
// (تعديل البروفايل/الحقول المخصصة/المستخدمون) لا يظهر للتابع أصلاً.
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/model/login_model.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/account_deletion_service.dart';
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
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _confirmDeleteAccount(context, colorScheme),
            icon: Icon(Icons.delete_forever, color: colorScheme.error),
            label: Text(
              'حذف حسابي',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.error),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'يحذف حسابك فقط ويزيل تفويضك من ${MemberSessionService.instance.activeDelegatedOwnerName} '
              'دون المساس ببياناته.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colorScheme.outline, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ========== حذف حساب المفوّض ==========
  // نفس مسار الحذف في إعدادات المالك مع كشف أثر مختلف: التفويض فقط.
  Future<void> _confirmDeleteAccount(BuildContext context, ColorScheme colorScheme) async {
    final service = AccountDeletionService.instance;
    final ownerName = MemberSessionService.instance.activeDelegatedOwnerName;

    final aware = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 40),
        title: const Text('حذف الحساب نهائياً'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('سيؤدي هذا إلى:'),
              const SizedBox(height: 10),
              const Text('• حذف حسابك وكل بياناتك الشخصية نهائياً.'),
              Text('• إزالة تفويضك لدى $ownerName.'),
              const Text('• حذف بيانات التطبيق من هذا الجهاز.'),
              const SizedBox(height: 10),
              Text(
                '• بيانات $ownerName لن تُحذف أو تتأثر إطلاقاً.',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('فهمت، متابعة'),
          ),
        ],
      ),
    );
    if (aware != true || !context.mounted) return;

    final reauthed = await _showReauth(context, service, colorScheme);
    if (reauthed != true || !context.mounted) return;

    final result = await service.deleteMyAccount();
    if (!context.mounted) return;

    if (result.serverSucceeded) {
      await AccountDeletionService.redirectToLogin(
        context,
        message: result.firestoreOnlyFallback
            ? 'حُذفت بياناتك وعضويتك من حساب $ownerName. '
                'لم يُحذف حساب الدخول نفسه لأن خدمة الخادم غير مفعّلة — بريدك سيبقى محجوزاً.'
            : result.authAccountLeftBehind
                ? 'حُذفت بياناتك نهائياً، وتعذّر إنهاء جلسة الدخول على الخادم. تواصل مع الإدارة.'
                : (result.localPurged
                    ? 'تم حذف حسابك نهائياً وإزالة تفويضك من $ownerName.'
                    : 'حُذف حسابك لكن تعذّر تنظيف بيانات هذا الجهاز.'),
        backgroundColor: result.firestoreOnlyFallback ||
                result.authAccountLeftBehind ||
                !result.localPurged
            ? colorScheme.error
            : Colors.green,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.errorMessage ?? 'تعذّر حذف الحساب.'),
        backgroundColor: colorScheme.error,
      ),
    );
  }

  Future<bool?> _showReauth(
    BuildContext context,
    AccountDeletionService service,
    ColorScheme colorScheme,
  ) async {
    final needsPassword = service.requiresPassword();
    final passwordCtrl = TextEditingController();
    var busy = false;
    String? error;
    // مسار الحوار: ننتظر إزالته الفعلية قبل تصفير المكدس (انظر الشرح في
    // AccountDeletionService.redirectToLogin).
    ModalRoute<dynamic>? dialogRoute;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogRoute ??= ModalRoute.of(ctx);
        return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: Icon(Icons.lock_outline, color: colorScheme.error),
          title: const Text('تأكيد هويتك'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('لحماية حسابك، أعد تأكيد هويتك قبل الحذف.'),
              if (needsPassword) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: colorScheme.error, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        if (needsPassword) {
                          if (passwordCtrl.text.isEmpty) {
                            throw AccountDeletionException('أدخل كلمة المرور');
                          }
                          await service.reauthenticateWithPassword(passwordCtrl.text);
                        } else {
                          await service.reauthenticateWithGoogle();
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (e) {
                        setState(() {
                          busy = false;
                          error = e is AccountDeletionException
                              ? e.message
                              : 'تعذّر التأكيد. تحقّق من كلمة المرور.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(needsPassword ? 'تأكيد وحذف' : 'تأكيد عبر Google'),
            ),
          ],
        ),
      );
      },
    );
    // ⚠️ الترتيب حاسم: ننتظر إزالة الحوار من الشجرة *قبل* تغيير أي
    // controller. الـTextField يبقى mounted ويبني إطارات متتابعة طوال حركة
    // الخروج (الـexit animation)، فإتلاف الـcontroller قبل ذلك يُسقط
    // `TextEditingController was used after being disposed` ويترك الشجرة في
    // حالة تالفة (RenderFlex overflow ثم `_dependents.isEmpty`).
    final dialogCompleted = dialogRoute?.completed;
    if (dialogCompleted != null) {
      await dialogCompleted.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    }
    passwordCtrl.dispose();
    return ok;
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
    ModalRoute<dynamic>? dialogRoute;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        dialogRoute ??= ModalRoute.of(dialogContext);
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

    // الـcontrollers كانت تُترك بلا إتلاف (تسريب). ننتظر إزالة الحوار من
    // الشجرة أولاً لأن الـTextFormField يبقى يقرأها أثناء حركة الخروج.
    final dialogCompleted = dialogRoute?.completed;
    if (dialogCompleted != null) {
      await dialogCompleted.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    }
    newPassword.dispose();
    confirm.dispose();
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