import 'package:flutter/material.dart';

/// شريط تحديد نطاق تاريخي (من تاريخ → إلى تاريخ) لكشوف الحسابات.
/// يفتح نافذة اختيار التاريخ عند الضغط، مع ضبط تلقائي للحدود وعرض بصيغة
/// `yyyy/MM/dd` (مطابق لأمثلة المستخدم مثل 2026/05/07).
class DateRangeFilterBar extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onCleared;

  const DateRangeFilterBar({
    super.key,
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onCleared,
  });

  Future<void> _pickFrom(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'حدد تاريخ البداية',
    );
    if (picked == null) return;
    final newFrom = DateTime(picked.year, picked.month, picked.day);
    var newTo = to;
    if (newTo == null) {
      newTo = newFrom;
    } else if (newTo.isBefore(newFrom)) {
      newTo = newFrom;
    }
    onFromChanged(newFrom);
    onToChanged(newTo);
  }

  Future<void> _pickTo(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: to ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'حدد تاريخ النهاية',
    );
    if (picked == null) return;
    final newTo = DateTime(picked.year, picked.month, picked.day);
    if (from != null && newTo.isBefore(from!)) onFromChanged(newTo);
    onToChanged(newTo);
  }

  String _fmtDate(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _pickFrom(context),
              child: Text(
                from == null ? 'من: الكل' : 'من: ${_fmtDate(from!)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _pickTo(context),
              child: Text(
                to == null ? 'إلى: الكل' : 'إلى: ${_fmtDate(to!)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (from != null || to != null)
            IconButton(
              onPressed: onCleared,
              icon: const Icon(Icons.clear),
              tooltip: 'إلغاء التحديد',
            ),
        ],
      ),
    );
  }
}

/// يفحص ما إذا كان تاريخ الحركة (ISO-string أو DateTime) داخل النطاق [from, to].
/// التواريخ غير الصالحة تُعرض فقط عندما يكون الفلتر معطلاً (مطابق لسلوك التقارير).
bool inDateRange(Object? date, DateTime? from, DateTime? to) {
  DateTime? d;
  if (date is DateTime) {
    d = DateTime(date.year, date.month, date.day);
  } else if (date != null) {
    final parsed = DateTime.tryParse(date.toString());
    if (parsed != null) {
      d = DateTime(parsed.year, parsed.month, parsed.day);
    }
  }
  if (d == null) return from == null && to == null;
  if (from != null && d.isBefore(from)) return false;
  if (to != null && d.isAfter(to)) return false;
  return true;
}