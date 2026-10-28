import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';
import { loadEnv } from 'vite';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, rootDir, 'MUYU_');
  const apiTarget = env.MUYU_API_PROXY_TARGET || 'https://muyu.bkverse.space';

  return {
    plugins: [react()],
    resolve: { alias: { '@': resolve(rootDir, 'src') } },
    server: { proxy: { '/api': { target: apiTarget, changeOrigin: true, ws: true } } },
    test: {
      environment: 'jsdom',
      setupFiles: './test/setup.ts',
      include: ['test/**/*.{test,spec}.{js,ts,jsx,tsx}'],
      exclude: ['e2e/**'],
    },
  };
});
