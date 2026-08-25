import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/controller/business_controller.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:provider/provider.dart';

class BusinessPage extends StatelessWidget {
  final String userId;

  const BusinessPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BusinessController(userId: userId),
      child: Consumer<BusinessController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;

          if (controller.isLoading) {
            return Scaffold(
              appBar: AppBar(
                title: Text("تساهيل",
                    style: TextStyle(color: colorScheme.primary)),
                centerTitle: true,
                backgroundColor: colorScheme.surface,
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    SizedBox(height: 16),
                    Text('جاري تحميل الأعمال...',
                        style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(
                "تساهيل",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  fontSize: 25,
                ),
              ),
              centerTitle: true,
              backgroundColor: colorScheme.surface,
              elevation: 0,
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

                          // المزامنة تتم عبر المتحكم
                          await controller.syncWithFirestore();
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
                      color: controller.isOffline
                          ? Colors.grey
                          : colorScheme.primary),
                  tooltip: 'مزامنة مع السحاب',
                ),
                if (controller.isOffline)
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Tooltip(
                      message: 'وضع غير متصل - سيتم حفظ الأعمال محلياً',
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off,
                                color: Colors.orange, size: 18),
                            SizedBox(width: 4),
                            Text(
                              'غير متصل',
                              style:
                                  TextStyle(color: Colors.orange, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            controller.resetForm();
                            _showAddEditBusinessBottomSheet(
                                context, controller, colorScheme);
                          },
                          label: Text(
                            "اضافة عمل",
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          icon: Icon(Icons.add, color: colorScheme.onPrimary),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                          ),
                        ),
                        Text(
                          "الاعمال",
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
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'وضع غير متصل. سيتم حفظ الأعمال الجديدة محلياً ومزامنتها تلقائياً عند عودة الاتصال.',
                              style: TextStyle(
                                  color: Colors.orange[700], fontSize: 12),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 5),
                  SizedBox(
                    width: 370,
                    child: TextFormField(
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        suffixIcon:
                            Icon(Icons.search, color: colorScheme.primary),
                        hintText: "البحث عن عمل",
                        hintStyle:
                            TextStyle(color: colorScheme.onSurfaceVariant),
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
                          borderSide:
                              BorderSide(color: colorScheme.primary, width: 2),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 15),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterButton(
                            "الكل", "الكل", controller, colorScheme),
                        SizedBox(width: 5),
                        _buildFilterButton("قيد الانتظار", "قيد الانتظار",
                            controller, colorScheme),
                        SizedBox(width: 5),
                        _buildFilterButton("جاري التنفيذ", "جاري التنفيذ",
                            controller, colorScheme),
                        SizedBox(width: 5),
                        _buildFilterButton(
                            "مكتمل", "مكتمل", controller, colorScheme),
                        SizedBox(width: 5),
                        _buildFilterButton(
                            "ملغي", "ملغي", controller, colorScheme),
                      ],
                    ),
                  ),
                  if (controller.businesses.isNotEmpty)
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'إجمالي الأعمال: ${controller.filteredBusinesses.length}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          if (controller.businesses
                              .any((e) => e['synced'] == 0))
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '⚠️ يوجد أعمال غير متزامنة',
                                style: TextStyle(
                                    color: Colors.orange, fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                  _buildBusinessesList(controller, colorScheme, context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ========== دوال بناء الـ UI ==========
  Widget _buildFilterButton(
    String label,
    String value,
    BusinessController controller,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ElevatedButton(
        onPressed: () => controller.toggleCategory(value),
        style: ElevatedButton.styleFrom(
          backgroundColor: controller.selectedCategory == value
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          foregroundColor: controller.selectedCategory == value
              ? colorScheme.onPrimary
              : colorScheme.onSurface,
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildBusinessesList(
    BusinessController controller,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    final filtered = controller.filteredBusinesses;
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(50),
          child: Column(
            children: [
              Icon(Icons.work_off,
                  size: 50, color: colorScheme.onSurfaceVariant),
              SizedBox(height: 10),
              Text(
                controller.selectedCategory != "الكل"
                    ? 'لا توجد أعمال في هذه الفئة'
                    : 'لا توجد أعمال',
                style: TextStyle(
                    fontSize: 18, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        var data = filtered[index];
        return _buildBusinessCard(data, controller, colorScheme, context);
      },
    );
  }

  Widget _buildBusinessCard(
    Map<String, dynamic> data,
    BusinessController controller,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    Color statusColor = colorScheme.primary;
    String status = data['status'] ?? '';
    bool isSynced = data['synced'] == 1;

    if (status == 'مكتمل')
      statusColor = Colors.green;
    else if (status == 'ملغي')
      statusColor = colorScheme.error;
    else if (status == 'جاري التنفيذ') statusColor = Colors.orange;

    return Card(
      margin: EdgeInsets.all(10),
      color: !isSynced ? Colors.orange.withOpacity(0.05) : colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: !isSynced
            ? BorderSide(color: Colors.orange, width: 1)
            : BorderSide.none,
      ),
      child: Container(
        padding: EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (!isSynced)
                      Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: 'غير متزامن - سيتم رفعه تلقائياً',
                          child: Icon(Icons.sync_problem,
                              color: Colors.orange, size: 20),
                        ),
                      ),
                    IconButton(
                      onPressed: () {
                        controller.loadBusinessForEditing(data);
                        _showAddEditBusinessBottomSheet(
                            context, controller, colorScheme);
                      },
                      icon: Icon(Icons.edit, color: colorScheme.primary),
                      tooltip: 'تعديل العمل',
                    ),
                    IconButton(
                      onPressed: () => _confirmDelete(context, data['id'],
                          data['name'] ?? 'بدون اسم', controller),
                      icon: Icon(Icons.delete, color: colorScheme.error),
                      tooltip: 'حذف العمل',
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: statusColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            SizedBox(height: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    data['name'] ?? 'بدون اسم',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  data['description'] ?? '',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.right,
                ),
                if (data['customFields'] != null &&
                    (data['customFields'] as Map).isNotEmpty)
                  ..._buildCustomFieldsDisplay(
                      data['customFields'], colorScheme),
                Divider(color: colorScheme.outline),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(data['date']),
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "${data['amount'] ?? 0} ريال",
                      style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCustomFieldsDisplay(
      Map<String, dynamic> customFieldsData, ColorScheme colorScheme) {
    List<Widget> widgets = [];
    customFieldsData.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        widgets.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _formatValue(value),
                    style: TextStyle(
                        fontSize: 14, color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.left,
                  ),
                ),
                Text(
                  key,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface),
                ),
              ],
            ),
          ),
        );
      }
    });
    return widgets;
  }

  String _formatDate(dynamic date) {
    if (date is String) {
      try {
        DateTime d = DateTime.parse(date);
        return "${d.day}-${d.month}-${d.year}";
      } catch (_) {
        return '';
      }
    }
    if (date is Timestamp) {
      DateTime d = date.toDate();
      return "${d.day}-${d.month}-${d.year}";
    }
    return '';
  }

  String _formatValue(dynamic value) {
    if (value is DateTime) return "${value.day}-${value.month}-${value.year}";
    return value?.toString() ?? '';
  }

  void _confirmDelete(BuildContext context, String id, String name,
      BusinessController controller) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل أنت متأكد من حذف العمل "$name"؟',
      btnOkText: 'حذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        await controller.deleteBusiness(id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("تم حذف العمل بنجاح"),
                backgroundColor: Colors.green),
          );
        }
      },
    ).show();
  }

  // ========== نافذة إضافة/تعديل ==========
  void _showAddEditBusinessBottomSheet(
    BuildContext context,
    BusinessController controller,
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
            return Form(
              key: controller.formKey,
              child: Container(
                padding: EdgeInsets.all(15),
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        controller.isEditing ? "تعديل عمل" : "إضافة عمل",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface),
                      ),
                      if (controller.isOffline)
                        Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.orange, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  controller.isEditing
                                      ? 'سيتم تعديل العمل محلياً لعدم وجود اتصال'
                                      : 'سيتم حفظ العمل محلياً لعدم وجود اتصال',
                                  style: TextStyle(
                                      color: Colors.orange[700], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(height: 30),
                      _buildTextField(
                        "اسم العمل",
                        "ادخل اسم العمل",
                        (value) => controller.businessName = value,
                        initialValue: controller.businessName,
                        validator: (value) => _validateBusinessName(value),
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      _buildTextField(
                        "وصف العمل",
                        "ادخل وصف العمل",
                        (value) => controller.businessDescription = value,
                        initialValue: controller.businessDescription,
                        validator: (value) =>
                            _validateBusinessDescription(value),
                        maxLines: 3,
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      _buildTextField(
                        "المبلغ(ريال)",
                        "0.0",
                        (value) => controller.businessAmount = value,
                        initialValue: controller.businessAmount,
                        keyboardType: TextInputType.number,
                        validator: (value) => _validateBusinessAmount(value),
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      // تمرير context هنا
                      _buildDateField(
                          context, controller, colorScheme, setStateBottomSheet),
                      SizedBox(height: 20),
                      _buildStatusField(
                          controller, colorScheme, setStateBottomSheet),
                      if (controller.customFieldsList.isNotEmpty) ...[
                        SizedBox(height: 30),
                        Divider(color: colorScheme.outline),
                        Center(
                          child: Text(
                            "حقول اضافية للتخصيص",
                            style: TextStyle(
                                fontSize: 16,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 20),
                        Column(
                          children: controller.customFieldsList.map((field) {
                            return _buildCustomField(
                                context, field, controller, setStateBottomSheet, colorScheme);
                          }).toList(),
                        ),
                      ],
                      SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              controller.resetForm();
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.error),
                            child: Text("الغاء",
                                style: TextStyle(color: colorScheme.onError)),
                          ),
                          SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: () async {
                              if (controller.isEditing) {
                                await controller.editBusiness(
                                    context, controller.editingBusinessId!);
                              } else {
                                await controller.addBusiness(context);
                              }
                              if (context.mounted) Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary),
                            child: Text(
                              controller.isEditing
                                  ? (controller.isOffline
                                      ? "تعديل محلياً"
                                      : "تحديث")
                                  : (controller.isOffline
                                      ? "حفظ محلياً"
                                      : "حفظ"),
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

  // ========== دوال بناء الحقول ==========
  Widget _buildTextField(
    String label,
    String hint,
    Function(String) onChanged, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    required ColorScheme colorScheme,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(label,
                style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
          ),
        ),
        TextFormField(
          controller: controller,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLines: maxLines,
          textAlign: TextAlign.right,
          keyboardType: keyboardType,
          onChanged: onChanged,
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

  // تم إضافة BuildContext context كمعامل أول
  Widget _buildDateField(
    BuildContext context,
    BusinessController controller,
    ColorScheme colorScheme,
    StateSetter setStateBottomSheet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text("التاريخ",
              style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
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
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary),
                onPressed: () async {
                  DateTime? newDate = await showDatePicker(
                    context: context, // الآن context صحيح
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
                child: Text("اختر التاريخ",
                    style: TextStyle(color: colorScheme.onPrimary)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusField(
    BusinessController controller,
    ColorScheme colorScheme,
    StateSetter setStateBottomSheet,
  ) {
    List<String> statusItems = [
      'مكتمل',
      'قيد الانتظار',
      'جاري التنفيذ',
      'ملغي'
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text("الحالة",
                style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
          ),
        ),
        Directionality(
          textDirection: TextDirection.rtl,
          child: DropdownButtonFormField<String>(
            value: controller.selectedStatus ?? "قيد الانتظار",
            decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
            iconSize: 30,
            dropdownColor: colorScheme.surface,
            isExpanded: true,
            items: statusItems.map((String item) {
              return DropdownMenuItem<String>(
                alignment: Alignment.centerRight,
                value: item,
                child: Text(item,
                    textAlign: TextAlign.right,
                    style:
                        TextStyle(fontSize: 16, color: colorScheme.onSurface)),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setStateBottomSheet(() {
                controller.setStatus(newValue);
              });
            },
          ),
        ),
      ],
    );
  }

  // تم إضافة BuildContext context كمعامل أول
  Widget _buildCustomField(
    BuildContext context,
    Map<String, dynamic> field,
    BusinessController controller,
    StateSetter setStateBottomSheet,
    ColorScheme colorScheme,
  ) {
    String fieldName = field['fieldName'];
    String fieldType = field['fieldType'];
    bool isRequired = field['isRequired'] ?? false;

    switch (fieldType) {
      case 'نص':
        return _buildTextCustomField(
            fieldName, isRequired, controller, colorScheme);
      case 'رقم':
        return _buildNumberCustomField(
            fieldName, isRequired, controller, colorScheme);
      case 'تاريخ':
        return _buildDateCustomField(
            context, fieldName, isRequired, controller, setStateBottomSheet, colorScheme);
      case 'قائمة منسدلة':
        List<String> options = List<String>.from(field['options'] ?? []);
        return _buildDropdownCustomField(
            fieldName, options, isRequired, controller, setStateBottomSheet, colorScheme);
      default:
        return SizedBox.shrink();
    }
  }

  Widget _buildTextCustomField(
    String fieldName,
    bool isRequired,
    BusinessController controller,
    ColorScheme colorScheme,
  ) {
    if (!controller.textControllers.containsKey(fieldName)) {
      controller.textControllers[fieldName] = TextEditingController();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text("مطلوب",
                    style: TextStyle(color: colorScheme.error, fontSize: 12)),
              Flexible(
                child: Text(fieldName,
                    style:
                        TextStyle(fontSize: 17, color: colorScheme.onSurface),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: controller.textControllers[fieldName],
            textAlign: TextAlign.right,
            style: TextStyle(color: colorScheme.onSurface),
            onChanged: (value) {
              controller.setCustomFieldValue(fieldName, value);
            },
            validator: isRequired
                ? (value) =>
                    (value == null || value.isEmpty) ? 'هذا الحقل مطلوب' : null
                : null,
            decoration: InputDecoration(
              filled: true,
              hintText: "ادخل $fieldName",
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberCustomField(
    String fieldName,
    bool isRequired,
    BusinessController controller,
    ColorScheme colorScheme,
  ) {
    if (!controller.textControllers.containsKey(fieldName)) {
      controller.textControllers[fieldName] = TextEditingController();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text("مطلوب",
                    style: TextStyle(color: colorScheme.error, fontSize: 12)),
              Expanded(
                child: Text(fieldName,
                    style:
                        TextStyle(fontSize: 17, color: colorScheme.onSurface),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: controller.textControllers[fieldName],
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colorScheme.onSurface),
            onChanged: (value) {
              controller.setCustomFieldValue(
                  fieldName, double.tryParse(value) ?? 0);
            },
            validator: isRequired
                ? (value) {
                    if (value == null || value.isEmpty)
                      return 'هذا الحقل مطلوب';
                    if (double.tryParse(value) == null)
                      return 'يرجى إدخال رقم صحيح';
                    return null;
                  }
                : null,
            decoration: InputDecoration(
              filled: true,
              hintText: "ادخل $fieldName",
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
            ),
          ),
        ],
      ),
    );
  }

  // تم إضافة BuildContext context كمعامل أول
  Widget _buildDateCustomField(
    BuildContext context,
    String fieldName,
    bool isRequired,
    BusinessController controller,
    StateSetter setStateBottomSheet,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text("مطلوب",
                    style: TextStyle(color: colorScheme.error, fontSize: 12)),
              Expanded(
                child: Text(fieldName,
                    style:
                        TextStyle(fontSize: 17, color: colorScheme.onSurface),
                    textAlign: TextAlign.right),
              ),
            ],
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
                  "${controller.dateValues[fieldName]?.day ?? DateTime.now().day}-${controller.dateValues[fieldName]?.month ?? DateTime.now().month}-${controller.dateValues[fieldName]?.year ?? DateTime.now().year}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary),
                  onPressed: () async {
                    DateTime? newDate = await showDatePicker(
                      context: context, // الآن context صحيح
                      initialDate:
                          controller.dateValues[fieldName] ?? DateTime.now(),
                      firstDate: DateTime(1700),
                      lastDate: DateTime(2200),
                    );
                    if (newDate != null) {
                      setStateBottomSheet(() {
                        controller.dateValues[fieldName] = newDate;
                        controller.setCustomFieldValue(fieldName, newDate);
                      });
                    }
                  },
                  child: Text("اختر التاريخ",
                      style: TextStyle(color: colorScheme.onPrimary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownCustomField(
    String fieldName,
    List<String> options,
    bool isRequired,
    BusinessController controller,
    StateSetter setStateBottomSheet, // تأكد من وجود هذا المعامل
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text("مطلوب",
                    style: TextStyle(color: colorScheme.error, fontSize: 12)),
              Expanded(
                child: Text(fieldName,
                    style:
                        TextStyle(fontSize: 17, color: colorScheme.onSurface),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
          SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.rtl,
            child: DropdownButtonFormField<String>(
              value: controller.dropdownValues[fieldName] ??
                  (options.isNotEmpty ? options[0] : null),
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
              iconSize: 30,
              dropdownColor: colorScheme.surface,
              isExpanded: true,
              items: options.map((String option) {
                return DropdownMenuItem<String>(
                  alignment: Alignment.centerRight,
                  value: option,
                  child: Text(option,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 16, color: colorScheme.onSurface)),
                );
              }).toList(),
              onChanged: (String? newValue) {
                // استخدم setStateBottomSheet بدلاً من setState
                setStateBottomSheet(() {
                  controller.dropdownValues[fieldName] = newValue;
                  controller.setCustomFieldValue(fieldName, newValue);
                });
              },
              validator: isRequired
                  ? (value) => (value == null || value.isEmpty)
                      ? 'هذا الحقل مطلوب'
                      : null
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // ========== دوال التحقق ==========
  String? _validateBusinessName(String? value) {
    if (value == null || value.trim().isEmpty) return 'اسم العمل مطلوب';
    if (value.length < 3) return 'اسم العمل يجب أن يكون 3 أحرف على الأقل';
    if (value.length > 100) return 'اسم العمل طويل جداً';
    return null;
  }

  String? _validateBusinessDescription(String? value) {
    if (value == null || value.trim().isEmpty) return 'وصف العمل مطلوب';
    if (value.length > 500) return 'الوصف طويل جداً (الحد الأقصى 500 حرف)';
    return null;
  }

  String? _validateBusinessAmount(String? value) {
    if (value == null || value.trim().isEmpty) return 'المبلغ مطلوب';
    final double? amount = double.tryParse(value);
    if (amount == null) return 'يرجى إدخال رقم صحيح';
    if (amount <= 0) return 'المبلغ يجب أن يكون أكبر من 0';
    if (amount > 999999999) return 'المبلغ كبير جداً';
    return null;
  }
}