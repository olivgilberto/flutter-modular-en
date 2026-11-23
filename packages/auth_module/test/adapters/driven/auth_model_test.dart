import 'dart:convert';
import 'dart:io';

import 'package:auth_module/adapters/driven/models/auth_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts the sample response from the API documentation', () {
    final json = jsonDecode(
      File('test/fixtures/sign_in_response.json').readAsStringSync(),
    );

    final model = AuthModel.fromJson(json);

    expect(model.userId, 'u-1');
    expect(model.email, 'ana@example.com');
    expect(model.refreshToken, 'rt-1');
  });

  test('rejects a response without the refresh token', () {
    expect(
      () => AuthModel.fromJson({
        'user': {'id': 'u-1', 'name': 'Ana', 'email': 'ana@example.com'},
        'accessToken': 'at-1',
      }),
      throwsFormatException,
    );
  });

  test('round trip through the database row', () {
    const model = AuthModel(
      userId: 'u-1',
      name: 'Ana',
      email: 'ana@example.com',
      accessToken: 'at-1',
      refreshToken: 'rt-1',
    );

    final back = AuthModel.fromMap(model.toMap());

    expect(back.toMap(), model.toMap());
  });
}
