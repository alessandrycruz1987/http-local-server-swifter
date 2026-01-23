import { registerPlugin } from '@capacitor/core';
import type { HttpLocalServerSwifterPlugin } from './definitions';

/**
 * Plugin de servidor HTTP local para Android e iOS.
 * 
 * Permite crear un servidor HTTP en el dispositivo que puede recibir
 * peticiones desde otros dispositivos en la misma red local.
 * 
 * @example
 * ```typescript
 * import { HttpLocalServerSwifter } from '@cappitolian/http-local-server-swifter';
 * 
 * // Iniciar servidor
 * const { ip, port } = await HttpLocalServerSwifter.connect();
 * console.log(`Servidor en http://${ip}:${port}`);
 * 
 * // Escuchar peticiones
 * await HttpLocalServerSwifter.addListener('onRequest', async (data) => {
 *   console.log('Petición recibida:', data);
 *   
 *   // Procesar y responder
 *   await HttpLocalServerSwifter.sendResponse({
 *     requestId: data.requestId,
 *     body: JSON.stringify({ success: true })
 *   });
 * });
 * 
 * // Detener servidor
 * await HttpLocalServerSwifter.disconnect();
 * ```
 */
const HttpLocalServerSwifter = registerPlugin<HttpLocalServerSwifterPlugin>('HttpLocalServerSwifter', {
  web: () => import('./web').then(m => new m.HttpLocalServerSwifterWeb()),
});

export * from './definitions';
export { HttpLocalServerSwifter };