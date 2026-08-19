# Account Lifecycle and Session Security Implementation Plan

> 执行状态（2026-08-18）：本地实现和 SQLite/PostgreSQL/Redis/Mailpit/Windows/Android 验收已完成；远端 CI 因本阶段未获 push 授权而未运行，最终状态为 PASSED WITH WARNINGS。真实命令、数量和产物见 `docs/account-lifecycle-security-validation-report.md`。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver secure account invitation, password recovery, account administration, per-device sessions with immediate JWT revocation, Flutter security/admin flows, Mailpit development email, and foundational cross-platform CI.

**Architecture:** Extend the existing `accounts` Django module and the existing Flutter ApiClient/AuthSessionStore/router. Security mutations live in focused transactional services; JWT `sid` binds Access/Refresh tokens to `AccountSession`; one-time invitation/reset codes are stored only as HMAC digests. CI and local scripts execute the same SQLite, PostgreSQL, OpenAPI, Flutter, build, Compose, and repository-safety commands.

**Tech Stack:** Python 3.12, Django 5.2, DRF, SimpleJWT 5.5.1, PostgreSQL 17, Redis 8, Mailpit 1.30.7, Flutter 3.47.0/Dart 3.13, Riverpod, go_router, Dio, GitHub Actions.

**Spec:** `docs/decisions/ADR-0005-account-lifecycle-session-security.md`

## Global Constraints

- Work only on `feature/account-lifecycle-security`, created from `origin/main` at `d64b122`.
- Preserve and never stage `docs/environment-configuration.md`.
- Keep one User, JWT stack, ApiClient, TokenStorage, AuthSessionStore, router, Riverpod graph, AuditEvent, and permission system.
- Support only Windows and Android; create no iOS/Web/macOS/Linux files.
- Store no raw invitation/reset token, password, JWT, Authorization header, email body, production secret, or real employee data.
- Do not modify existing migrations; do not reset/flush/drop databases or remove Docker volumes.
- Every behavior change follows red → verified failure → minimal implementation → green.
- Make 5–8 logical local commits; do not push or create a PR.

---

### Task 1: Account Models, Email Constraint, Password and Token Primitives

**Files:**
- Modify: `backend/modules/accounts/models.py`
- Create: `backend/modules/accounts/migrations/0002_account_lifecycle_security.py`
- Create: `backend/modules/accounts/security_tokens.py`
- Create: `backend/modules/accounts/password_validation.py`
- Modify: `backend/config/settings/base.py`
- Modify: `backend/config/settings/test.py`
- Test: `backend/tests/test_account_security_models.py`
- Test: `backend/tests/test_account_password_policy.py`

**Interfaces:**
- Produces: `normalize_account_email(value: str) -> str`
- Produces: `generate_one_time_token(purpose: str) -> tuple[str, str]`
- Produces: `digest_one_time_token(purpose: str, raw_token: str) -> str`
- Produces: `validate_account_password(password: str, *, user: User, employee: Employee | None) -> None`
- Produces models `AccountInvitation`, `PasswordResetChallenge`, `AccountSession` defined by ADR-0005.

- [ ] **Step 1: Write model and primitive failure tests**

Add tests proving non-empty email is normalized/lowercase and case-insensitively unique, blanks repeat, raw one-time codes are never stored, digests differ by purpose, AccountInvitation rejects system_admin role, and AccountSession stores only safe metadata.

- [ ] **Step 2: Run red tests**

Run: `backend\.venv\Scripts\python.exe -m pytest backend/tests/test_account_security_models.py backend/tests/test_account_password_policy.py -q`

Expected: collection/assertion failures because models and helpers do not exist.

- [ ] **Step 3: Implement models and helpers**

Use `UniqueConstraint(Lower("email"), condition=~Q(email=""), name="accounts_user_email_ci_unique")`; HMAC-SHA256 with purpose domain separation; `secrets.token_urlsafe(32)`; Django password validators with minimum length 12 and an account-context similarity validator.

