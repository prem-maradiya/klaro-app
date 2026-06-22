import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../theme/klaro.dart';

/// Email/password + Google sign-in. Sign-up and sign-in share this screen via a
/// mode toggle. On success the auth gate swaps to Home automatically (it listens
/// to the auth state), so this screen doesn't navigate itself.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Klaro.text)),
      backgroundColor: Klaro.raised,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_signUp) {
        await AuthService.instance.signUp(_email.text, _password.text);
        _snack('Account created — check your email to verify, then sign in.');
        if (mounted) setState(() => _signUp = false);
      } else {
        await AuthService.instance.signIn(_email.text, _password.text);
        // Auth gate reacts and shows Home.
      }
    } on AuthException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('Something went wrong. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.signInWithGoogle();
    } on AuthException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('Google sign-in is unavailable right now.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    if (_email.text.trim().isEmpty) {
      _snack('Enter your email first, then tap "Forgot password".');
      return;
    }
    try {
      await AuthService.instance.sendPasswordReset(_email.text);
      _snack('Password reset link sent to ${_email.text.trim()}.');
    } catch (_) {
      _snack("Couldn't send the reset link.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Klaro.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/brand/klaro_mark.png', width: 72, height: 72),
                    const SizedBox(height: 18),
                    Text(
                      _signUp ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: Klaro.display,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Klaro.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _signUp
                          ? 'Track your spending, automatically.'
                          : 'Sign in to your Klaro account.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Klaro.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 28),
                    _field(
                      controller: _email,
                      hint: 'Email',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _password,
                      hint: 'Password',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      validator: (v) => (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: Klaro.textFaint,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    if (!_signUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _forgot,
                          child: const Text('Forgot password?',
                              style: TextStyle(color: Klaro.violetLt, fontSize: 12.5)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _primaryButton(),
                    const SizedBox(height: 16),
                    Row(children: const [
                      Expanded(child: Divider(color: Klaro.line)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('or', style: TextStyle(color: Klaro.textFaint, fontSize: 12)),
                      ),
                      Expanded(child: Divider(color: Klaro.line)),
                    ]),
                    const SizedBox(height: 16),
                    _googleButton(),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _signUp ? 'Already have an account?' : "New to Klaro?",
                          style: const TextStyle(color: Klaro.textMuted, fontSize: 13),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                          child: Text(
                            _signUp ? 'Sign in' : 'Create account',
                            style: const TextStyle(
                                color: Klaro.violetLt, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Klaro.text),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Klaro.textFaint),
        prefixIcon: Icon(icon, color: Klaro.textFaint, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Klaro.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Klaro.radiusMd),
          borderSide: const BorderSide(color: Klaro.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Klaro.radiusMd),
          borderSide: const BorderSide(color: Klaro.violet),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Klaro.radiusMd),
          borderSide: const BorderSide(color: Klaro.danger),
        ),
      ),
    );
  }

  Widget _primaryButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: Klaro.gradient,
        borderRadius: BorderRadius.circular(Klaro.radiusMd),
      ),
      child: ElevatedButton(
        onPressed: _busy ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Klaro.radiusMd)),
        ),
        child: _busy
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(
                _signUp ? 'Create account' : 'Sign in',
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _googleButton() {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _google,
      icon: const Icon(Icons.g_mobiledata, color: Klaro.text, size: 28),
      label: const Text('Continue with Google',
          style: TextStyle(color: Klaro.text, fontSize: 14, fontWeight: FontWeight.w500)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        side: const BorderSide(color: Klaro.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Klaro.radiusMd)),
      ),
    );
  }
}
