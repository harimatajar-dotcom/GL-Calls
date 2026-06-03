import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';

class CheckAuthUseCase implements UseCase<bool, NoParams> {
  final AuthRepository repository;

  CheckAuthUseCase(this.repository);

  @override
  Future<bool> call(NoParams params) async {
    return await repository.isLoggedIn();
  }
}
