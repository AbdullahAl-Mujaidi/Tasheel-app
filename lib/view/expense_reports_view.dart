import 'package:flutter/material.dart';

/// شاشة تقارير المصروفات: تعرض كل المصروفات في جدول واحد
/// (الوصف، التصنيف، المبلغ، من أنشأه، التاريخ) مع إمكانية التحديد
/// من تاريخ إلى تاريخ + إجماليات ومجموع حسب التصنيف.
///
/// مبنية على نفس نمط `BusinessReportsView` و`WorkerReportsView` لتوحيد الشكل.
class ExpenseReportsView extends StatefulWidget {
  final List<Map<String, dynamic>> expenses;

  const ExpenseReportsView({
    super.key,
    required this.expenses,
  });

  @override
  State<ExpenseReportsView> createState() => _ExpenseReportsViewState();
}

class _ExpenseReportsViewState extends State<ExpenseReportsView> {
  DateTime? _from;
  DateTime? _to;

  List<Map<String, dynamic>> get _filtered {
    return widget.expenses.where((e) {
      final d = _parseDate(e['date']);
      if (d == null) return _from == null && _to == null;
      if (_from != null && d.isBefore(_from!)) return false;
      if (_to != null && d.isAfter(_to!)) return false;
      return true;
    }).toList();
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'حدد تاريخ البداية',
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.year, picked.month, picked.day);
        _to ??= DateTime(picked.year, picked.month, picked.day);
        if (_to != null && _to!.isBefore(_from!)) _to = _from;
      });
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'حدد تاريخ النهاية',
    );
    if (picked != null) {
      setState(() {
        _to = DateTime(picked.year, picked.month, picked.day);
        if (_from != null && _from!.isAfter(_to!)) _from = _to;
      });
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final d = DateTime.tryParse(v.toString());
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  String _fmtDate(dynamic v) {
    final d = _parseDate(v);
    if (d == null) return '—';
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

  String _grp(num n) {
    final sign = n < 0 ? '-' : '';
    final s = n.abs().round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$sign$buf';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = _filtered;

    var tTotal = 0.0;
    for (final e in rows) {
      tTotal += (e['amount'] as num?)?.toDouble() ?? 0;
    }

    // الإجمالي حسب التصنيف (مرتّب تنازلياً) — نفس ترتيب التقرير المالي.
    final byCategory = <String, double>{};
    for (final e in rows) {
      final cat = e['category']?.toString().trim();
      final key = (cat == null || cat.isEmpty) ? 'اخرى' : cat;
      byCategory[key] = (byCategory[key] ?? 0) +
          ((e['amount'] as num?)?.toDouble() ?? 0);
    }
    final catEntries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقارير المصروفات'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickFrom,
                    child: Text(
                      _from == null ? 'من: الكل' : 'من: ${_fmtDate(_from)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickTo,
                    child: Text(
                      _to == null ? 'إلى: الكل' : 'إلى: ${_fmtDate(_to)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (_from != null || _to != null)
                  IconButton(
                    onPressed: () => setState(() {
                      _from = null;
                      _to = null;
                    }),
                    icon: const Icon(Icons.clear),
                    tooltip: 'إلغاء التحديد',
                  ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long,
                        size: 50, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد مصروفات في هذا النطاق',
                      style: TextStyle(
                          fontSize: 16, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                        color: colorScheme.surface,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                            colorScheme.primary),
                        headingTextStyle: TextStyle(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        columnSpacing: 20,
                        horizontalMargin: 12,
                        headingRowHeight: 44,
                        columns: const [
                          DataColumn(label: Text('الوصف')),
                          DataColumn(label: Text('التصنيف')),
                          DataColumn(label: Text('المبلغ')),
                          DataColumn(label: Text('أنشئ بواسطة')),
                          DataColumn(label: Text('التاريخ')),
                        ],
                        rows: [
                          for (final e in rows)
                            DataRow(
                              cells: [
                                DataCell(SizedBox(
                                  width: 160,
                                  child: Text(
                                    e['description']?.toString().trim().isNotEmpty ==
                                            true
                                        ? e['description'].toString()
                                        : '—',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                )),
                                DataCell(Text(
                                  e['category']?.toString() ?? 'اخرى',
                                )),
                                DataCell(Text(
                                  _grp((e['amount'] as num?) ?? 0),
                                  style: TextStyle(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )),
                                DataCell(Text(
                                  e['createdByLabel']?.toString() ?? '—',
                                )),
                                DataCell(Text(_fmtDate(e['date']))),
                              ],
                            ),
                          DataRow(
                            color: WidgetStatePropertyAll(
                                colorScheme.surfaceContainerHighest),
                            cells: [
                              const DataCell(Text('الإجمالي',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(rows.length),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(
                                _grp(tTotal),
                                style: TextStyle(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.bold),
                              )),
                              const DataCell(Text('')),
                              const DataCell(Text('')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                _summaryChip(colorScheme, 'عدد المصروفات',
                                    rows.length.toString()),
                                _summaryChip(colorScheme, 'إجمالي المصروفات',
                                    _grp(tTotal),
                                    color: colorScheme.error),
                              ],
                            ),
                            if (catEntries.isNotEmpty) ...[
                              const Divider(height: 20),
                              Text(
                                'المجموع حسب التصنيف',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                children: [
                                  for (final c in catEntries)
                                    _summaryChip(
                                        colorScheme, c.key, _grp(c.value)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(ColorScheme cs, String label, String value,
      {Color? color}) {
    final c = color ?? cs.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value,
            style: TextStyle(
                color: c, fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }
}
