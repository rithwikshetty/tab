# tab

tab is an iOS-first expense tracker for group trips. It is a small Splitwise-style app focused on expenses, balances, settlements, receipt storage, and offline-first sync.

## Stack

- iOS 18+, Swift 6, SwiftUI, Observation, SwiftData
- TabCore Swift package for pure money/splitting/balance logic
- Supabase Postgres/Auth/Realtime/Storage for the backend
- Swift Testing and pgTAP

## Local Configuration

The repository does not include live Supabase credentials or project defaults.

1. Copy `Apps/Tab/Config/Secrets.xcconfig.example` to `Apps/Tab/Config/Secrets.xcconfig`.
2. Set `TAB_BUNDLE_ID`, `TAB_AUTH_CALLBACK_SCHEME`, `TAB_SUPABASE_URL`, and `TAB_SUPABASE_PUBLISHABLE_KEY`.
3. Copy `.env.example` to `.env.local` if you need the Supabase scripts, then fill only the variables needed for your workflow.

`Secrets.xcconfig` and `.env.local` are ignored by git.

## Build

Generate the Xcode project from `Apps/Tab/project.yml` with XcodeGen, then open `Apps/Tab/Tab.xcodeproj`.

For simulator testing, use mock auth because Apple Sign-In is unavailable in the simulator:

```bash
SIMCTL_CHILD_TAB_MOCK_AUTH=1 xcrun simctl launch <SIMULATOR_UDID> <BUNDLE_ID>
```

## Tests

```bash
cd Packages/TabCore
swift test

cd ../..
bash supabase/tests/00_sql_assembly.sh
```

## License

MIT. See `LICENSE`.
