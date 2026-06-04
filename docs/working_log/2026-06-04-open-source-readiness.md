# Open Source Readiness

## Goal

Prepare the repository for being open sourced by auditing release/deployment contents, especially credentials, local-only files, generated artifacts, and missing public-facing setup guidance. Patch concrete issues in-place where appropriate and validate the resulting tree.

## 2026-06-04 13:13:53 CEST

Started deployment-readiness review. Scope is the local repository intended for public source release: iOS app sources, TabCore Swift package, Supabase SQL/scripts/tests, design assets, docs, and repository metadata. Initial status: tracked working tree is clean; `.env.local` exists locally but is not tracked; `.mcp.json` is tracked and needs inspection because MCP config can accidentally expose private service details.

## 2026-06-04 13:20:00 CEST

Inventory found no CI workflows, Dockerfiles, package manager release manifests, or root README/license. Build inputs are `Apps/Tab/project.yml`, `Packages/TabCore/Package.swift`, Supabase SQL/scripts/tests, and generated local Xcode/SPM outputs. Tracked hidden configs `.codex/config.toml`, `.pi/mcp.json`, and `.claude/settings.json` are redundant with `.mcp.json` and should not be public source inputs. Current app config hardcodes the live Supabase URL and publishable key; scripts and docs also hardcode the live Supabase project ref as a default. Local `.env.local` contains Supabase-related variables but is ignored and not tracked.

## 2026-06-04 13:24:00 CEST

Git history scan found no committed `.env*`, PEM, P12, CER, key, or database URL files. History does contain Supabase project URLs and publishable keys in app config commits. These are not service-role secrets, but they directly tie public source history to the live backend, so current source should be de-personalized and the owner should rotate publishable keys or rewrite history before publishing if that exposure is unacceptable.

## 2026-06-04 13:34:00 CEST

Patched current source for public release: removed hardcoded Supabase URL/key from app config, added ignored local Xcode config with checked-in examples, removed live Supabase project ref defaults from scripts/docs, changed bundle/log defaults to `com.example.tab`, removed tracked hidden agent-local configs, added root setup docs and `.env.example`, expanded `.gitignore` for signing artifacts and local tool state, and neutralized personal test values. Moved the local `.env.local` out of the repository to `../tab.env.local.backup-20260604` and removed ignored generated/local clutter (`.DS_Store`, app/package build folders, Supabase temp state).

## 2026-06-04 13:43:00 CEST

Validated changes with `xcodegen generate`, `cd Packages/TabCore && swift test`, `bash supabase/tests/00_sql_assembly.sh`, XcodeBuildMCP simulator build for the `Tab` scheme, and XcodeBuildMCP simulator tests scoped to `TabTests` with mock auth. All passed. Targeted scans of the current tree no longer find the old live Supabase project ref, Supabase publishable key pattern, old bundle ID, or personal test values. Removed regenerated ignored Xcode/SPM outputs after validation so the repo directory is clean for public source packaging.

## 2026-06-04 13:48:00 CEST

Restored `.env.local` to the repository root for ongoing local development after confirming Git ignores it via `.gitignore`. The file remains excluded from source control; only `.env.example` is intended for public source.

## 2026-06-04 13:55:00 CEST

Rechecked Git history for critical credential patterns before deciding whether to rewrite history. No committed `.env*`, private key/cert/provisioning files, DB URLs, service-role keys, Supabase secret keys, GitHub/OpenAI/AWS-style tokens, or similar critical secrets were found. Historical matches remain limited to Supabase project metadata and publishable keys in app config/docs/scripts.

## 2026-06-04 14:02:00 CEST

Added an MIT `LICENSE` using the standard SPDX MIT license text and updated the README license section. User chose to keep Git history despite historical Supabase project metadata/publishable key exposure, then push and make the GitHub repository public.
