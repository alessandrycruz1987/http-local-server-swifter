import { WebPlugin } from '@capacitor/core';
import type {
  HttpLocalServerSwifterPlugin,
  HttpConnectResult,
    HttpSendResponseOptions
  } from './definitions';

/**
 * Implementación web (mock) del plugin HttpLocalServerSwifter.
 * 
 * Proporciona funcionalidad simulada para desarrollo en navegador.
 * El servidor real solo funciona en dispositivos iOS/Android nativos.
 */
export class HttpLocalServerSwifterWeb extends WebPlugin implements HttpLocalServerSwifterPlugin {

  private isRunning = false;

  async connect(): Promise<HttpConnectResult> {
    if (this.isRunning) {
      console.warn('[HttpLocalServerSwifter Web] El servidor ya está ejecutándose (Mock).');
      return { ip: '127.0.0.1', port: 8080 };
    }

    console.warn(
      '[HttpLocalServerSwifter Web] El servidor HTTP nativo no está disponible en navegador.\n' +
      'Retornando valores mock para desarrollo.\n' +
      'Para funcionalidad real, ejecuta en un dispositivo iOS/Android.'
    );

    this.isRunning = true;

    return {
      ip: '127.0.0.1',
      port: 8080
    };
  }

  async disconnect(): Promise<void> {
    if (!this.isRunning) {
      console.log('[HttpLocalServerSwifter Web] El servidor ya está detenido (Mock).');
      return;
    }

    console.log('[HttpLocalServerSwifter Web] Servidor detenido (Mock).');
    this.isRunning = false;
  }

  async sendResponse(options: HttpSendResponseOptions): Promise<void> {
    if (!this.isRunning) {
      throw new Error('Server is not running. Call connect() first.');
    }

    const { requestId, body } = options;

    if (!requestId) {
      throw new Error('Missing requestId');
    }

    if (!body) {
      throw new Error('Missing body');
    }

    console.log(
      `[HttpLocalServerSwifter Web] Mock response sent for requestId: ${requestId}`,
      '\nBody preview:', body.substring(0, 100) + (body.length > 100 ? '...' : '')
    );
  }
}