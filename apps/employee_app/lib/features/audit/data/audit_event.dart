class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.actorUsername,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    required this.resourceLabel,
    required this.changes,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String? actorUsername;
  final String action;
  final String resourceType;
  final String resourceId;
  final String resourceLabel;
  final Map<String, dynamic> changes;
  final String source;
  final DateTime createdAt;

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    final changes = json['changes'];
    final createdAt = DateTime.tryParse(_requiredString(json, 'created_at'));
    if (actor != null && actor is! Map<String, dynamic>) {
      throw const FormatException('invalid audit actor');
    }
    if (changes is! Map<String, dynamic> || createdAt == null) {
      throw const FormatException('invalid audit event');
    }
    return AuditEvent(
      id: _requiredString(json, 'id'),
      actorUsername: actor == null
          ? null
          : _requiredString(actor as Map<String, dynamic>, 'username'),
      action: _requiredString(json, 'action'),
      resourceType: _requiredString(json, 'resource_type'),
      resourceId: _requiredString(json, 'resource_id'),
      resourceLabel: _string(json, 'resource_label'),
      changes: Map<String, dynamic>.unmodifiable(changes),
      source: _requiredString(json, 'source'),
      createdAt: createdAt,
    );
  }
}

class AuditEventPage {
  const AuditEventPage({required this.count, required this.results});

  final int count;
  final List<AuditEvent> results;

  factory AuditEventPage.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    final results = json['results'];
    if (count is! int || results is! List) {
      throw const FormatException('invalid audit page');
    }
    return AuditEventPage(
      count: count,
      results: List<AuditEvent>.unmodifiable(
        results.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid audit event item');
          }
          return AuditEvent.fromJson(item);
        }),
      ),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('invalid $key');
  }
  return value;
}
