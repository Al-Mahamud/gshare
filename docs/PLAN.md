# gshare plan

**Goal:** a Flutter app for Android, iOS, Windows, macOS and Linux that sends files, photos, videos and text
directly between devices on the same Wi-Fi, or over a hotspot when there is no Wi-Fi. No internet, no accounts.

**Decisions:** Flutter · desktop included · own protocol (see `PROTOCOL.md`) · hotspot included · local only, no accounts.

Status: `[x]` written in this repo, `[ ]` to do. The Android build compiles (Flutter 3.47, 2026-10-22); not yet tested on a device.

## Phase 0: Proof of concept

- [x] Project structure, protocol spec
- [x] Run `tool/setup.ps1` / `tool/setup.sh`, fix any compile errors (Android)
- [ ] Test Android ↔ iOS, Android ↔ Windows on home Wi-Fi, office Wi-Fi and a hotspot

## Phase 1: MVP

- [x] Self-signed identity, certificate pinning, verification code
- [x] HTTPS server: `info`, `prepare`, `upload`, `status`, `finish`, `cancel`
- [x] Discovery: UDP multicast + mDNS + subnet scan + QR + manual IP
- [x] Send: pick files, photos/videos, text → tap a device
- [x] Receive: accept/decline dialog with code, progress, save to folder
- [x] Transfers list with progress, cancel, open file, copy text

## Phase 2: Reliability

- [x] Streamed chunked I/O (no whole file in memory)
- [x] Resume after a dropped connection (`/status` + offset), 4 attempts with backoff
- [x] SHA-256 check on every file
- [x] Android foreground service while transferring
- [x] Idle receive sessions cleaned up after 3 min
- [ ] iOS: `beginBackgroundTask` so a transfer can finish when the app is briefly backgrounded
- [ ] Send several files in parallel (currently sequential)

## Phase 3: Security and trust

- [x] Pinned TLS, sender callback verification, trusted-device list, auto-accept for trusted devices
- [ ] Rate-limit `/prepare` per IP
- [ ] Optional PIN for receiving from untrusted devices

## Phase 4: Hotspot and usability

- [x] Android: in-app hotspot (LocalOnlyHotspot) with Wi-Fi QR code
- [x] iOS / desktop: steps for using the system hotspot
- [x] Android share sheet ("Share to gshare")
- [x] Save received photos/videos to gallery (mobile), other files to Downloads/gshare (Android)
- [ ] iOS Share Extension (needs a new Xcode target and an App Group)
- [ ] Persist transfer history across restarts
- [ ] Desktop: choose receive folder, drag and drop to send
- [ ] Android: join the hotspot in-app with `WifiNetworkSpecifier` instead of the camera

## Phase 5: Release

- [ ] App icons, store listings, privacy texts
- [ ] iOS: request `com.apple.developer.networking.multicast` (optional, enables multicast discovery)
- [ ] Code signing: Windows (MSIX), macOS (notarization)
- [ ] Crash reporting (local-only opt-in)
