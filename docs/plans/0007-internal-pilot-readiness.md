# Internal Pilot Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不增加 HR 业务、不删除审计、不使用真实生产凭据的前提下，交付可安全导出/归档审计、可验证生产配置、可生成 NON-DISTRIBUTABLE 内部验证构建并具备仓库治理合同的第四阶段工程。

**Architecture:** 继续使用 Django 模块化单体和唯一 Flutter Riverpod/go_router/Dio 栈。审计过滤、导出、归档、保留报告分别放入明确服务边界；生产 keyring 和 checks 从 settings 注入；发布脚本只编排现有 Flutter/Docker 工具并生成可验证 manifest。GitHub 设置只读审查，代码库只增加治理文件和可选工作流。

**Tech Stack:** Python 3.12、Django 5.2、DRF、SimpleJWT、PostgreSQL 17、Redis 8、Gunicorn、Flutter 3.47/Dart 3.13、Riverpod、Dio、file_selector 1.1.0、PowerShell、Docker Compose、GitHub Actions、CodeQL Python。

**Spec:** `docs/decisions/ADR-0006-audit-governance.md`、`docs/decisions/ADR-0007-internal-release-readiness.md`

## Global Constraints

- 只支持 Windows 与 Android；不创建其他 Flutter 平台。
- 不增加考勤、薪资、审批、招聘、MFA、SSO、多租户或第二套身份/审计/网络/路由。
- `AuditEvent` 永不物理删除；不存在 purge 命令。
- 不提交真实密钥、SMTP 凭据、证书、keystore、PFX、归档或发布产物。
- production 不允许 Mailpit、LocMem、SQLite、HTTP API、通配 ALLOWED_HOSTS/CORS 或不安全默认值。
- 正式身份未提供，所有 Release Validation 产物必须 `NON-DISTRIBUTABLE`。
- GitHub visibility、ruleset、branch protection、Secrets、Environments 与 Actions 权限不在本阶段授权范围。
- 主工作区 `docs/environment-configuration.md` 不修改、不暂存、不提交；所有实现位于 `D:\Worktrees\yuangong-phase4`。
- 每个行为先红测再最小实现；最终 SQLite/PostgreSQL 使用同一完整后端矩阵。

---

### Task 1: Design Baseline and Line-Ending Governance

**Files:**
- Create: `.gitattributes`
- Create: `docs/decisions/ADR-0006-audit-governance.md`
- Create: `docs/decisions/ADR-0007-internal-release-readiness.md`
- Create: `docs/plans/0007-internal-pilot-readiness.md`

**Interfaces:**
- Consumes: `origin/main@4d200113ed183f5c84f89bccf05dc4a6b2db5043` and existing Ruff `line-ending = "lf"`.
- Produces: accepted audit/release decisions and deterministic LF checkout rules for Python/YAML/shell files.

- [ ] **Step 1: Add deterministic attributes**

```gitattributes
* text=auto
*.py text eol=lf
*.sh text eol=lf
*.yml text eol=lf
*.yaml text eol=lf
*.json text eol=lf
*.dart text eol=lf
*.ps1 text eol=crlf
*.bat text eol=crlf
```

- [ ] **Step 2: Verify attributes do not create mass content changes**

Run: `git diff --check` and `git diff --stat`

Expected: only `.gitattributes` and the three design/plan documents are changed.

- [ ] **Step 3: Commit**

```powershell
git add .gitattributes docs/decisions/ADR-0006-audit-governance.md docs/decisions/ADR-0007-internal-release-readiness.md docs/plans/0007-internal-pilot-readiness.md
git commit -m "docs: define audit governance and release readiness"
```

### Task 2: Secure Audit CSV Export

**Files:**
- Create: `backend/modules/audit/filters.py`
- Create: `backend/modules/audit/export.py`
- Modify: `backend/modules/audit/models.py`
- Modify: `backend/modules/audit/views.py`
- Modify: `backend/modules/audit/urls.py`
- Modify: `backend/modules/audit/services.py`
- Modify: `backend/modules/accounts/rbac.py`
- Modify: `backend/modules/accounts/serializers.py`
- Modify: `backend/config/settings/base.py`
- Modify: `backend/modules/common/exceptions.py`
- Test: `backend/tests/test_audit_export.py`
- Test: `backend/tests/test_audit_api.py`
- Test: `backend/tests/test_rbac.py`
- Test: `backend/tests/test_schema.py`

