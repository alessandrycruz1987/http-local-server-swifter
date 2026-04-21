# @cappitolian/http-local-server-swifter

[![npm version](https://img.shields.io/npm/v/@cappitolian/http-local-server-swifter)](https://www.npmjs.com/package/@cappitolian/http-local-server-swifter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Capacitor 8](https://img.shields.io/badge/Capacitor-8-blue)](https://capacitorjs.com/)

A Capacitor plugin that embeds a real HTTP server directly on your device — powered by **NanoHTTPD** on Android and **Swifter** on iOS. It allows you to receive and respond to HTTP requests from the JavaScript layer, enabling local peer-to-peer communication between devices on the same network without a cloud backend.

---

## Table of Contents

- [Installation](#installation)
- [Platform Configuration](#platform-configuration)
- [Usage](#usage)
- [Security](#security)
- [API Reference](#api-reference)
- [Platform Support](#platform-support)
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
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

To allow cleartext HTTP traffic on the local network, add or update your `network_security_config.xml`:

```xml
<!-- res/xml/network_security_config.xml -->
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">192.168.0.0/16</domain>
    </domain-config>
</network-security-config>
```

Then reference it in `AndroidManifest.xml`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

### iOS

No additional `Info.plist` entries are required for local HTTP servers. However, if your app uses **Bonjour/mDNS** for Network Discovery, add the following:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses the local network to communicate with nearby devices.</string>
<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
</array>
```

---

## Usage

### Import

```typescript
import { HttpLocalServerSwifter } from '@cappitolian/http-local-server-swifter';
```

### Start the server and listen for requests

```typescript
// 1. Register the request listener
await HttpLocalServerSwifter.addListener('onRequest', async (data) => {
  console.log(`${data.method} ${data.path}`);
  console.log('Headers:', data.headers);
  console.log('Body:', data.body);
  console.log('Query:', data.query);

  // 2. Send a response back using the requestId
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

### Stop the server

```typescript
await HttpLocalServerSwifter.disconnect();
```

---

## Security

This plugin runs an HTTP server on the local network. The following mechanisms are built into the native layer and recommended at the application layer.

### Rate Limiting (Native — Android & iOS)

IP-based rate limiting is enforced natively before requests reach TypeScript, protecting the server against denial-of-service (DoS) attacks.

| Platform | Limit | Window |
|---|---|---|
| Android | 30 requests | 60 seconds |
| iOS | 30 requests | 60 seconds |

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

> ⚠️ Since this plugin operates over HTTP, the API key is transmitted in plaintext. For sensitive environments, consider implementing HMAC request signing with short-lived timestamps to prevent replay attacks.

### CORS

CORS headers are set by default in the native layer. The `x-api-key` header is explicitly included in `Access-Control-Allow-Headers` on both platforms.

---

## API Reference

<!-- Auto-generated by @capacitor/docgen -->

### Methods

#### `connect() => Promise<HttpConnectResult>`

Starts the HTTP server and begins listening for incoming requests.

**Returns:** `Promise<HttpConnectResult>`

---

#### `disconnect() => Promise<void>`

Stops the HTTP server and releases all resources.

---

#### `sendResponse(options: HttpSendResponseOptions) => Promise<void>`

Sends an HTTP response back to the client for a given request.

| Param | Type | Description |
|---|---|---|
| `options` | `HttpSendResponseOptions` | Response options including requestId, status, headers, and body |

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
| `ip` | `string` | Local IP address where the server is bound |
| `port` | `number` | Port the server is listening on (default: 8080) |

---

#### `HttpRequestData`

| Property | Type | Description |
|---|---|---|
| `requestId` | `string` | Unique ID used to correlate the response |
| `method` | `string` | HTTP method (GET, POST, PUT, PATCH, DELETE, OPTIONS) |
| `path` | `string` | Request path (e.g. `/menu`, `/orders/123`) |
| `headers` | `Record<string, string>` | Request headers |
| `query` | `Record<string, string>` | Query string parameters |
| `body` | `string \| null` | Raw request body (for POST, PUT, PATCH) |

---

#### `HttpSendResponseOptions`

| Property | Type | Required | Description |
|---|---|---|---|
| `requestId` | `string` | ✅ | ID of the request to respond to |
| `status` | `number` | ❌ | HTTP status code (default: `200`) |
| `headers` | `Record<string, string>` | ❌ | Custom response headers |
| `body` | `string` | ❌ | Response body |

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
| Dynamic routing | ✅ | ✅ | ❌ |
| IP-based rate limiting | ✅ | ✅ | ❌ |
| CORS preflight handling | ✅ | ✅ | ❌ |

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