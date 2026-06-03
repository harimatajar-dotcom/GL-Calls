import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/error/exceptions.dart';
import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheUser(UserModel user);
  Future<UserModel?> getCachedUser();
  Future<bool> isLoggedIn();
  Future<void> clearCache();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final SharedPreferences sharedPreferences;

  static const String cachedUserKey = 'CACHED_USER';
  static const String authTokenKey = 'AUTH_TOKEN';
  static const String authTokenKeyAlt = 'auth_token'; // For background service
  static const String vendorIdKey = 'vendor_id'; // For background service

  AuthLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<void> cacheUser(UserModel user) async {
    try {
      final userJson = json.encode(user.toJson());
      await sharedPreferences.setString(cachedUserKey, userJson);
      await sharedPreferences.setString(authTokenKey, user.token);
      // Also save with alternate keys for background service
      await sharedPreferences.setString(authTokenKeyAlt, user.token);
      await sharedPreferences.setInt(vendorIdKey, user.vendorId);
      // business_id is set later by AuthProvider after calling
      // GET /api/mobile/businesses (different ULID from user.id).
      // Only save it here if the login response actually included it.
      if (user.businessId != null && user.businessId!.isNotEmpty) {
        await sharedPreferences.setString('business_id', user.businessId!);
      }
      if (user.userId != null && user.userId!.isNotEmpty) {
        await sharedPreferences.setString('user_id', user.userId!);
      }
      await sharedPreferences.setString('user_name', user.name);
      await sharedPreferences.setString('user_email', user.email);
    } catch (e) {
      throw const CacheException(message: 'Failed to cache user data');
    }
  }

  @override
  Future<UserModel?> getCachedUser() async {
    try {
      final userJson = sharedPreferences.getString(cachedUserKey);
      if (userJson != null) {
        return UserModel.fromJson(json.decode(userJson));
      }
      return null;
    } catch (e) {
      throw const CacheException(message: 'Failed to get cached user');
    }
  }

  @override
  Future<bool> isLoggedIn() async {
    // A-16: validate the token shape rather than trusting any non-empty
    // string. JWTs are `header.payload.signature` (three dot-separated
    // base64url segments). We don't crypto-verify here (no public key
    // available client-side) but a length + segment-count check rejects
    // the obvious garbage cases (empty after trim, "null", a leftover
    // sentinel from an old build) without sending bad auth headers.
    final raw = sharedPreferences.getString(authTokenKey) ??
        sharedPreferences.getString(authTokenKeyAlt);
    if (raw == null) return false;
    final token = raw.trim();
    if (token.isEmpty || token == 'null') return false;
    if (token.length < 20) return false;
    // Most server-issued tokens here are JWTs (3 segments). If a deploy
    // ever uses an opaque token, drop this check — but warn loudly so
    // we don't silently accept anything.
    final segments = token.split('.').length;
    if (segments != 3) return false;
    return true;
  }

  @override
  Future<void> clearCache() async {
    try {
      await sharedPreferences.remove(cachedUserKey);
      await sharedPreferences.remove(authTokenKey);
      await sharedPreferences.remove(authTokenKeyAlt);
      await sharedPreferences.remove(vendorIdKey);
    } catch (e) {
      throw const CacheException(message: 'Failed to clear cache');
    }
  }
}
