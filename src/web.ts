import { WebPlugin } from '@capacitor/core';

import type { HttpLocalServerSwifterPlugin } from './definitions';

export class HttpLocalServerSwifterWeb extends WebPlugin implements HttpLocalServerSwifterPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
