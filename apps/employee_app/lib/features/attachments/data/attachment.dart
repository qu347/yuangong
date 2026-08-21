class AttachmentUploader {
  const AttachmentUploader({required this.id, required this.username});

  final String id;
  final String username;

  factory AttachmentUploader.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final username = json['username'];
    if (id is! String ||
        id.isEmpty ||
        username is! String ||
        username.isEmpty) {
      throw const FormatException('invalid attachment uploader');
    }
    return AttachmentUploader(id: id, username: username);
  }
}

class EmployeeAttachment {
  const EmployeeAttachment({
    required this.id,
    required this.employeeId,
    required this.filename,
    required this.fileType,
    required this.fileSize,
    required this.uploadedBy,
    required this.createdAt,
  });

  final String id;
  final String employeeId;
  final String filename;
  final String fileType;
  final int fileSize;
  final AttachmentUploader? uploadedBy;
  final DateTime createdAt;

  factory EmployeeAttachment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final employeeId = json['employee_id'];
    final filename = json['filename'];
    final fileType = json['file_type'];
    final fileSize = json['file_size'];
    final uploadedBy = json['uploaded_by'];
    final createdAtValue = json['created_at'];
    if (id is! String ||
        id.isEmpty ||
        employeeId is! String ||
        employeeId.isEmpty ||
        filename is! String ||
        filename.isEmpty ||
        fileType is! String ||
        fileType.isEmpty ||
        fileSize is! int ||
        fileSize <= 0 ||
        (uploadedBy != null && uploadedBy is! Map<String, dynamic>) ||
        createdAtValue is! String) {
      throw const FormatException('invalid attachment');
    }
    final createdAt = DateTime.tryParse(createdAtValue);
    if (createdAt == null) {
      throw const FormatException('invalid attachment timestamp');
    }
    return EmployeeAttachment(
      id: id,
      employeeId: employeeId,
      filename: filename,
      fileType: fileType,
      fileSize: fileSize,
      uploadedBy: uploadedBy == null
          ? null
          : AttachmentUploader.fromJson(uploadedBy as Map<String, dynamic>),
      createdAt: createdAt,
    );
  }
}

class AttachmentPage {
  const AttachmentPage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<EmployeeAttachment> results;

  bool get hasNext => next != null;
  bool get hasPrevious => previous != null;

  factory AttachmentPage.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    final next = json['next'];
    final previous = json['previous'];
    final results = json['results'];
    if (count is! int ||
        count < 0 ||
        (next != null && next is! String) ||
        (previous != null && previous is! String) ||
        results is! List) {
      throw const FormatException('invalid attachment page');
    }
    return AttachmentPage(
      count: count,
      next: next as String?,
      previous: previous as String?,
      results: List<EmployeeAttachment>.unmodifiable(
        results.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid attachment item');
          }
          return EmployeeAttachment.fromJson(item);
        }),
      ),
    );
  }
}

class AttachmentUploadCandidate {
  const AttachmentUploadCandidate({
    required this.path,
    required this.name,
    required this.size,
    required this.extension,
  });

  final String path;
  final String name;
  final int size;
  final String extension;
}
