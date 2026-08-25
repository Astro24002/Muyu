import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  resolve: { alias: { '@': resolve(rootDir, 'src') } },
  server: { proxy: { '/api': { target: 'http://localhost:8080', ws: true } } },
  test: { environment: 'jsdom', setupFiles: './test/setup.ts' },
});
