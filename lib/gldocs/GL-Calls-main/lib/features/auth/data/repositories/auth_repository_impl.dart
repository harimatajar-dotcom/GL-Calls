import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_datasource.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<UserEntity> login({
    required String phoneNumber,
    required String password,
  }) async {
    final user = await remoteDataSource.login(
      phoneNumber: phoneNumber,
      password: password,
    );
    await localDataSource.cacheUser(user);
    return user;
  }

  @override
  Future<void> logout() async {
    await remoteDataSource.logout();
    await localDataSource.clearCache();
  }

  @override
  Future<bool> isLoggedIn() async {
    return await localDataSource.isLoggedIn();
  }

  @override
  Future<UserEntity?> getCachedUser() async {
    return await localDataSource.getCachedUser();
  }

  @override
  Future<void> cacheUser(UserEntity user) async {
    await localDataSource.cacheUser(UserModel.fromEntity(user));
  }
}
