import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl, String? accessToken})
    : _client = client ?? http.Client(),
      _accessToken = accessToken,
      _baseUrl = Uri.parse(
        baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://localhost:8080',
            ),
      );

  final http.Client _client;
  final Uri _baseUrl;
  final String? _accessToken;

  Future<LoginSession> loginUser({
    required String loginName,
    required String password,
    required String altchaPayload,
  }) async {
    final data = await _post(
      '/api/auth/user/login',
      body: {
        'loginName': loginName,
        'userNo': loginName,
        'password': password,
        'altchaPayload': altchaPayload,
      },
    );
    return LoginSession.fromJson(data as Map<String, dynamic>);
  }

  Future<void> registerStudent({
    required String email,
    required String realName,
    required String password,
    required String altchaPayload,
  }) async {
    await _post(
      '/api/auth/register',
      expectedStatuses: const {200, 201},
      body: {
        'email': email,
        'realName': realName,
        'password': password,
        'altchaPayload': altchaPayload,
      },
    );
  }

  Future<void> requestPasswordReset({
    required String email,
    required String altchaPayload,
  }) async {
    await _post(
      '/api/auth/password-reset/request',
      body: {
        'email': email,
        'altchaPayload': altchaPayload,
      },
    );
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String altchaPayload,
  }) async {
    await _post(
      '/api/auth/password-reset/confirm',
      body: {
        'email': email,
        'code': code,
        'newPassword': newPassword,
        'altchaPayload': altchaPayload,
      },
    );
  }

  Future<UserProfile> getCurrentUser() async {
    final data = await _get('/api/auth/me');
    return UserProfile.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updateProfile({String? avatar, String? password}) async {
    final body = <String, String>{};
    if (avatar != null) {
      body['avatar'] = avatar;
    }
    if (password != null) {
      body['password'] = password;
    }
    await _put('/api/auth/me/profile', body: body);
  }

  Future<String> uploadFile({
    required List<int> bytes,
    required String filename,
  }) async {
    final request =
        http.MultipartRequest('POST', _baseUrl.resolve('/api/upload'))
          ..headers.addAll(_authHeaders())
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response, const {200}) as String;
  }

  Future<void> bindEmail({required String email}) async {
    await _put('/api/auth/me/email', body: {'email': email});
  }

  Future<void> resendEmailVerification() async {
    await _post(
      '/api/auth/me/email/verification',
      body: const <String, String>{},
    );
  }

  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    await _post('/api/auth/email/verify', body: {'email': email, 'code': code});
  }

  Future<void> verifyMyEmail({
    required String email,
    required String code,
  }) async {
    await _post(
      '/api/auth/me/email/verify',
      body: {'email': email, 'code': code},
    );
  }

  Future<Object?> _post(
    String path, {
    required Map<String, String> body,
    int expectedStatus = 200,
    Set<int>? expectedStatuses,
  }) async {
    final response = await _client.post(
      _baseUrl.resolve(path),
      headers: _headers(),
      body: jsonEncode(body),
    );

    return _handleResponse(response, expectedStatuses ?? {expectedStatus});
  }

  Future<Object?> _get(String path) async {
    final response = await _client.get(
      _baseUrl.resolve(path),
      headers: _headers(),
    );
    return _handleResponse(response, const {200});
  }

  Future<Object?> _put(String path, {required Map<String, String> body}) async {
    final response = await _client.put(
      _baseUrl.resolve(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _handleResponse(response, const {200});
  }

  Object? _handleResponse(http.Response response, Set<int> expectedStatuses) {
    final decoded = _decodeResponse(response);
    if (!expectedStatuses.contains(response.statusCode)) {
      throw AuthApiException(_messageFrom(decoded, '请求失败，请稍后重试'));
    }

    final code = decoded['code'];
    if (code != 0) {
      throw AuthApiException(_messageFrom(decoded, '业务处理失败'));
    }
    return decoded['data'];
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ..._authHeaders(),
    };
  }

  Map<String, String> _authHeaders() {
    return {
      if (_accessToken != null && _accessToken.isNotEmpty)
        'Authorization': 'Bearer $_accessToken',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      throw const AuthApiException('服务器返回格式不正确');
    }
    throw const AuthApiException('服务器返回格式不正确');
  }

  String _messageFrom(Map<String, dynamic> response, String fallback) {
    final msg = response['msg'];
    if (msg is String && msg.trim().isNotEmpty) {
      return msg;
    }
    final message = response['message'];
    return message is String && message.trim().isNotEmpty ? message : fallback;
  }
}
