// lib/view/change_temporary_password_view.dart
// شاشة إجبارية تظهر عند أول دخول للمستخدم التابع بكلمة مرور مؤقتة:
// تغيير كلمة المرور (Auth) + إسقاط mustChangePassword (Firestore).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/home_page.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:flutter/material.dart';

class ChangeTemporaryPasswordPage extends StatefulWidget {
  final String ownerUid;
  const ChangeTemporaryPasswordPage({super.key, required this.ownerUid});

  @override
  State<ChangeTemporaryPasswordPage> createState() =>
      _ChangeTemporaryPasswordPageState();
}

class _ChangeTemporaryPasswordPageState extends State<ChangeTemporaryPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _saving = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'أدخل كلمة المرور';
    if (value.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'يجب أن تحتوي على حرف كبير';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'يجب أن تحتوي على حرف صغير';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'يجب أن تحتوي على رقم';
    if (value != _confirm.text) return 'كلمتا المرور غير متطابقتين';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('نفدت الجلسة، سجّل الدخول مجدداً');
      return;
    }

    try {
      await user.updatePassword(_newPassword.text.trim());
    } on FirebaseAuthException catch (e) {
      setState(() => _saving = false);
      if (e.code == 'requires-recent-login') {
        _toast('يرجى تسجيل الدخول من جديد ليتم تغيير كلمة المرور');
      } else {
        _toast('فشل تغيير كلمة المرور: ${e.message ?? 'حاول مرة أخرى'}');
      }
      return;
    } catch (_) {
      setState(() => _saving = false);
      _toast('فشل تغيير كلمة المرور، حاول مرة أخرى');
      return;
    }

    // إسقاط علم "يجب تغيير كلمة المرور" من الخادم ومن الجلسة المحلية.
    await MemberSessionService.instance.markPasswordChanged();

    setState(() => _saving = false);
    if (!mounted) return;
    // لا بد من تمرير memberUid وإلا عومل التابع كمالك (كل الصلاحيات تظهر).
    final session = MemberSessionService.instance;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => Homepage(
          userId: widget.ownerUid,
          memberUid: session.authUid,
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تغيير كلمة المرور'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        automaticallyImplyLeading: false,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Icon(Icons.password, size: 56, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'سجّلت الدخول بكلمة مرور مؤقتة. يجب تغييرها قبل المتابعة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _newPassword,
              obscureText: _obscure1,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure1 = !_obscure1),
                ),
              ),
              validator: _validate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure2,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'أعد إدخال كلمة المرور';
                if (v != _newPassword.text) return 'كلمتا المرور غير متطابقتين';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Text(
              '6 أحرف على الأقل، مع حرف كبير ورقم.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('حفظ كلمة المرور'),
            ),
          ],
        ),
      ),
    );
  }
}