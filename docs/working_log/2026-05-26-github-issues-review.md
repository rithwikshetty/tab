# GitHub issues review

## 2026-05-26 08:06 WEST
Goal: Check all open GitHub issues and identify the login-related one.

## 2026-05-26 08:07 WEST
Ran `gh issue list --limit 100`; found three open issues: #7, #6, #4. `gh issue view --comments` failed because the current GitHub token is missing `read:project`, so retried with explicit JSON fields that do not require project scope.

## 2026-05-26 08:08 WEST
Reviewed issue details. The login-related issue is #7, "Fix and add more login methods", describing Apple/email identity being set to private relay and requesting additional login methods.

## 2026-05-26 08:45 WEST
Started implementation pass for issue #7: inspect current iOS/Supabase auth, add Google/email/profile handling, and diagnose Apple private relay behavior.

## 2026-05-26 08:49 WEST
Findings: current app only has native Apple sign-in. Supabase is already in use. Auth email is used as the verified membership email, so Apple Hide My Email will legitimately produce an Apple private relay address; database resets do not change Apple/Supabase auth identity state. Implementation direction: keep Supabase Auth, add Google OAuth + email magic link, add custom auth callback URL, and avoid surfacing private relay prefixes as user-facing names/emails.

## 2026-05-26 08:54 WEST
Implemented first pass: Apple remains native, added Supabase Google OAuth and email magic-link entry points, configured app callback URL, handled auth callbacks, and hid Apple private relay emails from user-facing labels/fallback names. Added tests around private relay presentation helpers.

## 2026-05-26 08:54 WEST
First unit-test run failed because pure AuthService presentation helpers inherited MainActor isolation from the observable service. Marked those helpers nonisolated so they remain directly testable and usable as pure logic.

## 2026-05-26 08:56 WEST
Validation passed: `xcodebuild test -project Apps/Tab/Tab.xcodeproj -scheme Tab -destination platform=iOS Simulator,id=B88FE8F5-9E41-47D6-AC8C-2BFA899F551E -only-testing:TabTests` passed 13 app/unit tests. `cd Packages/TabCore && swift test` passed 76 tests.

## 2026-05-26 08:57 WEST
Re-ran app unit tests after cleanup; `xcodebuild ... -only-testing:TabTests` still passes 13 tests.

## 2026-05-26 08:57 WEST
Checked whether Supabase MCP could be used for provider/redirect configuration, but the local MCP connection requires re-authentication. The app-side implementation is complete; Google provider and redirect URL still need Supabase dashboard configuration with provider credentials.

## 2026-05-26 09:09 WEST
User reported the email flow sends a numeric code but the app only told them to check email; this is a real missing production path. Supabase `signInWithOTP` can send either links or `{{ .Token }}` codes depending on the email template, so the app should support code verification with `verifyOTP(email:token:type:.email)` plus resend/change-email handling.

## 2026-05-26 09:11 WEST
Implemented code-based email verification: after sending an email code the app now switches to a 6-digit code entry screen, supports verify/resend/change email, and calls Supabase `verifyOTP(... type: .email)`. Added normalization tests for verification codes.

## 2026-05-26 09:12 WEST
Hardened pending email-name handling so the saved name is only cleared after metadata update succeeds. Re-ran app unit tests; 14 tests pass.

## 2026-05-26 09:17 WEST
User surfaced Supabase Swift runtime warning about initial-session emission. Plan: opt into new behavior via `emitLocalSessionAsInitialSession: true`, explicitly hold auth in loading when the initial local session is expired, attempt a refresh via `client.auth.session`, and avoid treating expired current sessions as real sync sessions.

## 2026-05-26 09:18 WEST
Implemented Supabase initial-session warning fix: configured `emitLocalSessionAsInitialSession: true`, added expired-initial-session refresh handling in AuthService, and made SyncService reject expired current sessions. App unit tests pass: 14 tests.

## 2026-05-26 09:23 WEST
User confirmed Supabase email OTP is 8 digits while app capped/validated 6 digits. Need align client to backend: code field, copy, sanitization, and tests should use 8 digits.

## 2026-05-26 09:24 WEST
Aligned email OTP UI and validation to 8 digits via `AuthService.emailVerificationCodeLength`; updated field cap, copy, error, and tests. App unit tests pass: 14 tests.