- [ ] **Step 4: Create migration without editing 0001**

Generate then inspect `0002_account_lifecycle_security.py`; dependencies must include accounts 0001 and employees 0001. Run `sqlmigrate` for PostgreSQL review.

- [ ] **Step 5: Verify green and migration state**

Run:

```powershell
backend\.venv\Scripts\python.exe -m pytest backend/tests/test_account_security_models.py backend/tests/test_account_password_policy.py -q
backend\.venv\Scripts\python.exe backend/manage.py makemigrations --check --dry-run --settings=config.settings.test
```

### Task 2: Session-aware Login, Refresh and Authentication

**Files:**
- Create: `backend/modules/accounts/sessions.py`
- Create: `backend/modules/accounts/authentication.py`
- Modify: `backend/modules/accounts/serializers.py`
- Modify: `backend/modules/accounts/views.py`
- Modify: `backend/modules/accounts/tokens.py`
- Modify: `backend/config/settings/base.py`
- Test: `backend/tests/test_account_sessions.py`
- Test: `backend/tests/test_token_lifecycle.py`
- Test: `backend/tests/test_auth_api.py`

**Interfaces:**
- Produces: `issue_session_tokens(user, *, platform, client_name, app_version) -> IssuedSessionTokens`
- Produces: `rotate_session_refresh(raw_refresh: str) -> dict[str, str]`
- Produces: `revoke_session(session, *, reason: str) -> bool`
- Produces: `revoke_all_account_sessions(user, *, reason: str, exclude_sid: UUID | None = None) -> int`
- Produces: `SessionJWTAuthentication(JWTAuthentication)`.

- [ ] **Step 1: Write sid lifecycle tests**

Cover username/email login, identifier/username mutual exclusion, session creation, shared sid claims, rotation preserving sid, JTI mismatch/replay, missing sid rejection, revoked Access immediate 401, last_seen five-minute throttle, logout/logout-all session revocation, and cross-user isolation.

- [ ] **Step 2: Run red tests**

Run: `backend\.venv\Scripts\python.exe -m pytest backend/tests/test_account_sessions.py backend/tests/test_token_lifecycle.py backend/tests/test_auth_api.py -q`

Expected: failures for absent AccountSession and sid.

- [ ] **Step 3: Implement issuance and refresh**

Login resolves identifier securely, creates AccountSession in `transaction.atomic()`, issues Refresh via SimpleJWT, writes sid to Refresh so derived Access shares it, and stores current JTI. Refresh locks Session, checks current JTI, delegates rotation/blacklist semantics, then persists the new JTI.

- [ ] **Step 4: Implement authentication and logout**

`SessionJWTAuthentication.get_user()` calls the parent then validates sid/session and conditionally updates last_seen. Logout uses `request.auth["sid"]`; logout-all revokes every AccountSession and blacklists outstanding refresh records.

- [ ] **Step 5: Verify focused and legacy tests**

Run the three focused files and `backend/tests/test_directory_api.py` to prove protected directory APIs still work with new tokens.

### Task 3: Invitation, Password Recovery, Mail and Throttling

**Files:**
- Create: `backend/modules/accounts/notifications.py`
- Create: `backend/modules/accounts/throttles.py`
- Create: `backend/modules/accounts/invitation_services.py`
- Create: `backend/modules/accounts/password_services.py`
- Create: `backend/modules/accounts/invitation_serializers.py`
- Create: `backend/modules/accounts/password_serializers.py`
- Create: `backend/modules/accounts/invitation_views.py`
- Create: `backend/modules/accounts/password_views.py`
- Modify: `backend/modules/accounts/urls.py`
- Modify: `backend/config/settings/base.py`
- Modify: `backend/config/settings/development.py`
- Modify: `backend/config/settings/test.py`
- Modify: `backend/requirements/base.txt`
- Test: `backend/tests/test_account_invitations.py`
- Test: `backend/tests/test_password_recovery.py`
- Test: `backend/tests/test_auth_throttling.py`
- Test: `backend/tests/test_account_notifications.py`

