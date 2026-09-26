import 'package:flutter/material.dart';

/// شاشة تقارير العمال: تعرض كل العمال في جدول واحد
/// (اسم العامل، أيام العمل، المستحق، المدفوع، السلف، المصروفات، الباقي)
/// مع إمكانية التحديد من تاريخ إلى تاريخ + إجماليات.
/// عند تحديد نطاق زمني تُحسب القيم من السجلات الواقعة في النطاق فقط،
/// ويُعرض العمال الذين لديهم نشاط (عمل/دفع/سلفة/مصروف) في تلك الفترة.
class WorkerReportsView extends StatefulWidget {
  final List<Map<String, dynamic>> workers;

  const WorkerReportsView({super.key, required this.workers});

  @override
  State<WorkerReportsView> createState() => _WorkerReportsViewState();
}

class _WorkerReportsViewState extends State<WorkerReportsView> {
  DateTime? _from;
  DateTime? _to;

  List<Map<String, dynamic>> _listOf(Map<String, dynamic> w, String key) {
    final v = w[key];
    if (v is List) {
      return v.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final d = DateTime.tryParse(v.toString());
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  bool _inRange(dynamic v) {
    final d = _parseDate(v);
    if (d == null) return false;
    if (_from != null && d.isBefore(_from!)) return false;
    if (_to != null && d.isAfter(_to!)) return false;
    return true;
  }

  int _sumOf(
    List<Map<String, dynamic>> items,
    bool useRange, {
    String amountField = 'amount',
    String? sumField,
  }) {
    var sum = 0;
    for (final item in items) {
      if (useRange && !_inRange(item['date'])) continue;
      final num? v = (sumField != null ? item[sumField] : item[amountField]) as num?;
      sum += v?.toInt() ?? 0;
    }
    return sum;
  }

  /// إجماليات العامل — عند اختيار نطاق تُحسب من سجلات النطاق فقط.
  ({int days, int earned, int paid, int advances, int expenses, int remaining})
      _totalsOf(Map<String, dynamic> w) {
    final useRange = _from != null || _to != null;
    final workRecords = _listOf(w, 'workRecords');
    final payments = _listOf(w, 'payments');
    final advances = _listOf(w, 'advances');
    final expenses = _listOf(w, 'workerExpenses');

    final days = _sumOf(workRecords, useRange, sumField: 'quantity');
    final earned = _sumOf(workRecords, useRange);
    final paid = _sumOf(payments, useRange);
    final adv = _sumOf(advances, useRange);
    final exp = _sumOf(expenses, useRange);
    final remaining = earned - paid - adv;

    return (
      days: days,
      earned: earned,
      paid: paid,
      advances: adv,
      expenses: exp,
      remaining: remaining,
    );
  }

  /// هل للعامل أي نشاط خلال النطاق المحدد (يُستخدم في التصفية عند التحديد)؟
  bool _hasActivityInRange(Map<String, dynamic> w) {
    const keys = ['workRecords', 'payments', 'advances', 'workerExpenses'];
    for (final key in keys) {
      for (final item in _listOf(w, key)) {
        if (_inRange(item['date'])) return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> get _filtered {
    final useRange = _from != null || _to != null;
    return widget.workers.where((w) {
      if (!useRange) return true;
      return _hasActivityInRange(w);
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
        if (_from != null && _to!.isBefore(_from!)) _from = _to;
      });
    }
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
    var tDays = 0, tEarned = 0, tPaid = 0, tAdv = 0, tExp = 0, tRem = 0;
    final mapped =
        <({Map<String, dynamic> w, int days, int earned, int paid, int advances, int expenses, int remaining})>[];
    for (final w in rows) {
      final t = _totalsOf(w);
      tDays += t.days;
      tEarned += t.earned;
      tPaid += t.paid;
      tAdv += t.advances;
      tExp += t.expenses;
      tRem += t.remaining;
      mapped.add((
        w: w,
        days: t.days,
        earned: t.earned,
        paid: t.paid,
        advances: t.advances,
        expenses: t.expenses,
        remaining: t.remaining,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقارير العمال'),
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
                    Icon(Icons.groups_outlined,
                        size: 50, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'لا يوجد عمال في هذا النطاق',
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
                          DataColumn(label: Text('اسم العامل')),
                          DataColumn(label: Text('أيام العمل')),
                          DataColumn(label: Text('المستحق')),
                          DataColumn(label: Text('المدفوع')),
                          DataColumn(label: Text('السلف')),
                          DataColumn(label: Text('المصروفات')),
                          DataColumn(label: Text('الباقي')),
                        ],
                        rows: [
                          for (final m in mapped)
                            DataRow(
                              cells: [
                                DataCell(SizedBox(
                                  width: 140,
                                  child: Text(
                                    m.w['name']?.toString() ?? '—',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                )),
                                DataCell(Text(_grp(m.days))),
                                DataCell(Text(_grp(m.earned),
                                    style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(_grp(m.paid),
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(_grp(m.advances),
                                    style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(_grp(m.expenses),
                                    style: const TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(_grp(m.remaining),
                                    style: TextStyle(
                                        color: m.remaining > 0
                                            ? colorScheme.error
                                            : colorScheme.onSurface,
                                        fontWeight: FontWeight.w600))),
                              ],
                            ),
                          DataRow(
                            color: WidgetStatePropertyAll(
                                colorScheme.surfaceContainerHighest),
                            cells: [
                              const DataCell(Text('الإجمالي',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tDays),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tEarned),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tPaid),
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tAdv),
                                  style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tExp),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(_grp(tRem),
                                  style: TextStyle(
                                      color: tRem > 0
                                          ? colorScheme.error
                                          : colorScheme.onSurface,
                                      fontWeight: FontWeight.bold))),
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
                            _summaryChip(colorScheme, 'عدد العمال', mapped.length.toString()),
                            _summaryChip(colorScheme, 'إجمالي المستحق', _grp(tEarned), color: colorScheme.primary),
                            _summaryChip(colorScheme, 'إجمالي المدفوع', _grp(tPaid), color: Colors.green),
                            _summaryChip(colorScheme, 'إجمالي السلف', _grp(tAdv), color: Colors.orange),
                            _summaryChip(colorScheme, 'إجمالي المصروفات', _grp(tExp)),
                            _summaryChip(colorScheme, 'إجمالي الباقي', _grp(tRem), color: tRem > 0 ? colorScheme.error : colorScheme.onSurface),
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