**Interfaces:**
- Consumes: `apply_audit_filters(queryset, query_params) -> QuerySet[AuditEvent]` and existing `record_audit_event`.
- Produces: `GET /api/v1/audit-events/export.csv`, `audit.export_auditevent`, `can_export_audit`, `build_audit_csv(events) -> bytes`.

- [ ] **Step 1: Write permission and capability red tests**

```python
@pytest.mark.django_db
def test_audit_export_is_system_admin_only(users_by_role):
    assert client_for().get("/api/v1/audit-events/export.csv").status_code == 401
    assert client_for(users_by_role["employee"]).get(EXPORT_URL).status_code == 403
    assert client_for(users_by_role["hr_admin"]).get(EXPORT_URL).status_code == 403
    assert client_for(users_by_role["system_admin"]).get(EXPORT_URL).status_code == 200
```

Run: `backend\.venv\Scripts\python.exe -m pytest backend/tests/test_audit_export.py -q`

Expected: FAIL because route/permission does not exist.

- [ ] **Step 2: Add custom permission and idempotent RBAC grant**

Add `permissions = [("export_auditevent", "Can export audit events")]` to `AuditEvent.Meta`; add only this permission to `SYSTEM_ADMIN_PERMISSION_KEYS`; expose `can_export_audit=user.has_perm("audit.export_auditevent")`.

Run: `backend\.venv\Scripts\python.exe manage.py makemigrations audit`

Expected: one new audit migration; existing migrations unchanged.

- [ ] **Step 3: Write filter/limit/CSV red tests**

Cover exact filters and ordering, `AUDIT_EXPORT_MAX_ROWS`, UTF-8 BOM, CRLF, comma/quote/newline, actor null, stable changes JSON and values beginning with `=`, `+`, `-`, `@`, tab, CR or LF. Assert over-limit response is `400` with `code=export_too_large`, count/limit only.

- [ ] **Step 4: Implement shared filters and CSV builder**

`filters.py` validates exact filters/dates/ordering once for list/export. `export.py` uses `io.StringIO(newline="")`, `csv.writer(..., lineterminator="\r\n")`, `json.dumps(..., sort_keys=True, separators=(",", ":"), ensure_ascii=False)` and `utf-8-sig` encoding. `sanitize_csv_text(value)` prefixes a single quote when the first codepoint is unsafe.

- [ ] **Step 5: Implement export view and success audit**

Materialize at most `limit + 1` safe rows, reject excess before writing an audit event, then build `HttpResponse(content_type="text/csv; charset=utf-8")` with server-generated filename. Record `audit_exported` after bytes are built; changes contain `filters`, `row_count`, `format` only. Add the explicit export route before UUID detail.

- [ ] **Step 6: Run focused and strict schema tests**

```powershell
backend\.venv\Scripts\python.exe -m pytest backend/tests/test_audit_export.py backend/tests/test_audit_api.py backend/tests/test_rbac.py backend/tests/test_schema.py -q
backend\.venv\Scripts\python.exe backend/manage.py spectacular --validate --fail-on-warn --settings=config.settings.test --file $env:TEMP\phase4-schema.yaml
```

- [ ] **Step 7: Commit**

```powershell
git add backend/modules/audit backend/modules/accounts/rbac.py backend/modules/accounts/serializers.py backend/config/settings/base.py backend/modules/common/exceptions.py backend/tests
git commit -m "feat(audit): add secure audit export"
```

### Task 3: Verifiable Non-Destructive Audit Archives

**Files:**
- Create: `backend/modules/audit/archive.py`
- Create: `backend/modules/audit/keyrings.py`
- Create: `backend/modules/audit/management/__init__.py`
- Create: `backend/modules/audit/management/commands/__init__.py`
- Create: `backend/modules/audit/management/commands/archive_audit_events.py`
- Create: `backend/modules/audit/management/commands/verify_audit_archive.py`
- Create: `backend/modules/audit/management/commands/audit_retention_report.py`
- Modify: `backend/modules/audit/models.py`
- Modify: `backend/config/settings/base.py`
- Test: `backend/tests/test_audit_archive.py`
- Test: `backend/tests/test_audit_retention.py`

**Interfaces:**
- Produces: `AuditArchiveBatch`, `archive_events(cutoff, output_dir, execute)`, `verify_archive(manifest_path)`, and three management commands.
- Manifest: canonical schema version 1 from ADR-0006; HMAC input is canonical manifest JSON without `hmac`.

- [ ] **Step 1: Write model and dry-run red tests**

Assert batch fields/status choices, dry-run output counts without creating a Batch or any file, and `AuditEvent.objects.count()` unchanged.

