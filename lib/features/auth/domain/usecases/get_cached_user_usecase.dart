import '../../../../core/usecases/usecase.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class GetCachedUserUseCase implements UseCase<UserEntity?, NoParams> {
  final AuthRepository repository;

  GetCachedUserUseCase(this.repository);

  @override
  Future<UserEntity?> call(NoParams params) async {
    return await repository.getCachedUser();
  }
}
