import 'package:flutter/material.dart';

/// شاشة تقارير الأعمال: تعرض كل الأعمال في جدول واحد
/// (اسم العمل، المتفق عليه، الواصل، المصروفات، الباقي، التاريخ)
/// مع إمكانية التحديد من تاريخ إلى تاريخ + إجماليات.
class BusinessReportsView extends StatefulWidget {
  final List<Map<String, dynamic>> businesses;
  final List<Map<String, dynamic>> transactions;

  const BusinessReportsView({
    super.key,
    required this.businesses,
    required this.transactions,
  });

  @override
  State<BusinessReportsView> createState() => _BusinessReportsViewState();
}

class _BusinessReportsViewState extends State<BusinessReportsView> {
  DateTime? _from;
  DateTime? _to;

  List<Map<String, dynamic>> get _filtered {
    return widget.businesses.where((b) {
      final d = _parseDate(b['date']);
      if (d == null) return _from == null && _to == null;
      if (_from != null && d.isBefore(_from!)) return false;
      if (_to != null && d.isAfter(_to!)) return false;
      return true;
    }).toList();
  }

  ({int amount, int paid, int expenses, int remaining}) _totalsOf(
      Map<String, dynamic> b) {
    final amount = (b['amount'] as num?)?.toInt() ?? 0;
    int paid = 0;
    int expenses = 0;
    if (b.containsKey('totalPaid')) {
      paid = (b['totalPaid'] as num?)?.toInt() ?? 0;
      expenses = (b['totalExpenses'] as num?)?.toInt() ?? 0;
    } else {
      paid = (b['initialPaid'] as num?)?.toInt() ?? 0;
      final wid = b['id']?.toString();
      for (final t in widget.transactions) {
        if (t['workId']?.toString() != wid) continue;
        final amt = (t['amount'] as num?)?.toInt() ?? 0;
        if (t['type'] == 'payment') {
          paid += amt;
        } else if (t['type'] == 'expense') {
          expenses += amt;
        }
      }
    }
    final remaining = (b['remaining'] as num?)?.toInt() ?? (amount - paid);
    return (
      amount: amount,
      paid: paid,
      expenses: expenses,
      remaining: remaining,
    );
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
        if (_from != null && _to!.isBefore(_from!)) _from = _to;
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

  String _grp(int n) {
    final sign = n < 0 ? '-' : '';
    final s = n.abs().toString();
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
    var tAmount = 0, tPaid = 0, tExpenses = 0, tRemaining = 0;
    final mapped = <({Map<String, dynamic> b, int amount, int paid, int expenses, int remaining})>[];
    for (final b in rows) {
      final t = _totalsOf(b);
      tAmount += t.amount;
      tPaid += t.paid;
      tExpenses += t.expenses;
      tRemaining += t.remaining;
      mapped.add((b: b, amount: t.amount, paid: t.paid, expenses: t.expenses, remaining: t.remaining));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقارير الأعمال'),
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
                    Icon(Icons.bar_chart,
                        size: 50, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد أعمال في هذا النطاق',
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
                        border:
                            Border.all(color: colorScheme.outlineVariant),
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
                          DataColumn(label: Text('اسم العمل')),
                          DataColumn(label: Text('المتفق عليه')),
                          DataColumn(label: Text('الواصل')),
                          DataColumn(label: Text('المصروفات')),
                          DataColumn(label: Text('الباقي')),
                          DataColumn(label: Text('التاريخ')),
                        ],
                        rows: [
                          for (final m in mapped)
                            DataRow(
                              cells: [
                                DataCell(SizedBox(
                                  width: 140,
                                  child: Text(
                                    m.b['name']?.toString() ?? '—',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                )),
                                DataCell(Text(_grp(m.amount))),
                                DataCell(Text(_grp(m.paid),
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(_grp(m.expenses),
                                    style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(_grp(m.remaining),
                                    style: TextStyle(
                                        color: m.remaining > 0
                                            ? colorScheme.error
                                            : colorScheme.onSurface,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(_fmtDate(m.b['date']))),
                              ],
                            ),
                          DataRow(
                            color: WidgetStatePropertyAll(
                                colorScheme.surfaceContainerHighest),
                            cells: [
                              const DataCell(Text('الإجمالي',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tAmount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tPaid),
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tExpenses),
                                  style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tRemaining),
                                  style: TextStyle(
                                      color: tRemaining > 0
                                          ? colorScheme.error
                                          : colorScheme.onSurface,
                                      fontWeight: FontWeight.bold))),
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
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            _summaryChip(colorScheme, 'عدد الأعمال', mapped.length.toString()),
                            _summaryChip(colorScheme, 'إجمالي المتفق عليه', _grp(tAmount)),
                            _summaryChip(colorScheme, 'إجمالي الواصل', _grp(tPaid), color: Colors.green),
                            _summaryChip(colorScheme, 'إجمالي المصروفات', _grp(tExpenses), color: Colors.orange),
                            _summaryChip(colorScheme, 'إجمالي الباقي', _grp(tRemaining), color: tRemaining > 0 ? colorScheme.error : colorScheme.onSurface),
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