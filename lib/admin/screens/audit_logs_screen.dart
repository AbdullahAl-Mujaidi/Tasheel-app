// lib/admin/screens/audit_logs_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_audit_controller.dart';
import '../widgets/common.dart';

class AdminAuditLogsScreen extends StatelessWidget {
  const AdminAuditLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminAuditController()..load(),
      child: Consumer<AdminAuditController>(
        builder: (context, c, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('سجل العمليات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: c.load,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تحديث',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('سجل آمن لا يمكن تعديله أو حذفه. كل عملية حساسة تُسجل تلقائياً (من الخادم) مع البيانات التالية: من قام بها، UID، البريد، نوع العملية، الوقت، التفاصيل، والنتيجة.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (c.isLoading)
                loadingWidget()
              else if (c.error != null)
                errorBanner(context, c.error!, onRetry: c.load)
              else if (c.logs.isEmpty)
                emptyState(context, 'لا توجد عمليات مسجلة بعد')
              else
                for (final log in c.logs)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(log.actionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              _resultChip(log.result),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(log.actorEmail, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('UID: ${log.actorUid}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(_detailsText(log.details), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(formatDate(log.timestamp), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  String _detailsText(Map<String, dynamic> details) {
    if (details.isEmpty) return 'لا تفاصيل إضافية';
    final parts = <String>[];
    details.forEach((k, v) {
      if (k == 'changes' && v is Map) {
        v.forEach((ck, cv) {
          parts.add('$ck ← $cv');
        });
      } else if (k == 'id') {
        parts.add('المعرّف: $v');
      } else if (k == 'title') {
        parts.add('العنوان: $v');
      } else if (k == 'role') {
        parts.add('الدور: $v');
      } else if (k == 'email') {
        parts.add('البريد: $v');
      } else {
        parts.add('$k: $v');
      }
    });
    return parts.join(' • ');
  }

  Widget _resultChip(String result) {
    final ok = result == 'success' || result == 'sent';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        result == 'success' ? 'نجاح' : result,
        style: TextStyle(color: (ok ? Colors.green : Colors.orange).shade800, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}