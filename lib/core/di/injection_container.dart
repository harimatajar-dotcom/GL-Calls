import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../../features/auth/data/datasources/auth_local_datasource.dart';
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/domain/usecases/logout_usecase.dart';
import '../../features/auth/domain/usecases/check_auth_usecase.dart';
import '../../features/auth/domain/usecases/get_cached_user_usecase.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/call_logs/data/datasources/call_log_local_datasource.dart';
import '../../features/call_logs/data/datasources/call_log_database_datasource.dart';
import '../../features/call_logs/data/repositories/call_log_repository_impl.dart';
import '../../features/call_logs/domain/repositories/call_log_repository.dart';
import '../../features/call_logs/presentation/providers/call_log_provider.dart';
import '../../features/recordings/data/datasources/call_sync_datasource.dart';
import '../../features/recordings/data/datasources/recording_database_datasource.dart';
import '../../features/recordings/data/datasources/recording_scanner_datasource.dart';
import '../../features/recordings/data/datasources/recording_upload_datasource.dart';
import '../../features/recordings/data/repositories/recording_repository_impl.dart';
import '../../features/recordings/domain/repositories/recording_repository.dart';
import '../../features/recordings/presentation/providers/recording_provider.dart';

class InjectionContainer {
  static final InjectionContainer _instance = InjectionContainer._internal();
  factory InjectionContainer() => _instance;
  InjectionContainer._internal();

  late SharedPreferences _sharedPreferences;
  late ApiClient _apiClient;

  // Data Sources
  late AuthRemoteDataSource _authRemoteDataSource;
  late AuthLocalDataSource _authLocalDataSource;
  late CallLogLocalDataSource _callLogLocalDataSource;
  late CallLogDatabaseDataSource _callLogDatabaseDataSource;
  late RecordingDatabaseDataSource _recordingDatabaseDataSource;
  late RecordingScannerDataSource _recordingScannerDataSource;
  late RecordingUploadDataSourceImpl _recordingUploadDataSource;
  late CallSyncDataSourceImpl _callSyncDataSource;

  // Repositories
  late AuthRepository _authRepository;
  late CallLogRepository _callLogRepository;
  late RecordingRepository _recordingRepository;

  // Use Cases
  late LoginUseCase _loginUseCase;
  late LogoutUseCase _logoutUseCase;
  late CheckAuthUseCase _checkAuthUseCase;
  late GetCachedUserUseCase _getCachedUserUseCase;

  Future<void> init() async {
    // External
    _sharedPreferences = await SharedPreferences.getInstance();
    _apiClient = ApiClient();

    // Data Sources
    _authRemoteDataSource = AuthRemoteDataSourceImpl(apiClient: _apiClient);
    _authLocalDataSource = AuthLocalDataSourceImpl(
      sharedPreferences: _sharedPreferences,
    );

    // Repositories
    _authRepository = AuthRepositoryImpl(
      remoteDataSource: _authRemoteDataSource,
      localDataSource: _authLocalDataSource,
    );

    // Call Log Data Sources
    _callLogLocalDataSource = CallLogLocalDataSourceImpl();
    _callLogDatabaseDataSource = CallLogDatabaseDataSourceImpl();

    // Call Log Repositories
    _callLogRepository = CallLogRepositoryImpl(
      localDataSource: _callLogLocalDataSource,
      databaseDataSource: _callLogDatabaseDataSource,
    );

    // Recording Data Sources
    _recordingDatabaseDataSource = RecordingDatabaseDataSourceImpl();
    _recordingScannerDataSource = RecordingScannerDataSourceImpl();
    _recordingUploadDataSource = RecordingUploadDataSourceImpl(apiClient: _apiClient);
    _callSyncDataSource = CallSyncDataSourceImpl(apiClient: _apiClient);

    // Recording Repositories
    _recordingRepository = RecordingRepositoryImpl(
      databaseDataSource: _recordingDatabaseDataSource,
      scannerDataSource: _recordingScannerDataSource,
      uploadDataSource: _recordingUploadDataSource,
      callSyncDataSource: _callSyncDataSource,
    );

    // Use Cases
    _loginUseCase = LoginUseCase(_authRepository);
    _logoutUseCase = LogoutUseCase(_authRepository);
    _checkAuthUseCase = CheckAuthUseCase(_authRepository);
    _getCachedUserUseCase = GetCachedUserUseCase(_authRepository);
  }

  // Getters
  SharedPreferences get sharedPreferences => _sharedPreferences;
  ApiClient get apiClient => _apiClient;
  AuthRepository get authRepository => _authRepository;
  CallLogRepository get callLogRepository => _callLogRepository;
  RecordingRepository get recordingRepository => _recordingRepository;
  LoginUseCase get loginUseCase => _loginUseCase;
  LogoutUseCase get logoutUseCase => _logoutUseCase;
  CheckAuthUseCase get checkAuthUseCase => _checkAuthUseCase;
  GetCachedUserUseCase get getCachedUserUseCase => _getCachedUserUseCase;

  // Provider Factories
  AuthProvider createAuthProvider() {
    return AuthProvider(
      loginUseCase: _loginUseCase,
      logoutUseCase: _logoutUseCase,
      checkAuthUseCase: _checkAuthUseCase,
      getCachedUserUseCase: _getCachedUserUseCase,
    );
  }

  CallLogProvider createCallLogProvider() {
    return CallLogProvider(repository: _callLogRepository);
  }

  RecordingProvider createRecordingProvider() {
    return RecordingProvider(repository: _recordingRepository);
  }
}

final sl = InjectionContainer();
