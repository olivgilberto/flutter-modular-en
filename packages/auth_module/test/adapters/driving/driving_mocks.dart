import 'package:auth_module/adapters/driving/bloc/login_bloc.dart';
import 'package:auth_module/adapters/driving/bloc/logout_bloc.dart';
import 'package:auth_module/adapters/driving/bloc/register_bloc.dart';
import 'package:auth_module/application/use_cases/auth_use_case.dart';
import 'package:auth_module/domain/entities/user.dart';
import 'package:auth_module/domain/value_objects/email_address.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

/// Possible because `AuthUseCase` is not `final` (chapter 20).
final class MockAuthUseCase extends Mock implements AuthUseCase {}

/// Possible because the Blocs are not `final`.
final class MockLoginBloc extends MockBloc<LoginEvent, LoginState>
    implements LoginBloc {}

final class MockRegisterBloc extends MockBloc<RegisterEvent, RegisterState>
    implements RegisterBloc {}

final class MockLogoutBloc extends MockBloc<LogoutEvent, LogoutState>
    implements LogoutBloc {}

final ana = User(
  id: 'u-1',
  name: 'Ana',
  email: EmailAddress.parse('ana@example.com'),
);

const strongPassword = 'correct-horse-battery-staple';
