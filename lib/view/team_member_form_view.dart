// lib/view/team_member_form_view.dart
// نموذج إنشاء/تعديل مستخدم تابع: الاسم والبريد وكلمة المرور المؤقتة + الصلاحيات.
import 'package:fkra/controller/team_members_controller.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:flutter/material.dart';

class TeamMemberFormScreen extends StatefulWidget {
  final TeamMembersController controller;
  final TeamMember? member;
  const TeamMemberFormScreen({super.key, required this.controller, this.member});

  @override
  State<TeamMemberFormScreen> createState() => _TeamMemberFormScreenState();
}

class _TeamMemberFormScreenState extends State<TeamMemberFormScreen> {
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.member != null) {
      widget.controller.startEdit(widget.member!);
    } else {
      widget.controller.startCreate();
    }
  }

  Future<void> _save() async {
    final success = widget.member != null
        ? await widget.controller.updateMember()
        : await widget.controller.createMember();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.error ?? 'حدث خطأ')),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.member != null ? 'تعديل مستخدم' : 'مستخدم جديد'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: true,
      ),
      body: Form(
        key: c.formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: c.nameController,
              decoration: const InputDecoration(
                labelText: 'اسم المستخدم',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              validator: c.validateName,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: c.emailController,
              enabled: widget.member == null,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              validator: c.validateEmail,
            ),
            if (widget.member == null) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: c.passwordController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور المؤقتة',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: c.validatePassword,
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() {
                      c.passwordController.text =
                          TeamMembersController.generateTemporaryPassword();
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('توليد كلمة مرور'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _obscure = !_obscure;
                    }),
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    label: Text(_obscure ? 'إظهار' : 'إخفاء'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'الصلاحيات',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: c,
              builder: (context, _) => Column(
                children: [
                  for (final module in TeamPermissions.modules)
                    _PermissionSection(
                      module: module,
                      permissions: c.selectedPermissions[module] ?? {},
                      onChanged: c.setPermission,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: c.isActing ? null : _save,
              icon: c.isActing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(widget.member != null ? 'حفظ التعديلات' : 'إنشاء المستخدم'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionSection extends StatelessWidget {
  final String module;
  final Map<String, bool> permissions;
  final void Function(String module, String action, bool value) onChanged;

  const _PermissionSection({
    required this.module,
    required this.permissions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isReadOnly =
        module == TeamPermissions.reports || module == TeamPermissions.settings;
    final actions = isReadOnly
        ? const ['read']
        : TeamPermissions.actions;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TeamMembersController.moduleLabel(module),
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final action in actions)
                  FilterChip(
                    label: Text(TeamMembersController.actionLabel(action)),
                    selected: permissions[action] == true,
                    onSelected: (v) => onChanged(module, action, v),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}