**Interfaces:**
- Produces: `AccountNotificationService.send_invitation(...)` and `.send_password_reset(...)`.
- Produces: `create_invitation`, `resend_invitation`, `revoke_invitation`, `accept_invitation` transactional services.
- Produces: `request_password_reset`, `confirm_password_reset`, `change_password` services.
- Consumes Task 1 token/password helpers and Task 2 session revocation.

- [ ] **Step 1: Write invitation and password red tests**

Cover the complete matrices from the user spec, including 401/403, active/unlinked Employee constraints, email/username uniqueness, one-time/expired/revoked codes, resend invalidation, generic 202 enumeration protection, password policy, session revocation, transaction rollback, and no token/password leakage.

- [ ] **Step 2: Write throttle red tests**

Assert exact rates, reset-request generic 202 while suppressed, Redis-compatible cache behavior, and HMAC cache keys that do not contain raw identifiers.

- [ ] **Step 3: Implement service boundaries and serializers/views**

Views validate HTTP shape and permissions only. Services lock rows and write AuditEvent in the same transaction. Notification service uses Django `EmailMessage` and never logs bodies.

- [ ] **Step 4: Configure cache/email safely**

Add `redis>=6,<7`; base cache uses `django.core.cache.backends.redis.RedisCache`; test overrides LocMem; development SMTP reads safe environment values with Mailpit defaults; production retains environment-controlled backend.

- [ ] **Step 5: Verify focused suite and mail outbox**

Run the four focused files; assert locmem outbox counts/recipient/purpose without snapshotting raw message bodies or codes.

### Task 4: Account Administration, RBAC and Audit Expansion

**Files:**
- Create: `backend/modules/accounts/account_services.py`
- Create: `backend/modules/accounts/account_serializers.py`
- Create: `backend/modules/accounts/account_views.py`
- Create: `backend/modules/accounts/session_serializers.py`
- Create: `backend/modules/accounts/session_views.py`
- Modify: `backend/modules/accounts/urls.py`
- Modify: `backend/modules/accounts/rbac.py`
- Modify: `backend/modules/accounts/admin.py`
- Modify: `backend/modules/audit/models.py`
- Modify: `backend/modules/audit/services.py`
- Test: `backend/tests/test_account_admin_api.py`
- Test: `backend/tests/test_session_api.py`
- Test: `backend/tests/test_account_security_audit.py`
- Test: `backend/tests/test_rbac.py`

**Interfaces:**
- Produces account list/detail/PATCH and activate/deactivate/change-role/revoke-sessions APIs.
- Produces current-user session list/revoke/revoke-others APIs.
- Consumes Task 2 revocation and Task 3 invitation state.

- [ ] **Step 1: Write account/session permission and lifecycle tests**

Use parameterized anonymous/employee/hr_admin/system_admin tests. Prove self-deactivate, superuser/system_admin targets, system_admin role grant, departed activation, cross-user session IDs and unmanaged fields are rejected safely.

- [ ] **Step 2: Write audit red tests**

Assert each new success action, idempotent non-duplication, failed transaction rollback, append-only behavior, and recursive absence of token/password/JTI/body keys.

- [ ] **Step 3: Extend RBAC and capabilities**

Grant account/invitation permissions only to system_admin while preserving HR directory permissions. `/me/` adds six stable capabilities derived from permissions/authentication.

- [ ] **Step 4: Implement services and HTTP views**

Account PATCH exposes only email. Explicit actions own is_active/role/session changes. Account and invitation serializers never expose password, token_digest, JTI, or email body.

- [ ] **Step 5: Run backend security regression**

Run all Task 4 tests plus existing audit/RBAC/directory tests.

### Task 5: Backend OpenAPI and Full Dual-database Gate

**Files:**
- Modify: `backend/tests/test_schema.py`
- Modify: `docs/api-conventions.md`
- Modify: `docs/security-baseline.md`