- [ ] **Step 2: Add model migration without changing AuditEvent mutability**

Generate a new audit migration for `AuditArchiveBatch`; do not edit prior migrations and do not add delete logic.

- [ ] **Step 3: Write execute/manifest/integrity red tests**

Use pytest `tmp_path` outside the repository fixture boundary. Cover success, archive/manifest file names, gzip JSONL parse, stable `(created_at,id)` order, SHA-256, HMAC, event count/times, full Git SHA and completed batch.

- [ ] **Step 4: Implement atomic archive service**

Resolve output and Git roots; reject repository-contained/path traversal targets. Write `.tmp` files using exclusive creation, iterator chunking, gzip UTF-8 JSONL, flush/fsync; compute digest; write/fsync canonical manifest; self-verify temp files; `os.replace` into final names; update Batch completed last. On exception, remove only verified temp files and store an allowlisted `failure_code`.

- [ ] **Step 5: Write and pass tamper tests**

Mutate one archive byte, truncate gzip, use wrong key, change manifest count/time/name, duplicate an event ID, and pre-create final filename. Each verify/execute command must return nonzero without printing event content or deleting database rows.

- [ ] **Step 6: Implement retention report**

`AUDIT_RETENTION_DAYS=0` returns indefinite retention and zero delete behavior. Positive days calculate candidates at `now - days`; completed batch cutoff determines archived coverage; output JSON or stable text counts only. Assert no command named `purge_audit_events` exists.

- [ ] **Step 7: Run SQLite and migration checks**

```powershell
backend\.venv\Scripts\python.exe -m pytest backend/tests/test_audit_archive.py backend/tests/test_audit_retention.py -q
backend\.venv\Scripts\python.exe backend/manage.py makemigrations --check --dry-run --settings=config.settings.test
```

- [ ] **Step 8: Commit**

```powershell
git add backend/modules/audit backend/config/settings/base.py backend/tests/test_audit_archive.py backend/tests/test_audit_retention.py
git commit -m "feat(audit): add verifiable non-destructive archives"
```

### Task 4: Production Keyrings, SMTP and Deploy Checks

**Files:**
- Create: `backend/modules/common/keyrings.py`
- Create: `backend/modules/common/production_checks.py`
- Create: `backend/modules/accounts/management/commands/account_token_key_report.py`
- Create: `backend/modules/accounts/management/commands/send_account_email_probe.py`
- Modify: `backend/modules/common/apps.py`
- Modify: `backend/modules/accounts/models.py`
- Modify: `backend/modules/accounts/security_tokens.py`
- Modify: `backend/modules/accounts/invitation_services.py`
- Modify: `backend/modules/accounts/password_services.py`
- Modify: `backend/config/settings/base.py`
- Modify: `backend/config/settings/development.py`
- Modify: `backend/config/settings/test.py`
- Modify: `backend/config/settings/production.py`
- Modify: `.env.example`
- Create: `deploy/backend/Dockerfile.production`
- Create: `deploy/backend/entrypoint.production.sh`
- Create: `deploy/docker-compose.production.example.yml`
- Modify: `backend/requirements/base.txt`
- Test: `backend/tests/test_account_token_keyring.py`
- Test: `backend/tests/test_production_settings.py`
- Test: `backend/tests/test_production_compose.py`

**Interfaces:**
- Produces: `parse_keyring(json_text)`, account token format `<kid>.<random>`, `token_key_id` fields, production Django checks and production image/Compose contract.
- Legacy: `token_key_id IS NULL` verifies only with `SECRET_KEY` and raw legacy token format.

- [ ] **Step 1: Write keyring red tests**

Assert active key generation stores kid, known kid verifies, unknown kid fails without key iteration, legacy digest remains compatible, used/revoked tokens never reactivate, and report omits digests/keys.

- [ ] **Step 2: Add nullable key-id migration and keyring implementation**

Add `token_key_id` nullable/blank to `AccountInvitation` and `PasswordResetChallenge`. New tokens embed a URL-safe kid before the random segment. `digest_one_time_token(purpose, raw_token, key_id)` obtains exactly one key. Existing null rows stay unchanged.

- [ ] **Step 3: Write production contract subprocess tests**

For each case import `config.settings.production` in a clean subprocess: missing JWT/keyrings/archive dir, HTTP API URL, SQLite, LocMem, Mailpit, wildcard host/CORS, TLS+SSL and `.invalid` sender must fail without echoing values. A complete temporary-safe environment must import and pass `manage.py check --deploy`.

