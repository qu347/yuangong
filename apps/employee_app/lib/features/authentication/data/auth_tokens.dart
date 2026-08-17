class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final accessToken = json['access'];
    final refreshToken = json['refresh'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw const FormatException('invalid auth token response');
    }
    return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
  }
}