**Interfaces:**
- Produces a warning-free schema for every new endpoint and explicit 202/204/400/401/403/404/409/429 responses.

- [ ] **Step 1: Add schema contract tests**

Assert every route/method, public security declaration, request/response component, no secret fields, and session/account pagination/filter parameters.

- [ ] **Step 2: Run schema test red, then annotate serializers/views**

Use `extend_schema` with concrete serializers; do not use generic `dict` fallbacks.

- [ ] **Step 3: Run SQLite full suite**

Run Ruff, Django check, migration check, OpenAPI strict generation, then `python -m pytest -q` and record the new count.

- [ ] **Step 4: Run PostgreSQL full suite**

Use Compose test settings with `TEST_DATABASE_ENGINE=postgresql` and `EXPECTED_DATABASE_VENDOR=postgresql`; record the new count and fix PostgreSQL-only lock/constraint behavior before proceeding.

### Task 6: Mailpit Development Infrastructure

**Files:**
- Modify: `deploy/docker-compose.dev.yml`
- Modify: `.env.example`
- Test: `backend/tests/test_email_settings.py`

**Interfaces:**
- Produces SMTP `mailpit:1025`, UI `127.0.0.1:8025`, no Mailpit volume.

- [ ] **Step 1: Add settings/Compose failure tests**

Assert test backend is locmem, development defaults are SMTP/Mailpit, production requires explicit email configuration, UI host binding is loopback, and no volume is declared.

- [ ] **Step 2: Add pinned Mailpit service**

Use `axllent/mailpit:v1.30.7`, SMTP healthcheck, `restart: unless-stopped`, and API dependency only when mail health is not required for API startup.

- [ ] **Step 3: Rebuild and validate**

Run `docker compose ... config --quiet`, `up -d --build`, PostgreSQL SELECT 1, Redis PING, API health, Mailpit health/API, and send two `.invalid` messages through Django. Inspect counts only; do not print bodies/codes.

### Task 7: Flutter Public Recovery and Login Flows

**Files:**
- Modify: `apps/employee_app/lib/features/authentication/data/auth_repository.dart`
- Modify: `apps/employee_app/lib/features/authentication/presentation/auth_controller.dart`
- Modify: `apps/employee_app/lib/features/authentication/presentation/login_page.dart`
- Create: `apps/employee_app/lib/features/account_security/data/account_security_repository.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/recovery_controller.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/accept_invitation_page.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/forgot_password_page.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/reset_password_page.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/password_fields.dart`
- Modify: `apps/employee_app/lib/core/network/api_endpoints.dart`
- Modify: `apps/employee_app/lib/app/router/app_router.dart`
- Test: matching files under `apps/employee_app/test/features/account_security/` and authentication tests.

**Interfaces:**
- Login becomes `login(identifier:, password:)` and sends safe client metadata.
- Produces public repository methods `acceptInvitation`, `requestPasswordReset`, `confirmPasswordReset`.

- [ ] **Step 1: Write repository/controller/widget red tests**

Cover username/email login, generic errors, public route guards, password hints, mismatch, duplicate-submit prevention, success navigation, error input retention and sensitive field clearing.

- [ ] **Step 2: Implement repository/controller**

Use existing ApiClient with `authenticated:false`; map server errors to safe Chinese Failure values.

- [ ] **Step 3: Implement pages and routes**

Public pages remain accessible while unauthenticated; authenticated users are warned before invitation acceptance and never auto-switch accounts.

- [ ] **Step 4: Run focused Flutter tests and analyze**

Run account-security/auth/router tests, `dart format`, and the project ASCII-junction analyze helper.

### Task 8: Flutter Security Settings and Sessions

**Files:**
- Create: `apps/employee_app/lib/features/account_security/data/account_session.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/security_settings_page.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/session_controller.dart`
- Create: `apps/employee_app/lib/features/account_security/presentation/session_list_page.dart`
- Modify: `apps/employee_app/lib/features/shell/presentation/adaptive_shell.dart`
- Modify: `apps/employee_app/lib/app/router/app_router.dart`
- Test: `apps/employee_app/test/features/account_security/security_settings_page_test.dart`
- Test: `apps/employee_app/test/features/account_security/session_list_page_test.dart`

