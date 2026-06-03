import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login({
    required String phoneNumber,
    required String password,
  });

  Future<UserModel?> fetchUserInfo(String businessId);

  /// Fetch list of businesses the logged-in user has access to
  Future<List<Map<String, dynamic>>> fetchBusinesses();

  /// Fetch business meta (terminology, branches) - returns first branch id as company_id
  Future<String?> fetchCompanyId(String businessId);

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
      // Old API body (commented):
      // data: { 'phone_number': phoneNumber, 'password': password }
      // New API: /api/mobile/login - uses identifier + device_name
      final requestBody = {
        'identifier': phoneNumber,
        'password': password,
        'device_name': 'Android Device',
      };

      // Print API call in green
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] 🚀 LOGIN REQUEST\x1B[0m');
      debugPrint('\x1B[32m[API] URL: ${ApiConstants.baseUrl}${ApiConstants.login}\x1B[0m');
      debugPrint('\x1B[32m[API] Method: POST\x1B[0m');
      debugPrint('\x1B[32m[API] Headers: { "Content-Type": "application/json" }\x1B[0m');
      debugPrint('\x1B[32m[API] Body: $requestBody\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      final response = await apiClient.dio.post(
        ApiConstants.login,
        data: requestBody,
      );

      // Print API response in green
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] ✅ LOGIN RESPONSE\x1B[0m');
      debugPrint('\x1B[32m[API] Status Code: ${response.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Response Data: ${response.data}\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      if (response.statusCode == 200 || response.statusCode == 202) {
        final userModel = UserModel.fromJson(response.data);
        apiClient.setAuthToken(userModel.token);
        return userModel;
      } else {
        throw const ServerException(message: 'Login failed');
      }
    } on DioException catch (e) {
      // Print API error in green for visibility
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] ❌ LOGIN ERROR\x1B[0m');
      debugPrint('\x1B[32m[API] Status Code: ${e.response?.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Error Type: ${e.type}\x1B[0m');
      debugPrint('\x1B[32m[API] Error Message: ${e.message}\x1B[0m');
      debugPrint('\x1B[32m[API] Response Data: ${e.response?.data}\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

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
  Future<UserModel?> fetchUserInfo(String businessId) async {
    try {
      final endpoint = ApiConstants.businessUsers(businessId);

      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] 🚀 FETCH USER INFO REQUEST\x1B[0m');
      debugPrint('\x1B[32m[API] URL: ${ApiConstants.baseUrl}$endpoint\x1B[0m');
      debugPrint('\x1B[32m[API] Method: GET\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      final response = await apiClient.dio.get(endpoint);

      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] ✅ FETCH USER INFO RESPONSE\x1B[0m');
      debugPrint('\x1B[32m[API] Status Code: ${response.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Response Data: ${response.data}\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      if (response.statusCode == 200 || response.statusCode == 202) {
        final data = response.data;
        // Handle both array and single object responses
        Map<String, dynamic>? userJson;
        if (data is List && data.isNotEmpty) {
          userJson = data.first as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          userJson = data['data'] is Map
              ? data['data'] as Map<String, dynamic>
              : (data['user'] is Map
                  ? data['user'] as Map<String, dynamic>
                  : data);
          // If users is an array
          if (data['users'] is List && (data['users'] as List).isNotEmpty) {
            userJson = (data['users'] as List).first as Map<String, dynamic>;
          }
        }
        if (userJson == null) return null;
        return UserModel.fromJson(userJson);
      }
      return null;
    } on DioException catch (e) {
      debugPrint('\x1B[32m[API] ❌ FETCH USER INFO ERROR: ${e.message}\x1B[0m');
      debugPrint('\x1B[32m[API] Status: ${e.response?.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Data: ${e.response?.data}\x1B[0m');
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBusinesses() async {
    try {
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] 🚀 FETCH BUSINESSES REQUEST\x1B[0m');
      debugPrint('\x1B[32m[API] URL: ${ApiConstants.baseUrl}${ApiConstants.businesses}\x1B[0m');
      debugPrint('\x1B[32m[API] Method: GET\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      final response = await apiClient.dio.get(ApiConstants.businesses);

      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] ✅ FETCH BUSINESSES RESPONSE\x1B[0m');
      debugPrint('\x1B[32m[API] Status Code: ${response.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Response Data: ${response.data}\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      if (response.statusCode == 200 || response.statusCode == 202) {
        final data = response.data;
        // Try multiple response shapes: top-level array, {data: [...]}, {businesses: [...]}
        List<dynamic>? list;
        if (data is List) {
          list = data;
        } else if (data is Map<String, dynamic>) {
          if (data['data'] is List) {
            list = data['data'] as List;
          } else if (data['businesses'] is List) {
            list = data['businesses'] as List;
          } else if (data['data'] is Map<String, dynamic> &&
              (data['data'] as Map)['businesses'] is List) {
            list = (data['data'] as Map)['businesses'] as List;
          }
        }
        if (list == null) return [];
        return list
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      return [];
    } on DioException catch (e) {
      debugPrint('\x1B[32m[API] ❌ FETCH BUSINESSES ERROR\x1B[0m');
      debugPrint('\x1B[32m[API] Status: ${e.response?.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Data: ${e.response?.data}\x1B[0m');
      return [];
    }
  }

  @override
  Future<String?> fetchCompanyId(String businessId) async {
    try {
      final endpoint = ApiConstants.businessMeta(businessId);

      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');
      debugPrint('\x1B[32m[API] 🚀 FETCH BUSINESS META REQUEST\x1B[0m');
      debugPrint('\x1B[32m[API] URL: ${ApiConstants.baseUrl}$endpoint\x1B[0m');
      debugPrint('\x1B[32m[API] Method: GET\x1B[0m');
      debugPrint('\x1B[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1B[0m');

      final response = await apiClient.dio.get(endpoint);

      debugPrint('\x1B[32m[API] ✅ BUSINESS META RESPONSE: ${response.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Data: ${response.data}\x1B[0m');

      if (response.statusCode == 200 || response.statusCode == 202) {
        final data = response.data;
        Map<String, dynamic>? root;
        if (data is Map<String, dynamic>) {
          root = data['data'] is Map<String, dynamic>
              ? data['data'] as Map<String, dynamic>
              : data;
        }
        if (root == null) return null;

        // Extract first branch id as the "company_id"
        if (root['branches'] is List && (root['branches'] as List).isNotEmpty) {
          final firstBranch =
              (root['branches'] as List).first as Map<String, dynamic>;
          final branchId = firstBranch['id']?.toString();
          debugPrint('\x1B[32m[API] Extracted branch/company id: $branchId\x1B[0m');
          return branchId;
        }
      }
      return null;
    } on DioException catch (e) {
      debugPrint('\x1B[32m[API] ❌ BUSINESS META ERROR: ${e.message}\x1B[0m');
      debugPrint('\x1B[32m[API] Status: ${e.response?.statusCode}\x1B[0m');
      debugPrint('\x1B[32m[API] Data: ${e.response?.data}\x1B[0m');
      return null;
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
