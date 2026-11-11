import 'package:flutter/material.dart';

import '../services/auth_controller.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final success = await widget.auth.submit(
      _email.text,
      _password.text,
      signUp: _signUp,
    );
    if (!mounted) return;
    if (success) {
      _password.clear();
      _confirmation.clear();
      if (widget.auth.user != null) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('로컬 개발 계정')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListenableBuilder(
              listenable: widget.auth,
              builder: (context, _) => SurfaceCard(
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Brand(),
                        const SizedBox(height: 28),
                        Text(
                          _signUp ? '새로운 계정 만들기' : '다시 만나 반가워요.',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '로컬 Supabase 테스트 전용이에요.\n이 기기의 옷과 사진은 업로드하지 않아요.',
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const Key('auth-email'),
                          controller: _email,
                          enabled: !widget.auth.busy,
                          decoration: const InputDecoration(labelText: '이메일'),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(value?.trim() ?? '')
                              ? null
                              : '이메일 주소를 확인해 주세요.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('auth-password'),
                          controller: _password,
                          enabled: !widget.auth.busy,
                          decoration: InputDecoration(
                            labelText: '비밀번호',
                            helperText: _signUp
                                ? '6자 이상, 다른 곳에서 쓰지 않는 테스트 비밀번호'
                                : null,
                            helperMaxLines: 2,
                            suffixIcon: IconButton(
                              tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          obscureText: _obscure,
                          autofillHints: [
                            _signUp
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          enableSuggestions: false,
                          autocorrect: false,
                          textInputAction: _signUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!widget.auth.busy && !_signUp) _submit();
                          },
                          validator: (value) =>
                              (value?.length ?? 0) >= (_signUp ? 6 : 1)
                              ? null
                              : (_signUp
                                    ? '비밀번호를 6자 이상 입력해 주세요.'
                                    : '비밀번호를 입력해 주세요.'),
                        ),
                        if (_signUp) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('auth-confirmation'),
                            controller: _confirmation,
                            enabled: !widget.auth.busy,
                            decoration: const InputDecoration(
                              labelText: '비밀번호 확인',
                            ),
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            validator: (value) => value == _password.text
                                ? null
                                : '비밀번호가 서로 달라요.',
                          ),
                        ],
                        if (widget.auth.error != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              widget.auth.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                        if (widget.auth.notice != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(widget.auth.notice!),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const Key('auth-submit'),
                          onPressed: widget.auth.busy || !widget.auth.available
                              ? null
                              : _submit,
                          child: Text(
                            widget.auth.busy
                                ? '확인 중…'
                                : _signUp
                                ? '계정 만들기'
                                : '이메일로 로그인',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: widget.auth.busy
                              ? null
                              : () => setState(() {
                                  _signUp = !_signUp;
                                  _password.clear();
                                  _confirmation.clear();
                                  _form.currentState?.reset();
                                }),
                          child: Text(
                            _signUp ? '이미 계정이 있나요? 로그인' : '처음인가요? 회원가입',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
