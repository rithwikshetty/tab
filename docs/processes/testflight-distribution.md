# Shipping Tab to TestFlight

This is the runbook for getting builds of Tab onto another person's iPhone via TestFlight. It is written for the realistic case Tab cares about: a tiny circle of testers (in practice, one or two people, often abroad), not a public beta. If you ever expand beyond that, the same flow still works — you just add more emails or switch on the public link.

A note on tone: this document tries to be useful rather than exhaustive. Apple's own docs will tell you every checkbox; this one tells you what actually matters, what tripped us up the first time, and what to skip.

## How TestFlight actually works (the mental model)

Apple's TestFlight is a separate app your testers install on their iPhone. When you upload a build of Tab to App Store Connect, you can attach that build to a "group" of testers. Testers in that group see your build appear inside the TestFlight app and tap Install. There is no `.ipa` file to email, no UDID to collect, no Mac required on their side.

There are two flavours of group, and conflating them is the single most common mistake:

- **Internal Testing** is for people on your Apple Developer team — engineers, designers, the account holder. It is gated by Apple Developer roles, not arbitrary email addresses. Builds reach internal testers instantly with no Apple review.
- **External Testing** is for anyone else. You add them by email; they don't need to be on your team. But the *first* build you attach to an external group has to pass a short Apple "beta review" before testers can install it.

Tab's wife-and-friends use case is always External Testing. Internal is only useful for you.

Once a tester accepts an invite, they are bound to the *group*, not to a specific build. From that moment on, every build you attach to that group becomes available to them automatically — they just get a TestFlight notification "new build of Tab available" and tap Update. The invite email or link is reusable forever; nothing in it points to a specific build number.

Builds themselves expire ninety days after upload. That's the only hard ceiling. You will need to upload a fresh build at least every three months even if nothing in the app has changed, or testers will be locked out until you do.

## One-time setup (you only ever do this once)

Before any of the per-build steps make sense, three things have to be true:

1. You are enrolled in the **Apple Developer Program** at developer.apple.com. It costs ninety-nine US dollars a year and identity verification can take a day or two the first time. Without this, nothing else in this document works.
2. You have **signed into Xcode** with the same Apple ID, under Xcode → Settings → Accounts. This is what lets Xcode generate signing certificates and provisioning profiles for you on the fly — modern Xcode handles this automatically as long as you leave "Automatically manage signing" on in the project's Signing & Capabilities tab.
3. You have **registered the app in App Store Connect** at appstoreconnect.apple.com, under My Apps. You pick a name (display only — can change later), a unique bundle identifier that matches `TAB_BUNDLE_ID` in `Apps/Tab/Config/Secrets.xcconfig`, and an SKU. The SKU is purely an internal label for your own records — Apple never shows it to anyone — and any short string is fine.

After that's all done you don't think about it again unless your Apple Developer membership lapses or you start a brand-new app.

## The first build (the painful one)

The first time you ship a build to an external tester, you walk through a lot of forms. They only matter the first time. After this they're cached and you skip them.

Start in Xcode. Open `Apps/Tab/Tab.xcodeproj` and confirm the version and build number in `Apps/Tab/Sources/Tab/Info.plist`. The `CFBundleShortVersionString` is the human-facing version (currently `0.1.0`) and `CFBundleVersion` is the build counter inside that version (start at `1`). Every upload to App Store Connect must have a unique `CFBundleVersion` for a given version string — Apple will reject duplicates.

Change Xcode's run destination at the top of the window from a simulator to **Any iOS Device (arm64)**. You cannot archive against a simulator. Then go to **Product → Archive**. Xcode compiles the release configuration, signs it, packages it as an `.ipa`, and opens the Organizer window when it's done. The first archive of a session takes a couple of minutes; subsequent ones are faster.

