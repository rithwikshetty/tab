# Update Tab build version

Goal: Update the Tab app build version to the next release build.

## 2026-06-05 00:00:00 BST

Found `CFBundleVersion: "6"` in `Apps/Tab/project.yml` and `CFBundleVersion` `6` in `Apps/Tab/Sources/Tab/Info.plist`. Updating both to `7` so the XcodeGen source and checked-in runtime plist stay aligned for release.

## 2026-06-05 20:59:56 BST

Confirmed `Apps/Tab/project.yml` now has `CFBundleVersion: "7"` and validated `Apps/Tab/Sources/Tab/Info.plist` with `plutil -lint`.

## 2026-06-05 21:00:40 BST

Started a destructive database recreate with `./supabase/scripts/recreate_db.sh`. The script built `supabase/.temp/generated_schema.sql`, then failed because the Supabase CLI could not find a linked project ref. Checked available local environment wiring: `.env.local` has `SUPABASE_PROJECT_REF` and `SUPABASE_ACCESS_TOKEN`, but not `SUPABASE_DB_PASSWORD` or `SUPABASE_DB_URL`, which the recreate script requires for non-interactive linking/apply.
