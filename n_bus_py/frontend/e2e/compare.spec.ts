import { test, expect } from "@playwright/test";

test.describe("Compare Page", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/compare");
  });

  test("renders compare heading", async ({ page }) => {
    await expect(page.locator("h1, h2").first()).toContainText(/compare/i);
  });

  test("has solver selection buttons", async ({ page }) => {
    const buttons = page.locator("button.badge");
    const count = await buttons.count();
    expect(count).toBeGreaterThanOrEqual(2);
  });

  test("can run comparison", async ({ page }) => {
    // Select first two solver buttons
    const buttons = page.locator("button.badge");
    const count = await buttons.count();
    if (count < 2) return;
    await buttons.nth(0).click();
    await buttons.nth(1).click();

    // Click compare button
    const btn = page.getByRole("button", { name: /compare/i });
    if (await btn.isVisible()) {
      await btn.click();
      await page.waitForTimeout(8000);
      // Should show results table
      const body = page.locator("body");
      await expect(body).toContainText(/converged|iterations|loss/i, { timeout: 15000 });
    }
  });

  test("shows comparison table after run", async ({ page }) => {
    const buttons = page.locator("button.badge");
    const count = await buttons.count();
    if (count < 2) return;
    await buttons.nth(0).click();
    await buttons.nth(1).click();

    const btn = page.getByRole("button", { name: /compare/i });
    if (!(await btn.isVisible())) return;
    await btn.click();

    // Wait for table
    const table = page.locator("table");
    await expect(table).toBeVisible({ timeout: 15000 });
  });
});
