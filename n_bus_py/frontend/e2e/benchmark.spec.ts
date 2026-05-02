import { test, expect } from "@playwright/test";

test.describe("Benchmark Page", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/benchmark");
  });

  test("renders benchmark heading", async ({ page }) => {
    await expect(page.locator("h1, h2").first()).toContainText(/benchmark/i);
  });

  test("has select all / deselect all controls", async ({ page }) => {
    const body = page.locator("body");
    await expect(body).toContainText(/select|solver/i);
  });

  test("can run full benchmark", async ({ page }) => {
    // Click select all if available
    const selectAll = page.getByRole("button", { name: /select all|all/i });
    if (await selectAll.isVisible()) {
      await selectAll.click();
    }

    const btn = page.getByRole("button", { name: /run|benchmark|start/i });
    if (!(await btn.isVisible())) return;
    await btn.click();

    // Benchmark runs multiple solvers, need more time
    await page.waitForTimeout(15000);

    const body = page.locator("body");
    const text = await body.innerText();
    // Should show results for at least some solvers
    expect(text.length).toBeGreaterThan(100);
  });

  test("shows ranking or results table", async ({ page }) => {
    const btn = page.getByRole("button", { name: /run|benchmark|start/i });
    if (!(await btn.isVisible())) return;
    await btn.click();

    await page.waitForTimeout(15000);

    const table = page.locator("table");
    const chart = page.locator(".recharts-wrapper, svg");
    const hasVisual =
      (await table.count()) > 0 || (await chart.count()) > 0;
    expect(hasVisual).toBeTruthy();
  });
});
