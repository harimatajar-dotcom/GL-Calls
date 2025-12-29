import 'package:flutter/foundation.dart';

@immutable
class UserEntity {
  final String name;
  final String email;
  final String token;
  final int vendorId;

  const UserEntity({
    required this.name,
    required this.email,
    required this.token,
    required this.vendorId,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserEntity &&
        other.name == name &&
        other.email == email &&
        other.token == token &&
        other.vendorId == vendorId;
  }

  @override
  int get hashCode {
    return name.hashCode ^ email.hashCode ^ token.hashCode ^ vendorId.hashCode;
  }
}
