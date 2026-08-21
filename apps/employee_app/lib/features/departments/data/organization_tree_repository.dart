import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class OrganizationTreeNode {
  const OrganizationTreeNode({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.employeeCount,
    required this.children,
  });
  final String id;
  final String code;
  final String name;
  final String status;
  final int employeeCount;
  final List<OrganizationTreeNode> children;
  bool get isActive => status == 'active';

  factory OrganizationTreeNode.fromJson(Map<String, dynamic> json) {
    final children = json['children'];
    final employeeCount = json['employee_count'];
    if (children is! List || employeeCount is! int) {
      throw const FormatException('invalid tree node');
    }
    return OrganizationTreeNode(
      id: _requiredString(json, 'id'),
      code: _requiredString(json, 'code'),
      name: _requiredString(json, 'name'),
      status: _requiredString(json, 'status'),
      employeeCount: employeeCount,
      children: List.unmodifiable(
        children.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid tree child');
          }
          return OrganizationTreeNode.fromJson(item);
        }),
      ),
    );
  }
}

final organizationTreeRepositoryProvider = Provider<OrganizationTreeRepository>(
  (ref) => NetworkOrganizationTreeRepository(ref.watch(apiClientProvider)),
);

abstract interface class OrganizationTreeRepository {
  Future<List<OrganizationTreeNode>> fetchTree();
}

class NetworkOrganizationTreeRepository implements OrganizationTreeRepository {
  const NetworkOrganizationTreeRepository(this._client);
  final ApiClient _client;

  @override
  Future<List<OrganizationTreeNode>> fetchTree() async {
    try {
      final payload = await _client.getList(ApiEndpoints.departmentTree);
      return List.unmodifiable(
        payload.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid tree item');
          }
          return OrganizationTreeNode.fromJson(item);
        }),
      );
    } on AppException catch (error) {
      if (error.type == AppExceptionType.network) {
        throw const Failure.network();
      }
      throw const Failure.service();
    } on FormatException {
      throw const Failure.data();
    }
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}
