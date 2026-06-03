import 'package:flutter/foundation.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class LoginUseCase implements UseCase<UserEntity, LoginParams> {
  final AuthRepository repository;

  LoginUseCase(this.repository);

  @override
  Future<UserEntity> call(LoginParams params) async {
    return await repository.login(
      phoneNumber: params.phoneNumber,
      password: params.password,
    );
  }
}

@immutable
class LoginParams {
  final String phoneNumber;
  final String password;

  const LoginParams({
    required this.phoneNumber,
    required this.password,
  });
}
