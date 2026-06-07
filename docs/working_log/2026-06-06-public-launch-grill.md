# Public Launch Grill

## Goal

Clarify what it means for Tab to be opened beyond the developer, especially whether the near-term target is friends via TestFlight, an invite-only App Store release, or a broadly public App Store release. Capture resolved domain language and durable launch decisions in project docs as they crystallize.

## 2026-06-06 11:03 BST

Started `grill-with-docs` session. Existing context defines Tab as iOS-first, offline-first, private friend-group use with no monetisation. Existing process docs already cover TestFlight for a small external tester circle and explicitly leave full App Store release out of scope. Current app/backend surface includes Sign in with Apple, email code fallback, Supabase auth/data/storage/realtime, APNs push notification architecture, receipt photos, trip export, RLS, and soft deletes.

## 2026-06-06 11:10 BST

Checked current Apple distribution requirements from Apple Developer docs. Apple Developer Program enrollment can be individual or organization; an individual account can publish apps, but the individual's legal name is shown as seller/developer name. Organization enrollment requires a legal entity, D-U-N-S number, authority to bind the entity, public website, and organization-domain email. External TestFlight supports friends by email or public link after Beta App Review, while full App Store release additionally needs App Store review, app privacy details, privacy policy metadata, and reviewer-ready app/access. Current app Settings screen has sign-out and notification status but no in-app privacy policy link or account deletion flow, both relevant for App Store review.

## 2026-06-06 11:14 BST

User confirmed Apple Developer Program membership is already active, paid yearly. Enrollment itself is not a blocker for TestFlight or App Store distribution; the unresolved distribution question is whether the existing membership is individual or organization, because that controls the public seller/developer name and whether a company is needed for branding/privacy reasons.

## 2026-06-06 11:16 BST

User clarified the desired direction is public availability, not only a private TestFlight circle. Need distinguish public App Store distribution from public/social product scope: existing `CONTEXT.md` says private friend-group use, which can still be compatible with public App Store availability if the product remains invite/email-based and does not add global discovery or stranger-facing features.

## 2026-06-06 11:19 BST

Discussing public name. Apple product-page guidance says app names should be simple, memorable, distinctive, hint at what the app does, avoid generic terms or names too similar to existing apps, and fit the 30-character limit. Current app display name is `tab`; this is clean in-product but likely too generic as the App Store listing name. Candidate direction: keep in-app brand as `Tab`, use a slightly more descriptive App Store name such as `Tab Trips`, with a subtitle explaining the expense-splitting use case.

## 2026-06-06 11:22 BST

User shared Apple membership screenshot showing enrollment type is Individual, with renewal through April 17, 2027. User also expects to publish multiple apps. That shifts the naming question from a single product name to a durable publisher identity: Individual enrollment can still publish multiple public apps, but each public listing is under the individual's legal seller/developer name. An organization account becomes more attractive if the user wants a consistent studio/publisher name across apps.

## 2026-06-06 11:25 BST

Resolved: stay on Individual enrollment, publish under legal name "Rithwik Shetty." No separate brand, studio name, domain, or dedicated email for now. Rationale: zero overhead, no users yet, can add a brand or migrate to Organization enrollment later without losing apps or reviews. Personal email serves as App Store contact and support address.
