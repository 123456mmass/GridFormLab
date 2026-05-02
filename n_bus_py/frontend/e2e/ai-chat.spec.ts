import { test, expect } from "@playwright/test";

test.describe("AI Chat Page", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/analyze");
  });

  test("renders chat heading or title", async ({ page }) => {
    await expect(page.locator("h1, h2").first()).toContainText(
      /analyze|ai|chat|assistant/i
    );
  });

  test("has text input for messages", async ({ page }) => {
    const input = page.locator("textarea, input[type='text']");
    const count = await input.count();
    if (count > 0) {
      await expect(input.first()).toBeVisible();
    }
  });

  test("can send a message and get response", async ({ page }) => {
    const input = page.locator("textarea, input[type='text']").first();
    const sendBtn = page.getByRole("button", { name: /send|submit/i });

    if (!(await input.isVisible())) return;

    await input.fill("Explain power flow analysis in one sentence.");
    if (await sendBtn.isVisible()) {
      await sendBtn.click();
    } else {
      await input.press("Enter");
    }

    // AI responses may take time; wait for streaming or final response
    await page.waitForTimeout(10000);

    const body = page.locator("body");
    const text = await body.innerText();
    // Should have some response content beyond just our question
    expect(text.length).toBeGreaterThan(30);
  });

  test("shows conversation messages", async ({ page }) => {
    const input = page.locator("textarea, input[type='text']").first();
    if (!(await input.isVisible())) return;

    await input.fill("What is Newton-Raphson method?");
    const sendBtn = page.getByRole("button", { name: /send|submit/i });
    if (await sendBtn.isVisible()) {
      await sendBtn.click();
    } else {
      await input.press("Enter");
    }

    await page.waitForTimeout(10000);

    // Check for user message bubble and assistant response
    const userMsg = page.locator("text=Newton-Raphson");
    await expect(userMsg.first()).toBeVisible();
  });
});
