# GitHub issues review

## 2026-05-26 08:06 WEST
Goal: Check all open GitHub issues and identify the login-related one.

## 2026-05-26 08:07 WEST
Ran `gh issue list --limit 100`; found three open issues: #7, #6, #4. `gh issue view --comments` failed because the current GitHub token is missing `read:project`, so retried with explicit JSON fields that do not require project scope.

## 2026-05-26 08:08 WEST
Reviewed issue details. The login-related issue is #7, "Fix and add more login methods", describing Apple/email identity being set to private relay and requesting additional login methods.
