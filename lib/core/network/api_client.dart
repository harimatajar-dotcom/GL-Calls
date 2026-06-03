import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  String? _authToken;

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(milliseconds: ApiConstants.connectionTimeout),
        receiveTimeout: const Duration(milliseconds: ApiConstants.receiveTimeout),
        headers: {
          'Content-Type': ApiConstants.contentType,
          'Accept': ApiConstants.accept,
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authToken != null) {
            options.headers['Authorization'] = 'Bearer $_authToken';
          }
          return handler.next(options);
        },
        // A-16: 401 means the cached token is no longer accepted by the
        // server (revoked, password changed elsewhere, expired). Clear
        // the in-memory copy + the persisted prefs so the next foreground
        // launch lands on the login screen instead of silently making
        // unauthenticated calls. We don't auto-refresh because the
        // server has no refresh-token endpoint - re-login is required.
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            clearAuthToken();
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('auth_token');
              await prefs.remove('AUTH_TOKEN');
            } catch (_) {
              // best-effort; if prefs fail, in-memory clear still protects
              // this isolate from re-using the dead token.
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  void setAuthToken(String token) {
    _authToken = token;
  }

  void clearAuthToken() {
    _authToken = null;
  }

  String? get authToken => _authToken;
}
