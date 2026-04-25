# @cappitolian/http-local-server-swifter

[![npm version](https://img.shields.io/npm/v/@cappitolian/http-local-server-swifter)](https://www.npmjs.com/package/@cappitolian/http-local-server-swifter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Capacitor 7](https://img.shields.io/badge/Capacitor-7-blue)](https://capacitorjs.com/)

A Capacitor plugin that embeds a real HTTP server directly on your device — powered by **NanoHTTPD** on Android and **Swifter** on iOS. It allows you to receive and respond to HTTP requests from the JavaScript layer, enabling local peer-to-peer communication between devices on the same network without a cloud backend.

---

## Table of Contents

- [Installation](#installation)
- [Platform Configuration](#platform-configuration)
- [Usage](#usage)
- [Security](#security)
- [Architecture](#architecture)
- [API Reference](#api-reference)
- [Platform Support](#platform-support)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [License](#license)

---

## Installation

```bash
npm install @cappitolian/http-local-server-swifter
npx cap sync
```

---

## Platform Configuration

### Android

Add the following permissions to your `AndroidManifest.xml`:

```xml
<!-- Required: bind socket and receive connections -->
<uses-permission android:name="android.permission.INTERNET" />
<!-- Required: resolve local IP address via WifiManager -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

> **Note:** `CHANGE_WIFI_MULTICAST_STATE` is **not** needed by this plugin. It belongs to a Network Discovery plugin (mDNS/NSD).

To allow cleartext HTTP traffic on the local network, add or update your `network_security_config.xml`:

```xml
<!-- res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="true">
    <trust-anchors>
      <certificates src="system" />
    </trust-anchors>
  </base-config>

  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">localhost</domain>
    <domain includeSubdomains="false">127.0.0.1</domain>
  </domain-config>
</network-security-config>
```

Then reference it and enable cleartext in `AndroidManifest.xml`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    android:usesCleartextTraffic="true"
    ...>
```

### iOS

Add the following to your `Info.plist` to allow your app to serve and receive HTTP traffic on the local network:

```xml
<!-- Required: allow cleartext HTTP from/to the local server -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

> **Note:** `NSLocalNetworkUsageDescription` and `NSBonjourServices` are **not** required by this plugin. Those entries belong to a Network Discovery plugin (mDNS/Bonjour). Do not add them here unless you are also using that plugin.

---

## Usage

### Import

```typescript
import { HttpLocalServerSwifter } from '@cappitolian/http-local-server-swifter';
```

### Start the server and listen for requests

```typescript
// 1. Register the request listener BEFORE connecting
await HttpLocalServerSwifter.addListener('onRequest', async (data) => {
  console.log(`${data.method} ${data.path}`);
  console.log('Headers:', data.headers);
  console.log('Body:', data.body);
  console.log('Query:', data.query);

  // 2. Always send a response — the server blocks the native thread until you do
  await HttpLocalServerSwifter.sendResponse({
    requestId: data.requestId,
    status: 200,
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ success: true, message: 'Hello from the device!' })
  });
});

// 3. Start the server
const { ip, port } = await HttpLocalServerSwifter.connect();
console.log(`Server running at http://${ip}:${port}`);
```

> ⚠️ **Always call `sendResponse`** for every request. On Android, the native thread is blocked via `CompletableFuture.get()` until the response arrives or the timeout elapses. On iOS, a `DispatchSemaphore` is held open. Failing to respond will cause the request to time out with `408 Request Timeout` (iOS) or a JSON timeout error (Android) after the configured timeout (default: **10s on iOS**, **5s on Android**).

### Stop the server

```typescript
await HttpLocalServerSwifter.disconnect();
```

---

## Security

This plugin runs an HTTP server on the local network. The following mechanisms are built into the native layer.

### Rate Limiting (Native — Android & iOS)

IP-based rate limiting is enforced natively before requests reach TypeScript, protecting the server against denial-of-service (DoS) attacks.

| Platform | Limit | Window | Client IP source |
|---|---|---|---|
| Android | 30 requests | 60 seconds | `http-client-ip` → `remote-addr` header |
| iOS | 30 requests | 60 seconds | `x-forwarded-for` → `request.address` |

Requests exceeding the limit receive a `429 Too Many Requests` response automatically:

```json
{ "success": false, "error": "Too many requests" }
```

### API Key Pairing (Application layer)

To prevent unauthorized clients from accessing your endpoints, implement an API Key pairing flow:

1. The server generates a cryptographically random key on first launch using `crypto.getRandomValues` and persists it with `@capacitor/preferences`.
2. The client calls `GET /pair` (the only unauthenticated endpoint) immediately after discovering the server IP.
3. The server returns the key. The client stores it locally.
4. All subsequent requests must include the `x-api-key` header. The server validates it before processing any route.

```
Server generates key → Client calls /pair → Client stores key
        ↓
All requests: x-api-key: <key> → Server validates → 401 if invalid
```

> ⚠️ Since this plugin operates over HTTP (cleartext), the API key is transmitted in plaintext. For sensitive environments, consider implementing HMAC request signing with short-lived timestamps to prevent replay attacks. The `x-signature` and `x-timestamp` headers are already allowed by the built-in CORS configuration on both platforms.

### CORS

CORS headers are set natively on every response. The following headers are allowed by default on both platforms:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Origin, Content-Type, Accept, Authorization,
                              X-Requested-With, x-api-key, x-signature, x-timestamp
```

Custom headers returned via `sendResponse` are merged on top of these defaults and can override them.

---

## Architecture

### Request / Response Bridge

The plugin uses a **request ID bridge** pattern to cross the native ↔ JavaScript boundary asynchronously:

```
Incoming HTTP request
        ↓
Native layer generates requestId → fires onRequest event to JS
        ↓
JS handler processes logic → calls sendResponse({ requestId, ... })
        ↓
Native layer resolves the pending future/semaphore → returns HTTP response
```

| Platform | Blocking mechanism | Default timeout |
|---|---|---|
| Android | `CompletableFuture.get(timeout, SECONDS)` | 5 seconds |
| iOS | `DispatchSemaphore.wait(timeout:)` | 10 seconds |

Pending responses are stored in a thread-safe map (`ConcurrentHashMap` on Android, `DispatchQueue`-protected `Dictionary` on iOS) and cleaned up on timeout or `disconnect`.

### Connection Behavior

- **Android (NanoHTTPD):** Each request is handled in its own thread. The server forces `Connection: close` on every response to prevent keep-alive issues under rapid sequential requests (`ERR_INVALID_HTTP_RESPONSE`).
- **iOS (Swifter):** Requests are processed via a middleware chain on a global background queue. `notifyListeners` (Capacitor event bridge) is always dispatched to the main thread.
- **IP resolution:** Both platforms resolve the local WiFi IP via `WifiManager` (Android) / `getifaddrs en0` (iOS), falling back to `127.0.0.1` if unavailable.

---

## API Reference

### Methods

#### `connect() => Promise<HttpConnectResult>`

Starts the HTTP server and begins listening for incoming requests on port `8080`.

**Returns:** `Promise<HttpConnectResult>`

---

#### `disconnect() => Promise<void>`

Stops the HTTP server, drains all pending response futures/semaphores, and releases all resources.

---

#### `sendResponse(options: HttpSendResponseOptions) => Promise<void>`

Sends an HTTP response back to the client for a given request. Must be called for every `onRequest` event received.

| Param | Type | Description |
|---|---|---|
| `options` | `HttpSendResponseOptions` | Response options including `requestId`, `status`, `headers`, and `body` |

---

#### `addListener('onRequest', handler) => Promise<PluginListenerHandle>`

Registers a listener for incoming HTTP requests.

| Param | Type | Description |
|---|---|---|
| `eventName` | `'onRequest'` | Event name |
| `handler` | `(data: HttpRequestData) => void` | Callback receiving the request data |

---

#### `removeAllListeners() => Promise<void>`

Removes all registered listeners.

---

### Interfaces

#### `HttpConnectResult`

| Property | Type | Description |
|---|---|---|
| `ip` | `string` | Local WiFi IP address where the server is bound (`127.0.0.1` fallback) |
| `port` | `number` | Port the server is listening on (fixed: `8080`) |

---

#### `HttpRequestData`

| Property | Type | Description |
|---|---|---|
| `requestId` | `string` | Unique UUID used to correlate the response — **required in `sendResponse`** |
| `method` | `string` | HTTP method (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`) |
| `path` | `string` | Request path (e.g. `/menu`, `/orders/123`) |
| `headers` | `Record<string, string>` | Request headers |
| `query` | `Record<string, string>` | Query string parameters |
| `body` | `string \| null` | Raw request body (present for `POST`, `PUT`, `PATCH`) |

---

#### `HttpSendResponseOptions`

| Property | Type | Required | Description |
|---|---|---|---|
| `requestId` | `string` | ✅ | ID of the request to respond to |
| `status` | `number` | ❌ | HTTP status code (default: `200`) |
| `headers` | `Record<string, string>` | ❌ | Custom response headers (merged with CORS defaults) |
| `body` | `string` | ❌ | Response body string |

---

## Platform Support

| Feature | Android | iOS | Web |
|---|---|---|---|
| Start HTTP server | ✅ | ✅ | ✅ (mock) |
| Receive requests | ✅ | ✅ | ✅ (mock) |
| Send responses | ✅ | ✅ | ✅ (mock) |
| Custom status codes | ✅ | ✅ | ✅ (mock) |
| Custom response headers | ✅ | ✅ | ✅ (mock) |
| Request headers forwarding | ✅ | ✅ | ✅ (mock) |
| IP-based rate limiting | ✅ | ✅ | ❌ |
| CORS preflight handling | ✅ | ✅ | ❌ |
| `Connection: close` enforcement | ✅ | ❌ | ❌ |
| Request body parsing (POST/PUT/PATCH) | ✅ | ✅ | ✅ (mock) |

---

## Troubleshooting

### Requests timing out on the client side

The server resolves the native thread synchronously. If your JS handler throws before calling `sendResponse`, the request will hang until the native timeout fires. Always wrap your handler in `try/catch` and call `sendResponse` in both branches.

### `ERR_INVALID_HTTP_RESPONSE` on Android

NanoHTTPD does not handle keep-alive correctly under rapid sequential requests. The plugin forces `Connection: close` on every response. If you are still seeing this error, ensure you are on the latest version.

### Server returns `127.0.0.1` instead of the LAN IP

This happens when WiFi is disconnected or the `WifiManager` / `en0` interface returns no address. Verify the device is connected to WiFi before calling `connect()`.

### iOS server not reachable from Android

Ensure:
1. Both devices are on the **same WiFi network**
2. `NSAllowsLocalNetworking` and `NSAllowsArbitraryLoads` are set in `Info.plist`
3. The client is using the IP returned by `connect()`, not `localhost`

---

## Contributing

Clone the repository and install dependencies:

```bash
git clone https://github.com/cappitolian/http-local-server-swifter
cd http-local-server-swifter
npm install
```

Run the example project:

```bash
cd example
npm install
npx cap sync
# Open in Android Studio or Xcode
```

> ⚠️ Changes to native Swift/Java code require recompilation from the IDE. `npx cap sync` only syncs web assets.

---

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for the full list of changes.

---

## License

MIT — see [LICENSE](./LICENSE) for details.