- [ ] **Step 4: Implement settings/checks**

Production requires every variable listed in the attachment. Set `SIMPLE_JWT["SIGNING_KEY"]`, secure cookies/redirect/HSTS/referrer/nosniff, PostgreSQL/Redis, SMTP timeout/TLS/SSL/server email and archive/account keyrings. Development/test use distinct explicit non-production keys.

- [ ] **Step 5: Add controlled email probe**

Require `--confirm`; reject `.invalid` in production and never print body/code/SMTP values. Do not run against real SMTP during this phase.

- [ ] **Step 6: Implement production image/Compose contract**

Add Gunicorn, non-root UID, no source bind mount, no Mailpit, internal-only db/redis, required `${VAR:?}` secrets, API healthcheck and no automatic migrate. Test `docker compose config` with process-only placeholders and inspect built image user/files.

- [ ] **Step 7: Run focused tests and production check**

```powershell
backend\.venv\Scripts\python.exe -m pytest backend/tests/test_account_token_keyring.py backend/tests/test_production_settings.py backend/tests/test_production_compose.py -q
```

- [ ] **Step 8: Commit**

```powershell
git add backend .env.example deploy
git commit -m "feat(security): add production key and email contracts"
```

### Task 5: Governed Flutter Audit Export

**Files:**
- Modify: `apps/employee_app/pubspec.yaml`
- Modify: `apps/employee_app/pubspec.lock`
- Modify: `apps/employee_app/lib/core/network/api_client.dart`
- Modify: `apps/employee_app/lib/core/network/api_endpoints.dart`
- Modify: `apps/employee_app/lib/features/authentication/data/current_user.dart`
- Create: `apps/employee_app/lib/features/audit/data/audit_export_repository.dart`
- Create: `apps/employee_app/lib/features/audit/platform/audit_export_saver.dart`
- Create: `apps/employee_app/lib/features/audit/presentation/audit_export_controller.dart`
- Modify: `apps/employee_app/lib/features/audit/presentation/audit_page.dart`
- Test: `apps/employee_app/test/features/audit/audit_export_repository_test.dart`
- Test: `apps/employee_app/test/features/audit/audit_export_controller_test.dart`
- Test: `apps/employee_app/test/features/audit/audit_page_test.dart`
- Test: `apps/employee_app/test/features/authentication/current_user_test.dart`

**Interfaces:**
- Produces: `ApiDownload(bytes, filename)`, `AuditExportRepository.export(filters)`, `AuditExportSaver.save(bytes, filename) -> AuditSaveResult`, and capability `canExportAudit`.
- Platform behavior: Windows `getSaveLocation`; Android `getDirectoryPath` then safe fixed filename.

- [ ] **Step 1: Write capability and entry red tests**

Assert missing `can_export_audit` defaults false; employee/hr pages have no export key; system_admin capability shows one export button.

- [ ] **Step 2: Add `file_selector: ^1.1.0` and download API**

Add `ApiClient.downloadBytes(path, queryParameters)` returning only response bytes and a sanitized server filename. Never log bytes/headers beyond path/status.

- [ ] **Step 3: Write repository/controller/saver red tests**

Use Fake ApiClient and Fake Saver. Cover filter propagation, confirmation summary, save success/cancel/failure, `export_too_large`, duplicate submission and no CSV content in state/log messages.

- [ ] **Step 4: Implement platform saver**

Windows: `getSaveLocation(suggestedName, csv type)` and `XFile.fromData(...).saveTo(path)`. Android: `getDirectoryPath()` then validate server filename with `basename == filename`, join and write through `XFile.saveTo`. Reject unsupported platforms with a safe Failure. Tests inject a saver function and never open UI.

- [ ] **Step 5: Add confirmed UI flow**

Reuse audit filters; show a dialog with filter summary and export cap warning, then controller progress. Display safe saved path/OS confirmation; cancel is not an error. Entry remains capability-gated.

- [ ] **Step 6: Run Flutter focused/full tests**

