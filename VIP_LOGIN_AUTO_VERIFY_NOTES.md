# VIP Login Auto-Verify Preview — v2

- The app root uses a cold-launch gate so the original 3106 onboarding/content cannot render before the VIP gate is resolved.
- The full VIP login page remains visible during the saved-key check (6 seconds), rather than showing only a spinner.
- If the saved local demo key matches `VIP-DEMO-2026`, the preview advances automatically after the check.
- If there is no saved key, the key field becomes active after the check and the user can activate the local demo key.
- This is a local UI/flow preview only. It is NOT production license security. Real expiry, one-device binding, ban/unban, reseller controls, maintenance control, and automatic online verification require a server API and secure backend.
- Do not put Telegram bot tokens, API secrets, or signing credentials in this app or public repository.
