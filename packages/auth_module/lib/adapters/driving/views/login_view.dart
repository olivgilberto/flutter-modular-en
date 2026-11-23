import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/auth_failure.dart';
import '../bloc/login_bloc.dart';
import '../l10n/auth_module_localizations.dart';
import '../routes/auth_module_routes.dart';
import '../session/session_bloc.dart';

/// The content of the sign-in screen. It does not know where the Bloc comes
/// from. The strings come from the module's translation files (chapter 37).
final class LoginView extends StatefulWidget {
  const LoginView({super.key, this.expiredSession, this.onDiscard});

  /// A session that expired with unsent changes (chapter 29): the screen
  /// warns and offers to discard them, besides signing in again.
  final SessionExpiredWithPendingChanges? expiredSession;
  final VoidCallback? onDiscard;

  @override
  State<LoginView> createState() => _LoginViewState();
}

final class _LoginViewState extends State<LoginView> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() => context.read<LoginBloc>().add(
    LoginSubmitted(email: _email.text, password: _password.text),
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LoginBloc>().state;
    // After success the button stays busy until the host's redirect.
    final busy = state is LoginSubmitInProgress || state is LoginSubmitSuccess;

    final expired = widget.expiredSession;
    final l10n = AuthModuleLocalizations.of(context);

    return AppForm(
      title: l10n.loginTitle,
      children: [
        if (expired != null) ...[
          AppInlineError(
            message: _expiredMessage(l10n, expired.pendingChanges),
          ),
          AppTextButton(
            label: l10n.discardChanges,
            onPressed: busy ? null : _confirmDiscard,
          ),
        ],
        AppTextField(
          controller: _email,
          label: l10n.emailLabel,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
        ),
        AppTextField.password(
          controller: _password,
          label: l10n.passwordLabel,
          showLabel: l10n.showPassword,
          hideLabel: l10n.hidePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
        ),
        if (state case LoginSubmitFailure(:final failure))
          AppInlineError(
            message: failure == null
                ? l10n.loginUnexpectedError
                : _messageFor(l10n, failure),
          ),
        AppPrimaryButton(
          label: l10n.loginSubmit,
          loading: busy,
          onPressed: _submit,
        ),
        AppTextButton(
          label: l10n.loginCreateAccount,
          onPressed: busy ? null : () => context.pushNamed(AuthRoutes.register),
        ),
      ],
    );
  }

  Future<void> _confirmDiscard() async {
    final onDiscard = widget.onDiscard;
    final l10n = AuthModuleLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.discardChangesTitle,
      message: l10n.discardChangesMessage,
      confirmLabel: l10n.discard,
      cancelLabel: l10n.cancel,
    );
    if (confirmed) onDiscard?.call();
  }

  /// The plural lives in the ARB: each language has its own rules (chapter 37).
  static String _expiredMessage(AuthModuleLocalizations l10n, int? pending) =>
      pending == null
      ? l10n.sessionExpiredMaybeChanges
      : l10n.sessionExpiredChanges(pending);

  /// At sign-in, a password outside the policy cannot be the right one: the
  /// screen answers as it would to a wrong password. An email already in use
  /// does not happen here, but the exhaustive `switch` asks for an answer.
  static String _messageFor(
    AuthModuleLocalizations l10n,
    AuthFailure failure,
  ) => switch (failure) {
    InvalidEmailFailure() => l10n.checkEmail,
    WeakPasswordFailure() ||
    InvalidCredentialsFailure() ||
    EmailAlreadyRegisteredFailure() => l10n.loginInvalidCredentials,
  };
}
