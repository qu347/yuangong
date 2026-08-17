import 'package:flutter/material.dart';

Future<bool> confirmDiscardUnsavedChanges(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('放弃未保存更改？'),
          content: const Text('当前表单还有未保存内容，离开后将无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('放弃更改'),
            ),
          ],
        ),
      ) ??
      false;
}
