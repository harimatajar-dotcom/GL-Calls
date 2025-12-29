import 'package:dio/dio.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login({
    required String phoneNumber,
    required String password,
  });

  Future<void> logout();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final ApiClient apiClient;

  AuthRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<UserModel> login({
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final response = await apiClient.dio.post(
        ApiConstants.login,
        data: {
          'phone_number': phoneNumber,
          'password': password,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        final userModel = UserModel.fromJson(response.data);
        apiClient.setAuthToken(userModel.token);
        return userModel;
      } else {
        throw const ServerException(message: 'Login failed');
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const NetworkException(
          message: 'Connection timed out. Please try again.',
        );
      } else if (e.type == DioExceptionType.connectionError) {
        throw const NetworkException(
          message: 'No internet connection.',
        );
      } else if (e.response?.statusCode == 401) {
        throw const AuthenticationException(
          message: 'Invalid phone number or password.',
        );
      } else {
        throw ServerException(
          message: e.response?.data?['message'] ?? 'Login failed. Please try again.',
          statusCode: e.response?.statusCode,
        );
      }
    }
  }

  @override
  Future<void> logout() async {
    try {
      await apiClient.dio.post(ApiConstants.logout);
    } finally {
      apiClient.clearAuthToken();
    }
  }
}
