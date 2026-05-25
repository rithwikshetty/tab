# Currency config audit

## 2026-05-25 — Goal
Audit the app's configured currency options and look for configuration mismatches/bugs.

## 2026-05-25 — Findings
Found currency pickers in ExpenseEntryView and SettleUpFormView with the same hardcoded list: EUR, USD, GBP, JPY, CHF. MoneyFormatter supports symbols for those plus SEK/NOK/DKK fallback. Supabase only validates three uppercase letters, not the app picker allowlist.

## 2026-05-25 — Implementation start
User decided to build the end-version direction: centralized all-currency support, symbol+code UI, native/searchable picker, currency-aware formatting/precision, and DB amount scale changes as needed.

## 2026-05-25 — Core currency model
Added TabCore CurrencyCatalog backed by Foundation ISO/common currency metadata, with symbol/name/fraction digits and precision validation. Split/Payment calculators now split at each currency minor unit (JPY 0 decimals, KWD 3, etc.) and reject invalid precision. TabCore tests pass.

## 2026-05-25 — App and database changes
Replaced the hardcoded picker list with a native searchable CurrencyPickerSheet backed by CurrencyCatalog, updated formatter/input placeholders/sanitization for currency-specific fraction digits, switched money displays to code+symbol, and widened Supabase money columns/RPC casts from numeric(14,2) to numeric(20,8). Rebuilt baseline schema and SQL assembly passed.

## 2026-05-25 — Xcode project regenerated
Regenerated Apps/Tab/Tab.xcodeproj with XcodeGen so the new CurrencyPickerSheet source is part of the app target.

## 2026-05-25 — Validation
Validated with `cd Packages/TabCore && swift test`, `./supabase/scripts/build_schema.sh --write && bash supabase/tests/00_sql_assembly.sh`, `cd Apps/Tab && xcodebuild -project Tab.xcodeproj -scheme Tab -destination 'platform=iOS Simulator,name=iPhone 17' build`, and `xcodebuild ... -only-testing:TabTests test`; all passed.

## 2026-05-25 — DB recreation
User requested destructive DB recreation. Supabase MCP required re-auth, so using the repo CLI fallback script.

## 2026-05-25 — DB recreation complete
`./supabase/scripts/recreate_db.sh` completed successfully against the currently linked database.

## 2026-05-25 — Currency defaulting
User wants long-term, low-friction default currency behavior. Direction: layered defaults with trip recent currency, local last selected currency, device region, and INR fallback; avoid DB unless needed.

## 2026-05-25 — TDD currency default cycle 1
RED: Added CurrencyDefaults test for saved local currency beating device region; it failed because defaultCurrency had no injectable defaults/locale. GREEN: added injectable defaults/locale overload and the focused test passed.

## 2026-05-25 — TDD currency default cycle 2
Added behavior test for trip recent active currency beating saved/device defaults. It passed with the current helper implementation, confirming the intended top-priority rule.

## 2026-05-25 — TDD currency default cycle 3
Added behavior test for first-run hard fallback to INR when no trip, no saved currency, and no region currency. It passed.

## 2026-05-25 — TDD currency default cycle 4
Added behavior test for device region currency beating the INR hard fallback. It passed.

## 2026-05-25 — TDD currency default cycle 5
Added behavior test for ignoring deleted and unsupported trip currencies. It passed.

## 2026-05-25 — TDD currency default cycle 6
Added persistence edge test: remembering lower-case codes normalizes them and unsupported values do not overwrite the stored preference. Focused CurrencyDefaults tests pass (7 tests).

## 2026-05-25 — TDD currency default cycle 7
Added a TabCore red test requiring CurrencyCatalog.defaultCode to match the INR hard fallback, then changed the default from EUR to INR. Focused CurrencyCatalog tests pass.

## 2026-05-25 — Currency default UI wiring
Wired ExpenseEntryView and SettleUpFormView to CurrencyDefaults. New forms initialize from saved/device fallback immediately, then apply trip-recent defaults on prepopulate. Currency picker selections and saved expense/settlement currencies are remembered locally. Regenerated the Xcode project and app build passed.

## 2026-05-25 — Validation
Validated with: xcodegen generate; Apps/Tab app build; TabCore swift test (76 tests); App TabTests (10 tests); supabase SQL assembly test. All passed.

## 2026-05-25 — Final validation update
After tying CurrencyDefaults.fallbackCode to CurrencyCatalog.defaultCode, reran CurrencyDefaults focused tests and full TabTests. Both passed.
