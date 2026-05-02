import { test, expect } from "@playwright/test";

test.describe("Dashboard Page", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
  });

  test("renders main heading", async ({ page }) => {
    await expect(page.locator("h1")).toContainText(/Power Flow|N-Bus|Dashboard/i);
  });

  test("shows solver cards", async ({ page }) => {
    const cards = page.locator("button.card-glass");
    const count = await cards.count();
    expect(count).toBeGreaterThanOrEqual(8);
  });

  test("navigation sidebar is visible", async ({ page }) => {
    await expect(page.locator("aside").first()).toBeVisible();
    await expect(page.locator("nav").first()).toBeVisible();
  });

  test("Run All button triggers benchmark", async ({ page }) => {
    const runButton = page.getByRole("button", { name: /run all/i });
    if (await runButton.isVisible()) {
      await runButton.click();
      // Should show stat cards after benchmark completes
      await expect(
        page.getByText(/converged|P_loss/i).first()
      ).toBeVisible({ timeout: 30000 });
    }
  });

  test("can navigate to a solver page from dashboard", async ({ page }) => {
    const solverBtn = page.locator("button.card-glass").first();
    if (await solverBtn.isVisible()) {
      await solverBtn.click();
      await expect(page).toHaveURL(/methodology/);
    }
  });
});
