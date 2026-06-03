import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<UserEntity> login({
    required String phoneNumber,
    required String password,
  });

  Future<void> logout();

  Future<bool> isLoggedIn();

  Future<UserEntity?> getCachedUser();

  Future<void> cacheUser(UserEntity user);
}
