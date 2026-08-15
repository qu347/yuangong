# Android runner 状态

该目录按 Flutter Android Kotlin DSL 模板建立，applicationId 仍为开发占位符 `com.yourcompany.employee_app`，且未配置正式 Release 签名。

当前环境缺少 Flutter SDK，`gradle-wrapper.jar` 与默认 launcher icon 等生成产物未伪造。安装 Flutter stable 并用 `flutter --version` 记录准确版本后，在保护 `lib/`、`test/` 与 `pubspec.yaml` 的前提下执行以下命令补齐并核验标准生成文件：

```powershell
flutter create --platforms=android --org com.yourcompany --project-name employee_app .
```