In Organizer, pick the archive you just created and click **Distribute App**. Choose **App Store Connect**, then **Upload** (not Export — Export gives you a file on disk, which you don't want). Leave signing on Automatic, click through the summary, and Upload. You'll get a green checkmark and "App upload complete" — that means Apple's servers received the binary, not that it's ready to test yet. Click Done.

Apple then runs the build through a processing pipeline that takes anywhere from ten minutes to about an hour. You'll get an email at your Apple ID address when it's done: either "We have delivered your beta" (good) or "ITMS-xxxx" with an error message (something failed and you'll need to fix it and re-upload).

Once the build is processed, head to App Store Connect → Tab-it → TestFlight tab → Builds → iOS in the left sidebar. The build will be sitting there with a yellow "Missing Compliance" warning. Click **Manage** next to that warning and answer the encryption questions. Tab uses only standard iOS networking and authentication — no custom cryptography — so it qualifies as exempt. Save.

Next, fill out **Test Information** in the left sidebar. There are a few sections:

- **Beta App Description** is a sentence or two telling testers what the app does. One line is plenty.
- **Feedback Email** is your email. This is where TestFlight feedback from testers gets routed.
- **Contact Information** is also you — Apple's reviewer uses it if they have a question about the build. First name, last name, phone, email.
- **Sign-In Information** is for the Apple reviewer. If your build requires sign-in to test anything meaningful, you have to give the reviewer a way in. For Apple Sign-In, Apple reviewers have their own test Apple IDs, so you can usually leave "Sign-in required" unchecked and add a note in the review-notes field saying the app uses Sign in with Apple. If you use email magic link, you have to provide working credentials — a burner Gmail set up as a test account is the easiest path.
- **Privacy Policy URL** is mandatory for external testers. Apple will not approve the build without one. A simple static page on GitHub Pages, Notion, or your own site works fine — the content just needs to genuinely describe what data the app collects and where it goes.

Now create the external group. In the TestFlight tab's left sidebar, under **External Testing**, click the plus icon and name the group something memorable (we use "Family"). This is where the Internal-versus-External pitfall bites — make sure the group lives under External Testing, not Internal. If you accidentally make it Internal you'll see an "add testers" dialog that only shows your own team members and you won't be able to add your wife's email.

Inside the new External group there are two things to do, and the order doesn't matter:

1. Under the **Testers** sub-tab, click the plus icon and add your tester's email address along with their first and last name. They do not need to have an Apple Developer account or be on your team — any Apple ID works.
2. Under the **Builds** sub-tab, click the plus icon and attach the build you just uploaded.

The moment you attach the first build to an external group, App Store Connect prompts you to submit it for Beta App Review. You write a short "What to Test" note (one sentence is fine for an early build), and submit. The build status changes to **Waiting for Review**, which means it's sitting in Apple's queue waiting for a human reviewer. Once a reviewer picks it up, the status moves to **In Review**. When they're satisfied, it moves to **Ready to Test** and your tester gets an email automatically.

Apple's beta review for TestFlight is much lighter than a full App Store review and usually completes within twenty-four hours, often much less. If it gets rejected, the rejection email tells you exactly what to fix — typical reasons are missing privacy policy, app crashes on launch, or the reviewer couldn't sign in.

On the tester's side, all they need to do is install the **TestFlight** app from the App Store using the same Apple ID you invited, then tap the invite link they received. Tab will appear in their TestFlight app and they tap Install.

## Subsequent builds (the easy ones)

Once the first build has been through Beta Review, future builds are dramatically simpler. The Test Information, the privacy policy URL, the external group, the tester list — all of that is sticky. You don't redo it.

The flow becomes: open `Apps/Tab/Sources/Tab/Info.plist`, leave `CFBundleShortVersionString` exactly as it was (`0.1.0`), and bump `CFBundleVersion` by one (so `1` becomes `2`, `2` becomes `3`, and so on). Each upload needs a unique build number within the same version string — Apple rejects duplicates.

Then Archive in Xcode, Distribute → App Store Connect → Upload, and wait for the processing email exactly as before. The new build shows up under TestFlight → Builds. You click Manage on the Missing Compliance prompt — that one does have to be answered for each new build — and save.

Finally, go into your External group's **Builds** sub-tab, click the plus icon, and attach the new build. In the common case, where you've only changed UI, logic, or non-permission code, this build *will not trigger a fresh Beta Review*. It becomes available to your testers instantly. They get a TestFlight notification on their phone saying a new build of Tab is available, and they tap Update.

This is the loop you should expect to spend most of your time in: edit code, bump build number, archive, upload, attach, instant delivery.

There are a few changes that *do* force Apple to re-review even when you've only bumped the build number. Anything that touches privacy or capabilities is a re-review trigger: adding a new permission to Info.plist (camera, photos, location, contacts, notifications), enabling a new entitlement (CloudKit, push notifications, in-app purchase), or adding a new SDK that Apple flags. If you find a build mysteriously stuck in "Waiting for Review" after a build-number-only bump, one of those is usually why.

## When you bump the version (rarer)

When the version string itself changes — say, going from `0.1.0` to `0.2.0` — Apple treats it as a meaningfully new release and requires a fresh Beta Review for the first build of that version. After that one review, subsequent build-number bumps within `0.2.0` go through instantly again.

Use this when you ship a meaningful milestone (new major feature, a release worth marking) and don't otherwise. Iterating fast on `0.1.0` for weeks at a time is fine and is what you should default to during early development.

## What your tester sees

It's worth understanding the experience from the other side, because most questions you'll get from non-technical testers come from confusion at one of these steps:

1. They receive an email from Apple ("you have been invited to test Tab"). The invite is tied to the group, not the build, so it remains valid forever.
2. They install the **TestFlight** app from the App Store on their iPhone, signing in with the same Apple ID you invited.
3. They tap the link in the invite email, which opens TestFlight and shows Tab.
4. They tap Install. Tab installs onto their home screen like any other app, but with a small orange dot next to the icon indicating it's a beta.
5. When you ship a new build, TestFlight shows a small badge and a "new version available" notification. They tap Update inside TestFlight.

You can tell them to install the TestFlight app ahead of time, even before you've submitted a build for review, so they're ready the moment your build is approved.

## Common things that go wrong

**"No Builds Available" on the tester row.** The tester has been added to the group but no approved build is attached to that group yet. Either the build is still in review, or you haven't attached it to the group's Builds sub-tab.

**"Add testers" dialog only shows people on my team.** You're inside an Internal Testing group. Cancel out, scroll down in the sidebar to External Testing, create a group there, and add by email instead.

**"Missing Compliance" warning blocking submission.** Click Manage on the build, answer the encryption questions (Tab is exempt), save. This re-appears on every new build but takes ten seconds.

**Build stuck in "Waiting for Review" for more than a day.** Usually means Apple's reviewer is asking for something — check your email, including spam. Sometimes the queue is just slow over weekends.

**Build rejected.** The rejection email lists the reason. The two most common are "your privacy policy URL is missing or unreachable" and "we were unable to sign in to your app" — both are fixed in Test Information, not in the build itself, so you don't need to re-upload.

**Tester already installed the old build and you've pushed a new one.** Nothing to do. Their TestFlight app will show an Update prompt within a few minutes of the new build being approved. They tap it and the new build replaces the old.

**Ninety-day expiry approaching.** Upload any build — even a no-op rebuild with a bumped build number — before the ninety days are up. Testers will lose access the day the current build expires until a fresh one is uploaded.

## What this document deliberately leaves out

Public TestFlight links (the "share on Twitter" path) — not needed for a private circle.
Internal testing setup beyond mentioning what it is — internal is for you, not for the people you're sharing with.
The full App Store review process for actually releasing Tab to the App Store. That's a different document for a different day.
