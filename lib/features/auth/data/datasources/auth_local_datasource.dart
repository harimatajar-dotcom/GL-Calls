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

  AuthLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<void> cacheUser(UserModel user) async {
    try {
      final userJson = json.encode(user.toJson());
      await sharedPreferences.setString(cachedUserKey, userJson);
      await sharedPreferences.setString(authTokenKey, user.token);
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
    final token = sharedPreferences.getString(authTokenKey);
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> clearCache() async {
    try {
      await sharedPreferences.remove(cachedUserKey);
      await sharedPreferences.remove(authTokenKey);
    } catch (e) {
      throw const CacheException(message: 'Failed to clear cache');
    }
  }
}
