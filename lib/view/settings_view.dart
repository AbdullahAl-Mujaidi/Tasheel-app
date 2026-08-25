// lib/views/settings_view.dart
import 'package:fkra/controller/settings_controller.dart';
import 'package:fkra/view/login_view.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  final String userId;
  const SettingsPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsController(userId: userId),
      child: Consumer<SettingsController>(
        builder: (context, controller, child) {
          final colorScheme = Theme.of(context).colorScheme;

          if (controller.isLoading) {
            return Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
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
                      color: controller.isOffline
                          ? Colors.grey
                          : colorScheme.primary),
                  tooltip: 'مزامنة مع السحاب',
                ),
                if (controller.isOffline)
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Tooltip(
                      message: 'وضع غير متصل - سيتم حفظ التغييرات محلياً',
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
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
            body: SingleChildScrollView(
              child: Column(
                children: [
                  if (controller.isOffline)
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'وضع غير متصل. سيتم حفظ التغييرات محلياً ومزامنتها تلقائياً عند عودة الاتصال. (تغيير كلمة المرور يتطلب اتصال بالإنترنت)',
                              style: TextStyle(color: Colors.orange[700], fontSize: 12),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    margin: EdgeInsets.all(15),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "الاعدادات",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  _buildProfileCard(controller, colorScheme),
                  SizedBox(height: 40),
                  _buildSettingsSection("اعدادات الحساب", colorScheme),
                  _buildSettingsCard(
                    icon: Icons.person,
                    title: "تعديل الملف الشخصي",
                    onTap: () => _showEditProfileBottomSheet(context, controller, colorScheme),
                    colorScheme: colorScheme,
                  ),
                  _buildSettingsCard(
                    icon: Icons.lock,
                    title: "تغيير كلمة السر",
                    onTap: () => _showChangePasswordBottomSheet(context, controller, colorScheme),
                    colorScheme: colorScheme,
                  ),
                  _buildCustomFieldsHeader(context, controller, colorScheme),
                  _buildCustomFieldsList(controller, colorScheme, context),
                  _buildDangerZone(context, controller, colorScheme),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ========== بطاقة الملف الشخصي ==========
  Widget _buildProfileCard(SettingsController controller, ColorScheme colorScheme) {
    return Container(
      width: 350,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.primary,
      ),
      child: Column(
        children: [
          CircleAvatar(
            maxRadius: 30,
            backgroundColor: colorScheme.primary.withOpacity(0.3),
            child: Text(
              controller.name.isNotEmpty ? controller.name[0].toUpperCase() : '',
              style: TextStyle(color: colorScheme.onPrimary, fontSize: 25),
            ),
          ),
          SizedBox(height: 7),
          Text(controller.name,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.onPrimary)),
          SizedBox(height: 7),
          Text(controller.businessName,
              style: TextStyle(color: colorScheme.onPrimary, fontSize: 19)),
          SizedBox(height: 7),
          Text(controller.phone,
              style: TextStyle(color: colorScheme.onPrimary, fontSize: 19)),
          SizedBox(height: 7),
          Text(controller.email,
              style: TextStyle(color: colorScheme.onPrimary, fontSize: 19)),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, ColorScheme colorScheme) {
    return Container(
      margin: EdgeInsets.all(10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
      child: Card(
        color: colorScheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          onTap: onTap,
          title: Text(title,
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              textAlign: TextAlign.right),
          leading: Icon(icon, size: 30, color: colorScheme.primary),
          trailing: Icon(Icons.arrow_back_ios, size: 16, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  // ========== نافذة تعديل الملف الشخصي ==========
  void _showEditProfileBottomSheet(
    BuildContext context,
    SettingsController controller,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      isScrollControlled: true,
      showDragHandle: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return Container(
          width: double.infinity,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              top: 20,
              left: 10,
              right: 10,
            ),
            child: Form(
              key: controller.formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("تعديل الملف الشخصي",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                  if (controller.isOffline)
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('⚠️ وضع غير متصل - سيتم حفظ التغييرات محلياً',
                          style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ),
                  SizedBox(height: 10),
                  _buildFormField(label: "الاسم الكامل", controller: controller.nameController,
                      validator: (value) => _validateFullName(value), icon: Icons.person, colorScheme: colorScheme),
                  _buildFormField(label: "اسم النشاط التجاري", controller: controller.businessNameController,
                      validator: (value) => _validateBusinessName(value), icon: Icons.apartment, colorScheme: colorScheme),
                  _buildFormField(label: "البريد الالكتروني", controller: controller.emailController,
                      validator: (value) => _validateEmail(value), icon: Icons.email, colorScheme: colorScheme),
                  _buildFormField(label: "رقم الهاتف", controller: controller.phoneController,
                      validator: (value) => _validatePhone(value), icon: Icons.phone, colorScheme: colorScheme),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.error,
                            foregroundColor: colorScheme.onError,
                            minimumSize: Size(100, 40)),
                        onPressed: () => Navigator.pop(context),
                        child: Text("الغاء"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            minimumSize: Size(100, 40)),
                        onPressed: () async {
                          try {
                            await controller.updateUserInfo();
                            if (context.mounted) Navigator.pop(context);
                            AwesomeDialog(
                              context: context,
                              dialogType: controller.isOffline ? DialogType.info : DialogType.success,
                              title: controller.isOffline ? 'تم الحفظ محلياً' : 'تم التحديث',
                              desc: controller.isOffline
                                  ? 'تم حفظ التغييرات محلياً وسيتم مزامنتها عند عودة الاتصال.'
                                  : 'تم تحديث البيانات بنجاح',
                              btnOkText: 'حسناً',
                            ).show();
                          } catch (e) {
                            AwesomeDialog(
                              context: context,
                              dialogType: DialogType.error,
                              title: 'خطأ',
                              desc: 'حدث خطأ: $e',
                              btnOkText: 'حسناً',
                            ).show();
                          }
                        },
                        child: Text(controller.isOffline ? "حفظ محلياً" : "حفظ"),
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
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.only(right: 20, left: 15, top: 10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          ),
        ),
        Container(
          margin: EdgeInsets.all(15),
          child: TextFormField(
            validator: validator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: controller,
            cursorColor: colorScheme.primary,
            textAlign: TextAlign.right,
            style: TextStyle(color: colorScheme.onSurface),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
              suffixIcon: Icon(icon, color: colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  // ========== نافذة تغيير كلمة المرور ==========
  void _showChangePasswordBottomSheet(
    BuildContext context,
    SettingsController controller,
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
            bool isPasswordVisible = false;
            bool isConfirmPasswordVisible = false;

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 20,
                left: 10,
                right: 10,
              ),
              child: Container(
                margin: EdgeInsets.all(15),
                width: double.infinity,
                child: Form(
                  key: controller.formKeyPassword,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("تغيير كلمة السر",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                      if (controller.isOffline)
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('⚠️ يتطلب تغيير كلمة المرور اتصال بالإنترنت',
                              style: TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      SizedBox(height: 20),
                      _buildPasswordField(
                        label: "كلمة السر",
                        controller: controller.newPasswordController,
                        validator: (value) => _validatePassword(value),
                        obscureText: !isPasswordVisible,
                        onToggle: () => setStateBottomSheet(() => isPasswordVisible = !isPasswordVisible),
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      _buildPasswordField(
                        label: "تأكيد كلمة السر",
                        controller: controller.confirmPasswordController,
                        validator: (value) => _validateConfirmPassword(value, controller.newPasswordController.text),
                        obscureText: !isConfirmPasswordVisible,
                        onToggle: () => setStateBottomSheet(() => isConfirmPasswordVisible = !isConfirmPasswordVisible),
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                                minimumSize: Size(100, 40)),
                            onPressed: () => Navigator.pop(context),
                            child: Text("الغاء"),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: controller.isOffline ? Colors.grey : colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                minimumSize: Size(100, 40)),
                            onPressed: controller.isOffline
                                ? null
                                : () async {
                                    try {
                                      await controller.changePassword();
                                      if (context.mounted) Navigator.pop(context);
                                      AwesomeDialog(
                                        context: context,
                                        dialogType: DialogType.success,
                                        title: 'تم التحديث',
                                        desc: 'تم تغيير كلمة المرور بنجاح',
                                        btnOkText: 'حسناً',
                                      ).show();
                                      controller.newPasswordController.clear();
                                      controller.confirmPasswordController.clear();
                                    } catch (e) {
                                      AwesomeDialog(
                                        context: context,
                                        dialogType: DialogType.error,
                                        title: 'خطأ',
                                        desc: 'حدث خطأ: $e',
                                        btnOkText: 'حسناً',
                                      ).show();
                                    }
                                  },
                            child: Text("حفظ"),
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

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required bool obscureText,
    required VoidCallback onToggle,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(label,
              style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ),
        SizedBox(height: 10),
        TextFormField(
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          controller: controller,
          textAlign: TextAlign.right,
          obscureText: obscureText,
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: label == "كلمة السر" ? '6 احرف على الأقل، مع حرف كبير ورقم' : 'اعد كتابة كلمة السر للتأكيد',
            filled: true,
            fillColor: colorScheme.surface,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.outline), borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(10)),
            suffixIcon: InkWell(
              onTap: onToggle,
              child: Icon(obscureText ? Icons.visibility_off : Icons.visibility,
                  color: colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  // ========== الحقول المخصصة ==========
  Widget _buildCustomFieldsHeader(BuildContext context,SettingsController controller, ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.only(right: 15, left: 15, top: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: controller.isOffline
                    ? null
                    : () => _showAddEditCustomFieldBottomSheet(context, controller, colorScheme),
                child: Icon(Icons.add, color: colorScheme.onPrimary, size: 18),
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.isOffline ? Colors.grey : colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              Text("حقول مخصصة للأعمال",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface)),
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.only(right: 18),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text("حقول اضافية تظهر في نموذج انشاء الاعمال",
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }

  void _showAddEditCustomFieldBottomSheet(
    BuildContext context,
    SettingsController controller,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateBottomSheet) {
            return Form(
              key: controller.formKeyProfile,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(15),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.isEditingField ? "تعديل حقل" : "إضافة حقل جديد",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      SizedBox(height: 20),
                      _buildFormField(
                        label: "اسم الحقل",
                        controller: controller.newFieldNameController,
                        validator: (value) => _validateNewFieldName(value),
                        icon: Icons.text_fields,
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("نوع الحقل",
                            style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(height: 10),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: DropdownButtonFormField<String>(
                          value: controller.selectedFieldType,
                          decoration: InputDecoration(
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                                borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: colorScheme.outline),
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: colorScheme.surface,
                            prefixIcon: Icon(Icons.question_mark, color: colorScheme.primary),
                          ),
                          items: controller.fieldTypes.map((String item) {
                            return DropdownMenuItem<String>(
                                alignment: Alignment.centerRight,
                                value: item,
                                child: Text(item, style: TextStyle(color: colorScheme.onSurface)));
                          }).toList(),
                          onChanged: (String? newValue) {
                            setStateBottomSheet(() {
                              controller.setSelectedFieldType(newValue);
                            });
                          },
                        ),
                      ),
                      if (controller.selectedFieldType == 'قائمة منسدلة') ...[
                        SizedBox(height: 20),
                        _buildInfoCard(Icons.menu, "قائمة اختيار", "اختيار من قائمة خيارات محددة مسبقاً", colorScheme),
                        SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text("خيارات القائمة",
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        ),
                        SizedBox(height: 10),
                        ...controller.newFieldOptions.asMap().entries.map((entry) {
                          int index = entry.key;
                          String option = entry.value;
                          return Card(
                            color: colorScheme.surface,
                            child: ListTile(
                              leading: IconButton(
                                  onPressed: () {
                                    setStateBottomSheet(() {
                                      controller.removeOptionFromList(index);
                                    });
                                  },
                                  icon: Icon(Icons.delete, color: colorScheme.error)),
                              title: Text(option, style: TextStyle(color: colorScheme.onSurface), textAlign: TextAlign.right),
                              trailing: Text("${index + 1}", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                            ),
                          );
                        }),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: controller.optionInputController,
                                textAlign: TextAlign.right,
                                style: TextStyle(color: colorScheme.onSurface),
                                decoration: InputDecoration(
                                    hintText: 'أدخل خيار جديد',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                              ),
                            ),
                            SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                setStateBottomSheet(() {
                                  controller.addOptionToList();
                                });
                              },
                              child: Icon(Icons.add),
                              style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary),
                            ),
                          ],
                        ),
                      ],
                      if (controller.selectedFieldType == 'نص') ...[
                        SizedBox(height: 20),
                        _buildInfoCard(Icons.text_fields, "حقل نصي", "حقل لإدخال نصوص حرة", colorScheme),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: controller.textInputController,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'قيمة افتراضية (اختياري)',
                            filled: true,
                            fillColor: colorScheme.surface,
                            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                      if (controller.selectedFieldType == 'رقم') ...[
                        SizedBox(height: 20),
                        _buildInfoCard(Icons.numbers, "حقل رقمي", "حقل لإدخال أرقام فقط", colorScheme),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: controller.numberOptionController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'قيمة افتراضية (اختياري)',
                            filled: true,
                            fillColor: colorScheme.surface,
                            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("حقل مطلوب", style: TextStyle(color: colorScheme.onSurface)),
                          Switch(
                            value: controller.isRequired,
                            onChanged: (value) {
                              setStateBottomSheet(() {
                                controller.toggleRequired(value);
                              });
                            },
                            activeColor: colorScheme.primary,
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                                minimumSize: Size(100, 40)),
                            onPressed: () {
                              controller.resetFieldForm();
                              Navigator.pop(context);
                            },
                            child: Text("الغاء"),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                minimumSize: Size(100, 40)),
                            onPressed: () async {
                              try {
                                await controller.addOrUpdateCustomField();
                                if (context.mounted) Navigator.pop(context);
                                AwesomeDialog(
                                  context: context,
                                  dialogType: DialogType.success,
                                  title: controller.isEditingField ? 'تم التعديل' : 'تم الإضافة',
                                  desc: controller.isEditingField
                                      ? 'تم تعديل الحقل بنجاح'
                                      : 'تم إضافة الحقل بنجاح',
                                  btnOkText: 'حسناً',
                                ).show();
                              } catch (e) {
                                AwesomeDialog(
                                  context: context,
                                  dialogType: DialogType.error,
                                  title: 'خطأ',
                                  desc: 'حدث خطأ: $e',
                                  btnOkText: 'حسناً',
                                ).show();
                              }
                            },
                            child: Text(controller.isEditingField ? "تحديث" : "حفظ"),
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

  Widget _buildInfoCard(IconData icon, String title, String subtitle, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.primary.withOpacity(0.1),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFieldsList(
    SettingsController controller,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    return Container(
      margin: EdgeInsets.all(15),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.surface,
        boxShadow: [BoxShadow(color: colorScheme.shadow.withOpacity(0.1), spreadRadius: 2, offset: Offset(0, 3))],
      ),
      child: controller.customFieldsList.isEmpty && !controller.isOffline
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text("لا توجد حقول مخصصة حتى الآن\nاضغط على زر + لإضافة حقل جديد",
                    textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ),
            )
          : controller.customFieldsList.isEmpty && controller.isOffline
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("لا توجد حقول مخصصة\nيتطلب إضافة الحقول اتصال بالإنترنت",
                        textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ),
                )
              : Column(
                  children: controller.customFieldsList.map((field) {
                    return Container(
                      margin: EdgeInsets.only(bottom: 15),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => _showDeleteDialog(context, field['id'], field['fieldName'], controller, colorScheme),
                                    icon: Icon(Icons.delete, color: colorScheme.error),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      controller.loadFieldForEditing(field);
                                      _showAddEditCustomFieldBottomSheet(context, controller, colorScheme);
                                    },
                                    icon: Icon(Icons.edit, color: colorScheme.primary),
                                    tooltip: 'تعديل الحقل',
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  if (field['isRequired'] == true)
                                    Container(
                                      padding: EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          color: colorScheme.error.withOpacity(0.1)),
                                      child: Text("مطلوب",
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.error)),
                                    ),
                                  SizedBox(width: 10),
                                  Container(
                                    padding: EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: colorScheme.primary.withOpacity(0.1)),
                                    child: Row(
                                      children: [
                                        Text(_getFieldTypeName(field['fieldType']),
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                        SizedBox(width: 5),
                                        Icon(_getFieldTypeIcon(field['fieldType']), size: 20, color: colorScheme.primary),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(field['fieldName'] ?? 'بدون اسم',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                          ),
                          if (field['fieldType'] == 'قائمة منسدلة' && field['options'] != null &&
                              (field['options'] as List).isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 8, right: 8),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: (field['options'] as List).map((option) {
                                    return Chip(
                                      label: Text(option.toString()),
                                      backgroundColor: colorScheme.surfaceContainerHighest,
                                      labelStyle: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          Divider(height: 20, thickness: 1, color: colorScheme.outline),
                        ],
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    String fieldId,
    String fieldName,
    SettingsController controller,
    ColorScheme colorScheme,
  ) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      title: 'حذف الحقل',
      desc: 'هل أنت متأكد من حذف الحقل "$fieldName"؟',
      btnOkText: 'نعم، احذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        try {
          await controller.deleteCustomField(fieldId);
          AwesomeDialog(
            context: context,
            dialogType: DialogType.success,
            title: 'تم الحذف',
            desc: 'تم حذف الحقل بنجاح',
            btnOkText: 'حسناً',
          ).show();
        } catch (e) {
          AwesomeDialog(
            context: context,
            dialogType: DialogType.error,
            title: 'خطأ',
            desc: 'حدث خطأ أثناء الحذف: $e',
            btnOkText: 'حسناً',
          ).show();
        }
      },
    ).show();
  }

  // ========== منطقة الخطر ==========
  Widget _buildDangerZone(
    BuildContext context,
    SettingsController controller,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text("منطقة الخطر",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.error)),
          ),
        ),
        Container(padding: EdgeInsets.only(left: 15, right: 15), child: Divider(color: colorScheme.outline)),
        Container(
          margin: EdgeInsets.only(right: 15, left: 15, top: 15),
          child: TextButton(
            onPressed: () => _confirmLogout(context, controller, colorScheme),
            child: Row(
              children: [
                Spacer(),
                Text("تسجيل الخروج",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.error)),
                SizedBox(width: 10),
                Icon(Icons.logout, color: colorScheme.error),
                Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _confirmLogout(BuildContext context, SettingsController controller, ColorScheme colorScheme) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      title: 'تسجيل الخروج',
      desc: 'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
      btnOkText: 'نعم',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        try {
          await controller.logout();
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => LoginScreen()),
              (route) => false,
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('حدث خطأ أثناء تسجيل الخروج: $e'), backgroundColor: colorScheme.error),
          );
        }
      },
    ).show();
  }

  // ========== دوال التحقق ==========
  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال الاسم الكامل';
    if (value.length < 3) return 'الاسم يجب أن يكون 3 أحرف على الأقل';
    if (value.length > 50) return 'الاسم طويل جداً';
    return null;
  }

  String? _validateBusinessName(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال اسم النشاط التجاري';
    if (value.length < 3) return 'اسم النشاط يجب أن يكون 3 أحرف على الأقل';
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال رقم الهاتف';
    String phone = value.replaceAll(RegExp(r'[\s\-]'), '');
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) return 'رقم الهاتف يجب أن يحتوي على أرقام فقط';
    if (phone.length < 9 || phone.length > 12) return 'رقم الهاتف غير صحيح (يجب أن يكون 9-12 رقم)';
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال البريد الإلكتروني';
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(emailPattern);
    if (!regex.hasMatch(value)) return 'البريد الإلكتروني غير صحيح (example@domain.com)';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال كلمة المرور';
    if (value.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'كلمة المرور يجب أن تحتوي على حرف كبير واحد على الأقل';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'كلمة المرور يجب أن تحتوي على رقم واحد على الأقل';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'كلمة المرور يجب أن تحتوي على حرف صغير واحد على الأقل';
    return null;
  }

  String? _validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'يرجى تأكيد كلمة المرور';
    if (value != password) return 'كلمة المرور غير متطابقة';
    return null;
  }

  String? _validateNewFieldName(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال اسم الحقل';
    if (value.length < 3) return 'اسم الحقل يجب أن يكون 3 أحرف على الأقل';
    return null;
  }

  String _getFieldTypeName(String? type) {
    switch (type) {
      case 'نص': return 'حقل نصي';
      case 'رقم': return 'حقل رقمي';
      case 'تاريخ': return 'حقل تاريخ';
      case 'قائمة منسدلة': return 'قائمة اختيار';
      default: return 'نص';
    }
  }

  IconData _getFieldTypeIcon(String? type) {
    switch (type) {
      case 'نص': return Icons.text_fields;
      case 'رقم': return Icons.numbers;
      case 'تاريخ': return Icons.calendar_today;
      case 'قائمة منسدلة': return Icons.menu;
      default: return Icons.text_fields;
    }
  }
}