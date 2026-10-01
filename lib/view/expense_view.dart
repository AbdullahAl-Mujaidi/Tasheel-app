// lib/views/expense_view.dart
import 'package:fkra/controller/expense_controller.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/view/expense_reports_view.dart';
import 'package:fkra/view/widgets/delegated_accounts_dialog.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:provider/provider.dart';
class ExpensesPage extends StatelessWidget {
  final String userId;
  const ExpensesPage({super.key, required this.userId});

  bool _canCreateExpense() =>
      MemberSessionService.instance.canCreate(TeamPermissions.expenses);
  bool _canUpdateExpense() =>
      MemberSessionService.instance.canUpdate(TeamPermissions.expenses);
  bool _canDeleteExpense() =>
      MemberSessionService.instance.canDelete(TeamPermissions.expenses);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExpenseController(userId: userId),
      child: Consumer<ExpenseController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;
          final filtered = controller.filteredExpenses;

          if (controller.isLoading) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    SizedBox(height: 16),
                    Text('جاري تحميل المصروفات...',
                        style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(
                "تسهيل",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  fontSize: 25,
                ),
              ),
              centerTitle: true,
              backgroundColor: colorScheme.surface,
              elevation: 0,
              leadingWidth: 100,
              leading: TextButton(
                onPressed: () {
                  DelegatedAccountsDialog.show(context, onAccountSwitched: () {
                    controller.syncNow();
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.supervisor_account_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 2),
                    Text(
                      'المفوضين',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  onPressed: controller.isOffline
                      ? null
                      : () async {
                          AwesomeDialog(
                            context: context,
                            dialogType: DialogType.info,
                            animType: AnimType.bottomSlide,
                            title: 'جاري المزامنة',
                            desc: 'يرجى الانتظار...',
                            dismissOnTouchOutside: false,
                            showCloseIcon: false,
                          ).show();
                          await controller.syncNow();
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('تمت المزامنة بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                  icon: Icon(Icons.sync,
                      color: controller.isOffline ? Colors.grey : colorScheme.primary),
                  tooltip: 'مزامنة مع السحاب',
                ),
                if (controller.isOffline)
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Tooltip(
                      message: 'وضع غير متصل - سيتم حفظ المصروفات محلياً',
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange, size: 18),
                            SizedBox(width: 4),
                            Text(
                              'غير متصل',
                              style: TextStyle(color: Colors.orange, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            body: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_canCreateExpense())
                        ElevatedButton.icon(
                        onPressed: () {
                          controller.resetForm();
                          _showAddEditExpenseBottomSheet(context, controller, colorScheme);
                        },
                        label: Text(
                          "إضافة مصروف",
                          style: TextStyle(fontSize: 14, color: colorScheme.onPrimary),
                        ),
                        icon: Icon(Icons.add, color: colorScheme.onPrimary),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                        ),
                      ),
                      Text(
                        "المصروفات",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                if (controller.isOffline)
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off, color: Colors.orange),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'وضع غير متصل. سيتم حفظ المصروفات الجديدة محلياً ومزامنتها تلقائياً عند عودة الاتصال.',
                            style: TextStyle(color: Colors.orange[700], fontSize: 12),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                // زر تقارير المصروفات — مطابق لزرَّي الأعمال والعمال.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ExpenseReportsView(
                            expenses: controller.expenses,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.table_view, size: 18),
                    label: const Text(
                      'تقارير المصروفات',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                SizedBox(height: 5),
                SizedBox(
                  width: 370,
                  child: TextFormField(
                    cursorColor: colorScheme.primary,
                    textAlign: TextAlign.right,
                    controller: controller.searchController,
                    style: TextStyle(color: colorScheme.onSurface),
                    onChanged: (value) => controller.updateSearch(value),
                    decoration: InputDecoration(
                      suffixIcon: Icon(Icons.search, color: colorScheme.primary),
                      hintText: "البحث عن مصروف",
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: colorScheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                _buildFilterButtons(controller, colorScheme),
                if (controller.expenses.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'إجمالي المصروفات: ${filtered.length}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (controller.expenses.any((e) => e['synced'] == 0))
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '⚠️ يوجد مصروفات غير متزامنة',
                              style: TextStyle(color: Colors.orange, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              SizedBox(height: 16),
                              Text(
                                controller.searchController.text.isNotEmpty
                                    ? 'لا توجد نتائج للبحث عن "${controller.searchController.text}"'
                                    : 'لا يوجد مصروفات\nاضغط على زر "إضافة مصروف" لإضافة أول مصروف',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final expense = filtered[index];
                            return _buildExpenseCard(expense, controller, colorScheme, context);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ========== أزرار التصفية ==========
  Widget _buildFilterButtons(ExpenseController controller, ColorScheme colorScheme) {
    List<Map<String, String>> filters = [
      {'label': 'الكل', 'value': 'الكل'},
      {'label': 'ادوات ومعدات', 'value': 'ادوات ومعدات'},
      {'label': 'مواد ومستلزمات', 'value': 'مواد ومستلزمات'},
      {'label': 'نقل ومواصلات', 'value': 'نقل ومواصلات'},
      {'label': 'اكل ومشروبات', 'value': 'اكل ومشروبات'},
      {'label': 'أجور', 'value': 'أجور'},
      {'label': 'سلف', 'value': 'سلف'},
      {'label': 'عمال', 'value': 'عمال'},
      {'label': 'اخرى', 'value': 'اخرى'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ElevatedButton(
              onPressed: () => controller.toggleCategory(filter['value']!),
              style: ElevatedButton.styleFrom(
                backgroundColor: controller.selectedCategory == filter['value']
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: controller.selectedCategory == filter['value']
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ),
              child: Text(filter['label']!),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ========== بطاقة المصروف ==========
  Widget _buildExpenseCard(
    Map<String, dynamic> expense,
    ExpenseController controller,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    String amount = expense['amount']?.toString() ?? '0';
    String category = expense['category'] ?? 'غير محدد';
    String description = expense['description'] ?? 'بدون وصف';
    bool isSynced = expense['synced'] == 1;
    String displayDate = '';
    try {
      DateTime expenseDate = DateTime.parse(expense['date']);
      displayDate = '${expenseDate.year}-${expenseDate.month}-${expenseDate.day}';
    } catch (_) {
      displayDate = 'تاريخ غير محدد';
    }

    Color categoryColor = Colors.green;
    if (category == 'ادوات ومعدات') {
      categoryColor = Colors.blue;
    } else if (category == 'نقل ومواصلات') {
      categoryColor = Colors.orange;
    } else if (category == 'اكل ومشروبات') {
      categoryColor = Colors.deepOrange;
    } else if (category == 'أجور') {
      categoryColor = Colors.teal;
    } else if (category == 'سلف') {
      categoryColor = Colors.indigo;
    } else if (category == 'عمال') {
      categoryColor = Colors.amber;
    } else if (category == 'اخرى') {
      categoryColor = Colors.purple;
    }

    return Card(
      margin: EdgeInsets.all(10),
      color: colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isSynced)
                      Container(
                        margin: EdgeInsets.only(left: 8),
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.sync_problem, color: Colors.orange, size: 16),
                      ),
                    if (_canUpdateExpense())
                      IconButton(
                        onPressed: () {
                          controller.loadExpenseForEditing(expense);
                          _showAddEditExpenseBottomSheet(context, controller, colorScheme);
                        },
                        icon: Icon(Icons.edit, color: colorScheme.primary),
                        tooltip: 'تعديل المصروف',
                      ),
                    if (_canDeleteExpense())
                      IconButton(
                        onPressed: () => _confirmDelete(context, expense['id'], description, controller),
                        icon: Icon(Icons.delete, color: colorScheme.error),
                        tooltip: 'حذف المصروف',
                      ),
                  ],
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        description,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: colorScheme.onSurface),
                      ),
                      SizedBox(height: 5),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(color: categoryColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "-$amount ريال",
                      style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 5),
                    Text(
                      displayDate,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            if ((expense['createdByLabel'] ?? '').toString().isNotEmpty ||
                (expense['lastModifiedByLabel'] ?? '')
                    .toString()
                    .isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if ((expense['createdByLabel'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt_1,
                                size: 13, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'أضيف بواسطة: ${expense['createdByLabel']}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      if ((expense['lastModifiedByLabel'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, size: 13, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text(
                              'آخر تعديل: ${expense['lastModifiedByLabel']}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========== نافذة الإضافة / التعديل ==========
  void _showAddEditExpenseBottomSheet(
    BuildContext context,
    ExpenseController controller,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateBottomSheet) {
            return Container(
              padding: EdgeInsets.all(15),
              width: double.infinity,
              height: 600,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Form(
                  key: controller.formKey,
                  child: Column(
                    children: [
                      Text(
                        controller.isEditing ? "تعديل مصروف" : "إضافة مصروف",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      SizedBox(height: 30),
                      _buildTextField(
                        "وصف المصروف",
                        "ادخل وصف المصروف",
                        controller.descriptionController,
                        (value) => null, // لا نحتاج validator هنا لأننا نستخدم form
                        colorScheme,
                      ),
                      SizedBox(height: 20),
                      _buildTextField(
                        "المبلغ(ريال)",
                        "0.0",
                        controller.amountController,
                        (value) {
                          if (value == null || value.isEmpty) return "الرجاء ادخال مبلغ المصروف";
                          try {
                            double amount = double.parse(value);
                            if (amount <= 0) return "الرجاء ادخال مبلغ صحيح";
                          } catch (_) {
                            return "الرجاء ادخال مبلغ صحيح";
                          }
                          return null;
                        },
                        colorScheme,
                        keyboardType: TextInputType.number,
                      ),
                      SizedBox(height: 20),
                      _buildCategoryDropdown(controller, colorScheme, setStateBottomSheet),
                      SizedBox(height: 20),
                      _buildDateField(context,controller, colorScheme, setStateBottomSheet),
                      SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              controller.resetForm();
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error),
                            child: Text("الغاء", style: TextStyle(color: colorScheme.onError)),
                          ),
                          SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              if (controller.isEditing) {
                                final bool ok =
                                    await controller.editExpense(context);
                                if (ok && context.mounted) {
                                  Navigator.pop(context);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(controller.isOffline
                                          ? 'تم تعديل المصروف محلياً وسيتم مزامنته تلقائياً عند عودة الاتصال'
                                          : 'تم تعديل المصروف بنجاح'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } else {
                                final bool ok =
                                    await controller.addExpense(context);
                                if (ok && context.mounted) {
                                  Navigator.pop(context);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(controller.isOffline
                                          ? 'تم حفظ المصروف محلياً وسيتم مزامنته تلقائياً عند عودة الاتصال'
                                          : 'تم إضافة المصروف بنجاح'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary),
                            child: Text(
                              controller.isEditing
                                  ? (controller.isOffline ? "تعديل محلياً" : "تحديث")
                                  : (controller.isOffline ? "حفظ محلياً" : "حفظ"),
                              style: TextStyle(color: colorScheme.onPrimary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(
    String label,
    String hint,
    TextEditingController controller,
    String? Function(String?)? validator,
    ColorScheme colorScheme, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(label, style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          textAlign: TextAlign.right,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator,
          keyboardType: keyboardType,
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            filled: true,
            hintText: hint,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.outline),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            errorBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.error),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(
    ExpenseController controller,
    ColorScheme colorScheme,
    StateSetter setStateBottomSheet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text("الفئة", style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
        ),
        SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.rtl,
          child: DropdownButtonFormField<String>(
            initialValue: controller.selectedValue ?? "اخرى",
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.primary),
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
            iconSize: 30,
            dropdownColor: colorScheme.surface,
            isExpanded: true,
            items: controller.categoryItems.map((String item) {
              return DropdownMenuItem<String>(
                alignment: Alignment.centerRight,
                value: item,
                child: Text(item, textAlign: TextAlign.right, style: TextStyle(fontSize: 16, color: colorScheme.onSurface)),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setStateBottomSheet(() {
                controller.setCategory(newValue);
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(
    BuildContext context, 
    ExpenseController controller,
    ColorScheme colorScheme,
    StateSetter setStateBottomSheet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text("التاريخ", style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
        ),
        SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${controller.date.day}-${controller.date.month}-${controller.date.year}",
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary),
                onPressed: () async {
                  DateTime? newDate = await showDatePicker(
                    context: context,
                    initialDate: controller.date,
                    firstDate: DateTime(1700),
                    lastDate: DateTime(2200),
                  );
                  if (newDate != null) {
                    setStateBottomSheet(() {
                      controller.setDate(newDate);
                    });
                  }
                },
                child: Text("اختر التاريخ", style: TextStyle(color: colorScheme.onPrimary)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========== تأكيد الحذف ==========
  void _confirmDelete(BuildContext context, String id, String description, ExpenseController controller) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل أنت متأكد أنك تريد حذف المصروف "$description"؟',
      btnCancelText: 'إلغاء',
      btnOkText: 'حذف',
      btnOkOnPress: () async {
        await controller.deleteExpense(id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("تم حذف المصروف بنجاح"), backgroundColor: Colors.green),
          );
        }
      },
    ).show();
  }
}