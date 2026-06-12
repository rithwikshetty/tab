# 2026-06-11 — App Store readiness: account deletion (+ domain, SMTP, abuse-guard scoping)

## Goal

The app is going to the App Store for general public use (premise change from
"private friend group"). Agreed scope with Rithwik, in priority order:

1. In-app account deletion — **missing today**, hard rejection under App Store
   guideline 5.1.1(v). This log's main thread.
2. Privacy policy + App Privacy label answers (GitHub Pages hosting).
3. Resend custom SMTP for auth OTP emails (Supabase built-in email is dev-only).
4. Auth abuse protection — Turnstile CAPTCHA + rate limits (user opted in).
5. Cross-provider duplicate-account handling.
6. Contact picker on add-person (CNContactPickerViewController needs no
   permission — verified against Apple docs).

Deferred by user: invite link / QR join.

## 12:00 — Domain decision

"tab" namespace is heavily taken (tabapp.com, gettab.app, mytab.app, tabit.com/.io/.app
all gone). User floated "tabit" — flagged trademark risk: Tabit Technologies is an
established restaurant-payments company. User settled on **gettab.io** ($37.99/yr via
Vercel; purchase is on Rithwik). SMTP task blocked until the domain exists.

## 12:10 — Account deletion design

FK audit: trips.created_by, expenses.created_by/last_edited_by,
settlements.created_by, activity_log.actor_id all reference profiles
**on delete restrict**; profiles.id cascades from auth.users. Net effect: deleting
an auth user is impossible without untangling, by design.

Chosen model (Splitwise-style, defensible under 5.1.1(v) + GDPR):

