# @cappitolian/http-local-server-swifter

A Capacitor plugin to run a local HTTP server on your device, allowing you to receive and respond to HTTP requests directly from Angular/JavaScript.

---

## Features

- ✅ Embed a real HTTP server (NanoHTTPD on Android, **Swifter** on iOS)
- ✅ Receive requests via events and send responses back from the JS layer
- ✅ CORS support enabled by default for local communication
- ✅ Support for all HTTP methods (GET, POST, PUT, PATCH, DELETE, OPTIONS)
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

## Migration from v0.0.x

Version 0.1.0 migrates from GCDWebServer to Swifter on iOS for better Swift Package Manager support. The API remains the same, so no code changes are needed in your app.

---

## License

MIT

---

## Support

If you have any issues or feature requests, please open an issue on the repository.
```

---

## 📋 Cambios Principales

### **GCDWebServer → Swifter**

| Aspecto | GCDWebServer | Swifter |
|---------|--------------|---------|
| **Importar** | `import GCDWebServer` | `import Swifter` |
| **Crear servidor** | `GCDWebServer()` | `HttpServer()` |
| **Tipo de puerto** | `UInt` | `UInt16` |
| **Handlers** | `.addDefaultHandler(forMethod:)` | `server["/(.*)"] = { ... }` |
| **Request type** | `GCDWebServerRequest` | `HttpRequest` |
| **Response type** | `GCDWebServerDataResponse` | `HttpResponse` |
| **Método HTTP** | `request.method` | `request.method` (igual) |
| **Path** | `request.url.path` | `request.path` |
| **Body** | `(request as? GCDWebServerDataRequest)?.data` | `request.body` (bytes) |
| **Headers** | `request.headers` | `request.headers` (igual) |
| **Query params** | `request.query` | `request.queryParams` |
| **Start server** | `try server.start(options:)` | `try server.start(port)` |
| **Stop server** | `server.stop()` | `server.stop()` (igual) |
| **Response** | `GCDWebServerDataResponse(text:)` | `.ok(.text())` |
| **CORS headers** | `setValue(_:forAdditionalHeader:)` | Custom extension |

---

## ✅ Pasos para Aplicar

1. **Reemplaza `HttpLocalServerSwifter.swift`** con la versión de arriba
2. **Actualiza `Package.swift`**
3. **Actualiza `.podspec`**
4. **Actualiza `package.json`** (versiones de Capacitor 8)
5. **En Xcode**:
```
   File → Packages → Reset Package Caches
   File → Packages → Resolve Package Versions
   Product → Clean Build Folder