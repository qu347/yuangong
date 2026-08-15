class HealthResponse {
  const HealthResponse({
    required this.status,
    required this.service,
    required this.version,
    required this.database,
  });

  final String status;
  final String service;
  final String version;
  final String database;

  factory HealthResponse.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final service = json['service'];
    final version = json['version'];
    final database = json['database'];

    if (status is! String ||
        service is! String ||
        version is! String ||
        database is! String) {
      throw const FormatException('invalid health response');
    }

    return HealthResponse(
      status: status,
      service: service,
      version: version,
      database: database,
    );
  }

  bool get isHealthy => status == 'ok' && database == 'ok';
}
