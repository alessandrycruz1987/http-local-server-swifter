import { WebPlugin } from '@capacitor/core';
import type {
  HttpLocalServerSwifterPlugin,
  HttpConnectResult,
  HttpSendResponseOptions
} from './definitions';

export class HttpLocalServerSwifterWeb extends WebPlugin implements HttpLocalServerSwifterPlugin {
  private isRunning = false;

  async connect(): Promise<HttpConnectResult> {
    this.isRunning = true;
    console.warn('[HttpLocalServerSwifter Web] Mock server started at 127.0.0.1:8080');
    return { ip: '127.0.0.1', port: 8080 };
  }

  async disconnect(): Promise<void> {
    this.isRunning = false;
    console.log('[HttpLocalServerSwifter Web] Mock server stopped.');
  }

  async sendResponse(options: HttpSendResponseOptions): Promise<void> {
    if (!this.isRunning) throw new Error('Server not running');

    const { requestId, body, status, headers } = options;

    console.log(
      `[HttpLocalServerSwifter Web] Mock Response:`,
      { requestId, status: status ?? 200, headers: headers ?? {}, bodyLength: body.length }
    );
  }
}