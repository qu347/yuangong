class AccountSession {
  const AccountSession({
    required this.id,
    required this.clientPlatform,
    required this.clientName,
    required this.appVersion,
    required this.createdAt,
    required this.lastSeenAt,
    required this.expiresAt,
    required this.isCurrent,
  });

  final String id;
  final String clientPlatform;
  final String clientName;
  final String appVersion;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime expiresAt;
  final bool isCurrent;

  factory AccountSession.fromJson(Map<String, dynamic> json) {
    DateTime readDate(String key) {
      final value = json[key];
      if (value is! String || DateTime.tryParse(value) == null) {
        throw FormatException('invalid $key');
      }
      return DateTime.parse(value);
    }

    final id = json['id'];
    final platform = json['client_platform'];
    final name = json['client_name'];
    final version = json['app_version'];
    final current = json['is_current'];
    if (id is! String ||
        platform is! String ||
        name is! String ||
        version is! String ||
        current is! bool) {
      throw const FormatException('invalid account session');
    }
    return AccountSession(
      id: id,
      clientPlatform: platform,
      clientName: name,
      appVersion: version,
      createdAt: readDate('created_at'),
      lastSeenAt: readDate('last_seen_at'),
      expiresAt: readDate('expires_at'),
      isCurrent: current,
    );
  }
}
