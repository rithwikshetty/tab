# App Store Connect: App Privacy ("nutrition label") answers

Fill these in App Store Connect → App → App Privacy. Answers reflect what the app
actually sends off-device as of 2026-06-11 (Supabase backend, no analytics, no ads,
no tracking SDKs). Re-audit before submission if new data flows are added
(e.g. crash reporting, analytics, CAPTCHA).

## Top-level question

**Do you or your third-party partners collect data from this app?** → **Yes**

## Data types collected

All collected data is **Linked to the user's identity** (it is keyed to their
account) and used **only for App Functionality**. Nothing is used for tracking,
advertising, or analytics. Answer **No** to "Do you use this data for tracking?"
for every type.

| ASC category | ASC data type | What it actually is |
|---|---|---|
| Contact Info | Name | Display name from Apple/Google/email sign-up; names of people added to trips |
| Contact Info | Email Address | Account email (or Apple private relay); emails of people added to trips |
| User Content | Photos or Videos | Receipt photos attached to expenses |
| User Content | Other User Content | Trip names, expense descriptions/amounts, settlements |
| Identifiers | User ID | Supabase account UUID |
| Identifiers | Device ID | APNs push token stored server-side for notifications |

## Explicitly NOT collected (answer No / leave unchecked)

- Health & Fitness, Financial Info (no bank or card data; amounts are user content),
  Location, Sensitive Info, Contacts (the system contact picker shares only the
  single selected email; the address book is never read), Browsing History,
  Search History, Usage Data, Diagnostics, Purchases, Audio Data.

Note on "Contacts": Apple's category means address-book access. tab uses
`CNContactPickerViewController`, which runs out-of-process and returns only the
tapped email. The app has no Contacts permission and cannot read the address
book, so "Contacts" is not collected. The selected email is covered under
Contact Info → Email Address.

## Privacy policy URL

Host `docs/legal/privacy-policy.html` and use that URL, e.g.
`https://tab-it.app/privacy` (or the GitHub Pages URL until the domain is live).

## Account deletion review note

Reviewer-facing note (App Review Information): account deletion is in
Settings → Delete account, available to every signed-in user without contacting
support. This satisfies guideline 5.1.1(v).
