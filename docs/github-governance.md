# GitHub 仓库治理方案

## 当前只读审查结果

截至 2026-08-19，对 `qu347/yuangong` 的只读检查结果为：仓库是 `public`，默认分支是 `main`，`main` 未受保护、没有 ruleset；只有一名直接协作者且其权限为管理员。Actions 仓库权限允许全部 Action，默认工作流权限为只读；secret scanning 与 push protection 已启用，Dependabot security updates 未启用，Code scanning 尚无分析结果。

本阶段只增加代码库内的治理合同。仓库可见性、branch protection、ruleset、Actions 权限、Secrets、Environments 均未应用或修改。

## Public 仓库风险

- 源码、业务规则、提交历史和内部架构会被公开复制或 fork，后续改为 private 不能收回既有副本。
- 不得提交真实员工信息、生产域名、内部路径、邮件正文、审计归档、数据库备份或配置凭据。
- 当前项目缺少经组织批准的公开发布/许可证决策；在明确前不得把 public 状态等同于允许第三方使用。
- GitHub secret scanning 是重要基线，但不能证明历史中不存在所有类型的秘密或个人信息。
- 安全问题使用 GitHub Security Advisories 私下报告，不在公开 Issue 中披露。

## 建议的 main 保护规则（未应用）

在至少有两名可实际参与审查的协作者，并获得明确授权后，再配置：

1. 只允许 Pull Request 合并，禁止直接 push。
2. 至少一名审批者；新提交使旧审批失效。
3. 必须解决全部 review conversations。
4. 禁止 force push，禁止删除 `main`。
5. 合并前要求分支与 `main` 保持最新。
6. 要求以下六个稳定检查名称完全匹配：
   - `backend-sqlite`
   - `backend-postgresql`
   - `flutter-quality`
   - `android-build`
   - `windows-build`
   - `repository-safety`

只有一名协作者时启用“一名审批者”会把唯一管理员锁在流程之外，因此本阶段未应用。也没有创建 `CODEOWNERS`，因为不存在可核实的第二名所有者账号。

## 建议执行与回退（需要另行授权）

应用前应重新读取分支、ruleset、实际 check run 名称和协作者列表，并保存原始 JSON。可以通过 GitHub ruleset API 或 branch protection API 创建规则；不得直接复制此文档中的占位参数执行。

回退时删除本阶段实际创建的 ruleset，或恢复保存的 branch protection JSON。示例端点分别为 `DELETE /repos/qu347/yuangong/rulesets/{ruleset_id}` 与 `DELETE /repos/qu347/yuangong/branches/main/protection`。回退同样需要明确授权，并在执行后重新读取远端状态确认。

## 供应链基线

- Dependabot 每周检查 pip、pub 和 GitHub Actions；每个生态最多同时打开 5 个 PR，不自动合并。
- 依赖 PR 必须同步锁文件，运行 Flutter 双平台构建、SQLite/PostgreSQL 测试，并检查迁移和安全公告。
- CodeQL 使用官方 v4 Action，仅分析仓库受支持的 Python；不声称覆盖 Dart。
- 第三方 Action 固定完整 commit SHA，并由 Dependabot 提议更新。
- `release-readiness.yml` 仅允许手动触发，使用虚构的进程级配置和一次性 Android 验证证书，不创建 tag、Release 或上传产物。
