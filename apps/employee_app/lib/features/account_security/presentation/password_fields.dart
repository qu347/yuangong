import 'package:flutter/material.dart';

String? validateStrongPassword(String? value) {
  if (value == null || value.length < 12) return '密码至少需要 12 个字符';
  if (RegExp(r'^\d+$').hasMatch(value)) return '密码不能是纯数字';
  return null;
}

class SecurePasswordField extends StatefulWidget {
  const SecurePasswordField({
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.enabled = true,
    super.key,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<SecurePasswordField> createState() => _SecurePasswordFieldState();
}

class _SecurePasswordFieldState extends State<SecurePasswordField> {
  bool obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: obscure,
    onChanged: widget.onChanged,
    validator: widget.validator ?? validateStrongPassword,
    decoration: InputDecoration(
      labelText: widget.label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: obscure ? '显示密码' : '隐藏密码',
        onPressed: () => setState(() => obscure = !obscure),
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}
