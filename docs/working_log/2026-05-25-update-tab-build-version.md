# Update Tab build version

Goal: Update `Apps/Tab/project.yml` build version to 5.

## 2026-05-25 11:40:16 BST

Found `CFBundleVersion: "4"` in `Apps/Tab/project.yml`; updating it to `"5"`.

## 2026-05-25 11:40:24 BST

Updated `Apps/Tab/project.yml` so `CFBundleVersion` is now `"5"`. No tests run; config-only change.

## 2026-05-25 11:43:32 BST

Screenshot still showed build 4 because the app target uses the checked-in `Apps/Tab/Sources/Tab/Info.plist` at build/runtime. `project.yml` is XcodeGen input and does not update the existing plist automatically. Updated `Info.plist` to `5` as well.
