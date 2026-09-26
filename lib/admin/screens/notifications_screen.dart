// lib/admin/screens/notifications_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_notifications_controller.dart';
import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../widgets/common.dart';

class AdminNotificationsScreen extends StatelessWidget {
  const AdminNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminNotificationsController()..load(),
      child: Consumer<AdminNotificationsController>(
        builder: (context, c, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('الإشعارات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (c.notificationsEnabled == false) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'الإشعارات معطلة حالياً من إعدادات المنصة — تعذّر إرسال إشعارات جديدة حتى إعادة التفعيل.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: c.titleController,
                        enabled: c.notificationsEnabled != false,
                        maxLength: AdminNotificationsController.maxTitle,
                        decoration: InputDecoration(
                          labelText: 'عنوان الإشعار',
                          border: const OutlineInputBorder(),
                          counterText: '${c.remainingTitle} متبقية',
                          errorText: c.titleInvalid ? 'العنوان إلزامي' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: c.bodyController,
                        enabled: c.notificationsEnabled != false,
                        maxLines: 3,
                        maxLength: AdminNotificationsController.maxBody,
                        decoration: InputDecoration(
                          labelText: 'نص الإشعار',
                          border: const OutlineInputBorder(),
                          counterText: '${c.remainingBody} متبقية',
                          errorText: c.bodyInvalid ? 'نص الإشعار إلزامي' : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('إرسال للجميع')),
                          ButtonSegment(value: 'user', label: Text('مستخدم محدد')),
                        ],
                        selected: {c.targetType ?? 'all'},
                        onSelectionChanged: c.notificationsEnabled == false ? null : (s) => c.setTargetType(s.first),
                      ),
                      if (c.targetType == 'user') ...[
                        const SizedBox(height: 12),
                        _userPicker(context, c),
                      ],
                      if (c.targetEmail != null) ...[
                        const SizedBox(height: 6),
                        Text('المستلم: ${c.targetEmail}', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green)),
                      ],
                      if (c.bulkRateLimited && c.targetType == 'all') ...[
                        const SizedBox(height: 8),
                        Text(
                          'الحد الأقصى: إشعار جماعي واحد كل 10 دقائق',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: c.canSend && !c.isSending ? () => _handleSend(context, c) : null,
                        icon: c.isSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        label: Text(c.isSending ? 'جاري الإرسال...' : 'إرسال الإشعار'),
                      ),
                      if (c.error != null) ...[
                        const SizedBox(height: 8),
                        Text(c.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      if (c.successMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(c.successMessage!, style: const TextStyle(color: Colors.green)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              sectionTitle(context, 'سجل الإرسال'),
              if (c.isLoading) loadingWidget() else _history(context, c),
            ],
          );
        },
      ),
    );
  }

  Widget _userPicker(BuildContext context, AdminNotificationsController c) {
    final TextEditingController searchController = TextEditingController();
    List<UserSnapshot> results = [];
    var searched = false;
    return StatefulBuilder(builder: (context, setState) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'ابحث عن المستخدم (بريد أو اسم)...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (q) async {
              searched = true;
              results = await AdminFirestoreService.instance.searchUsers(q, limit: 10);
              if (context.mounted) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          if (results.isNotEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  for (final u in results.take(5))
                    ListTile(
                      dense: true,
                      title: Text(u.fullName),
                      subtitle: Text(u.email),
                      onTap: () {
                        c.setTargetUser(u.uid, u.email);
                        setState(() => results = []);
                      },
                    ),
                ],
              ),
            )
          else if (searched && searchController.text.trim().isNotEmpty)
            Text(
              'لا يوجد مستخدم بهذا المعرّف',
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
        ],
      );
    });
  }

  Future<void> _handleSend(BuildContext context, AdminNotificationsController c) async {
    // نافذة التأكيد تُعرض فقط عند استهداف "الجميع"؛ هدف محدد يُرسل مباشرة.
    if (c.targetType == 'all') {
      final confirmed = await _confirmBulkSend(context, c);
      if (confirmed != true || !context.mounted) return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ok = await c.send(createdBy: uid);
    if (context.mounted) {
      showSnack(context, ok ? 'تم إرسال طلب الإشعار' : 'فشل الإرسال', ok ? SnackKind.success : SnackKind.error);
    }
  }

  Future<bool?> _confirmBulkSend(BuildContext context, AdminNotificationsController c) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإرسال للجميع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل أنت متأكد من إرسال هذا الإشعار لكل المستخدمين؟', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('العنوان: ${c.titleController.text.trim()}'),
            const SizedBox(height: 4),
            Text('النص: ${c.bodyController.text.trim()}'),
            const SizedBox(height: 12),
            const Text('سيتم تسجيل هذه العملية في سجل العمليات (Audit Log).', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الإرسال')),
        ],
      ),
    );
  }

  Widget _history(BuildContext context, AdminNotificationsController c) {
    if (c.history.isEmpty) return emptyState(context, 'لم يتم إرسال أي إشعار بعد', icon: Icons.notifications_none);
    return Column(
      children: [
        for (final n in c.history)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            child: ListTile(
              title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${formatDate(n.createdAt)} • ${n.targetType == 'user' ? 'مستخدم محدد' : 'الجميع'}'
                '${n.sentCount > 0 || n.failureCount > 0 ? ' • نجح ${n.sentCount} / فشل ${n.failureCount}' : ''}',
              ),
              trailing: _statusChip(n),
              onTap: () => _showDetails(context, n),
            ),
          ),
      ],
    );
  }

  void _showDetails(BuildContext context, NotificationRequest n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل الإرسال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(n.body),
            const Divider(height: 24),
            _detailRow('الهدف', n.targetType == 'user' ? 'مستخدم محدد' : 'جميع المستخدمين'),
            if (n.targetType == 'user' && n.targetUid != null) _detailRow('المعرّف', n.targetUid!),
            _detailRow('تاريخ الإنشاء', formatDate(n.createdAt)),
            _detailRow('حالة الإرسال', _statusLabel(n)),
            if (n.createdBy.isNotEmpty) _detailRow('أرسله', n.createdBy),
            _detailRow('نجح التسليم', n.sentCount.toString()),
            _detailRow('فشل التسليم', n.failureCount.toString()),
            if (n.finishedAt != null) _detailRow('وقت الانتهاء', formatDate(n.finishedAt)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  String _statusLabel(NotificationRequest n) {
    if (n.status == 'sent_with_errors') {
      final total = n.sentCount + n.failureCount;
      return 'فشل جزئي (${n.failureCount} من $total)';
    }
    return n.statusLabel;
  }

  Widget _statusChip(NotificationRequest n) {
    final MaterialColor color;
    switch (n.status) {
      case 'sent':
        color = Colors.green;
      case 'sent_with_errors':
        color = Colors.orange;
      case 'pending':
        color = Colors.blue;
      case 'failed':
      case 'no_devices':
        color = Colors.red;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        _statusLabel(n),
        style: TextStyle(color: color.shade800, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}