**Interfaces:**
- Repository methods: `changePassword`, `fetchSessions`, `revokeSession`, `revokeOtherSessions`.
- Revoking current session or changing password calls AuthController local clear and redirects login.

- [ ] **Step 1: Write four-state/session-action red tests**

Cover loading/empty/error/data, current badge, wide table/mobile cards, confirmations, revoke-other retention, current revoke logout, password success logout and 403/409 mapping.

- [ ] **Step 2: Implement controller and pages**

Widgets call controllers only; controllers invalidate providers and coordinate AuthController.

- [ ] **Step 3: Run focused tests and full Flutter regression**

Ensure all existing 66 tests remain and record the new count.

### Task 9: Flutter system_admin Account and Invitation Management

**Files:**
- Create: `apps/employee_app/lib/features/accounts/data/account.dart`
- Create: `apps/employee_app/lib/features/accounts/data/account_repository.dart`
- Create: `apps/employee_app/lib/features/accounts/presentation/account_controller.dart`
- Create: `apps/employee_app/lib/features/accounts/presentation/account_list_page.dart`
- Create: `apps/employee_app/lib/features/accounts/presentation/account_detail_page.dart`
- Create: `apps/employee_app/lib/features/accounts/presentation/invitation_form_page.dart`
- Modify: `apps/employee_app/lib/features/authentication/data/current_user.dart`
- Modify: `apps/employee_app/lib/features/authentication/presentation/auth_session_store.dart`
- Modify: `apps/employee_app/lib/app/router/app_router.dart`
- Modify: `apps/employee_app/lib/features/shell/presentation/adaptive_shell.dart`
- Test: matching repository/controller/widget/router tests.

**Interfaces:**
- Account repository supports list/detail/email update/activate/deactivate/change role/revoke sessions and invitation list/create/resend/revoke.
- capabilities add six fields, missing values default false.

- [ ] **Step 1: Write capability and repository red tests**

Assert system_admin entries only, employee/hr_admin hidden and deep-link redirected, serializers omit codes/digests, and role options exclude system_admin.

- [ ] **Step 2: Write form/action widget red tests**

Cover filters/pagination, four states, confirmations, 409/403, duplicate submit, retained input, successful invalidation and PopScope.

- [ ] **Step 3: Implement feature-first layers**

Reuse existing responsive breakpoint 900 and shared unsaved guard; wide layouts use table/panel, mobile layouts use cards/forms.

- [ ] **Step 4: Run full Flutter suite**

Run format/analyze/test and record the new count without skips.

### Task 10: CI and Local Repository Safety

**Files:**
- Rewrite: `.github/workflows/ci.yml`
- Create: `scripts/repository-safety.ps1`
- Modify: `scripts/check.ps1`
- Create: `docs/ci.md`
- Test: `backend/tests/test_ci_contract.py`

**Interfaces:**
- Produces jobs `backend-sqlite`, `backend-postgresql`, `flutter-quality`, `android-build`, `windows-build`, `repository-safety`.
- Produces `scripts/repository-safety.ps1` with nonzero exit on forbidden tracked files/private-key headers/build artifacts.

- [ ] **Step 1: Write CI contract red tests**

Parse YAML as text/structured YAML where available and assert triggers, concurrency, permissions, versions, service health, job commands, full Action SHAs and no artifact upload on PR.

- [ ] **Step 2: Implement pinned workflow**

Use ADR SHAs with release comments, Python 3.12, Flutter 3.47.0, JDK 21, PostgreSQL 17 and Redis 8. Use only test credentials.

- [ ] **Step 3: Implement local safety/check orchestration**

Extend `check.ps1` to run migration check, SQLite pytest, OpenAPI strict, PostgreSQL pytest, Compose config and repository safety while preserving native exit codes.

