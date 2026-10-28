import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  testMatch: 'website-pages.spec.ts',
  workers: 1,
  reporter: 'list',
  use: {
    ...devices['Desktop Chrome'],
    baseURL: 'http://127.0.0.1:4176/Muyu/',
    contextOptions: { reducedMotion: 'reduce' },
  },
  webServer: {
    command: 'npx vite preview --config vite.website.config.ts --base /Muyu/ --host 127.0.0.1 --port 4176 --strictPort',
    url: 'http://127.0.0.1:4176/Muyu/',
    reuseExistingServer: false,
  },
});
