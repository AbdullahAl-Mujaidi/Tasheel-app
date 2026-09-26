import 'package:fkra/controller/workers_controller.dart';
import 'package:fkra/db/database_helper.dart';
import 'package:fkra/view/worker_statement_view.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';

class WorkerDetailsView extends StatefulWidget {
  final WorkersController controller;
  final String workerId;

  const WorkerDetailsView({
    super.key,
    required this.controller,
    required this.workerId,
  });

  @override
  State<WorkerDetailsView> createState() => _WorkerDetailsViewState();
}

class _WorkerDetailsViewState extends State<WorkerDetailsView> {
  int _tabIndex = 0;

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
              title: Text('تفاصيل العامل',
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
        final int remaining = summary['remaining']!;
        final int wExpenses = summary['totalWorkerExpenses']!;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              worker['name'] ?? '',
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
                onPressed: () => _showBusinessPicker(context, colorScheme),
                icon: Icon(Icons.link, color: colorScheme.primary),
                tooltip: 'ربط بعمل',
              ),
              IconButton(
                onPressed: () {
                  _ctrl.loadWorkerForEditing(worker);
                  Navigator.pop(context);
                },
                icon: Icon(Icons.edit, color: colorScheme.primary),
                tooltip: 'تعديل العامل',
              ),
              IconButton(
                onPressed: () =>
                    _confirmDeleteWorker(context, worker['id'], worker['name'], colorScheme),
                icon: Icon(Icons.delete, color: colorScheme.error),
                tooltip: 'حذف العامل',
              ),
            ],
          ),
          body: Column(
            children: [
              _buildHeader(worker, colorScheme),
              _buildSummaryGrid(earned, paid, remaining, wExpenses, colorScheme),
              _buildActionRow(colorScheme),
              _buildTabBar(colorScheme),
              Expanded(child: _buildTabContent(worker, colorScheme)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Map<String, dynamic> worker, ColorScheme colorScheme) {
    final wageType = worker['wageType'] ?? 'monthly';
    final wageLabel = _ctrl.wageTypeLabel(wageType);
    final salary = worker['salary']?.toString() ?? '0';
    final phone = worker['phone'] ?? '';
    final specialization = worker['specialization'] ?? '';

    return Container(
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
          Row(
            children: [
              Expanded(
                child: _headerItem(Icons.person, worker['name'] ?? '', colorScheme.primary, colorScheme),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              if (phone.isNotEmpty)
                Expanded(child: _headerItem(Icons.phone, phone, colorScheme.primary, colorScheme)),
              if (specialization.isNotEmpty)
                Expanded(child: _headerItem(Icons.hotel_class, specialization, Colors.deepOrange, colorScheme)),
              Expanded(child: _headerItem(Icons.attach_money, "$salary ريال/$wageLabel", Colors.green, colorScheme)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerItem(IconData icon, String text, Color color, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryGrid(
      int earned, int paid, int remaining, int wExpenses, ColorScheme colorScheme) {
    final double boxWidth = (MediaQuery.of(context).size.width - 32) / 2;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('المستحق', earned, colorScheme.primary, Icons.work_outline, colorScheme),
        ),
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('المدفوع', paid, Colors.green, Icons.trending_down, colorScheme),
        ),
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('المتبقي', remaining,
              remaining == 0 ? Colors.green : Colors.orange, Icons.hourglass_empty, colorScheme),
        ),
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('مصروفات العامل', wExpenses, colorScheme.error, Icons.remove_circle_outline, colorScheme),
        ),
      ],
    );
  }

  Widget _buildSummaryBox(String label, int value, Color color,
      IconData icon, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              _formatAmount(value),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          Text('ريال', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildActionRow(ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkerStatementView(
                  controller: _ctrl,
                  workerId: widget.workerId,
                ),
              ),
            );
          },
          icon: Icon(Icons.receipt_long),
          label: Text('كشف الحساب'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ColorScheme colorScheme) {
    final tabs = ['الدفعات', 'سجل العمل', 'السلف', 'المصروفات'];
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final bool selected = _tabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tabIndex = i),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent(Map<String, dynamic> worker, ColorScheme colorScheme) {
    switch (_tabIndex) {
      case 0:
        return _buildPaymentsTab(worker, colorScheme);
      case 1:
        return _buildWorkRecordsTab(worker, colorScheme);
      case 2:
        return _buildAdvancesTab(worker, colorScheme);
      case 3:
        return _buildExpensesTab(worker, colorScheme);
      default:
        return SizedBox.shrink();
    }
  }

  // ========== الدفعات ==========
  Widget _buildPaymentsTab(Map<String, dynamic> worker, ColorScheme colorScheme) {
    final list = (worker['payments'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.sort((a, b) {
      try { return DateTime.parse(b['date'].toString()).compareTo(DateTime.parse(a['date'].toString())); }
      catch (_) { return 0; }
    });
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: ElevatedButton.icon(
            onPressed: () => _showAddPaymentSheet(context, colorScheme),
            icon: Icon(Icons.add),
            label: Text('إضافة دفعة'),
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('لا توجد دفعات', style: TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _buildListItem(
                    colorScheme,
                    amount: (list[i]['amount'] as num?)?.toInt() ?? 0,
                    date: list[i]['date']?.toString() ?? '',
                    label: 'دفعة',
                    note: list[i]['note']?.toString() ?? '',
                    createdByLabel:
                        list[i]['createdByLabel']?.toString() ?? '',
                    onDelete: () => _confirmDelete(
                      'حذف الدفعة',
                      'هل تريد حذف هذه الدفعة؟',
                      () => _ctrl.deletePayment(widget.workerId, list[i]['id'].toString()),
                      colorScheme,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _showAddPaymentSheet(BuildContext context, ColorScheme colorScheme) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('إضافة دفعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
            SizedBox(height: 12),
            _dialogTextField('المبلغ', amountCtrl, colorScheme, keyboardType: TextInputType.number),
            SizedBox(height: 12),
            _dialogTextField('ملاحظة', noteCtrl, colorScheme),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text) ?? 0;
                if (amt > 0) {
                  _ctrl.addPayment(widget.workerId, amount: amt, note: noteCtrl.text);
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
              child: Text('حفظ'),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ========== سجل العمل ==========
  Widget _buildWorkRecordsTab(Map<String, dynamic> worker, ColorScheme colorScheme) {
    final list = (worker['workRecords'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.sort((a, b) {
      try { return DateTime.parse(b['date'].toString()).compareTo(DateTime.parse(a['date'].toString())); }
      catch (_) { return 0; }
    });
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: ElevatedButton.icon(
            onPressed: () => _showAddWorkRecordSheet(context, colorScheme),
            icon: Icon(Icons.add),
            label: Text('إضافة سجل عمل'),
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('لا يوجد سجل عمل', style: TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final unit = _ctrl.unitLabel(list[i]['unit']?.toString() ?? 'day');
                    return _buildListItem(
                      colorScheme,
                      amount: (list[i]['amount'] as num?)?.toInt() ?? 0,
                      date: list[i]['date']?.toString() ?? '',
                      label: 'سجل: ${list[i]['quantity'] ?? 0} $unit',
                      note: list[i]['note']?.toString() ?? '',
                      createdByLabel:
                          list[i]['createdByLabel']?.toString() ?? '',
                      onDelete: () => _confirmDelete(
                        'حذف السجل',
                        'هل تريد حذف هذا السجل؟',
                        () => _ctrl.deleteWorkRecord(widget.workerId, list[i]['id'].toString()),
                        colorScheme,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showAddWorkRecordSheet(BuildContext context, ColorScheme colorScheme) {
    final worker = _worker;
    final wageType = worker?['wageType'] ?? 'monthly';
    final rate = (worker?['salary'] as num?)?.toDouble() ?? 0;
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String unit;
    switch (wageType) {
      case 'daily': unit = 'day'; break;
      case 'halfDay': unit = 'halfDay'; break;
      case 'hourly': unit = 'hour'; break;
      case 'weekly': unit = 'week'; break;
      default: unit = 'day'; break;
    }
    final unitOptions = [
      MapEntry('day', 'يوم'),
      MapEntry('halfDay', 'نصف يوم'),
      MapEntry('hour', 'ساعة'),
    ];

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('إضافة سجل عمل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
              SizedBox(height: 12),
              Text('الوحدة', style: TextStyle(fontSize: 14, color: colorScheme.onSurface)),
              SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: unitOptions.map((opt) => ChoiceChip(
                  label: Text(opt.value),
                  selected: unit == opt.key,
                  onSelected: (_) => setSheetState(() => unit = opt.key),
                  selectedColor: colorScheme.primary,
                  labelStyle: TextStyle(
                    color: unit == opt.key ? colorScheme.onPrimary : colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                )).toList(),
              ),
              SizedBox(height: 12),
              _dialogTextField('الكمية', qtyCtrl, colorScheme, keyboardType: TextInputType.number),
              SizedBox(height: 8),
              if (rate > 0)
                Text('الإجمالي: ${_formatAmount(_calcAmount(qtyCtrl.text, rate, unit))} ريال',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              _dialogTextField('ملاحظة', noteCtrl, colorScheme),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final qty = double.tryParse(qtyCtrl.text) ?? 0;
                  final amt = _calcAmount(qtyCtrl.text, rate, unit);
                  if (qty > 0 && amt > 0) {
                    _ctrl.addWorkRecord(widget.workerId, quantity: qty, unit: unit, amount: amt, note: noteCtrl.text);
                  }
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
                child: Text('حفظ'),
              ),
              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  double _calcAmount(String qtyStr, double rate, String unit) {
    final qty = double.tryParse(qtyStr) ?? 0;
    switch (unit) {
      case 'halfDay': return qty * rate * 0.5;
      case 'hour': return qty * rate;
      default: return qty * rate; // day, week, month
    }
  }

  // ========== السلف ==========
  Widget _buildAdvancesTab(Map<String, dynamic> worker, ColorScheme colorScheme) {
    final list = (worker['advances'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.sort((a, b) {
      try { return DateTime.parse(b['date'].toString()).compareTo(DateTime.parse(a['date'].toString())); }
      catch (_) { return 0; }
    });
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: ElevatedButton.icon(
            onPressed: () => _showAddAdvanceSheet(context, colorScheme),
            icon: Icon(Icons.add),
            label: Text('إضافة سلفة'),
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('لا توجد سلف', style: TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _buildListItem(
                    colorScheme,
                    amount: (list[i]['amount'] as num?)?.toInt() ?? 0,
                    date: list[i]['date']?.toString() ?? '',
                    label: 'سلفة',
                    note: list[i]['note']?.toString() ?? '',
                    createdByLabel:
                        list[i]['createdByLabel']?.toString() ?? '',
                    onDelete: () => _confirmDelete(
                      'حذف السلفة',
                      'هل تريد حذف هذه السلفة؟',
                      () => _ctrl.deleteAdvance(widget.workerId, list[i]['id'].toString()),
                      colorScheme,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _showAddAdvanceSheet(BuildContext context, ColorScheme colorScheme) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('إضافة سلفة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
            SizedBox(height: 12),
            _dialogTextField('المبلغ', amountCtrl, colorScheme, keyboardType: TextInputType.number),
            SizedBox(height: 12),
            _dialogTextField('ملاحظة', noteCtrl, colorScheme),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text) ?? 0;
                if (amt > 0) {
                  _ctrl.addAdvance(widget.workerId, amount: amt, note: noteCtrl.text);
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
              child: Text('حفظ'),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ========== مصروفات العامل ==========
  Widget _buildExpensesTab(Map<String, dynamic> worker, ColorScheme colorScheme) {
    final list = (worker['workerExpenses'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.sort((a, b) {
      try { return DateTime.parse(b['date'].toString()).compareTo(DateTime.parse(a['date'].toString())); }
      catch (_) { return 0; }
    });
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: ElevatedButton.icon(
            onPressed: () => _showAddExpenseSheet(context, colorScheme),
            icon: Icon(Icons.add),
            label: Text('إضافة مصروف'),
            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('لا توجد مصروفات', style: TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _buildListItem(
                    colorScheme,
                    amount: (list[i]['amount'] as num?)?.toInt() ?? 0,
                    date: list[i]['date']?.toString() ?? '',
                    label: 'مصروف',
                    note: list[i]['description']?.toString() ?? '',
                    createdByLabel:
                        list[i]['createdByLabel']?.toString() ?? '',
                    onDelete: () => _confirmDelete(
                      'حذف المصروف',
                      'هل تريد حذف هذا المصروف؟',
                      () => _ctrl.deleteWorkerExpense(widget.workerId, list[i]['id'].toString()),
                      colorScheme,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _showAddExpenseSheet(BuildContext context, ColorScheme colorScheme) {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('إضافة مصروف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
            SizedBox(height: 12),
            _dialogTextField('المبلغ', amountCtrl, colorScheme, keyboardType: TextInputType.number),
            SizedBox(height: 12),
            _dialogTextField('الوصف', descCtrl, colorScheme),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text) ?? 0;
                if (amt > 0) {
                  _ctrl.addWorkerExpense(widget.workerId, amount: amt, description: descCtrl.text);
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
              child: Text('حفظ'),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ========== مكونات مشتركة ==========
  Widget _buildListItem(
    ColorScheme colorScheme, {
    required int amount,
    required String date,
    required String label,
    required String note,
    required VoidCallback onDelete,
    String createdByLabel = '',
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        title: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$date${note.isNotEmpty ? ' - $note' : ''}',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            if (createdByLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'بواسطة: $createdByLabel',
                  style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_formatAmount(amount)} ريال',
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogTextField(String label, TextEditingController ctrl,
      ColorScheme colorScheme, {TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.primary, width: 2)),
      ),
    );
  }

  void _confirmDelete(String title, String desc, VoidCallback onConfirm, ColorScheme colorScheme) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: title,
      desc: desc,
      btnOkText: 'حذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () {
        onConfirm();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم الحذف'), backgroundColor: Colors.green),
          );
        }
      },
    ).show();
  }

  void _confirmDeleteWorker(
      BuildContext context, dynamic id, String? name, ColorScheme colorScheme) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل أنت متأكد من حذف العامل "$name"؟',
      btnOkText: 'حذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        await _ctrl.deleteWorker(id.toString());
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("تم حذف العامل"), backgroundColor: Colors.green),
          );
        }
      },
    ).show();
  }

  Future<void> _showBusinessPicker(BuildContext context, ColorScheme colorScheme) async {
    final businesses = await _loadBusinesses();
    if (!context.mounted) return;
    final worker = _worker;
    final currentBizId = worker?['businessId'];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(12),
              child: Text('ربط بعمل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
            ),
            ListTile(
              leading: Icon(Icons.close, color: colorScheme.error),
              title: Text('بدون ربط', style: TextStyle(color: colorScheme.onSurface)),
              selected: currentBizId == null,
              onTap: () {
                _ctrl.setWorkerBusiness(widget.workerId, null);
                Navigator.pop(ctx);
              },
            ),
            ...businesses.map((biz) => ListTile(
                  leading: Icon(Icons.work, color: colorScheme.primary),
                  title: Text(biz['name'] ?? '', style: TextStyle(color: colorScheme.onSurface)),
                  selected: biz['id'].toString() == currentBizId?.toString(),
                  onTap: () {
                    _ctrl.setWorkerBusiness(widget.workerId, biz['id'].toString());
                    Navigator.pop(ctx);
                  },
                )),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadBusinesses() async {
    try {
      return await DatabaseHelper.instance.loadAll('businesses', _ctrl.userId);
    } catch (_) {}
    return [];
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
}