- [ ] **Step 4: Validate workflow locally**

Run every job command locally. If `actionlint` is absent, record `NOT RUN`; do not install globally. Confirm YAML parsing and safety tests pass.

### Task 11: Existing PostgreSQL Upgrade and Real Security Integration

**Files:**
- Create: `backend/tests/integration/test_account_security_flow.py`
- Modify: `apps/employee_app/integration_test/employee_directory_real_test.dart` or create `account_security_real_test.dart`
- Create: `docs/account-lifecycle-security-validation-report.md`

**Interfaces:**
- Produces end-to-end evidence without returning codes through normal APIs.

- [ ] **Step 1: Re-audit existing data and apply migration**

Check duplicate normalized emails again, apply migrations without fake/flush/drop, run sync_rbac twice, and prove original counts/data remain.

- [ ] **Step 2: Run Mailpit invitation/reset closure**

Create process-only fictional system_admin and Employee with `.invalid` email; use ordinary API to create invitation/reset; retrieve codes only from Mailpit test interface in the validation harness; accept/use once; verify second use fails; redact values from output.

- [ ] **Step 3: Run session/account lifecycle closure**

Create two sessions, revoke one and prove old Access immediately 401; reset password and prove old password/session fail; deactivate/activate account and verify Access/relogin rules. Cleanup leaves validation users inactive and all sessions revoked; no physical deletion.

- [ ] **Step 4: Run Windows and Android shared integration**

Use process-only credentials/codes, no repository secrets. Both platforms execute the same security routes and server behavior.

### Task 12: Final Dual-platform Build, Documentation and Commits

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/development.md`
- Modify: `docs/security-baseline.md`
- Modify: `docs/api-conventions.md`
- Modify: `docs/OPEN_DECISIONS.md`
- Complete: `docs/account-lifecycle-security-validation-report.md`

**Interfaces:**
- Produces final PASSED WITH WARNINGS report in the exact 16-section format from the user specification.

- [ ] **Step 1: Run final unified gate**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1`; require exit 0 and record new Flutter/SQLite/PostgreSQL counts.

- [ ] **Step 2: Build and validate Windows**

Use process-only `TrackFileAccess=false` only if reproduced. Record EXE absolute path, bytes, full SHA-256, PID, nonzero window handle, Responding, normal close and real account-security flow.

- [ ] **Step 3: Build and validate Android**

Use real-user persistent Gradle/Pub paths, no proxy/offline/isolated cache. Record APK absolute path, bytes, full SHA-256, install Success, boot=1, PID, foreground MainActivity, FATAL=0 and real flow.

- [ ] **Step 4: Update docs and security scan**

Document old sid-less Token invalidation, email distinction, generic reset response, Mailpit-only development, CI not remotely run, limitations and next phase. Scan staged diff for passwords/codes/tokens/private keys and prohibited files.

- [ ] **Step 5: Create 5–8 logical local commits**

Recommended messages:

```text
docs: define account lifecycle and session security
feat(security): add session-aware JWT authentication
feat(backend): add account invitation and password recovery
feat(backend): add account lifecycle administration
feat(app): add account security and recovery flows
ci: add cross-platform quality and build workflows
test(docs): validate phase three across real environments
```

Before every commit inspect status/diff/staged diff and explicitly exclude `docs/environment-configuration.md`, `.env`, build outputs, Mailpit data and all credentials. Do not push or create a PR.

## Completion Criteria

- Every endpoint, permission, lifecycle transition, one-time code and session revocation behavior in ADR-0005 has automated coverage on SQLite and PostgreSQL.
- Existing 75 backend and 66 Flutter tests remain; new totals are recorded from actual runs.
- Mailpit, Redis throttling, Windows and Android real flows pass without leaking code/password/Token/JTI.
- CI commands pass locally; remote Actions are explicitly NOT RUN because push is unauthorized.
- 5–8 local commits exist on `feature/account-lifecycle-security`; tracked worktree is clean and only `docs/environment-configuration.md` remains untracked.
