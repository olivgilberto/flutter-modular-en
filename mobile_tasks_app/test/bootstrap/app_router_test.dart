import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/app_router.dart';

String? redirect(
  String location, {
  required bool languageChosen,
  bool authenticated = true,
}) => appRedirect(
  Uri.parse(location),
  languageChosen: languageChosen,
  authenticated: authenticated,
);

void main() {
  group('with no language chosen', () {
    test('any screen leads to the choice, taking the destination along', () {
      expect(redirect('/', languageChosen: false), '/language?from=%2F');
      expect(
        redirect('/auth/login?next=1', languageChosen: false),
        '/language?from=%2Fauth%2Flogin%3Fnext%3D1',
      );
    });

    test('the selection screen itself does not redirect', () {
      expect(redirect('/language?from=%2F', languageChosen: false), isNull);
    });

    test('the language comes before the session', () {
      expect(
        redirect('/', languageChosen: false, authenticated: false),
        '/language?from=%2F',
      );
    });
  });

  group('with a language chosen', () {
    test('the selection screen returns to the original destination', () {
      expect(
        redirect(
          '/language?from=%2Fauth%2Flogin%3Fnext%3D1',
          languageChosen: true,
        ),
        '/auth/login?next=1',
      );
    });

    test('with no destination, or with an external one, goes to the start '
        'screen', () {
      expect(redirect('/language', languageChosen: true), '/');
      expect(
        redirect(
          '/language?from=https%3A%2F%2Fexample.com',
          languageChosen: true,
        ),
        '/',
      );
      expect(
        redirect('/language?from=%2F%2Fexample.com', languageChosen: true),
        '/',
      );
    });

    test('with a session, the other screens go on without a redirect', () {
      expect(redirect('/', languageChosen: true), isNull);
    });
  });

  group('with no session', () {
    String? signedOut(String location) =>
        redirect(location, languageChosen: true, authenticated: false);

    test(
      'any app screen leads to the sign-in, taking the destination along',
      () {
        expect(signedOut('/'), '/auth/login?from=%2F');
        expect(signedOut('/tasks/42'), '/auth/login?from=%2Ftasks%2F42');
      },
    );

    test('auth_module screens open', () {
      expect(signedOut('/auth/login'), isNull);
      expect(signedOut('/auth/register'), isNull);
      expect(signedOut('/auth/login?from=%2Ftasks%2F42'), isNull);
    });

    test('a path that only starts like the module\'s does not get through', () {
      expect(signedOut('/authors'), '/auth/login?from=%2Fauthors');
    });
  });

  group('with a session', () {
    test(
      'the sign-in screens lead to the original destination, or to the start',
      () {
        expect(
          redirect('/auth/login?from=%2Ftasks%2F42', languageChosen: true),
          '/tasks/42',
        );
        expect(redirect('/auth/register', languageChosen: true), '/');
        expect(
          redirect(
            '/auth/login?from=https%3A%2F%2Fexample.com',
            languageChosen: true,
          ),
          '/',
        );
      },
    );
  });
}
