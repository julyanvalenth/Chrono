import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chrono_mark.dart';
import '../widgets/common.dart';

/// Sign up / log in. Shown after "Get started" (or "Log in") on the Welcome
/// screen, and when a saved session has expired.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _hidePassword = true;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState state) async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = state.authMode == AuthMode.signUp
        ? await state.signUp(name: _name.text.trim(), email: _email.text.trim(), password: _password.text)
        : await state.logIn(email: _email.text.trim(), password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  void _switch(AppState state) {
    setState(() => _error = null);
    state.showAuth(state.authMode == AuthMode.signUp ? AuthMode.logIn : AuthMode.signUp);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final signUp = state.authMode == AuthMode.signUp;
    final pad = MediaQuery.paddingOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, pad.top + 14, 24, pad.bottom + 16),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 32,
            child: Transform.translate(
              offset: const Offset(-8, 0),
              child: IconButton(
                onPressed: _busy ? null : () => state.goStage(Stage.welcome),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, color: C.ink, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 17),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const ChronoMark(size: 36, hole: 9),
                const SizedBox(height: 18),
                Text(
                  signUp ? 'Create your account' : 'Welcome back',
                  style: poppins(27, weight: w600, lineHeight: 28.35, letterSpacing: -0.54),
                ),
                const SizedBox(height: 4),
                Text(
                  signUp
                      ? 'Your schedule and chats are saved to your account, on any phone.'
                      : 'Log in to pick up your schedule where you left it.',
                  style: poppins(14.5, color: C.ink2, lineHeight: 21.75),
                ),
                const SizedBox(height: 24),
                if (signUp) ...[
                  _Field(
                    controller: _name,
                    label: 'Name',
                    hint: 'What should Chrono call you?',
                    autofill: const [AutofillHints.name],
                    capitalization: TextCapitalization.words,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 14),
                ],
                _Field(
                  controller: _email,
                  label: 'Email',
                  hint: 'you@student.ac.id',
                  keyboard: TextInputType.emailAddress,
                  autofill: const [AutofillHints.email],
                  validator: (v) =>
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 14),
                _Field(
                  controller: _password,
                  label: 'Password',
                  hint: signUp ? 'At least 6 characters' : 'Your password',
                  obscure: _hidePassword,
                  autofill: [signUp ? AutofillHints.newPassword : AutofillHints.password],
                  action: TextInputAction.done,
                  onSubmitted: (_) => _submit(state),
                  validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  suffix: IconButton(
                    tooltip: _hidePassword ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: C.ink2, size: 20),
                  ),
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(_error!, style: poppins(13, color: C.danger, lineHeight: 18.2)),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Btn(
            label: _busy ? (signUp ? 'Creating account…' : 'Logging in…') : (signUp ? 'Create account' : 'Log in'),
            onTap: _busy ? null : () => _submit(state),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => _switch(state),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: signUp ? 'Already have an account? ' : 'New to Chrono? ',
                  style: poppins(13.5, color: C.ink2),
                ),
                TextSpan(text: signUp ? 'Log in' : 'Create an account', style: poppins(13.5, weight: w600, color: C.lime)),
              ])),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.keyboard,
    this.obscure = false,
    this.autofill,
    this.capitalization = TextCapitalization.none,
    this.action = TextInputAction.next,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboard;
  final bool obscure;
  final Iterable<String>? autofill;
  final TextCapitalization capitalization;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: poppins(13, weight: w600)),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboard,
        obscureText: obscure,
        autocorrect: !obscure && keyboard != TextInputType.emailAddress,
        enableSuggestions: !obscure,
        autofillHints: autofill,
        textCapitalization: capitalization,
        textInputAction: action,
        onFieldSubmitted: onSubmitted,
        style: poppins(15),
        cursorColor: C.lime,
        decoration: chronoField(hint, suffix: suffix),
      ),
    ]);
  }
}
