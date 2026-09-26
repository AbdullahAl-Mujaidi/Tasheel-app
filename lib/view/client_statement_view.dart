import 'package:fkra/controller/business_controller.dart';
import 'package:fkra/view/widgets/date_range_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ClientStatementView extends StatefulWidget {
  final BusinessController controller;
  final String workId;

  const ClientStatementView({
    super.key,
    required this.controller,
    required this.workId,
  });

  @override
  State<ClientStatementView> createState() => _ClientStatementViewState();
}

class _ClientStatementViewState extends State<ClientStatementView> {
  bool _exporting = false;
  DateTime? _from;
  DateTime? _to;

  Map<String, dynamic>? get _business {
    final String id = widget.workId;
    for (final b in widget.controller.businesses) {
      if (b['id'] != null && b['id'].toString() == id) return b;
    }
    return null;
  }

  List<Map<String, dynamic>> get _payments {
    final all = widget.controller
        .getStatementRows(widget.workId, paymentsOnly: true);
    return all.where((tx) => inDateRange(tx['date'], _from, _to)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final business = _business;
        if (business == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text('كشف حساب العميل',
                  style: TextStyle(color: colorScheme.primary)),
              centerTitle: true,
              backgroundColor: colorScheme.surface,
            ),
            body: Center(
              child: Text('العمل غير موجود',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ),
          );
        }

        final summary = widget.controller.calculateSummary(widget.workId);
        final int amount = (business['amount'] as num?)?.toInt() ?? 0;
        final int totalPaid = summary['totalPaid']!;
        final int remaining = summary['remaining']!;
        final payments = _payments;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'كشف حساب العميل',
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
                tooltip: 'تصدير PDF',
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      business['name'] ?? '',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface),
                      textAlign: TextAlign.right,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'تُرسل هذه النسخة إلى العميل ولا تتضمن المصاريف',
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.right,
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatColumn('المتفق عليه',
                              _formatAmount(amount), colorScheme.primary,
                              colorScheme),
                        ),
                        Expanded(
                          child: _buildStatColumn('الواصل',
                              _formatAmount(totalPaid), Colors.green,
                              colorScheme),
                        ),
                        Expanded(
                          child: _buildStatColumn('الباقي',
                              _formatAmount(remaining),
                              remaining == 0 ? Colors.green : Colors.orange,
                              colorScheme),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _exporting ? null : _exportPdf,
                        icon: _exporting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary),
                              )
                            : Icon(Icons.ios_share,
                                color: colorScheme.onPrimary, size: 18),
                        label: Text(_exporting ? 'جارٍ التصدير...' : 'تصدير PDF',
                            style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            minimumSize: Size(0, 44)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10),
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: _headerCell('التاريخ', colorScheme)),
                    Expanded(flex: 3, child: _headerCell('البيان', colorScheme)),
                    Expanded(flex: 2, child: _headerCell('المبلغ', colorScheme)),
                  ],
                ),
              ),
              if (payments.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                        (_from != null || _to != null)
                            ? 'لا توجد دفعات في هذا النطاق'
                            : 'لا توجد دفعات بعد',
                        style: TextStyle(
                            color: colorScheme.onSurfaceVariant)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: payments.length,
                    itemBuilder: (context, index) {
                      return _buildTableRow(payments[index], colorScheme);
                    },
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: colorScheme.primary, width: 1),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatAmount(amount),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface)),
                            Text('المبلغ المتفق عليه',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatAmount(totalPaid),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green)),
                            Text('إجمالي الواصل',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                '${_formatAmount(remaining)} ريال',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: remaining == 0
                                        ? Colors.green
                                        : Colors.orange)),
                            Text('الباقي على العميل',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: remaining == 0
                                        ? Colors.green
                                        : Colors.orange)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatColumn(
      String label, String value, Color color, ColorScheme colorScheme) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        SizedBox(height: 2),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _headerCell(String text, ColorScheme colorScheme) {
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary));
  }

  Widget _buildTableRow(Map<String, dynamic> tx, ColorScheme colorScheme) {
    final int amount = (tx['amount'] as num?)?.toInt() ?? 0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(tx['date']),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (tx['description'] ?? '').toString().isEmpty
                  ? 'دفعة'
                  : tx['description'].toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '+${_formatAmount(amount)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
            ],
          ),
          if ((tx['createdByLabel'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'بواسطة: ${tx['createdByLabel']}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  // ========== توليد ملف PDF ==========
  Future<void> _exportPdf() async {
    final business = _business;
    if (business == null) return;
    setState(() => _exporting = true);
    try {
      final summary = widget.controller.calculateSummary(widget.workId);
      final bytes = await _generatePdf(
        business,
        _payments,
        totalPaid: summary['totalPaid']!,
        remaining: summary['remaining']!,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'كشف-حساب-العميل.pdf',
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

  Future<Uint8List> _generatePdf(
    Map<String, dynamic> business,
    List<Map<String, dynamic>> payments, {
    required int totalPaid,
    required int remaining,
  }) async {
    final int amount = (business['amount'] as num?)?.toInt() ?? 0;

    final pw.Font baseFont = await _loadFont('assets/fonts/Cairo/static/Cairo-Regular.ttf');
    final pw.Font boldFont =
        await _loadFont('assets/fonts/Cairo/static/Cairo-Bold.ttf');
    final theme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);

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
                    child: pw.Text('كشف حساب العميل',
                        style: pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      business['name']?.toString() ?? '',
                      style: pw.TextStyle(fontSize: 13),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 1.2),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    children: [
                      pw.Expanded(
                          flex: 2,
                          child: _pdfHeaderCell('التاريخ')),
                      pw.Expanded(
                          flex: 3,
                          child: _pdfHeaderCell('البيان')),
                      pw.Expanded(
                          flex: 2,
                          child: _pdfHeaderCell('المبلغ')),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 0.7),
                  pw.SizedBox(height: 4),
                  if (payments.isEmpty)
                    pw.Center(
                      child: pw.Padding(
                        padding: pw.EdgeInsets.all(12),
                        child: pw.Text('لا توجد دفعات بعد'),
                      ),
                    )
                  else
                    ...payments.map((tx) {
                      return pw.Padding(
                        padding: pw.EdgeInsets.symmetric(vertical: 3),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                _formatDate(tx['date']),
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 12),
                              ),
                            ),
                            pw.Expanded(
                              flex: 3,
                              child: pw.Text(
                                (tx['description'] ?? '').toString().isEmpty
                                    ? 'دفعة'
                                    : tx['description'].toString(),
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 12),
                              ),
                            ),
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                '+${_formatAmount((tx['amount'] as num?)?.toInt() ?? 0)}',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.green700),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  pw.SizedBox(height: 24),
                  pw.Divider(thickness: 1.2),
                  pw.SizedBox(height: 12),
                  _pdfTotalsRow('المبلغ المتفق عليه', _formatAmount(amount),
                      bold: true),
                  pw.SizedBox(height: 4),
                  _pdfTotalsRow('إجمالي الواصل', _formatAmount(totalPaid)),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    padding: pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green100,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: _pdfTotalsRow(
                        'الباقي على العميل', '${_formatAmount(remaining)} ريال',
                        bold: true, color: PdfColors.green900, fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Text(text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
            fontSize: 12, fontWeight: pw.FontWeight.bold));
  }

  pw.Widget _pdfTotalsRow(String label, String value,
      {bool bold = false, PdfColor? color, double fontSize = 13}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? PdfColors.black,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
            color: color ?? PdfColors.black,
          ),
        ),
      ],
    );
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
    return '${d.day}-${d.month}-${d.year}';
  }

  String _formatAmount(num value) {
    final String s = value.toInt().toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final int remaining = s.length - 1 - i;
      if (remaining > 0 && remaining % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }
}