import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  root: fileURLToPath(new URL('./about', import.meta.url)),
  base: './',
  plugins: [react()],
  define: {
    'import.meta.env.VITE_MUYU_WEB_URL': JSON.stringify('https://muyu.bkverse.space/'),
  },
  build: {
    outDir: '../dist-website',
    emptyOutDir: true,
  },
});
