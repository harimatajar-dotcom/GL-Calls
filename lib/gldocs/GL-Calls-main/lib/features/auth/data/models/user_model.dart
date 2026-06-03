import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  final String? businessId;
  final String? userId;
  final String? phone;
  final String? role;
  final Map<String, dynamic>? extraData;

  const UserModel({
    required super.name,
    required super.email,
    required super.token,
    required super.vendorId,
    this.businessId,
    this.userId,
    this.phone,
    this.role,
    this.extraData,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // New /api/mobile/login response format:
    // { "data": { "token": "...", "user": { "id", "name", "email" } } }
    Map<String, dynamic> root = json;
    if (json['data'] is Map<String, dynamic>) {
      root = json['data'] as Map<String, dynamic>;
    }

    final userData = root['user'] is Map
        ? root['user'] as Map<String, dynamic>
        : root;

    final userId = _parseString(userData['id'] ?? userData['user_id']);
    return UserModel(
      name: (userData['name'] ?? userData['full_name'] ?? '').toString(),
      email: (userData['email'] ?? '').toString(),
      token: (root['token'] ?? root['access_token'] ?? userData['token'] ?? '').toString(),
      vendorId: _parseInt(userData['vendor_id'] ?? root['vendor_id']),
      // business.id and user.id are DIFFERENT - businessId is set later by /api/mobile/businesses call
      businessId: _parseString(userData['business_id'] ?? root['business_id']),
      userId: userId,
      phone: _parseString(userData['phone'] ?? userData['phone_number']),
      role: _parseString(userData['role']),
      extraData: root,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'token': token,
      'vendor_id': vendorId,
      if (businessId != null) 'business_id': businessId,
      if (userId != null) 'user_id': userId,
      if (phone != null) 'phone': phone,
      if (role != null) 'role': role,
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

  UserModel copyWith({
    String? name,
    String? email,
    String? token,
    int? vendorId,
    String? businessId,
    String? userId,
    String? phone,
    String? role,
    Map<String, dynamic>? extraData,
  }) {
    return UserModel(
      name: name ?? this.name,
      email: email ?? this.email,
      token: token ?? this.token,
      vendorId: vendorId ?? this.vendorId,
      businessId: businessId ?? this.businessId,
      userId: userId ?? this.userId,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      extraData: extraData ?? this.extraData,
    );
  }
}
