// lib/view/team_members_view.dart
// شاشة "المستخدمون": قائمة المستخدمين التابعين لصاحب الحساب مع عمليات الإدارة.
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:fkra/controller/team_members_controller.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/view/team_member_form_view.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TeamMembersPage extends StatelessWidget {
  final String ownerUid;
  const TeamMembersPage({super.key, required this.ownerUid});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TeamMembersController(ownerUid: ownerUid)..load(),
      child: const _TeamMembersView(),
    );
  }
}

class _TeamMembersView extends StatelessWidget {
  const _TeamMembersView();

  void _showMessage(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm(BuildContext context, TeamMembersController c,
      {TeamMember? member}) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeamMemberFormScreen(controller: c, member: member),
      ),
    );
    if (done == true) {
      await c.load();
      final msg = c.success;
      if (msg != null && context.mounted) _showMessage(context, msg);
    }
  }

  Future<void> _confirm(
    BuildContext context,
    TeamMembersController c,
    String title,
    String body,
    Future<bool> Function() action,
  ) {
    return AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.scale,
      title: title,
      desc: body,
      btnOkText: 'نعم',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        final ok = await action();
        if (ok && c.success != null && context.mounted) {
          _showMessage(context, c.success!);
        } else if (!ok && c.error != null && context.mounted) {
          _showMessage(context, c.error!);
        }
      },
    ).show();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<TeamMembersController>(
      builder: (context, c, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'المستخدمون',
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
            ),
            centerTitle: true,
            backgroundColor: colorScheme.surface,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openForm(context, c),
            icon: const Icon(Icons.person_add),
            label: const Text('مستخدم جديد'),
          ),
          body: RefreshIndicator(
            onRefresh: c.load,
            child: c.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: c.members.length,
                    itemBuilder: (context, index) {
                      final m = c.members[index];
                      return _MemberCard(
                        member: m,
                        onEdit: () => _openForm(context, c, member: m),
                        onToggleStatus: c.isActing
                            ? null
                            : () => _confirm(
                                  context,
                                  c,
                                  m.isActive ? 'تعطيل المستخدم' : 'تفعيل المستخدم',
                                  m.isActive
                                      ? 'سيتم منع ${m.name} من تسجيل الدخول فوراً.'
                                      : 'سيتم السماح لـ ${m.name} بتسجيل الدخول.',
                                  () => c.toggleStatus(m),
                                ),
                        onResetPassword: c.isActing
                            ? null
                            : () => _confirm(
                                  context,
                                  c,
                                  'إعادة تعيين كلمة المرور',
                                  'ستُولّد كلمة مرور مؤقتة جديدة وسيُجبر ${m.name} '
                                      'على تغييرها عند تسجيل الدخول.',
                                  () => c.resetPassword(m),
                                ),
                        onDelete: c.isActing
                            ? null
                            : () => _confirm(
                                  context,
                                  c,
                                  'حذف المستخدم',
                                  'سيتم حذف حساب ${m.name} نهائياً ولا يمكن التراجع.',
                                  () => c.deleteMember(m),
                                ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onEdit;
  final VoidCallback? onToggleStatus;
  final VoidCallback? onResetPassword;
  final VoidCallback? onDelete;

  const _MemberCard({
    required this.member,
    required this.onEdit,
    this.onToggleStatus,
    this.onResetPassword,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = member.isActive;
    final pending = member.isPending;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: pending
              ? Colors.amber.shade100
              : active
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
          child: Icon(
            pending ? Icons.hourglass_empty : Icons.person,
            color: pending
                ? Colors.amber.shade800
                : active
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                member.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: pending
                    ? Colors.amber.shade100
                    : active
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                pending ? 'قيد التفعيل' : (active ? 'نشط' : 'موقوف'),
                style: TextStyle(
                  fontSize: 12,
                  color: pending
                      ? Colors.amber.shade900
                      : active
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.email),
            const SizedBox(height: 2),
            Text(
              pending
                  ? 'بانتظار تسجيل دخول العضو لتفعيل التفويض'
                  : _modulesSummary(member),
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: pending
            ? Icon(Icons.hourglass_empty, color: Colors.amber.shade700)
            : PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
                break;
              case 'toggle':
                onToggleStatus?.call();
                break;
              case 'reset':
                onResetPassword?.call();
                break;
              case 'delete':
                onDelete?.call();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(leading: Icon(Icons.edit), title: Text('تعديل')),
            ),
            PopupMenuItem(
              value: 'toggle',
              child: ListTile(
                leading: Icon(active ? Icons.block : Icons.check_circle),
                title: Text(active ? 'تعطيل' : 'تفعيل'),
              ),
            ),
            const PopupMenuItem(
              value: 'reset',
              child: ListTile(
                leading: Icon(Icons.lock_reset),
                title: Text('إعادة كلمة المرور'),
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('حذف', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _modulesSummary(TeamMember m) {
    final parts = <String>[];
    // مشاركة على مستوى السجل: عضو يملك عناصر محددة فقط (قراءة وتعديل).
    final scopedWorks = m.scopedIdsFor(TeamPermissions.businesses);
    if (scopedWorks.isNotEmpty) {
      parts.add('مشاركة ${scopedWorks.length} '
          '${scopedWorks.length == 1 ? 'عمل' : 'أعمال'} (قراءة وتعديل)');
    }
    final scopedWorkers = m.scopedIdsFor(TeamPermissions.workers);
    if (scopedWorkers.isNotEmpty) {
      parts.add('مشاركة ${scopedWorkers.length} '
          '${scopedWorkers.length == 1 ? 'عامل' : 'عمال'} (قراءة وتعديل)');
    }
    final granted = <String>[];
    for (final module in TeamPermissions.modules) {
      // تُعرض الأعمال/العمال المقيّدون عبر "المشاركة" أعلاه بدل صلاحية عامة.
      if (module == TeamPermissions.businesses && scopedWorks.isNotEmpty) {
        continue;
      }
      if (module == TeamPermissions.workers && scopedWorkers.isNotEmpty) {
        continue;
      }
      if (m.canRead(module)) {
        granted.add(TeamMembersController.moduleLabel(module));
      }
    }
    if (granted.isNotEmpty) parts.add('صلاحيات: ${granted.join('، ')}');
    return parts.isEmpty ? 'بدون صلاحيات' : parts.join(' — ');
  }
}