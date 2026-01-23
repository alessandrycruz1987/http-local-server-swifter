import { registerPlugin } from '@capacitor/core';

import type { HttpLocalServerSwifterPlugin } from './definitions';

const HttpLocalServerSwifter = registerPlugin<HttpLocalServerSwifterPlugin>('HttpLocalServerSwifter', {
  web: () => import('./web').then((m) => new m.HttpLocalServerSwifterWeb()),
});

export * from './definitions';
export { HttpLocalServerSwifter };
