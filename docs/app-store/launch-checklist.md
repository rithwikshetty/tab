# tab-it 1.0 launch checklist

State of the App Store launch as of 12 June 2026. The decision: ship 1.0 first,
add features in 1.1+. Update this file as items complete.

## Done (engineering — nothing left here)

- [x] In-app account deletion (guideline 5.1.1(v)), edge function + DB purge, pgTAP tests
- [x] Contact picker in the add-person flow
- [x] Landing page live at https://tab-it.app, mobile-verified, privacy at /privacy
- [x] Custom SMTP via Resend, sender auth@tab-it.app
- [x] Branded sign-in emails, code-only (no clickable link, so corporate mail
      scanners can't auto-create accounts)
- [x] Email rate limit 20/hour
- [x] Cloudflare Turnstile CAPTCHA on email sign-in, enforced server-side,
      verified end to end on a real device
- [x] Cross-provider sign-in linking (Google + Apple, same email, one account)
- [x] User-facing rename to tab-it (display name lives in project.yml)
- [x] App Store icon alpha channel stripped (was causing the placeholder grid
      icon in App Store Connect)
- [x] Debug fixture people restricted to mock auth (were breaking real-auth sync)
- [x] Listing copy written: `docs/app-store/metadata.md`
- [x] App Privacy answers written: `docs/legal/app-store-privacy-labels.md`

## Remaining (Rithwik, in App Store Connect and on device)

- [ ] Fresh archive + upload (Product → Archive, as usual). First build that
      carries the icon fix, the CAPTCHA, and the tab-it name.
- [ ] App Store (Distribution) tab → 1.0 listing: paste every field from
      `docs/app-store/metadata.md` (name, subtitle, promo text, description,
      keywords, URLs, categories, copyright, age rating)
- [ ] App Privacy section: answer from `docs/legal/app-store-privacy-labels.md`,
      privacy policy URL https://tab-it.app/privacy
- [ ] Upload 6.9" screenshots (ask the agent to generate, or take manually at
      1320×2868 on an iPhone 16 Pro Max class simulator)
- [ ] Real-device account-deletion test (Settings → Delete account, then sign
      back in)
- [ ] Select the build on the 1.0 page and Submit for Review
- [ ] Hygiene, non-blocking: delete the temporary full-access Resend API key
      (keep the sending-access one — Supabase SMTP uses it)

## After submission

- Review typically takes 1–2 days for a first app; expect at least one round of
  questions. The review notes suggestion in metadata.md explains the
  no-password sign-in.
- Once live: the pre-launch "destructive DB, no migrations" convention in
  CLAUDE.md flips to compatibility-preserving migrations. Big schema changes
  get harder; plan accordingly when scoping 1.1 features.

## Post-launch backlog (not for 1.0)

- Invite-link / QR trip joining (also the real fix for Apple Hide My Email
  duplicate identities)
- Brandable ideas live in working logs; new feature list TBD with Rithwik
