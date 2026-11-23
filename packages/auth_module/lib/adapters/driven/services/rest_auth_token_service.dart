import 'package:core/core.dart';

import '../auth_api_paths.dart';
import 'auth_token_remote_service.dart';

final class RestAuthTokenService implements AuthTokenRemoteService {
  RestAuthTokenService({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  @override
  Future<({String accessToken, String refreshToken})> renew(
    String refreshToken,
  ) async {
    // Without the access token, which is the one that expired: a 401 here
    // cannot ask for another refresh (chapter 27).
    final json = await _api.post(
      AuthApiPaths.refresh,
      body: {'refreshToken': refreshToken},
      authenticated: false,
    );
    if (json case {
      'accessToken': String accessToken,
      'refreshToken': String refreshToken,
    }) {
      return (accessToken: accessToken, refreshToken: refreshToken);
    }
    throw const ApiError(ApiErrorKind.invalidResponse);
  }
}
