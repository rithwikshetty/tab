# FAB Placement

## 2026-06-06 08:36 BST - Goal

Review the inconsistent primary action placement between the Trips list `+` button and the Trip Detail `Add expense` button. Decide which placement fits the app and apply a focused fix if the implementation has drifted from the design/source-of-truth.

## 2026-06-06 08:36 BST - Findings

The current Git diff does not include SwiftUI placement changes; it is mostly notification SQL and UI test prompt fixes from the existing branch work. The actual button implementations are in `TripListView` and `TripDetailView`, both using the shared `Fab` component.

Apple's current SwiftUI guidance maps semantic primary actions to the trailing navigation bar on iOS, but this app's locked `design/mockups/v1.html` deliberately uses a bottom-trailing FAB pattern. That mockup sets the FAB at `right: 18px; bottom: 100px` for both the Trips list and Trip Detail. SwiftUI currently matches that on the Trips list and diverges on Trip Detail with a `bottom: 24` padding.

## 2026-06-06 08:39 BST - Direction change

The preferred direction is the lower Trip Detail placement, not the raised mockup placement. Updated the shared FAB layout constants so both the Trips list and Trip Detail use the lower bottom-trailing position while keeping a shared scroll clearance.

## 2026-06-06 08:41 BST - Validation

Built and launched the app on the iPhone 17 simulator with mock auth. Verified the Trips list `+` button now sits in the lower position above the tab bar, the Trip Detail `Add expense` button matches that placement, and tapping `Add expense` still pushes to the New Expense screen with the tab bar hidden. `git diff --check` passed.

## 2026-06-06 08:43 BST - Fine tune

Raised the shared lower FAB placement slightly from 24pt to 36pt above the bottom edge, with matching scroll clearance. This keeps the lower placement direction while giving the button more breathing room above the tab bar.

## 2026-06-06 08:49 BST - Standard-pattern adjustment

Checked current Apple and Material guidance. Apple treats primary screen actions as toolbar actions on iOS and keeps tab bars for navigation, but the app's visual language deliberately uses a bottom FAB. For that custom pattern, Material guidance is the closest concrete FAB reference: one promoted action, clear spacing from edges/bottom UI, and enough list padding so content is not blocked. Moved the shared FAB placement to 56pt above the tab bar/content bottom, a deliberate middle ground between the too-low 24/36pt positions and the old high 100pt placement.

## 2026-06-06 08:50 BST - Validation

Rebuilt and relaunched on the iPhone 17 simulator with mock auth. Verified the Trips list and Trip Detail FABs both use the 56pt clearance above the floating tab bar, making the action read as content-level rather than as a tab-bar item. `git diff --check` passed.
