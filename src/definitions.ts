import type { PluginListenerHandle } from '@capacitor/core';

/**
 * Resultado de la conexión del servidor HTTP local
 */
export interface HttpConnectResult {
  /**
   * Dirección IP del servidor (ej: "192.168.1.100")
   */
  ip: string;

  /**
   * Puerto en el que escucha el servidor (típicamente 8080)
   */
  port: number;
}

/**
 * Datos de una petición HTTP entrante
 */
export interface HttpRequestData {
  /**
   * ID único de la petición. Debe usarse en sendResponse()
   */
  requestId: string;

  /**
   * Método HTTP (GET, POST, PUT, PATCH, DELETE, OPTIONS)
   */
  method: string;

  /**
   * Ruta de la petición (ej: "/api/users")
   */
  path: string;

  /**
   * Cuerpo de la petición (opcional, presente en POST/PUT/PATCH)
   * Típicamente es un string JSON
   */
  body?: string;

  /**
   * Encabezados HTTP de la petición
   */
  headers?: Record<string, string>;

  /**
   * Parámetros de query string (ej: { id: "123", name: "test" })
   */
  query?: Record<string, string>;
}

/**
 * Opciones para enviar una respuesta HTTP
 */
export interface HttpSendResponseOptions {
  /**
   * ID de la petición (recibido en el evento 'onRequest')
   */
  requestId: string;

  /**
   * Cuerpo de la respuesta. Típicamente un JSON stringificado.
   * Ejemplo: JSON.stringify({ success: true, data: {...} })
   */
  body: string;
}

/**
 * Plugin para ejecutar un servidor HTTP local en dispositivos iOS y Android.
 * 
 * Permite recibir peticiones HTTP desde otros dispositivos en la red local
 * y responder desde JavaScript/TypeScript.
 * 
 * @since 0.1.0
 */
export interface HttpLocalServerSwifterPlugin {
  /**
   * Inicia el servidor HTTP local en el dispositivo.
   * 
   * El servidor escucha en todas las interfaces de red (0.0.0.0)
   * y es accesible desde otros dispositivos en la misma red local.
   * 
   * @returns Promesa con la IP y puerto del servidor
   * @throws Error si el servidor no puede iniciarse (ej: puerto ocupado)
   * 
   * @example
   * ```typescript
   * const { ip, port } = await HttpLocalServerSwifter.connect();
   * console.log(`Servidor corriendo en http://${ip}:${port}`);
   * ```
   * 
   * @since 0.1.0
   */
  connect(): Promise<HttpConnectResult>;

  /**
   * Detiene el servidor HTTP local.
   * 
   * Cierra todas las conexiones activas y libera el puerto.
   * Las peticiones pendientes recibirán un timeout.
   * 
   * @returns Promesa que se resuelve cuando el servidor se detiene
   * 
   * @example
   * ```typescript
   * await HttpLocalServerSwifter.disconnect();
   * console.log('Servidor detenido');
   * ```
   * 
   * @since 0.1.0
   */
  disconnect(): Promise<void>;

  /**
   * Envía una respuesta HTTP de vuelta al cliente.
   * 
   * Debe llamarse con el `requestId` recibido en el evento 'onRequest'.
   * Si no se llama dentro de 5 segundos, el cliente recibirá un timeout (408).
   * 
   * @param options - Objeto con requestId y cuerpo de la respuesta
   * @returns Promesa que se resuelve cuando la respuesta se envía
   * @throws Error si faltan requestId o body
   * 
   * @example
   * ```typescript
   * await HttpLocalServerSwifter.sendResponse({
   *   requestId: '123-456-789',
   *   body: JSON.stringify({ status: 'ok', data: { id: 1 } })
   * });
   * ```
   * 
   * @since 0.1.0
   */
  sendResponse(options: HttpSendResponseOptions): Promise<void>;

  /**
   * Registra un listener para recibir peticiones HTTP entrantes.
   * 
   * Este evento se dispara cada vez que el servidor recibe una petición.
   * Debes responder usando `sendResponse()` con el mismo `requestId`.
   * 
   * @param eventName - Debe ser 'onRequest'
   * @param listenerFunc - Callback que recibe los datos de la petición
   * @returns Handle para remover el listener posteriormente
   * 
   * @example
   * ```typescript
   * const listener = await HttpLocalServerSwifter.addListener('onRequest', async (data) => {
   *   console.log(`${data.method} ${data.path}`);
   *   
   *   const response = {
   *     message: 'Hello from device',
   *     timestamp: Date.now()
   *   };
   *   
   *   await HttpLocalServerSwifter.sendResponse({
   *     requestId: data.requestId,
   *     body: JSON.stringify(response)
   *   });
   * });
   * 
   * // Remover listener cuando ya no sea necesario
   * await listener.remove();
   * ```
   * 
   * @since 0.1.0
   */
  addListener(
    eventName: 'onRequest',
    listenerFunc: (data: HttpRequestData) => void | Promise<void>
  ): Promise<PluginListenerHandle>;

  /**
   * Elimina todos los listeners del evento 'onRequest'.
   * 
   * @returns Promesa que se resuelve cuando se eliminan los listeners
   * 
   * @example
   * ```typescript
   * await HttpLocalServerSwifter.removeAllListeners();
   * ```
   * 
   * @since 0.1.0
   */
  removeAllListeners(): Promise<void>;
}