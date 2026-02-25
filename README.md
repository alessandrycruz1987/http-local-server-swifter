# @cappitolian/http-local-server-swifter

A Capacitor plugin to run a local HTTP server on your device, allowing you to receive and respond to HTTP requests directly from Angular/JavaScript.

---

## Features

- ✅ Embed a real HTTP server (NanoHTTPD on Android, **Swifter** on iOS)
- ✅ Receive requests via events and send responses back from the JS layer
- ✅ CORS support enabled by default for local communication
- ✅ Support for all HTTP methods (GET, POST, PUT, PATCH, DELETE, OPTIONS)
- ✅ Dynamic URL routing (e.g. `/orders/:id`) supported via middleware
- ✅ Swift Package Manager (SPM) support
- ✅ Tested with **Capacitor 8** and **Ionic 8**

---

## Installation

```bash
npm install @cappitolian/http-local-server-swifter
npx cap sync
```

---

## Usage

### Import

```typescript
import { HttpLocalServerSwifter } from '@cappitolian/http-local-server-swifter';
```

### Listen and Respond

```typescript
// 1. Set up the listener for incoming requests
await HttpLocalServerSwifter.addListener('onRequest', async (data) => {
  console.log(`${data.method} ${data.path}`);
  console.log('Body:', data.body);
  console.log('Headers:', data.headers);
  console.log('Query:', data.query);

  // 2. Send a response back to the client using the requestId
  await HttpLocalServerSwifter.sendResponse({
    requestId: data.requestId,
    body: JSON.stringify({
      success: true,
      message: 'Request processed!'
    })
  });
});

// 3. Start the server
HttpLocalServerSwifter.connect().then(result => {
  console.log('Server running at:', result.ip, 'Port:', result.port);
});
```

### Stop Server

```typescript
// 4. Stop the server
await HttpLocalServerSwifter.disconnect();
```

---

## Platforms

- **iOS** (Swift with Swifter)
- **Android** (Java with NanoHTTPD)
- **Web** (Returns mock values for development)

---

## Requirements

- [Capacitor 8](https://capacitorjs.com/)
- iOS 13.0+
- Android API 22+

---

## Migration from v0.1.x

Version 0.2.0 introduces middleware-based routing on iOS and dynamic response support (custom `status` and `headers`) on both platforms. See changes below.

---

## License

MIT

---

## Support

If you have any issues or feature requests, please open an issue on the repository.

---

## 📋 Cambios Principales

### **Route Handlers → Middleware (iOS)**

| Aspecto | v0.1.x | v0.2.0 |
|---------|--------|--------|
| **Routing** | `server["/:path"] = { ... }` | `server.middleware.append { ... }` |
| **Rutas dinámicas** | ❌ Solo un segmento (`/menu`) | ✅ Cualquier ruta (`/orders/:id`) |
| **CORS preflight** | Manejado por handler estático | Interceptado en middleware antes del JS |
| **Thread de inicio** | Main thread | Background thread (`DispatchQueue.global`) |
| **Respuesta dinámica** | Solo `body` | `body` + `status` + `headers` |

### **sendResponse — Nuevos campos opcionales**

```typescript
await HttpLocalServerSwifter.sendResponse({
  requestId: data.requestId,
  body: JSON.stringify({ success: true }),
  status: 200,           // NEW: opcional, default 200
  headers: {             // NEW: opcional, headers custom
    'X-Custom-Header': 'value'
  }
});
```

### **Archivos modificados**

| Archivo | Cambio |
|---------|--------|
| `HttpLocalServerSwifter.swift` | Middleware en lugar de route handlers; `handleJsResponse` acepta `[String: Any]` |
| `HttpLocalServerSwifterPlugin.swift` | `sendResponse` pasa `dictionaryRepresentation` completo |
| `HttpLocalServerSwifterPlugin.java` | `sendResponse` pasa `call.getData()` completo |
| `definitions.ts` | `HttpSendResponseOptions` agrega `status?` y `headers?` |
| `web.ts` | Mock actualizado con los nuevos campos |

---

## ✅ Pasos para Aplicar

1. **Reemplaza `HttpLocalServerSwifter.swift`** con la versión nueva (middleware)
2. **Reemplaza `HttpLocalServerSwifterPlugin.swift`** con la versión nueva
3. **Reemplaza `HttpLocalServerSwifterPlugin.java`** con la versión nueva
4. **Actualiza `definitions.ts`**, **`web.ts`** e **`index.ts`**
5. **En Xcode**:
```
   File → Packages → Reset Package Caches
   File → Packages → Resolve Package Versions
   Product → Clean Build Folder
   Product → Run
```
6. **En Android Studio**:
```
   Build → Clean Project
   Build → Rebuild Project
   Run
```

> ⚠️ `npx cap sync` solo sincroniza archivos web. Los cambios en código nativo Swift/Java **requieren recompilación desde el IDE**.