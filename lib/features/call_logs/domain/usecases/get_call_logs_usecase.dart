import '../../../../core/usecases/usecase.dart';
import '../entities/call_log_entity.dart';
import '../repositories/call_log_repository.dart';

class GetCallLogsUseCase implements UseCase<List<CallLogEntity>, NoParams> {
  final CallLogRepository repository;

  GetCallLogsUseCase(this.repository);

  @override
  Future<List<CallLogEntity>> call(NoParams params) async {
    return await repository.getCallLogs();
  }
}
