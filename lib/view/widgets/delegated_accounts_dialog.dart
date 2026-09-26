// lib/view/widgets/delegated_accounts_dialog.dart
import 'package:flutter/material.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/member_session_service.dart';

class DelegatedAccountsDialog extends StatefulWidget {
  final VoidCallback onAccountSwitched;

  const DelegatedAccountsDialog({
    super.key,
    required this.onAccountSwitched,
  });

  static Future<void> show(BuildContext context, {required VoidCallback onAccountSwitched}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DelegatedAccountsDialog(onAccountSwitched: onAccountSwitched),
    );
  }

  @override
  State<DelegatedAccountsDialog> createState() => _DelegatedAccountsDialogState();
}

class _DelegatedAccountsDialogState extends State<DelegatedAccountsDialog> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await MemberSessionService.instance.fetchDelegations();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _linkByEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    final member = await MemberSessionService.instance.linkDelegatorByEmail(email);
    if (!mounted) return;

    if (member != null) {
      setState(() {
        _isLoading = false;
        _success = 'تم التبديل بنجاح إلى حساب المفوض';
      });
      widget.onAccountSwitched();
      Navigator.pop(context);
    } else {
      setState(() {
        _isLoading = false;
        _error = 'لم يتم العثور على عضوية أو تفويض بهذا البريد الإلكتروني';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = MemberSessionService.instance;
    final colorScheme = Theme.of(context).colorScheme;
    final isDelegated = session.isDelegatedActive;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // مقبض السحب للأعلى
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // العنوان الرئيسية
          Row(
            children: [
              Icon(Icons.supervisor_account_rounded, color: colorScheme.primary, size: 28),
              const SizedBox(width: 10),
              Text(
                'المفوضين (الحسابات المتاحة)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'يمكنك التبديل بين حسابك الشخصي المستقل والحسابات المفوض بها لاستعراض الأعمال والعمال حسب الصلاحيات.',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // 1. الخيار الأول: حسابي الشخصي المستقل
          Card(
            elevation: isDelegated ? 0 : 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: !isDelegated ? colorScheme.primary : colorScheme.outlineVariant,
                width: !isDelegated ? 2 : 1,
              ),
            ),
            color: !isDelegated ? colorScheme.primaryContainer.withValues(alpha: 0.3) : colorScheme.surface,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: !isDelegated ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  color: !isDelegated ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                ),
              ),
              title: const Text('حسابي الشخصي', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('الحساب المستقل الخاص بك'),
              trailing: !isDelegated
                  ? Icon(Icons.check_circle, color: colorScheme.primary)
                  : ElevatedButton(
                      onPressed: () async {
                        await session.switchToPersonal();
                        widget.onAccountSwitched();
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                      child: const Text('تفعيل'),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // 2. قائمة الحسابات المفوض بها (مثل حساب عبد الله)
          if (session.availableDelegations.isNotEmpty) ...[
            Text(
              'الحسابات المفوض بها:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            ...session.availableDelegations.map((m) {
              final isCurrent = isDelegated && session.ownerUid == m.ownerUid;
              final displayName = m.ownerName.isNotEmpty ? m.ownerName : 'حساب مالك مفوض';

              return Card(
                elevation: isCurrent ? 2 : 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isCurrent ? colorScheme.primary : colorScheme.outlineVariant,
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                color: isCurrent ? colorScheme.primaryContainer.withValues(alpha: 0.3) : colorScheme.surface,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent ? colorScheme.primary : Colors.teal,
                    child: const Icon(Icons.store, color: Colors.white),
                  ),
                  title: Text('حساب $displayName', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('الصلاحيات: ${_getPermissionsSummary(m)}'),
                  trailing: isCurrent
                      ? Icon(Icons.check_circle, color: colorScheme.primary)
                      : ElevatedButton(
                          onPressed: () async {
                            await session.switchToOwner(m);
                            widget.onAccountSwitched();
                            if (context.mounted) Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('انتقال'),
                        ),
                ),
              );
            }),
          ],

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // 3. قسم ربط حساب مفوض يدوياً بالبريد
          Text(
            'ربط تفويض جديد بالبريد الإلكتروني:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'بريد المالك (مثال: abdullah@gmail.com)',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : _linkByEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: _isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('ربط وتفعيل'),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colorScheme.error, fontSize: 12)),
          ],
          if (_success != null) ...[
            const SizedBox(height: 8),
            Text(_success!, style: const TextStyle(color: Colors.green, fontSize: 12)),
          ],

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  String _getPermissionsSummary(TeamMember m) {
    final activeModules = <String>[];
    if (m.canRead(TeamPermissions.businesses)) activeModules.add('الأعمال');
    if (m.canRead(TeamPermissions.workers)) activeModules.add('العمال');
    if (m.canRead(TeamPermissions.expenses)) activeModules.add('المصروفات');
    if (m.canRead(TeamPermissions.reports)) activeModules.add('التقارير');
    return activeModules.isNotEmpty ? activeModules.join(' • ') : 'صلاحيات محددة';
  }
}
