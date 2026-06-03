class UserProfile {
  const UserProfile({
    required this.id,
    required this.loginName,
    required this.realName,
    required this.role,
    required this.status,
    required this.activated,
    this.userNo,
    this.username,
    this.email,
    this.avatar,
  });

  final int id;
  final String loginName;
  final String? userNo;
  final String? username;
  final String realName;
  final String? email;
  final bool activated;
  final String role;
  final String status;
  final String? avatar;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      loginName: json['loginName'] as String,
      userNo: json['userNo'] as String?,
      username: json['username'] as String?,
      realName: json['realName'] as String,
      email: json['email'] as String?,
      activated: json['activated'] == true,
      role: json['role'] as String,
      status: json['status'] as String,
      avatar: json['avatar'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'loginName': loginName,
      'userNo': userNo,
      'username': username,
      'realName': realName,
      'email': email,
      'activated': activated,
      'role': role,
      'status': status,
      'avatar': avatar,
    };
  }
}

class LoginSession {
  const LoginSession({required this.accessToken, required this.user});

  final String accessToken;
  final UserProfile user;

  factory LoginSession.fromJson(Map<String, dynamic> json) {
    return LoginSession(
      accessToken: json['accessToken'] as String,
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {'accessToken': accessToken, 'user': user.toJson()};
  }
}
