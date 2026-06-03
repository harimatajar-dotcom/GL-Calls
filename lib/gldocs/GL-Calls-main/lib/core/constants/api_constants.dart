class ApiConstants {
  ApiConstants._();

  // Base URL (new v3 API for login & sync)
  // static const String baseUrl = 'https://app.getleadcrm.com';
  static const String baseUrl = 'https://v3.getleadcrm.com';

  // Old base URL (still used for presigned URL endpoint)
  static const String legacyBaseUrl = 'https://app.getleadcrm.com';

  // Endpoints
  // static const String login = '/gl-dialer/login';
  static const String login = '/api/mobile/login';
  static const String logout = '/gl-dialer/logout';
  // Old presigned URL (commented):
  // static const String presignedUrl = '/gl-dialer/voice/presigned-url';
  // static const String presignedUrlFull = '$legacyBaseUrl/gl-dialer/voice/presigned-url';
  // static const String syncCalls = '/gl-dialer/calls/sync';
  static const String syncCalls = '/api/mobile/gl-dialer/calls';

  /// Get user info endpoint - {{baseUrl}}/api/mobile/businesses/{businessId}/users
  static String businessUsers(String businessId) =>
      '/api/mobile/businesses/$businessId/users';

  /// Get list of businesses the logged-in user has access to
  /// {{baseUrl}}/api/mobile/businesses
  static const String businesses = '/api/mobile/businesses';

  /// Get business meta info (branches, terminology, etc.)
  /// {{baseUrl}}/api/mobile/businesses/{businessId}/meta
  static String businessMeta(String businessId) =>
      '/api/mobile/businesses/$businessId/meta';

  /// New presigned URL endpoint - {{baseUrl}}/api/mobile/businesses/{businessId}/upload/presigned-url
  /// (matches pattern of other v3 mobile endpoints)
  static String presignedUrlForBusiness(String businessId) =>
      '/api/mobile/businesses/$businessId/upload/presigned-url';

  // Timeout Configuration (in milliseconds)
  static const int connectionTimeout = 30000;
  static const int receiveTimeout = 30000;

  // Retry Configuration
  static const int maxRetryAttempts = 3;

  // Headers
  static const String contentType = 'application/json';
  static const String accept = 'application/json';
}
