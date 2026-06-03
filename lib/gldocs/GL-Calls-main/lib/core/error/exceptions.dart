class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException({
    this.message = 'Server error occurred',
    this.statusCode,
  });

  @override
  String toString() => message;
}

class CacheException implements Exception {
  final String message;

  const CacheException({this.message = 'Cache error occurred'});

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;

  const NetworkException({this.message = 'Network error occurred'});

  @override
  String toString() => message;
}

class AuthenticationException implements Exception {
  final String message;

  const AuthenticationException({this.message = 'Authentication failed'});

  @override
  String toString() => message;
}
