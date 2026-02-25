import type { PluginListenerHandle } from '@capacitor/core';

export interface HttpConnectResult {
  ip: string;
  port: number;
}

export interface HttpRequestData {
  requestId: string;
  method: string;
  path: string;
  body?: string;
  headers?: Record<string, string>;
  query?: Record<string, string>;
}

/**
 * Options for sending an HTTP response.
 * Updated to support custom status codes and headers for CORS.
 */
export interface HttpSendResponseOptions {
  /** The ID received in the 'onRequest' event */
  requestId: string;

  /** The response body (usually stringified JSON) */
  body: string;

  /** * NEW: HTTP Status code (e.g., 200, 204, 404). 
   * Default is 200.
   */
  status?: number;

  /** * NEW: Custom HTTP headers.
   * Crucial for fixing CORS by providing 'Access-Control-Allow-Origin'.
   */
  headers?: Record<string, string>;
}

export interface HttpLocalServerSwifterPlugin {
  connect(): Promise<HttpConnectResult>;
  disconnect(): Promise<void>;

  /**
   * Sends a response back to the client.
   * Now supports status and headers to handle CORS Preflight correctly.
   */
  sendResponse(options: HttpSendResponseOptions): Promise<void>;

  addListener(
    eventName: 'onRequest',
    listenerFunc: (data: HttpRequestData) => void | Promise<void>
  ): Promise<PluginListenerHandle>;

  removeAllListeners(): Promise<void>;
}