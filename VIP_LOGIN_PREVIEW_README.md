# 3106 VIP Login Preview (demo only)

This package adds a local-only SwiftUI login gate to the 3106 source project.

## Demo behavior
- Demo license key: `VIP-DEMO-2026`
- Telegram join link: https://t.me/viphacker999ofc
- In DEBUG builds, Developer Preview Controls can simulate maintenance mode.
- A successful demo activation opens the existing 3106 interface.

## Important security limitation
This is a UI/integration preview only. The demo key is embedded in the app and can be extracted or bypassed. The maintenance switch is local to the app and is not remotely controlled. Do not distribute this build to customers or treat it as license enforcement.

Before production, replace the local demo check with HTTPS API verification, server-side expiry/device binding, and a remotely fetched maintenance status. Keep the Telegram bot token only on the VPS/backend; never embed it in the iOS app.

## Build
Use the repository's existing GitHub Actions workflow `Build unsigned IPA`. It creates an unsigned IPA; signing is still required before installing on a normal iPhone.

## Files changed
- `ThreeOneOSSix/App.swift`: wraps the existing app/onboarding with the preview login gate and adds the preview SwiftUI view.

No existing website repository or files are touched.
