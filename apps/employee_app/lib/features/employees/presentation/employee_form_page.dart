import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../departments/data/department.dart';
import '../../departments/presentation/department_controller.dart';
import '../../positions/data/position.dart';
import '../../positions/presentation/position_management_controller.dart';
import '../data/employee.dart';
import 'employee_management_controller.dart';

class EmployeeFormPage extends ConsumerStatefulWidget {
  const EmployeeFormPage({this.employeeId, super.key});

  final String? employeeId;

  bool get isEditing => employeeId != null;

  @override
  ConsumerState<EmployeeFormPage> createState() => _EmployeeFormPageState();
}

class _EmployeeFormPageState extends ConsumerState<EmployeeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _employeeNo = TextEditingController();
  final _fullName = TextEditingController();
  final _workEmail = TextEditingController();
  final _workPhone = TextEditingController();
  final _hireDate = TextEditingController();
  Future<Employee?>? _initialLoad;
  Employee? _loadedEmployee;
  String? _departmentId;
  String? _positionId;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final id = widget.employeeId;
    _initialLoad = id == null
        ? Future<Employee?>.value()
        : ref.read(employeeManagementControllerProvider).load(id).then((
            employee,
          ) {
            _loadedEmployee = employee;
            _employeeNo.text = employee.employeeNo;
            _fullName.text = employee.fullName;
            _workEmail.text = employee.workEmail;
            _workPhone.text = employee.workPhone;
            _hireDate.text = _formatDate(employee.hireDate);
            _departmentId = employee.department.id;
            _positionId = employee.position?.id;
            return employee;
          });
  }

  @override
  void dispose() {
    _employeeNo.dispose();
    _fullName.dispose();
    _workEmail.dispose();
    _workPhone.dispose();
    _hireDate.dispose();
    super.dispose();
  }

  void _markDirty([Object? _]) {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentControllerProvider);
    final positions = ref.watch(positionListProvider);
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving) {
          return;
        }
        await _requestLeave();
      },
      child: SafeArea(
        child: FutureBuilder<Employee?>(
          future: _initialLoad,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoadingView(label: '正在加载员工表单');
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Center(
                child: Text(error is Failure ? error.message : '员工表单加载失败。'),
              );
            }
            return departments.when(
              loading: () => const AppLoadingView(label: '正在加载部门选项'),
              error: (error, _) => Center(
                child: Text(error is Failure ? error.message : '部门选项加载失败。'),
              ),
              data: (departmentItems) => positions.when(
                loading: () => const AppLoadingView(label: '正在加载岗位选项'),
                error: (error, _) => Center(
                  child: Text(error is Failure ? error.message : '岗位选项加载失败。'),
                ),
                data: (positionItems) =>
                    _buildForm(context, departmentItems, positionItems),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    List<Department> departments,
    List<Position> positions,
  ) {
    final activeDepartments = departments
        .where((item) => item.isActive)
        .toList();
    final activePositions = positions
        .where((item) => item.isActive && item.department.id == _departmentId)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: _saving ? null : _requestLeave,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isEditing ? '编辑员工' : '新增员工',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('employee_form_no'),
                  controller: _employeeNo,
                  onChanged: _markDirty,
                  decoration: const InputDecoration(labelText: '工号'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('employee_form_name'),
                  controller: _fullName,
                  onChanged: _markDirty,
                  decoration: const InputDecoration(labelText: '姓名'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workEmail,
                  onChanged: _markDirty,
                  decoration: const InputDecoration(labelText: '工作邮箱'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workPhone,
                  onChanged: _markDirty,
                  decoration: const InputDecoration(labelText: '工作电话'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('employee_form_department'),
                  initialValue: _departmentId,
                  decoration: const InputDecoration(labelText: '部门'),
                  validator: (value) => value == null ? '请选择部门' : null,
                  items: [
                    for (final department in activeDepartments)
                      DropdownMenuItem<String>(
                        value: department.id,
                        child: Text(department.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() {
                            _departmentId = value;
                            _positionId = null;
                            _dirty = true;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey(
                    'employee_form_position_${_departmentId ?? 'none'}',
                  ),
                  initialValue: _positionId,
                  decoration: const InputDecoration(labelText: '岗位（可选）'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不分配岗位'),
                    ),
                    for (final position in activePositions)
                      DropdownMenuItem<String?>(
                        value: position.id,
                        child: Text(position.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _positionId = value;
                          _dirty = true;
                        }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hireDate,
                  onChanged: _markDirty,
                  decoration: const InputDecoration(
                    labelText: '入职日期（YYYY-MM-DD）',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('employee_form_save'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? '正在保存' : '保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项为必填项' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'employee_no': _employeeNo.text.trim(),
        'full_name': _fullName.text.trim(),
        'work_email': _workEmail.text.trim(),
        'work_phone': _workPhone.text.trim(),
        'department': _departmentId,
        'position': _positionId,
        'hire_date': _hireDate.text.trim().isEmpty
            ? null
            : _hireDate.text.trim(),
        if (_loadedEmployee?.updatedAt case final updatedAt?)
          'expected_updated_at': updatedAt.toIso8601String(),
      };
      final controller = ref.read(employeeManagementControllerProvider);
      final saved = widget.isEditing
          ? await controller.update(widget.employeeId!, data)
          : await controller.create(data);
      _dirty = false;
      if (mounted) {
        context.go('/employees/${saved.id}');
      }
    } on Failure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _requestLeave() async {
    if (_saving) {
      return;
    }
    if (_dirty && !await confirmDiscardUnsavedChanges(context)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _dirty = false);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/employees');
    }
  }
}

String _formatDate(DateTime? date) {
  if (date == null) {
    return '';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
