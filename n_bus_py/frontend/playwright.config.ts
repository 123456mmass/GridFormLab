import { defineConfig, devices } from "@playwright/test";

const backendPort = Number(process.env.PLAYWRIGHT_BACKEND_PORT ?? 8000);
const frontendPort = Number(process.env.PLAYWRIGHT_FRONTEND_PORT ?? 3000);
const reuseBackend = process.env.PLAYWRIGHT_REUSE_BACKEND !== "0";
const reuseFrontend = process.env.PLAYWRIGHT_REUSE_FRONTEND !== "0";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "html",
  use: {
    baseURL: `http://127.0.0.1:${frontendPort}`,
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: [
    {
      command: `cd ../backend && python -m uvicorn main:app --host 127.0.0.1 --port ${backendPort}`,
      port: backendPort,
      reuseExistingServer: reuseBackend,
      timeout: 15000,
    },
    {
      command: `npm run dev -- --hostname 127.0.0.1 --port ${frontendPort}`,
      port: frontendPort,
      reuseExistingServer: reuseFrontend,
      timeout: 30000,
    },
  ],
});
