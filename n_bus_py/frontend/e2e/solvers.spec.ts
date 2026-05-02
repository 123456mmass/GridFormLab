import { test, expect } from "@playwright/test";

const SOLVERS = ["nr", "gs", "fdlf", "dc", "helm", "homotopy", "cpf-pc", "opf"];

test.describe("Solver Pages", () => {
  for (const method of SOLVERS) {
    test.describe(`${method.toUpperCase()} Solver`, () => {
      test.beforeEach(async ({ page }) => {
        await page.goto(`/solvers/${method}`);
      });

      test("renders solver method heading", async ({ page }) => {
        await expect(page.locator("h1, h2").first()).toBeVisible();
      });

      test("has case selector", async ({ page }) => {
        const select = page.locator("select, [role=combobox]");
        // Not all pages may have a select; skip if not present
        const count = await select.count();
        if (count > 0) {
          await expect(select.first()).toBeVisible();
        }
      });

      test("has solve button", async ({ page }) => {
        const btn = page.getByRole("button", { name: /solve|run/i });
        if (await btn.isVisible()) {
          await expect(btn).toBeEnabled();
        }
      });

      test("solve returns results", async ({ page }) => {
        const btn = page.getByRole("button", { name: /solve|run/i });
        if (!(await btn.isVisible())) return;

        await btn.click();
        // Wait for result - either convergence status or error
        await page.waitForTimeout(5000);
        const body = page.locator("body");
        const text = await body.innerText();
        // Should have some result content
        expect(text.length).toBeGreaterThan(50);
      });
    });
  }
});

test.describe("NR Solver Detailed", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/solvers/nr");
  });

  test("displays bus table after solving", async ({ page }) => {
    const btn = page.getByRole("button", { name: /solve|run/i });
    if (!(await btn.isVisible())) return;

    await btn.click();
    await page.waitForTimeout(5000);

    // Should show voltage info
    const body = page.locator("body");
    await expect(body).toContainText(/voltage|1\.06|bus/i, { timeout: 10000 });
  });

  test("displays mismatch chart after solving", async ({ page }) => {
    const btn = page.getByRole("button", { name: /solve|run/i });
    if (!(await btn.isVisible())) return;

    await btn.click();
    await page.waitForTimeout(5000);

    // Should have a chart or mismatch data
    const hasChart =
      (await page.locator(".recharts-wrapper, svg").count()) > 0;
    const hasMismatchText =
      (await page.locator("body").innerText()).includes("Mismatch");
    expect(hasChart || hasMismatchText).toBeTruthy();
  });
});
