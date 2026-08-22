# Board

Board is a native SwiftUI client for `board-api`, the Rust service running on Justin Middler's Ubuntu `board` guest. It links over LAN or Tailscale, presents GitHub issues as a five-column kanban, and starts coding harness jobs on the guest.

The phone never receives a GitHub PAT or vendor CLI credential. It only sends authenticated requests to `board-api`.

![Board showing the mock repository in dark mode](docs/board-simulator.png)

## Requirements

- iOS 18 or newer
- Swift 6
- Xcode 16 or newer
- XcodeGen to regenerate `Board.xcodeproj` from `project.yml`
- A reachable `board-api`, preferably at `http://board.<tailnet>.ts.net:8787`

The app is iPhone-first and remains readable on iPad. It supports light and dark appearances, Dynamic Type, VoiceOver labels, drag and drop, and explicit move actions.

## Build

```sh
xcodegen generate
open Board.xcodeproj
```

Command-line build and test:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project Board.xcodeproj \
  -scheme Board \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The checked-in Xcode project is generated from `project.yml`. Edit the source specification and regenerate instead of hand-editing the project file.

## Link a server

On first launch:

1. Enter the LAN, Tailscale IP, or Tailscale MagicDNS URL for `board-api`.
2. Test `GET /v1/health`.
3. Enter the current eight-character pair code shown on the Ubuntu guest.
4. Pair once. The returned `board_` token and server ID are stored in Keychain.

The base URL is stored in app preferences because it is not a secret. Settings can verify a replacement URL against the linked server ID or forget the local credential. A `401` clears the rejected credential and returns to pairing.

## Network and ATS policy

`Info.plist` enables local networking and has one insecure HTTP exception domain, `ts.net`, including subdomains. `ServerURLValidator` applies the narrower runtime rule:

- HTTPS is accepted.
- HTTP is accepted only for RFC1918 addresses, Tailscale's `100.64.0.0/10` range, and `*.ts.net`.
- Public HTTP, credentials in URLs, paths, query strings, and fragments are rejected.

No broad `NSAllowsArbitraryLoads` exception is present.

## API contract

[`openapi.yaml`](openapi.yaml) is copied byte-for-byte from the Rust `board-api` repository and is the client contract. The app uses these routes:

| Purpose | Route |
| --- | --- |
| Health and pairing | `GET /v1/health`, `POST /v1/pair` |
| Server details | `GET /v1/server` |
| Repositories | `GET /v1/repos` |
| Cards | `GET /v1/cards`, `POST /v1/cards`, `GET /v1/cards/{number}`, `PATCH /v1/cards/{number}` |
| Jobs | `GET /v1/jobs`, `POST /v1/jobs`, `GET /v1/jobs/{id}`, `POST /v1/jobs/{id}/cancel` |
| Job events | `GET /v1/jobs/{id}/events` |

Authenticated requests send `Authorization: Bearer board_...`. Server-sent events are consumed as an asynchronous stream. JSON keys remain camelCase and dates remain ISO 8601.

### Contract gaps handled explicitly

- The API does not return issue comments, so card details state that comments are unavailable.
- Cards do not embed active jobs or pull requests. The app joins cards to `GET /v1/jobs` by repository and issue number.
- The current API statuses are `queued`, `running`, `cancelling`, `cancelled`, `succeeded`, and `failed`. A successful job shows `prUrl` when supplied; the client does not invent `pr_open` or `done` values.
- `/v1/keys` exists in the server contract but is not used by the app. New keys remain a server-side operation.

## Local storage

- `board_` token and server ID: Keychain generic-password item, accessible only when the device is unlocked and not migrated to another device.
- Base URL and first-launch marker: app preferences.
- Last successful card lists: protected JSON files in the app cache directory, excluded from backup.

Cached cards remain readable offline. Creating, moving, running, and cancelling require the server.

## Test support

`MockBoardAPIClient` implements the same protocol and exact JSON model surface for deterministic tests. It is selected only when the app launches with `-board-ui-testing`; production launches always use `BoardAPIClient`.

The automated coverage includes URL policy, OpenAPI model decoding, SSE decoding, Keychain persistence, disk cache persistence, optimistic rollback, repository conflict handling, and a Simulator flow that pairs, creates and moves a card, starts a Codex job, receives an event, cancels, and relaunches with its Keychain credential.
