// lib/views/workers_view.dart
import 'package:fkra/controller/workers_controller.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/view/worker_details_view.dart';
import 'package:fkra/view/worker_reports_view.dart';
import 'package:fkra/view/widgets/delegated_accounts_dialog.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:provider/provider.dart';

class WorkersPage extends StatelessWidget {
  final String userId;
  const WorkersPage({super.key, required this.userId});

  bool _canCreateWorker() =>
      MemberSessionService.instance.canCreate(TeamPermissions.workers);
  bool _canUpdateWorker() =>
      MemberSessionService.instance.canUpdate(TeamPermissions.workers);
  bool _canDeleteWorker() =>
      MemberSessionService.instance.canDelete(TeamPermissions.workers);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WorkersController(userId: userId),
      child: Consumer<WorkersController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;
          final filtered = controller.filteredWorkers;

          if (controller.isLoading) {
            return Scaffold(
              appBar: AppBar(
                title: Text("تسهيل", style: TextStyle(color: colorScheme.primary)),
                centerTitle: true,
                backgroundColor: colorScheme.surface,
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    SizedBox(height: 16),
                    Text('جاري تحميل العمال...',
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
                      message: 'وضع غير متصل - سيتم حفظ البيانات محلياً',
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
                if (controller.isOffline)
                  Container(
                    margin: EdgeInsets.all(10),
                    padding: EdgeInsets.all(12),
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
                            'وضع غير متصل - سيتم حفظ العمال محلياً ومزامنتهم تلقائياً عند عودة الاتصال',
                            style: TextStyle(color: Colors.orange[700], fontSize: 12),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_canCreateWorker())
                        ElevatedButton.icon(
                        onPressed: () {
                          controller.resetForm();
                          _showAddEditWorkerBottomSheet(context, controller, colorScheme);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text("اضافة عامل"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                      ),
                      Text(
                        "العمال",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WorkerReportsView(
                            workers: controller.workers,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.table_view, size: 18),
                    label: const Text(
                      'تقارير العمال',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextFormField(
                    controller: controller.searchController,
                    textAlign: TextAlign.right,
                    onChanged: (value) => controller.updateSearch(value),
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      suffixIcon: Icon(Icons.search, color: colorScheme.primary),
                      hintText: "البحث باسم العامل",
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
                const SizedBox(height: 15),
                if (controller.workers.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'إجمالي العمال: ${filtered.length}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (controller.workers.any((e) => e['synced'] == 0))
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '⚠️ يوجد عمال غير متزامنين',
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
                              Icon(Icons.people, size: 64, color: colorScheme.onSurfaceVariant),
                              SizedBox(height: 16),
                              Text(
                                controller.searchController.text.isNotEmpty
                                    ? 'لا توجد نتائج للبحث عن "${controller.searchController.text}"'
                                    : 'لا يوجد عمال\nاضغط على زر "اضافة عامل" لإضافة أول عامل',
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
                          padding: const EdgeInsets.all(10),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final worker = filtered[index];
                            return _buildWorkerCard(
                              worker,
                              controller,
                              colorScheme,
                              context,
                            );
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

  // ========== حوار مشاركة عامل واحد ==========
  Future<void> _showShareWorkerDialog(
    BuildContext context,
    WorkersController controller,
    Map<String, dynamic> worker,
  ) async {
    final result = await showDialog<({bool ok, String message})>(
      context: context,
      builder: (_) => _ShareWorkerDialog(
        controller: controller,
        worker: worker,
      ),
    );
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            result.ok ? null : Theme.of(context).colorScheme.error,
        content: Text(result.message),
      ),
    );
  }

  // ========== بطاقة العامل ==========
  Widget _buildWorkerCard(
    Map<String, dynamic> worker,
    WorkersController controller,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    String name = worker['name'] ?? 'بدون اسم';
    String phone = worker['phone'] ?? 'بدون رقم';
    String specialization = worker['specialization'] ?? 'بدون تخصص';
    String salary = worker['salary']?.toString() ?? '0';
    String wageType = worker['wageType'] ?? 'monthly';
    String wageLabel = controller.wageTypeLabel(wageType);
    bool isSynced = worker['synced'] == 1;
    String displayDate = '';
    try {
      DateTime workerDate = DateTime.parse(worker['date']);
      displayDate = '${workerDate.year}-${workerDate.month}-${workerDate.day}';
    } catch (_) {
      displayDate = 'تاريخ غير محدد';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorkerDetailsView(
                controller: controller,
                workerId: worker['id'].toString(),
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
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
                    // مشاركة عامل واحد: للمالك فقط (لا تظهر لمستخدم مفوَّض).
                    if (MemberSessionService.instance
                        .isActiveOwnerOf(userId))
                      IconButton(
                        onPressed: () =>
                            _showShareWorkerDialog(context, controller, worker),
                        icon: Icon(Icons.ios_share, color: colorScheme.primary),
                        tooltip: 'مشاركة العامل',
                      ),
                    if (_canUpdateWorker())
                      IconButton(
                        onPressed: () {
                          controller.loadWorkerForEditing(worker);
                          _showAddEditWorkerBottomSheet(context, controller, colorScheme);
                        },
                        icon: Icon(Icons.edit, color: colorScheme.primary),
                        tooltip: 'تعديل العامل',
                      ),
                    if (_canDeleteWorker())
                      IconButton(
                        onPressed: () => _confirmDelete(context, worker['id'], name, controller),
                        icon: Icon(Icons.delete, color: colorScheme.error),
                        tooltip: 'حذف العامل',
                      ),
                  ],
                ),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.person, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Divider(color: colorScheme.outline),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.phone, phone, color: colorScheme.primary, colorScheme: colorScheme),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.attach_money, "$salary ريال/$wageLabel", color: Colors.green, colorScheme: colorScheme),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.hotel_class, specialization, color: Colors.deepOrange, colorScheme: colorScheme),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.punch_clock, displayDate, color: Colors.indigo, colorScheme: colorScheme),
            const SizedBox(height: 10),
            if ((worker['createdByLabel'] ?? '').toString().isNotEmpty)
              _buildInfoRow(
                Icons.person_add_alt_1,
                'أضيف بواسطة: ${worker['createdByLabel']}',
                color: colorScheme.primary,
                colorScheme: colorScheme,
              ),
            if ((worker['lastModifiedByLabel'] ?? '').toString().isNotEmpty)
              _buildInfoRow(
                Icons.edit,
                'آخر تعديل: ${worker['lastModifiedByLabel']}',
                color: Colors.orange,
                colorScheme: colorScheme,
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text,
      {Color? color, required ColorScheme colorScheme}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: color ?? colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: color ?? colorScheme.primary),
        ],
      ),
    );
  }

  // ========== نافذة إضافة/تعديل عامل ==========
  void _showAddEditWorkerBottomSheet(
    BuildContext context,
    WorkersController controller,
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
                padding: const EdgeInsets.all(15),
width: double.infinity,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom),
                    child: Column(
                    children: [
                      Text(
                        controller.isEditing ? "تعديل عامل" : "إضافة عامل",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (controller.isOffline)
                        Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  controller.isEditing
                                      ? 'سيتم تعديل العامل محلياً لعدم وجود اتصال'
                                      : 'سيتم حفظ العامل محلياً لعدم وجود اتصال',
                                  style: TextStyle(color: Colors.orange[700], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 30),
                      _buildTextField(
                        "اسم العامل",
                        "ادخل اسم العامل",
                        controller.nameController,
                        (value) => _validateName(value),
                        colorScheme,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        "رقم الهاتف",
                        "ادخل رقم الهاتف",
                        controller.phoneController,
                        (value) => _validatePhone(value),
                        colorScheme,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        "التخصص",
                        "مثال: كهربائي أو سباك",
                        controller.specializationController,
                        (value) => _validateSpecialization(value),
                        colorScheme,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text("الراتب",
                                      style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
                                ),
                                SizedBox(height: 8),
                                TextFormField(
                                  controller: controller.salaryController,
                                  validator: (value) => _validateSalary(value),
                                  autovalidateMode: AutovalidateMode.onUserInteraction,
                                  textAlign: TextAlign.right,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(color: colorScheme.onSurface),
                                  decoration: InputDecoration(
                                    filled: true,
                                    hintText: "0.0",
                                    hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                                    fillColor: colorScheme.surface,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: colorScheme.outline)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: colorScheme.outline)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: colorScheme.primary, width: 2)),
                                    errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: colorScheme.error)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text("طريقة الأجر",
                                      style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
                                ),
                                SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: controller.wageType,
                                  items: [
                                    DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                                    DropdownMenuItem(value: 'weekly', child: Text('أسبوعي')),
                                    DropdownMenuItem(value: 'daily', child: Text('يومي')),
                                    DropdownMenuItem(value: 'halfDay', child: Text('نصف يوم')),
                                    DropdownMenuItem(value: 'hourly', child: Text('بالساعة')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setStateBottomSheet(() => controller.setWageType(val));
                                    }
                                  },
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: colorScheme.surface,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: colorScheme.outline)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: colorScheme.outline)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: colorScheme.primary, width: 2)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      _buildDateField(context, controller, colorScheme, setStateBottomSheet),
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
                              backgroundColor: colorScheme.error,
                            ),
                            child: Text("الغاء", style: TextStyle(color: colorScheme.onError)),
                          ),
                          const SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              if (controller.isEditing) {
                                final bool ok =
                                    await controller.editWorker(context);
                                if (ok && context.mounted) {
                                  Navigator.pop(context);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(controller.isOffline
                                          ? 'تم تعديل العامل محلياً وسيتم مزامنته تلقائياً عند عودة الاتصال'
                                          : 'تم تعديل العامل بنجاح'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } else {
                                final bool ok =
                                    await controller.addWorker(context);
                                if (ok && context.mounted) {
                                  Navigator.pop(context);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(controller.isOffline
                                          ? 'تم حفظ العامل محلياً وسيتم مزامنته تلقائياً عند عودة الاتصال'
                                          : 'تم إضافة العامل بنجاح'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                            ),
                            child: Text(
                              controller.isEditing ? "تحديث" : "حفظ",
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
          child: Text(label,
              style: TextStyle(fontSize: 17, color: colorScheme.onSurface)),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textAlign: TextAlign.right,
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

  Widget _buildDateField(
    BuildContext context,
    WorkersController controller,
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
                child: Text("اختر التاريخ",
                    style: TextStyle(color: colorScheme.onPrimary)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========== تأكيد الحذف ==========
  void _confirmDelete(BuildContext context, String id, String name, WorkersController controller) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل أنت متأكد من حذف العامل "$name"؟',
      btnOkText: 'حذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        await controller.deleteWorker(id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("تم حذف العامل بنجاح"),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
    ).show();
  }

  // ========== دوال التحقق ==========
  String? _validateName(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال اسم العامل';
    if (value.length < 3) return 'الاسم يجب أن يكون على الأقل 3 أحرف';
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال رقم الهاتف';
    if (!RegExp(r'^\d{9}$').hasMatch(value)) {
      return 'الرجاء إدخال رقم هاتف صالح (9 أرقام)';
    }
    return null;
  }

  String? _validateSpecialization(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال تخصص العامل';
    if (value.length < 3) return 'التخصص يجب أن يكون على الأقل 3 أحرف';
    return null;
  }

  String? _validateSalary(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال راتب العامل';
    if (double.tryParse(value) == null) return 'الرجاء إدخال رقم صالح للراتب';
    return null;
  }
}

// حوار مشاركة عامل واحد. الحالة تملك المتحكمات وترتيبها فيدمر عند إزالة
// الحوار نهائياً من الشجرة (بعد انتهاء حركة الخروج) — لا تتحرر مبكراً فتُقرأ
// حقول النموذج أثناء إغلاق الحوار وتتسبب في "controller used after disposed".
class _ShareWorkerDialog extends StatefulWidget {
  final WorkersController controller;
  final Map<String, dynamic> worker;

  const _ShareWorkerDialog({required this.controller, required this.worker});

  @override
  State<_ShareWorkerDialog> createState() => _ShareWorkerDialogState();
}

class _ShareWorkerDialogState extends State<_ShareWorkerDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSharing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSharing = true);
    ({bool ok, String message}) result;
    try {
      final message = await widget.controller.shareWorker(
        widget.worker['id'].toString(),
        _nameController.text.trim(),
        _emailController.text.trim(),
      );
      result = (ok: true, message: message);
    } catch (e) {
      result = (ok: false, message: e.toString());
    }
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('مشاركة العامل'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'شارك هذا العامل مع مستخدم تابع: يحصل على عرض وتعديل '
                  'على هذا العامل فقط (لا يرى باقي عمالك).',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'الاسم',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 3) {
                      return 'أدخل اسم المستخدم (3 أحرف على الأقل)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$')
                        .hasMatch(value)) {
                      return 'أدخل بريداً إلكترونياً صحيحاً';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _isSharing
                ? null
                : () {
                    // إخفاء لوحة المفاتيح قبل انتظار الشبكة كي لا يتهاتف إغلاق
                    // لوحة المفاتيح مع حوار الإغلاق (واقي من خطأ Flutter المعروف).
                    FocusScope.of(context).unfocus();
                    _submit();
                  },
            child: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('مشاركة'),
          ),
        ],
      ),
    );
  }
}