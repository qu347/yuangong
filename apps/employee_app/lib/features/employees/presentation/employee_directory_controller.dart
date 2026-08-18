import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/employee_page.dart';
import '../data/employee_repository.dart';

const _notProvided = Object();

class EmployeeQuery {
  const EmployeeQuery({
    this.search = '',
    this.departmentId,
    this.status,
    this.page = 1,
    this.pageSize = 20,
    this.ordering = 'employee_no',
  });

  final String search;
  final String? departmentId;
  final String? status;
  final int page;
  final int pageSize;
  final String ordering;

  EmployeeQuery copyWith({
    String? search,
    Object? departmentId = _notProvided,
    Object? status = _notProvided,
    int? page,
    int? pageSize,
    String? ordering,
  }) {
    return EmployeeQuery(
      search: search ?? this.search,
      departmentId: identical(departmentId, _notProvided)
          ? this.departmentId
          : departmentId as String?,
      status: identical(status, _notProvided) ? this.status : status as String?,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      ordering: ordering ?? this.ordering,
    );
  }
}

class EmployeeDirectoryState {
  const EmployeeDirectoryState({required this.query, required this.page});

  final EmployeeQuery query;
  final AsyncValue<EmployeePage> page;

  EmployeeDirectoryState copyWith({
    EmployeeQuery? query,
    AsyncValue<EmployeePage>? page,
  }) {
    return EmployeeDirectoryState(
      query: query ?? this.query,
      page: page ?? this.page,
    );
  }
}

final employeeDirectoryControllerProvider =
    NotifierProvider<EmployeeDirectoryController, EmployeeDirectoryState>(
      EmployeeDirectoryController.new,
    );

class EmployeeDirectoryController extends Notifier<EmployeeDirectoryState> {
  Timer? _searchTimer;
  int _requestId = 0;

  @override
  EmployeeDirectoryState build() {
    ref.onDispose(() => _searchTimer?.cancel());
    Future<void>.microtask(_load);
    return const EmployeeDirectoryState(
      query: EmployeeQuery(),
      page: AsyncLoading(),
    );
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    final query = state.query;
    state = state.copyWith(page: const AsyncLoading());
    try {
      final page = await ref
          .read(employeeRepositoryProvider)
          .fetchEmployees(
            search: query.search,
            departmentId: query.departmentId,
            status: query.status,
            page: query.page,
            pageSize: query.pageSize,
            ordering: query.ordering,
          );
      if (requestId == _requestId) {
        state = state.copyWith(page: AsyncData(page));
      }
    } on Object catch (error, stackTrace) {
      if (requestId == _requestId) {
        state = state.copyWith(page: AsyncError(error, stackTrace));
      }
    }
  }

  void setSearch(String search) {
    state = state.copyWith(
      query: state.query.copyWith(search: search, page: 1),
    );
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_load());
    });
  }

  void setDepartment(String? departmentId) {
    _searchTimer?.cancel();
    state = state.copyWith(
      query: state.query.copyWith(departmentId: departmentId, page: 1),
    );
    unawaited(_load());
  }

  void setStatus(String? status) {
    _searchTimer?.cancel();
    state = state.copyWith(
      query: state.query.copyWith(status: status, page: 1),
    );
    unawaited(_load());
  }

  void nextPage() {
    if (state.page.value?.hasNext != true) {
      return;
    }
    state = state.copyWith(
      query: state.query.copyWith(page: state.query.page + 1),
    );
    unawaited(_load());
  }

  void previousPage() {
    if (state.page.value?.hasPrevious != true || state.query.page <= 1) {
      return;
    }
    state = state.copyWith(
      query: state.query.copyWith(page: state.query.page - 1),
    );
    unawaited(_load());
  }

  void retry() => unawaited(_load());
  void refresh() => unawaited(_load());
}