```powershell
flutter test test/features/audit test/features/authentication/current_user_test.dart
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

- [ ] **Step 7: Commit**

```powershell
git add apps/employee_app
git commit -m "feat(app): add governed audit export flow"
```

### Task 6: Internal Release Validation Tooling

**Files:**
- Create: `config/release.validation.json`
- Modify: `apps/employee_app/android/app/build.gradle.kts`
- Create: `scripts/validate-release-identity.ps1`
- Create: `scripts/build-internal-release.ps1`
- Create: `scripts/verify-release-artifacts.ps1`
- Create: `scripts/tests/release-scripts.tests.ps1`
- Modify: `.gitignore`
- Test: `backend/tests/test_release_contract.py`

**Interfaces:**
- Produces: strict identity validator, `build-internal-release` parameters from attachment, release manifest schema 1 and artifact verifier.
- Validation-only config uses HTTPS `https://validation.invalid/api/v1`, version `0.1.0+1`, placeholder identity allowed only by explicit switch.

- [ ] **Step 1: Write release contract red tests**

Invoke scripts in subprocesses and assert strict placeholder/HTTP/missing signing rejection, validation-only naming, existing output refusal, success/nonzero exits, manifest fields, SHA verification and no environment-value leakage.

- [ ] **Step 2: Implement identity/version validator**

Parse pubspec, Android Gradle, Runner.rc and Dart-define JSON. Strict mode rejects placeholders; allow flag returns `validation_only=true` and a reason list rather than silently passing.

- [ ] **Step 3: Implement Android release signing contract**

Gradle release signing reads four environment variables and throws when absent. Build script ValidationOnly generates a random password and one-time keystore in `New-TemporaryFile` sibling directory, passes env only to Flutter, verifies with `apksigner`, captures safe certificate SHA-256, then removes the temp directory in `finally`.

- [ ] **Step 4: Implement Windows release ZIP**

Build `flutter build windows --release`; use process-only `TrackFileAccess=false` only on this host; copy Release directory to a new output tree and create `WINDOWS-UNSIGNED-NON-DISTRIBUTABLE.zip`. Do not select an installer format or invoke signing without all three Windows vars.

- [ ] **Step 5: Generate and verify manifest**

Use full commit SHA, UTC, product/version/build, validation flag, API scheme, platform filename/size/SHA/signed/fingerprint. Write canonical JSON and `SHA256SUMS.txt`; verifier rejects missing, extra, wrong-size or wrong-hash artifacts.

