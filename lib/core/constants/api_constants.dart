class ApiConstants {
  ApiConstants._();

  // Base URL
  static const String baseUrl = 'https://app.getleadcrm.com';

  // Endpoints
  static const String login = '/gl-dialer/login';
  static const String logout = '/gl-dialer/logout';
  static const String presignedUrl = '/gl-dialer/voice/presigned-url';
  static const String syncCalls = '/gl-dialer/calls/sync';

  // Timeout Configuration (in milliseconds)
  static const int connectionTimeout = 30000;
  static const int receiveTimeout = 30000;

  // Retry Configuration
  static const int maxRetryAttempts = 3;

  // Headers
  static const String contentType = 'application/json';
  static const String accept = 'application/json';
}
