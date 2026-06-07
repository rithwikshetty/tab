## 2026-06-07 09:04 BST

Goal: add a Trips-tab "New expense" button matching the Friends-tab global expense action, without removing the existing top-right new-trip button.

Initial direction: route the new Trips button to the existing `newNonGroupExpense` path so it opens the same people-first flow used by Friends.

## 2026-06-07 09:06 BST

Found the current WIP had moved trip creation into a top trailing toolbar plus and removed the old Trips FAB. Direction for this change: add a separate labeled Trips-tab "Add expense" FAB that reuses the Friends people-first route, and keep trip creation as a header-level plus so the two actions stay distinct.

## 2026-06-07 09:09 BST

Implemented the Trips header row with the trip-create plus beside the "Trips" title, added the bottom labeled "Add expense" FAB on Trips, and routed it through the existing `newNonGroupExpense` path. Added a UI regression test that asserts the Trips header plus is present and the Trips expense FAB opens the people-first picker.

## 2026-06-07 09:10 BST

Validation: `git diff --check` passed. XcodeBuildMCP simulator compile for scheme `Tab` on `iPhone 17` passed with no warnings or errors. Launched the app with mock auth and screenshot-checked the Trips root: title plus header button and the bottom "Add expense" button render as intended. Targeted UI test `TabUITests/FriendsFlowUITests/testTripsAddExpenseOpensPeopleFirstPicker` passed.