- **Sole trips** (no other *claimed* member): hard delete — expenses (cascades
  payments/splits), settlements, then trip (cascades trip_people, activity_log,
  categories, mute prefs). Receipt storage paths collected and returned so the
  edge function can delete the objects (storage can't be purged from SQL).
- **Shared trips**: ledger rows stay (they are the group's data). The user's
  claimed trip_people rows get email scrubbed to `deleted-<id>@account-deleted.invalid`;
  user_id/joined_at stay pointing at the ghost profile so FK + join-state
  constraints hold. trip_people.display_name is kept as the ledger label —
  same line Splitwise draws; will be stated in the privacy policy.
- **Pending pre-add rows in other people's trips** (email matches, never claimed)
  are treated as the inviter's address-book data and left alone.
- **Profile becomes a ghost**: display_name 'Deleted user', avatar_url null,
  activity cursor null, deleted_at stamped. To let the profile outlive the auth
  user, the profiles→auth.users FK is **dropped** (destructive baseline rewrite,
  allowed pre-launch). Re-signup with the same email creates a fresh profile;
  scrubbed emails can never re-claim old memberships — deletion is permanent.
- **push_devices + trip_mute_prefs** for the user deleted outright.
- **Auth user** deleted last via admin API from a new `delete-account` edge
  function (JWT-verified, service role). SQL purge function is
  `public.delete_account_data(uuid)`, EXECUTE revoked from public/anon/authenticated,
  granted to service_role only.

App side: `AuthService.deleteAccount()` invokes the edge function then drives the
existing sign-out path (local SwiftData wipe via onSignedOut). SettingsView gets a
Account section with a destructive confirm dialog. No new Swift files — avoids
pbxproj registration.

Tests: new pgTAP suite (deny path: authenticated cannot execute; allow path:
sole-trip purge, shared-trip scrub, ghost profile, device cleanup).

## 13:05 — Account deletion implemented end-to-end

- `supabase/sql/02_profiles.sql`: profiles.id FK to auth.users dropped (ghost
  profiles must outlive the auth user); added profiles.deleted_at. Verified
  purge_soft_deleted_records does NOT touch profiles, so ghosts are safe.
- `supabase/sql/20_account_deletion.sql`: public.delete_account_data(uuid),
  service-role-only. First run hit FK fallout: deleting a sole trip cascades
  trip_people, whose member-left activity trigger inserts a row referencing the
  already-deleted trip. Prod would skip it (auth.uid() null under service role)
  but fixed properly by deleting trip_people explicitly before trips.
- Edge function `delete-account` deployed (verify_jwt=true, v1) to project
  gaseuxsieddlksxtdliq: JWT user → rpc purge → storage receipt cleanup
  (best-effort) → auth.admin.deleteUser.
- App: AuthService.deleteAccount() + SettingsView destructive confirm dialog.
  Mock-auth mode short-circuits to local sign-out. No new Swift files, so no
  pbxproj registration needed.
- pgTAP suite 13_account_deletion.sql (15 assertions, deny + allow paths) —
  all 13 suites green after destructive recreate of the linked DB. iOS app
  builds clean.

Remaining for this item: nothing code-side. Real-device verification of the
full flow (real auth) still worth doing before submission.

## 13:40 — Contact picker, privacy docs, identity-linking finding

- Contact picker shipped in TripPeopleSheet: `CNContactPickerViewController`
  wrapped in a representable, email-property selection only
  (`displayedPropertyKeys = [emails]`, enable-predicate requires an email).
  No Contacts permission involved; picking auto-adds with the contact's name
  passed through `addTripPerson(displayName:)`.
- Privacy policy drafted at `docs/legal/privacy-policy.html` (Sage-styled
  standalone page, support@gettab.io contact, documents the shared-ledger
  deletion semantics). App Privacy label answers at
  `docs/legal/app-store-privacy-labels.md`. Hosting still needs a decision:
  GitHub Pages needs a public repo (or Pro plan for private) — likely a tiny
  separate public repo, or the gettab.io site later.
- Cross-provider duplicates: verified in Supabase docs that Auth automatically
  links identities sharing a verified email to one user. Google/Apple(real
  email)/email-OTP all converge — no code needed. The only duplicate path is
  Apple Hide My Email (different address by design); real fix is the deferred
  invite-link join. Task closed as no-op.
- CLAUDE.md premise updated: public App Store release, gettab.io.
- Full app test suite green: 73/73 (incl. UI tests). pgTAP 13/13 suites.

## Blocked on Rithwik (all external accounts/payments)

1. Buy gettab.io (Vercel domains or Cloudflare/Namecheap).
2. Resend account + API key; then I wire DNS records + Supabase SMTP.
3. Cloudflare Turnstile site/secret keys; then I enable Supabase CAPTCHA +
   add captchaToken to signInWithOTP and tighten rate limits.
4. Decide privacy-policy hosting (public repo for GitHub Pages vs gettab.io
   site) and fill App Store Connect privacy labels from the prepared doc.

## 2026-06-12 — Domain decision revised: tab-it.app

The App Store listing is already named "tab-it", so brand consistency flips the
choice from gettab.io to **tab-it.app** ($9.99/yr, available). Trademark
adjacency to Tabit Technologies now attaches to the brand itself; risk stated
to Rithwik (low-but-not-zero, worst case a dispute-driven rename) and accepted.
Updated CLAUDE.md, privacy policy (app name + support@tab-it.app), and label
doc. Purchase still pending on Rithwik; SMTP task remains blocked on it.

## 2026-06-12 — Domain live, site deployed, SMTP wired end-to-end

- tab-it.app purchased (Vercel registrar, team rithwiks-projects-94097a11).
- Static site (landing + /privacy) in `site/`, deployed to Vercel project
  "tab-it", domain attached: https://tab-it.app live, privacy policy at
  https://tab-it.app/privacy — use that URL in App Store Connect.
- Resend: domain tab-it.app registered (eu-west-1), DKIM/SPF/MX added to
  Vercel DNS via CLI, verified within a minute. Sending-only API key kept as
  the long-lived SMTP credential; a temporary full-access key was used for
  setup and must be deleted by Rithwik.
- Supabase auth config via Management API: custom SMTP smtp.resend.com:465,
  sender auth@tab-it.app "tab-it"; rate_limit_email_sent 2→100/hr;
  mailer_otp_exp 3600→600s. mailer_otp_length already 8 (matches app).
- End-to-end proof: real OTP triggered through /auth/v1/otp, Resend log shows
  "delivered" to rithwik.shetty@gleeds.com.
- Remaining: Turnstile CAPTCHA (blocked on Cloudflare keys), ASC privacy-label
  entry, real-device account-deletion test. Email template subject still the
  Supabase default ("Confirm your email address") — cosmetic polish available.

## 2026-06-12 — Landing page: 5 design options from real app screenshots

- DemoScreenshotSeed added (TAB_SEED_DEMO=1, appended to DebugFriendsSeed.swift,
  wired in RootView): 3 realistic trips (Lisbon EUR / Japan JPY / Flat 23 GBP),
  8 friends, balanced expenses across all categories, a settlement, activity
  feed. ScreenshotTourUITests (in FriendsFlowUITests.swift) walks
  trips → trip detail → expense detail → friends → activity and attaches
  keep-always screenshots; extracted via xcresulttool into site/assets/.
  Gotchas hit: rows are Buttons (label-collapse) not StaticTexts; iOS 18
  SwiftUI tab bar vends no TabBar element; persisted mock store needed an app
  uninstall for the seed's empty-store guard. simctl status_bar override for
  the 9:41 status bar.
- Five committed directions in site/options/ (all with load + scroll
  animations, all using the real screenshots): 1 editorial ledger (Fraunces,
  ruled paper, stamped £0) · 2 sunset travel poster (Bricolage Grotesque,
  rising sun) · 3 dark terminal-fintech (scanlines, paper receipt pricing) ·
  4 corkboard scrapbook (polaroids, Gochi Hand) · 5 Swiss-grid brutalist
  (Archivo, FIG. labels, marquee).
- Floating 1–5 switcher pill (preview-only, arrow keys work) injected into
  every option; options/index.html lists all. Verified in Playwright.
- Awaiting Rithwik's pick → refine → promote to site/index.html → deploy.

## 2026-06-12 — Copy rewrite: plain register, de-AI'd

Rithwik flagged the landing copy as AI-sounding. Researched the telltale
patterns (em dashes, "not X but Y" pivots, punchy fragments, triads, hype
words, overpolished enthusiasm) and rewrote all five options in the opposite
register: short plain sentences, contractions, concrete numbers from the
screenshots, modest claims. Anchor line per Rithwik: "a simple way to keep
track of your amounts". All em dashes removed (only the option-5 TAB—IT
wordmark glyph remains). 54 copy swaps across the five files, verified
rendering in Playwright. Floating 1-5 switcher confirmed working.

## 2026-06-12 — Plain-writing guide + app-wide text sweep

- Reusable guide written at docs/writing/plain-writing-guide.md: the ten AI
  tells, the opposite-direction rules, before/after table from this project,
  and a pre-ship checklist. Project-agnostic so Rithwik can copy it anywhere.
- App strings swept. Most were already plain; fixed: AuthView tagline
  "trip expenses, no friction" → "keep track of shared expenses", dropped
  "secure" from the email-code blurb, "Off — enable in iOS Settings" →
  "Off. Enable it in iOS Settings". The "—" empty-value placeholders in
  expense rows are typographic, not prose; left alone.
- Privacy policy + App Privacy labels doc de-dashed and simplified;
  site/privacy.html re-synced from docs/legal source.
- Live site redeployed: new tagline + privacy page. Design options are also
  publicly reachable at tab-it.app/options (useful for picking on a phone).
- App builds clean after string edits.

## 2026-06-12 — stray gleeds.com test account cleaned up

Rithwik received the SMTP delivery-test email (sent to rithwik.shetty@gleeds.com during
Resend setup) and asked about the mismatch. Auth logs showed Gleeds' email security
scanner opened the magic link, which auto-created an account for that address
(ba8d9cc3, created 06:40 UTC). Deleted it via delete_account_data + profile + auth.users
row. Remaining accounts: rithwikshetty96@gmail.com (Rithwik) and nehanithin0603@gmail.com.
No config change needed — sender auth@tab-it.app is correct.

## 2026-06-12 — landing page final: option 4 promoted to tab-it.app

Rithwik picked option 4 (corkboard scrapbook). Changes while promoting it to
site/index.html: inlined the app logo SVG in header (staggered dot pop-in animation)
and footer, added /assets/favicon.svg (rounded-square app icon), removed the price
card section and its nav link (kept the "it's free, promise" annotation), CTA is now
a non-link badge, hero gets staggered rise-on-load animations, added
prefers-reduced-motion fallback, fixed asset paths to /assets/. Deleted site/options/
entirely and stripped the preview switcher. Verified locally via Playwright, deployed
with vercel deploy --prod (READY), confirmed live: new title at tab-it.app, favicon
200, privacy 200, /options 404.

## 2026-06-12 — landing fixes: relative paths, Fraunces, standard privacy page

Rithwik opened site/index.html via file:// and images broke (absolute /assets/ paths)
and asked for a small font refresh plus a working privacy link. Switched all asset,
favicon, and privacy hrefs to relative paths so the file works opened directly and on
the server (cleanUrls redirects privacy.html → /privacy live). Swapped Domine for
Fraunces (variable, opsz) for headings/body; Gochi Hand stays for scribbles. He also
asked for the privacy policy page in a standard serious style: rewrote
docs/legal/privacy-policy.html as a plain white legal document (system font, plain
headings, no cards), added favicon link, synced to site/privacy.html. Deployed twice,
verified live homepage and /privacy render correctly; only prior console error was the
missing favicon on /privacy, now fixed.

## 2026-06-12 — GitHub links made prominent on landing page

Repo is public (github.com/rithwikshetty/tab). Added the octocat mark as an inline SVG
symbol used three times: nav link with icon, a second hero button "See the code"
(card-white, ink border, rotated opposite to the App Store badge) beside the CTA, and
the footer open-source line. Annotation updated to "it's free, promise. open source
too" (caught and removed an em dash per the plain-writing guide). Deployed and
verified live.

## 2026-06-12 — nav alignment, app-style wordmark, rename tab → tab-it

Fixed nav misalignment (inline-flex GitHub link sat off-baseline; nav is now a
baseline-aligned flex row, octocat icon inline). Header wordmark switched from Gochi
Hand to the app's system-semibold style per Rithwik. Then renamed the product to
"tab-it" in every user-facing surface: CFBundleDisplayName (home screen),
SplashView and AuthView wordmarks, and the send-push fallback title (edge function
redeployed, v4). Internal names left alone on purpose (bundle id, target/scheme,
UserDefaults keys, repo name) until the GitHub repo rename happens. build_sim
SUCCEEDED.

## 2026-06-12 — footer cleanup, repo rename, branded OTP emails, App Store metadata

- Removed the GitHub link from the landing page footer (user request: privacy + email is enough there). Nav and hero GitHub links remain. Deployed.
- User renamed the GitHub repo tab → tab-it. Verified the new URL resolves, updated the local git remote and both remaining site links (nav, hero CTA). Deployed.
- Rebranded the Supabase auth emails via Management API PATCH /config/auth:
  - Magic link (existing users) template still said "roam" — leftover from an old project — and claimed a 60-minute expiry when mailer_otp_exp is 600s. Replaced with a tab-it card (cream bg, sage wordmark, 8-digit code, 10-minute copy).
  - Confirmation (new users) template still contained {{ .ConfirmationURL }} — the exact link the Gleeds email scanner clicked to create the phantom account on 06-11. Now code-only ({{ .Token }}), no link anywhere, so scanners can't auto-confirm accounts.
  - Subjects: "{{ .Token }} is your tab-it sign-in code" / "… sign-up code".
  - Lowered rate_limit_email_sent 100 → 20/hr (the non-Turnstile half of task #5).
- Wrote docs/app-store/metadata.md: name/subtitle/promo/description/keywords (all within ASC char limits, plain-writing compliant, no competitor trademarks), URLs, categories (Finance + Travel), age rating 4+, screenshot spec (6.9" 1320×2868), and App Review sign-in notes (no demo account; Apple sign-in path).
- Note for the internal rename sweep: bundle id stays com.rithwikshetty.tab for now (changing it would mean redoing the Apple App ID, push entitlements, and Sign in with Apple config for zero user-visible gain). Scheme/target/TabCore names are cosmetic and can move whenever.

## 2026-06-12 — fix: debug fixture people contaminated real-auth trips

- User bug report: trip created under Google sign-in lost its expense after re-signing-in with Apple. Diagnosis: cross-provider linking was fine (one auth user, google+apple identities). The culprit was NewTripSheet's DEBUG fixture, which auto-inserted local-only "Alex"/"Sam" into every new trip, on by default even under real auth. The server forbids direct trip_people inserts and sync never pushes people, so the expense's splits referenced members that didn't exist remotely and its push failed forever; the Apple re-login just pulled the server truth (bare trip).
- Fix: fixture now requires mock auth (auth.isUsingMockAuth && !TAB_DISABLE_DEBUG_PEOPLE). Real-auth debug builds behave like production. Removed the dead TAB_UI_TEST_SEED_PEOPLE launch env from PaidByFlowUITests (app never read it).
- Verified: FriendsFlowUITests + PaidByFlowUITests, 6/6 passed on the sim.
