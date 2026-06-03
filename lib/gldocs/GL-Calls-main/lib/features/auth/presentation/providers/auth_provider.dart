import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/country_codes.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/app_version_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/usecases/usecase.dart';
import '../../data/datasources/auth_remote_datasource.dart';
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
      // If input contains '@' it's an email - don't add country code
      final isEmail = phoneNumber.contains('@');
      final identifier = isEmail
          ? phoneNumber.trim()
          : '${_selectedCountry.dialCode}$phoneNumber';

      // Persist selected dial code so background sync isolates can
      // include it in call-sync payloads.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('country_code', _selectedCountry.dialCode);
      await prefs.setString('country_iso', _selectedCountry.code);
      _user = await loginUseCase(
        LoginParams(
          phoneNumber: identifier,
          password: password,
        ),
      );

      // Fetch full user info from /api/mobile/businesses/{businessId}/users
      await _fetchAndStoreUserInfo();

      // Post tracking info to app-users API (non-blocking)
      // mobile = whatever identifier was used to login (phone OR email)
      if (_user != null) {
        unawaited(AppVersionService.postUserDetails(
          name: _user!.name,
          email: _user!.email,
          mobile: identifier,
          vendorId: _user!.vendorId,
        ));
      }

      _status = AuthStatus.authenticated;
      notifyListeners();

      // Add welcome notification
      await NotificationService.addWelcomeNotification(_user?.name ?? 'User');

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

  /// After login: fetch list of businesses, auto-select if only one,
  /// save selected business_id to SharedPreferences.
  /// Per the v3 API contract, business.id and user.id are DIFFERENT ULIDs.
  Future<void> _fetchAndStoreUserInfo() async {
    try {
      final currentUser = _user;
      if (currentUser == null) return;

      final remote = AuthRemoteDataSourceImpl(apiClient: ApiClient());

      // Step 1: Fetch businesses the user has access to
      final businesses = await remote.fetchBusinesses();
      debugPrint('\x1B[32m[AuthProvider] Found ${businesses.length} business(es)\x1B[0m');

      if (businesses.isEmpty) {
        debugPrint('\x1B[33m[AuthProvider] No businesses found - user has no access\x1B[0m');
        return;
      }

      // Step 2: Auto-select if only one, otherwise pick first (TODO: show picker for multi)
      final selected = businesses.first;
      final businessId = (selected['id'] ?? selected['business_id'] ?? '').toString();
      final businessName = (selected['name'] ?? selected['business_name'] ?? '').toString();

      if (businessId.isEmpty) {
        debugPrint('\x1B[31m[AuthProvider] Business has no id field: $selected\x1B[0m');
        return;
      }

      // Step 3: Save selected business_id to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('business_id', businessId);
      if (businessName.isNotEmpty) {
        await prefs.setString('business_name', businessName);
      }
      await prefs.setString('user_name', currentUser.name);
      await prefs.setString('user_email', currentUser.email);

      debugPrint('\x1B[32m[AuthProvider] ✅ Selected business: $businessName ($businessId)\x1B[0m');

      // Step 3.5: Fetch business meta to get branch/company id
      // This company_id is used as vendor_id for auto-sync-status tracking
      try {
        final companyId = await remote.fetchCompanyId(businessId);
        if (companyId != null && companyId.isNotEmpty) {
          await prefs.setString('company_id', companyId);
          debugPrint('\x1B[32m[AuthProvider] ✅ Saved company_id: $companyId\x1B[0m');
        }
      } catch (e) {
        debugPrint('\x1B[33m[AuthProvider] Company id fetch failed: $e\x1B[0m');
      }

      // Login response already has name + email + id, no need to refetch.
      // Only call /users if we need extra fields (phone, role) and ONLY merge
      // if the response has a non-empty name (otherwise we'd overwrite good data).
      try {
        final fullUser = await remote.fetchUserInfo(businessId);
        if (fullUser != null && fullUser.name.isNotEmpty) {
          _user = fullUser.copyWith(
            token: currentUser.token,
            businessId: businessId,
          );
          if (fullUser.userId != null) {
            await prefs.setString('user_id', fullUser.userId!);
          }
          if (fullUser.phone != null) {
            await prefs.setString('user_phone', fullUser.phone!);
          }
          if (fullUser.role != null) {
            await prefs.setString('user_role', fullUser.role!);
          }
          debugPrint('\x1B[32m[AuthProvider] User info merged: ${fullUser.name}\x1B[0m');
        } else {
          debugPrint('\x1B[33m[AuthProvider] User info skipped (empty/null) - keeping login user\x1B[0m');
        }
      } catch (e) {
        debugPrint('\x1B[33m[AuthProvider] User info fetch optional/failed: $e\x1B[0m');
      }
    } catch (e) {
      debugPrint('\x1B[33m[AuthProvider] Business setup failed (non-fatal): $e\x1B[0m');
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
