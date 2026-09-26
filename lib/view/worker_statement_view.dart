import 'package:fkra/controller/workers_controller.dart';
import 'package:fkra/view/widgets/date_range_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class WorkerStatementView extends StatefulWidget {
  final WorkersController controller;
  final String workerId;

  const WorkerStatementView({
    super.key,
    required this.controller,
    required this.workerId,
  });

  @override
  State<WorkerStatementView> createState() => _WorkerStatementViewState();
}

class _WorkerStatementViewState extends State<WorkerStatementView> {
  bool _exporting = false;
  DateTime? _from;
  DateTime? _to;
  WorkersController get _ctrl => widget.controller;

  Map<String, dynamic>? get _worker {
    final id = widget.workerId;
    for (final w in _ctrl.workers) {
      if (w['id'] != null && w['id'].toString() == id) return w;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final worker = _worker;
        if (worker == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text('كشف الحساب',
                  style: TextStyle(color: colorScheme.primary)),
              centerTitle: true,
              backgroundColor: colorScheme.surface,
            ),
            body: Center(
              child: Text('العامل غير موجود',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ),
          );
        }

        final summary = _ctrl.calculateWorkerSummary(widget.workerId);
        final int earned = summary['totalEarned']!;
        final int paid = summary['totalPaid']!;
        final int advances = summary['totalAdvances']!;
        final int wExpenses = summary['totalWorkerExpenses']!;
        final int workDays = summary['totalWorkDays']!;
        final int remaining = summary['remaining']!;

        final workRecords = (worker['workRecords'] as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .where((r) => inDateRange(r['date'], _from, _to))
            .toList();
        final payments = (worker['payments'] as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .where((p) => inDateRange(p['date'], _from, _to))
            .toList();
        final advList = (worker['advances'] as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .where((a) => inDateRange(a['date'], _from, _to))
            .toList();
        final expenses = (worker['workerExpenses'] as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .where((e) => inDateRange(e['date'], _from, _to))
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'كشف الحساب',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
            backgroundColor: colorScheme.surface,
            elevation: 0,
            actions: [
              IconButton(
                onPressed: _exporting ? null : _exportPdf,
                icon: _exporting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colorScheme.primary),
                      )
                    : Icon(Icons.picture_as_pdf, color: colorScheme.primary),
                tooltip: 'طباعة / تصدير PDF',
              ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.all(12),
            children: [
              _buildSummarySection(
                  worker, workDays, earned, paid, advances, wExpenses, remaining, colorScheme),
              SizedBox(height: 16),
              DateRangeFilterBar(
                from: _from,
                to: _to,
                onFromChanged: (v) => setState(() => _from = v),
                onToChanged: (v) => setState(() => _to = v),
                onCleared: () => setState(() {
                  _from = null;
                  _to = null;
                }),
              ),
              if (workRecords.isNotEmpty)
                _buildGroupSection(
                  title: 'سجل العمل',
                  icon: Icons.work_outline,
                  color: colorScheme.primary,
                  totalLabel: '${workRecords.length} سجل',
                  colorScheme: colorScheme,
                  children: workRecords.map((r) {
                    final unit =
                        _ctrl.unitLabel(r['unit']?.toString() ?? 'day');
                    return _groupItemRow(
                      date: r['date']?.toString() ?? '',
                      description:
                          '${r['quantity'] ?? 0} $unit${(r['note'] ?? '').toString().isNotEmpty ? ' - ${r['note']}' : ''}',
                      amount: (r['amount'] as num?)?.toInt() ?? 0,
                      sign: '+',
                      color: Colors.green,
                      colorScheme: colorScheme,
                      createdByLabel:
                          (r['createdByLabel'] ?? '').toString(),
                    );
                  }).toList(),
                ),
              if (workRecords.isNotEmpty) SizedBox(height: 12),
              if (payments.isNotEmpty)
                _buildGroupSection(
                  title: 'الدفعات',
                  icon: Icons.payments,
                  color: Colors.green,
                  totalLabel: '${payments.length} دفعة',
                  colorScheme: colorScheme,
                  children: payments.map((p) {
                    return _groupItemRow(
                      date: p['date']?.toString() ?? '',
                      description:
                          (p['note'] ?? '').toString().isNotEmpty
                              ? p['note'].toString()
                              : 'دفعة',
                      amount: (p['amount'] as num?)?.toInt() ?? 0,
                      sign: '+',
                      color: Colors.green,
                      colorScheme: colorScheme,
                      createdByLabel:
                          (p['createdByLabel'] ?? '').toString(),
                    );
                  }).toList(),
                ),
              if (payments.isNotEmpty) SizedBox(height: 12),
              if (advList.isNotEmpty)
                _buildGroupSection(
                  title: 'السلف',
                  icon: Icons.account_balance_wallet,
                  color: Colors.orange,
                  totalLabel: '${advList.length} سلفة',
                  colorScheme: colorScheme,
                  children: advList.map((a) {
                    return _groupItemRow(
                      date: a['date']?.toString() ?? '',
                      description:
                          (a['note'] ?? '').toString().isNotEmpty
                              ? a['note'].toString()
                              : 'سلفة',
                      amount: (a['amount'] as num?)?.toInt() ?? 0,
                      sign: '-',
                      color: Colors.orange,
                      colorScheme: colorScheme,
                      createdByLabel:
                          (a['createdByLabel'] ?? '').toString(),
                    );
                  }).toList(),
                ),
              if (advList.isNotEmpty) SizedBox(height: 12),
              if (expenses.isNotEmpty)
                _buildGroupSection(
                  title: 'المصروفات',
                  icon: Icons.remove_circle_outline,
                  color: colorScheme.error,
                  totalLabel: '${expenses.length} مصروف',
                  colorScheme: colorScheme,
                  children: expenses.map((e) {
                    return _groupItemRow(
                      date: e['date']?.toString() ?? '',
                      description:
                          (e['description'] ?? '').toString().isNotEmpty
                              ? e['description'].toString()
                              : 'مصروف',
                      amount: (e['amount'] as num?)?.toInt() ?? 0,
                      sign: '-',
                      color: colorScheme.error,
                      colorScheme: colorScheme,
                      createdByLabel:
                          (e['createdByLabel'] ?? '').toString(),
                    );
                  }).toList(),
                ),
              if (expenses.isNotEmpty) SizedBox(height: 12),
              if (workRecords.isEmpty &&
                  payments.isEmpty &&
                  advList.isEmpty &&
                  expenses.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Text(
                        (_from != null || _to != null)
                            ? 'لا توجد حركات في هذا النطاق'
                            : 'لا توجد حركات لعرضها',
                        style:
                            TextStyle(color: colorScheme.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ========== قسم الملخص ==========
  Widget _buildSummarySection(
      Map<String, dynamic> worker,
      int workDays,
      int earned,
      int paid,
      int advances,
      int wExpenses,
      int remaining,
      ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            worker['name'] ?? '',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface),
            textAlign: TextAlign.right,
          ),
          if ((worker['createdByLabel'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1,
                      size: 14, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'أضيف بواسطة: ${worker['createdByLabel']}',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          SizedBox(height: 12),
          _summaryRow(
              'عدد أيام العمل', '$workDays يوم', colorScheme.primary, colorScheme),
          Divider(height: 20),
          _summaryRow(
              'المستحق', '${_formatAmount(earned)} ريال', colorScheme.primary, colorScheme),
          Divider(height: 20),
          _summaryRow(
              'المدفوع', '${_formatAmount(paid)} ريال', Colors.green, colorScheme),
          Divider(height: 20),
          _summaryRow(
              'السلف', '${_formatAmount(advances)} ريال', Colors.orange, colorScheme),
          Divider(height: 20),
          _summaryRow('المصروفات', '${_formatAmount(wExpenses)} ريال',
              colorScheme.error, colorScheme),
          Divider(height: 20),
          _summaryRow(
              'المتبقي',
              '${_formatAmount(remaining)} ريال',
              remaining == 0 ? Colors.green : Colors.orange,
              colorScheme,
              isBold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color,
      ColorScheme colorScheme,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ========== قسم مُجمَّع ==========
  Widget _buildGroupSection({
    required String title,
    required IconData icon,
    required Color color,
    required String totalLabel,
    required ColorScheme colorScheme,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(totalLabel,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 18),
                    SizedBox(width: 6),
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ],
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _groupItemRow({
    required String date,
    required String description,
    required int amount,
    required String sign,
    required Color color,
    required ColorScheme colorScheme,
    String createdByLabel = '',
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(_formatDate(date),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ),
              Expanded(
                flex: 4,
                child: Text(description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                flex: 2,
                child: Text('$sign${_formatAmount(amount)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),
          if (createdByLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'بواسطة: $createdByLabel',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  // ========== دوال مساعدة ==========
  String _formatDate(dynamic date) {
    DateTime? d;
    if (date is DateTime) {
      d = date;
    } else if (date is String) {
      try {
        d = DateTime.parse(date);
      } catch (_) {}
    }
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatAmount(num value) {
    final String s = value.toInt().toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final int rem = s.length - 1 - i;
      if (rem > 0 && rem % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }

  // ========== طباعة / تصدير PDF ==========
  Future<void> _exportPdf() async {
    final worker = _worker;
    if (worker == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _generatePdf(worker);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'كشف-حساب-العامل.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التصدير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Uint8List> _generatePdf(Map<String, dynamic> worker) async {
    final pw.Font baseFont =
        await _loadFont('assets/fonts/Cairo/static/Cairo-Regular.ttf');
    final pw.Font boldFont =
        await _loadFont('assets/fonts/Cairo/static/Cairo-Bold.ttf');
    final theme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);

    final summary = _ctrl.calculateWorkerSummary(widget.workerId);
    final int earned = summary['totalEarned']!;
    final int paid = summary['totalPaid']!;
    final int advances = summary['totalAdvances']!;
    final int wExpenses = summary['totalWorkerExpenses']!;
    final int workDays = summary['totalWorkDays']!;
    final int remaining = summary['remaining']!;

    final allRows = _ctrl.getStatementRows(widget.workerId);
    final rows = allRows
        .where((tx) => inDateRange(tx['date'], _from, _to))
        .toList();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Center(
                    child: pw.Text('كشف حساب العامل',
                        style: pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      worker['name']?.toString() ?? '',
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 1.2),
                  pw.SizedBox(height: 10),
                  _pdfSummaryRow('عدد أيام العمل', '$workDays يوم'),
                  _pdfDivider(),
                  _pdfSummaryRow('المستحق',
                      '${_formatAmount(earned)} ريال'),
                  _pdfDivider(),
                  _pdfSummaryRow('المدفوع',
                      '${_formatAmount(paid)} ريال'),
                  _pdfDivider(),
                  _pdfSummaryRow('السلف',
                      '${_formatAmount(advances)} ريال'),
                  _pdfDivider(),
                  _pdfSummaryRow('المصروفات',
                      '${_formatAmount(wExpenses)} ريال'),
                  _pdfDivider(),
                  _pdfSummaryRow('المتبقي',
                      '${_formatAmount(remaining)} ريال',
                      bold: true,
                      color: remaining == 0
                          ? PdfColors.green900
                          : PdfColors.orange900),
                  pw.SizedBox(height: 16),
                  _pdfSectionHeader('تفاصيل جميع الحركات'),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(flex: 2, child: _pdfHeaderCell('التاريخ')),
                      pw.Expanded(flex: 4, child: _pdfHeaderCell('البيان')),
                      pw.Expanded(flex: 2, child: _pdfHeaderCell('المبلغ')),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Divider(thickness: 0.7),
                  pw.SizedBox(height: 2),
                  if (rows.isEmpty)
                    pw.Center(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('لا توجد حركات',
                            style: pw.TextStyle(fontSize: 11)),
                      ),
                    )
                  else
                    ...rows.map((tx) {
                      final int amt =
                          (tx['amount'] as num?)?.toInt() ?? 0;
                      final bool isPlus = tx['sign'] == '+';
                      final String typeLabel = _typeLabel(
                          tx['type']?.toString() ?? '');
                      final String desc = (tx['description'] ?? '')
                              .toString()
                              .isEmpty
                          ? typeLabel
                          : tx['description'].toString();
                      return pw.Padding(
                        padding: pw.EdgeInsets.symmetric(vertical: 3),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                _formatDate(tx['date']),
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                            pw.Expanded(
                              flex: 4,
                              child: pw.Text(
                                desc,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ),
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                '${tx['sign']}${_formatAmount(amt)}',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                    color: isPlus
                                        ? PdfColors.green700
                                        : PdfColors.red700),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
    return doc.save();
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'work':
        return 'سجل عمل';
      case 'payment':
        return 'دفعة';
      case 'advance':
        return 'سحب';
      case 'expense':
        return 'مصروف';
      default:
        return type;
    }
  }

  pw.Widget _pdfSummaryRow(String label, String value,
      {bool bold = false, PdfColor? color}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? PdfColors.black,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: color ?? PdfColors.black,
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfDivider() {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Divider(thickness: 0.4),
    );
  }

  pw.Widget _pdfSectionHeader(String title) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Center(
        child: pw.Text(title,
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ),
    );
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Text(text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
            fontSize: 11, fontWeight: pw.FontWeight.bold));
  }

  // ========== تحميل الخط مع بديل احتياطي ==========
  Future<pw.Font> _loadFont(String path) async {
    final List<String> candidates = [
      path,
      'assets/fonts/Cairo-VariableFont_slnt,wght.ttf',
      'assets/fonts/Tajawal/Tajawal-Regular.ttf',
    ];
    for (final String candidate in candidates) {
      try {
        final data = await rootBundle.load(candidate);
        if (data.lengthInBytes > 0) {
          return pw.Font.ttf(data);
        }
      } catch (_) {
        // جرّب الخط التالي
      }
    }
    throw Exception('تعذر تحميل خط عربي لتوليد الـ PDF');
  }
}
