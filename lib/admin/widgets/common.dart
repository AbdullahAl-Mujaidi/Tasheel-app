// lib/admin/widgets/common.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatDate(DateTime? dt) {
  if (dt == null) return '-';
  return DateFormat('yyyy/MM/dd HH:mm').format(dt.toLocal());
}

String formatTodayOnly(DateTime? dt) {
  if (dt == null) return '-';
  return DateFormat('yyyy/MM/dd').format(dt.toLocal());
}

String daysAgo(DateTime? dt) {
  if (dt == null) return '-';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inDays < 1) return 'اليوم';
  if (diff.inDays < 2) return 'بالأمس';
  return '${diff.inDays} يوم';
}

Widget sectionTitle(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
  );
}

Widget loadingWidget() => const Center(child: CircularProgressIndicator());

Widget errorBanner(BuildContext context, String message, {VoidCallback? onRetry}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text('حدث خطأ في التحميل', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
          ],
        ],
      ),
    ),
  );
}

Widget emptyState(BuildContext context, String text, {IconData icon = Icons.inbox_outlined}) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 28),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

enum SnackKind { success, error, info }

void showSnack(BuildContext context, String message, [SnackKind kind = SnackKind.success]) {
  FocusManager.instance.primaryFocus?.unfocus();
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  final Color bg;
  switch (kind) {
    case SnackKind.success:
      bg = Colors.green.shade700;
    case SnackKind.error:
      bg = Colors.red.shade700;
    case SnackKind.info:
      bg = Colors.blue.shade700;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      backgroundColor: bg,
      behavior: SnackBarBehavior.fixed,
      duration: const Duration(seconds: 3),
    ),
  );
}