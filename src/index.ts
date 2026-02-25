import { registerPlugin } from '@capacitor/core';
import type { HttpLocalServerSwifterPlugin } from './definitions';

/**
 * Local HTTP server plugin for Android and iOS.
 * * Allows creating an HTTP server on the device that can receive
 * requests from other devices on the same local network or 
 * from the app's own WebView (fixing CORS issues).
 */
const HttpLocalServerSwifter = registerPlugin<HttpLocalServerSwifterPlugin>('HttpLocalServerSwifter', {
  // We point to the web mock for browser development
  web: () => import('./web').then(m => new m.HttpLocalServerSwifterWeb()),
});

// Re-export everything from definitions so they are available to the app
export * from './definitions';
export { HttpLocalServerSwifter };