# gshare protocol v1

Every running gshare app is both a **server** (receives) and a **client** (sends).
All traffic is HTTPS on the local network. Nothing goes to the internet.

## Identity

- On first launch each device generates an RSA-2048 key and a self-signed X.509 certificate.
- **Device ID = SHA-256 of the certificate's DER bytes** (64 hex chars).
- A client never trusts a CA. It accepts a peer's certificate only if its fingerprint equals the ID it expects
  (certificate pinning). During discovery the ID is learned from `/info` and checked against the TLS certificate
  that served it, so a device cannot claim another device's ID.
- **Verification code**: `sha256(sort([idA, idB]).join(':'))`, first 4 bytes as an unsigned int, `% 1_000_000`,
  shown as `123 456`. Both screens show the same code the first time two devices talk, so users can spot a
  man-in-the-middle. After a user ticks "Trust this device", transfers from it can be auto-accepted.

## Discovery

A device is "found" when `GET /api/v1/info` succeeds over TLS and the certificate matches the returned ID.
Candidates come from four sources:

| Source | How | Platforms |
|---|---|---|
| UDP multicast | JSON announce to `239.255.77.77:47821` every 15 s; peers answer by unicast | Android (with multicast lock), Windows, macOS, Linux. Not iOS (needs Apple's multicast entitlement) |
| mDNS / DNS-SD | Service type `_gshare._tcp` (Bonjour / NSD) | Android, iOS, macOS, Windows |
| Subnet scan | Probe `https://x.x.x.1-254:47820/api/v1/info` with 48 parallel workers, 0.9 s timeout | All. This is what finds devices on a hotspot |
| QR / manual | `gshare://connect?ip=a,b&port=47820&id=<fingerprint>` or typed IP | All |

Multicast announce payload:

```json
{ "app": "gshare", "v": 1, "id": "<fingerprint>", "port": 47820, "reply": false }
```

## HTTP API

Base URL: `https://<ip>:<port>/api/v1` (default port **47820**; if busy, the next free one up to +9).

### `GET /info`

```json
{ "id": "<fingerprint>", "name": "Pixel 8", "platform": "android", "port": 47820, "protocol": 1 }
```

### `POST /prepare`

Asks the receiver to accept a transfer. The request is held open until the user answers (max 60 s).

```json
{
  "sender": { "id": "...", "name": "...", "platform": "ios", "port": 47820, "protocol": 1 },
  "items": [
    { "id": "a1b2c3d4", "kind": "file", "name": "IMG_0001.jpg", "size": 2483921, "mime": "image/jpeg" },
    { "id": "e5f6a7b8", "kind": "text", "name": "Text", "size": 12, "mime": "text/plain", "text": "hello there!" }
  ]
}
```

Before asking the user, the receiver calls the sender back on `GET https://<sender ip>:<sender.port>/api/v1/info`
pinned to `sender.id`. If that fails the request is shown as **unverified** and can't be auto-accepted.

| Status | Body | Meaning |
|---|---|---|
| 200 | `{ "sessionId": "...", "tokens": { "<itemId>": "<token>" } }` | Accepted. One token per file item. Text items are already delivered |
| 400 | `{ "error": "..." }` | Malformed request |
| 403 | `{ "error": "declined" }` | User declined or did not answer in 60 s |

### `POST /upload?session=&item=&token=&offset=`

Body: raw bytes of the file starting at `offset`. `Content-Length` = bytes in this request.

| Status | Body | Meaning |
|---|---|---|
| 200 | `{ "received": 123 }` | Bytes stored so far |
| 403 | | Wrong token |
| 404 / 410 | | Session unknown, finished or cancelled by the receiver. Sender stops |
| 409 | `{ "received": 123 }` | Offset does not match what the receiver has. Resume from `received` |
| 413 | | More data than announced |

### `GET /status?session=`

```json
{ "items": { "<itemId>": 123456 } }
```

Bytes stored per file item. Used to **resume** after a dropped connection.

### `POST /finish?session=&item=&token=&sha256=`

The receiver hashes the stored file and compares it with `sha256` (hex).

| Status | Meaning |
|---|---|
| 200 | Verified and moved to the receive folder |
| 409 | Size does not match yet. Resume |
| 422 | Checksum mismatch. Partial file deleted. Sender restarts the item from 0 |

### `POST /cancel?session=`

Cancels the session and deletes partial files.

## Limits and rules

- Max 5,000 items per session. Item IDs must match `^[A-Za-z0-9_-]{1,64}$`.
- File names are reduced to a base name, illegal characters are replaced, and duplicates get ` (1)`, ` (2)` ...
- A receiving session with no activity for 3 minutes is failed and its partial files deleted.
