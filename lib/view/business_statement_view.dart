import 'package:fkra/controller/business_controller.dart';
import 'package:fkra/view/widgets/date_range_filter_bar.dart';
import 'package:flutter/material.dart';

class BusinessStatementView extends StatefulWidget {
  final BusinessController controller;
  final String workId;

  const BusinessStatementView({
    super.key,
    required this.controller,
    required this.workId,
  });

  @override
  State<BusinessStatementView> createState() => _BusinessStatementViewState();
}

class _BusinessStatementViewState extends State<BusinessStatementView> {
  DateTime? _from;
  DateTime? _to;

  Map<String, dynamic>? get _business {
    final String id = widget.workId;
    for (final b in widget.controller.businesses) {
      if (b['id'] != null && b['id'].toString() == id) return b;
    }
    return null;
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
              title: Text('كشف الحساب',
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

        final allTransactions =
            widget.controller.getStatementRows(widget.workId);
        final transactions =
            allTransactions.where((tx) => inDateRange(tx['date'], _from, _to)).toList();
        final totalPaid =
            (business['totalPaid'] as num?)?.toInt() ?? 0;
        final totalExpenses =
            (business['totalExpenses'] as num?)?.toInt() ?? 0;
        final remaining = (business['remaining'] as num?)?.toInt() ?? 0;
        final net = totalPaid - totalExpenses;

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
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatColumn('قيمة العمل',
                              _formatAmount(business['amount'] ?? 0),
                              colorScheme.primary, colorScheme),
                        ),
                        Expanded(
                          child: _buildStatColumn('المدفوع',
                              _formatAmount(totalPaid), Colors.green,
                              colorScheme),
                        ),
                        Expanded(
                          child: _buildStatColumn('المتبقي',
                              _formatAmount(remaining),
                              remaining == 0 ? Colors.green : Colors.orange,
                              colorScheme),
                        ),
                        Expanded(
                          child: _buildStatColumn('المصاريف',
                              _formatAmount(totalExpenses),
                              colorScheme.error, colorScheme),
                        ),
                      ],
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
              SizedBox(height: 4),
              _buildTableHeader(colorScheme),
              if (transactions.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                        (_from != null || _to != null)
                            ? 'لا توجد حركات في هذا النطاق'
                            : 'لا توجد حركات لعرضها',
                        style: TextStyle(
                            color: colorScheme.onSurfaceVariant)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      return _buildTableRow(transactions[index], colorScheme);
                    },
                  ),
                ),
              _buildFooter(net, colorScheme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatColumn(String label, String value, Color color,
      ColorScheme colorScheme) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildTableHeader(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _headerCell('التاريخ', colorScheme)),
          Expanded(flex: 3, child: _headerCell('البيان', colorScheme)),
          Expanded(flex: 2, child: _headerCell('النوع', colorScheme)),
          Expanded(flex: 2, child: _headerCell('المبلغ', colorScheme)),
        ],
      ),
    );
  }

  Widget _headerCell(String text, ColorScheme colorScheme) {
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary));
  }

  Widget _buildTableRow(Map<String, dynamic> tx, ColorScheme colorScheme) {
    final bool isPayment = tx['type'] == 'payment';
    final Color color = isPayment ? Colors.green : colorScheme.error;
    final int amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final String sign = isPayment ? '+' : '-';

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
              (tx['description'] ?? '')
                      .toString()
                      .isEmpty
                  ? (isPayment ? 'دفعة' : 'مصروف')
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
              isPayment ? 'دفعة' : 'مصروف',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$sign${_formatAmount(amount)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color),
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

  Widget _buildFooter(int net, ColorScheme colorScheme) {
    final Color color = net < 0 ? colorScheme.error : Colors.green;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(12),
        margin: EdgeInsets.fromLTRB(12, 6, 12, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${net < 0 ? '' : '+'}${_formatAmount(net)} ريال',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
            Text('الصافي (المدفوع − المصاريف)',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
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