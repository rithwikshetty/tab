# Activity feed visibility investigation

## Goal

Investigate the current behavior for Activity feed visibility: whether expenses and settlements are visible to all members of the relevant trip/non-group container, whether the actor can see their own additions, and whether unrelated users are protected from data leakage.

## Log

### 2026-06-08 22:53:32 BST

Started by locating app activity-related Swift code, Supabase SQL, RLS policies, and activity notification tests. This touches Supabase activity/RLS behavior, so I am following the Supabase workflow while inspecting the local schema and app sync path first.

### 2026-06-08 23:02:00 BST

Found the primary client-side behavior: `ActivityPresenter.sections` filters out every `ActivityEntity` whose `actorID` matches the current user. This means self-authored expense/settlement activity can exist in the local mirror but will never render in the Activity table. The unread badge separately uses the same actor exclusion, which is appropriate for notifications but currently conflated with feed visibility.

### 2026-06-08 23:06:00 BST

Checked server activity generation. Expense and settlement triggers insert append-only `activity_log` rows for create/update/delete events using the authenticated actor and include a snapshot for offline rendering. This is event-level, not participant-level: a trip expense or settlement creates a trip activity row regardless of whether the current user paid or owed that specific item.

### 2026-06-08 23:10:00 BST

Checked RLS. `activity_log` SELECT is scoped by `private.is_trip_member(trip_id)`, where membership requires a joined `trip_people` row for `auth.uid()`. This should allow all joined members of the same trip/non-group container to read the activity while blocking unrelated users, even if they know one participant elsewhere.

### 2026-06-08 23:14:00 BST

Checked sync timing. The app pulls `activity_log` through `SyncService.pullActivity()` during `pullAll()` with a 90-day/300-row window. `activity_log` is not itself in the realtime publication; realtime changes on expenses/settlements/trip_people for the currently viewed trip trigger `pullAll()`. Opening Activity also triggers `pullAll()`. Local expense/settlement saves call `pushPending()` but do not immediately pull activity afterward.

### 2026-06-08 23:17:00 BST

Checked test coverage. SQL tests cover activity row creation, direct insert denial, and unread counts excluding the actor. I did not find Swift tests for `ActivityPresenter.sections`, so the self-action suppression in the visible Activity table is not covered by presenter tests.

### 2026-06-08 22:56:29 BST

User asked to proceed with a TDD fix and simulator validation. I am adding a presenter-level behavior test first: Activity sections should include the current user's own expense/settlement activity, while unread notification counts should continue to exclude own actions.

### 2026-06-08 22:58:37 BST

RED confirmed on the new presenter test: `ActivityPresenter.sections` returned only the other user's expense row. I changed the feed filtering to sort all activities, while computing `isUnread` only for non-current-user activity. `unreadCount` remains unchanged.

### 2026-06-08 22:59:43 BST

GREEN confirmed on simulator. The focused Activity presenter suite passed with 2 tests, and the full `TabTests` target passed with 34 Swift Testing tests on the booted iPhone 17 simulator.

### 2026-06-08 23:00:20 BST

Simulator app smoke check completed. XcodeBuildMCP built and launched the app successfully; its launch env did not trigger mock auth, so I relaunched the installed app using the documented `SIMCTL_CHILD_TAB_MOCK_AUTH=1` path. The app opened to the Activity tab with seeded rows visible.

### 2026-06-08 23:02:05 BST

Regenerated the ignored Xcode project from `Apps/Tab/project.yml` so the new test file is included through the normal XcodeGen source-of-truth path. Re-ran `xcodebuild test -project Apps/Tab/Tab.xcodeproj -scheme Tab -destination 'id=AEDDE485-459F-47E0-A5DA-65F3CA770D7D' -only-testing:TabTests`; 34 tests passed. `git diff --check` also passed.

### 2026-06-08 23:10:35 BST

User reported a navigation bug from Activity: opening an activity expense/settlement and pressing Back returns to the group/trip screen instead of the Activity feed. Found the cause in `RootView.open`: Activity expense/settlement deep-links intentionally set the stack to `[.trip(tripID), .expense(expenseID)]` or `[.trip(tripID), .settlement(settlementID)]`, so the previous screen is the trip detail. Plan is to route openable Activity expense/settlement rows directly to their detail route and keep trip detail only as the missing/deleted fallback.

### 2026-06-08 23:11:39 BST

Implemented the Activity navigation fix by extracting `ActivityNavigation.stack`: openable expense and settlement activity rows now push only `.expense` or `.settlement`, so Back returns to Activity. Missing/deleted detail rows still fall back to `.trip`. Added `ActivityNavigationTests` for expense direct navigation, expense fallback, and settlement direct navigation. Regenerated the ignored Xcode project with XcodeGen and validated on the booted iPhone 17 simulator: targeted Activity tests passed (5 tests), and full `TabTests` passed (37 tests).

### 2026-06-08 23:21:00 BST

Updated `Apps/Tab/project.yml` `CFBundleVersion` from `7` to `10` at user request. Preparing to stage all current changes, commit, and push to `origin/main`.
