import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.name,
    required super.email,
    required super.token,
    required super.vendorId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      token: json['token'] ?? '',
      vendorId: json['vendor_id'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'token': token,
      'vendor_id': vendorId,
    };
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      name: entity.name,
      email: entity.email,
      token: entity.token,
      vendorId: entity.vendorId,
    );
  }
}