- [ ] **Step 6: Run script tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\release-scripts.tests.ps1
backend\.venv\Scripts\python.exe -m pytest backend/tests/test_release_contract.py -q
```

- [ ] **Step 7: Commit**

```powershell
git add .gitignore config/release.validation.json apps/employee_app/android/app/build.gradle.kts scripts backend/tests/test_release_contract.py
git commit -m "build: add internal release validation tooling"
```

### Task 7: GitHub and Supply-Chain Governance Contracts

**Files:**
- Create: `SECURITY.md`
- Create: `.github/dependabot.yml`
- Create: `.github/workflows/release-readiness.yml`
- Create: `.github/workflows/codeql.yml`
- Modify: `.github/PULL_REQUEST_TEMPLATE.md`
- Modify: `.github/workflows/ci.yml`
- Create: `docs/github-governance.md`
- Create: `docs/release-checklist.md`
- Modify: `docs/ci.md`
- Modify: `backend/tests/test_ci_contract.py`

**Interfaces:**
- Preserves existing six CI job names.
- Adds local contract checks to `repository-safety`; manual `release-readiness`; Python-only CodeQL with `contents:read` and `security-events:write`.

- [ ] **Step 1: Write governance/workflow red tests**

Parse YAML and assert Dependabot ecosystems/directories/weekly limits/no auto-merge, workflow_dispatch-only release readiness, no `pull_request_target`, minimal permissions, full Action SHAs, Python-only CodeQL, no Dart claim, no production secrets on PR.

- [ ] **Step 2: Add SECURITY and PR governance**

SECURITY directs private reports to GitHub Security Advisories and contains no private email. PR template adds dependency, production config, audit/archive, release identity and external-decision checklists.

- [ ] **Step 3: Add Dependabot**

Configure pip `/backend`, pub `/apps/employee_app`, github-actions `/`; weekly schedule, open PR limit 5, patch/minor groups, no auto-merge.

- [ ] **Step 4: Add pinned CodeQL Python workflow**

Use current official `github/codeql-action` full SHA, Python only, push/PR main + weekly schedule. Do not include Dart/Kotlin/C++ claims. Document public-repo availability and Node deprecation observation.

- [ ] **Step 5: Add manual release-readiness workflow**

Use only workflow_dispatch, `contents:read`, concurrency cancellation and pinned existing actions. Generate temporary non-production values and temporary Android signing material, run production checks/build scripts, do not tag/release/publish. Artifact upload remains omitted unless a later explicit decision adds short retention.

- [ ] **Step 6: Document unapplied GitHub plan**

Record current public/main-unprotected/single-collaborator state, exact six required checks, proposed rules and rollback API. Explicitly state ruleset/visibility/Actions permissions were not applied because only one reviewer exists and no authorization was granted. Do not create CODEOWNERS.

- [ ] **Step 7: Run CI contract and safety tests**

```powershell
backend\.venv\Scripts\python.exe -m pytest backend/tests/test_ci_contract.py -q
pwsh -NoProfile -File scripts/repository-safety.ps1
```

- [ ] **Step 8: Commit**

```powershell
git add SECURITY.md .github docs/github-governance.md docs/release-checklist.md docs/ci.md backend/tests/test_ci_contract.py
git commit -m "ci: harden repository and release-readiness checks"
```

### Task 8: Real Audit, Production and Dual-Platform Validation

**Files:**
- Modify: `scripts/check.ps1`
- Modify: `README.md`
- Modify: `docs/OPEN_DECISIONS.md`
- Modify: `docs/security-baseline.md`
- Modify: `docs/development.md`
- Modify: `docs/api-conventions.md`
- Create: `docs/production-configuration.md`
- Create: `docs/audit-governance.md`
- Create: `docs/internal-pilot-readiness-validation-report.md`

**Interfaces:**
- Produces final local evidence only; no push/PR/tag/Release/GitHub setting mutation.

- [ ] **Step 1: Apply migrations non-destructively**

Record counts for User/Employee/AuditEvent/Invitation/Reset/Session/Outstanding/Blacklisted, apply migrations, run `sync_rbac` twice and re-count. Require AuditEvent count unchanged before validation writes and no valid legacy token regression.

- [ ] **Step 2: Run real audit export**

Use process-only fictitious system_admin, request filtered CSV, save outside repo, validate BOM/Chinese/row count/formula escaping/SHA and one `audit_exported` event. End with validation account inactive and sessions revoked.

- [ ] **Step 3: Run real archive dry-run/execute/verify**

Use `D:\EmployeeAuditArchives\Validation`, process-only archive keyring and full Git SHA. Preserve one valid archive/manifest; create a copy, mutate one byte, require verify nonzero, then delete only the known tampered copy. Confirm AuditEvent count did not decrease.

- [ ] **Step 4: Run production config and image smoke**

Use process-only generated secrets and `.invalid`-free safe placeholders. Run `check --deploy`, production Compose config/build, inspect non-root user and absence of `.env`, `.git`, venv, pyc, tests and Mailpit; run health with local PostgreSQL/Redis. Label as production-like local smoke only. SMTP staging remains NOT RUN.

- [ ] **Step 5: Build and verify ValidationOnly releases**

Output to a new repository-external directory. Run all-platform build/verify. Record Android APK version/applicationId/temp certificate/SHA/install/PID/MainActivity/FATAL and Windows ZIP/SHA/EXE PID/window/responding/normal close. Mark Android signed with temporary validation certificate and Windows unsigned; both NON-DISTRIBUTABLE.

- [ ] **Step 6: Extend and run unified gate**

Add production settings contract, production Compose config, audit archive tests and release script tests to `scripts/check.ps1` without swallowing exit codes.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1`

Expected: exit 0 with new real Flutter/SQLite/PostgreSQL counts.

- [ ] **Step 7: Update all docs and final report**

Document actual vs NOT RUN/unapplied decisions, archive hashes without content/key, release hashes without credential paths, GitHub public risk, and exact external authorization list.

- [ ] **Step 8: Final security scan and commit**

Scan current/staged files and Git history for forbidden paths/private-key headers/common token formats without printing matches. Confirm no `.env`, archive, release-output, keystore/PFX, Mailpit data or main-workspace protected file is staged.

```powershell
git add README.md docs scripts/check.ps1
git commit -m "test(docs): record phase four validation"
```

## Self-Review

- Spec coverage: audit export/permission/CSV, archive/HMAC/manifest/tamper, retention/no delete, keyrings/legacy, production SMTP/settings/Compose, Flutter save abstraction, Android/Windows ValidationOnly, GitHub governance/Dependabot/CodeQL/CI, migrations and real validation all map to Tasks 2-8.
- Placeholder scan: no TBD/TODO or deferred implementation instruction remains; external company decisions are explicit non-implementation constraints, not plan placeholders.
- Type consistency: export/filter/keyring/archive/saver/release manifest interfaces are named once and consumed consistently.
- Commit count: exactly 8 logical commits when each task commits once.
