class User {
  const User({
    required this.id,
    required this.phone,
    required this.nickname,
    required this.avatarKey,
    required this.role,
  });

  final String id;
  final String phone;
  final String nickname;
  final String avatarKey;
  final String role;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    phone: json['phone'] as String,
    nickname:
        json['nickname'] as String? ??
        json['display_name'] as String? ??
        json['phone'] as String,
    avatarKey: json['avatar_key'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
  );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.phone == phone &&
      other.nickname == nickname &&
      other.avatarKey == avatarKey &&
      other.role == role;

  @override
  int get hashCode => Object.hash(id, phone, nickname, avatarKey, role);
}
