import 'package:flutter/material.dart';
import '../../../../core/constants/country_codes.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/check_auth_usecase.dart';
import '../../domain/usecases/get_cached_user_usecase.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final LoginUseCase loginUseCase;
  final LogoutUseCase logoutUseCase;
  final CheckAuthUseCase checkAuthUseCase;
  final GetCachedUserUseCase getCachedUserUseCase;

  AuthProvider({
    required this.loginUseCase,
    required this.logoutUseCase,
    required this.checkAuthUseCase,
    required this.getCachedUserUseCase,
  });

  AuthStatus _status = AuthStatus.initial;
  String? _errorMessage;
  UserEntity? _user;
  CountryCode _selectedCountry = CountryCodes.defaultCountry;

  // Getters
  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  UserEntity? get user => _user;
  CountryCode get selectedCountry => _selectedCountry;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  void setSelectedCountry(CountryCode country) {
    _selectedCountry = country;
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    try {
      final isLoggedIn = await checkAuthUseCase(const NoParams());
      if (isLoggedIn) {
        _user = await getCachedUserUseCase(const NoParams());
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
      notifyListeners();
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String phoneNumber,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final fullPhoneNumber = '${_selectedCountry.dialCode}$phoneNumber';
      _user = await loginUseCase(
        LoginParams(
          phoneNumber: fullPhoneNumber,
          password: password,
        ),
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on AuthenticationException catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } on NetworkException catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } on ServerException catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = 'An unexpected error occurred';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await logoutUseCase(const NoParams());
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
