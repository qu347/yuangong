# Windows runner 状态

该目录包含标准 Win32/Flutter CMake runner 源码，窗口标题与版本资源使用“企业员工管理系统”。

当前环境缺少 Flutter SDK，`windows/flutter/ephemeral` 和 `generated_plugin_registrant` 等生成文件未伪造。安装 Flutter stable 并用 `flutter --version` 记录准确版本后，在保护 `lib/`、`test/` 与 `pubspec.yaml` 的前提下执行以下命令补齐并核验：

```powershell
flutter create --platforms=windows --org com.yourcompany --project-name employee_app .
```
