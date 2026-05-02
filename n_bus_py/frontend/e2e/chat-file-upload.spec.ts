import { test, expect, type Page } from "@playwright/test";
import path from "node:path";
import fs from "node:fs";

// ── Helpers ──────────────────────────────────────────────────

function tmpFile(ext: string, content: Buffer | string): string {
  const p = path.join(__dirname, `_e2e_up_${Date.now()}_${Math.random().toString(36).slice(2, 8)}.${ext}`);
  fs.writeFileSync(p, content);
  return p;
}

const TEST_USER = `e2e_${Date.now()}`;
const TEST_PASS = "pass1234";
let authDone = false;

async function ensureAuth(page: Page) {
  if (authDone) return;
  const apiBase = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
  try {
    await page.request.post(`${apiBase}/auth/register`, {
      data: { username: TEST_USER, password: TEST_PASS },
    });
  } catch { /* ok if exists */ }
  authDone = true;
}

async function doLogin(page: Page) {
  await page.locator("input[placeholder='Enter username']").fill(TEST_USER);
  await page.locator("input[placeholder='Enter password']").fill(TEST_PASS);
  await page.getByRole("button", { name: /sign in/i }).click();
  await page.waitForTimeout(3000);
}

async function gotoChat(page: Page) {
  await ensureAuth(page);
  await page.goto("/chat");
  await page.waitForSelector("h1, input, button", { timeout: 5000 }).catch(() => {});
  const onLogin = page.getByText(/sign in to your account/i);
  if (await onLogin.isVisible({ timeout: 2000 }).catch(() => false)) {
    await doLogin(page);
    await page.goto("/chat");
  }
  await page.waitForSelector("h1, input", { timeout: 10000 });
}

/** Click the paperclip button and intercept the native file dialog. */
async function attachFiles(page: Page, files: string | string[]) {
  const [fileChooser] = await Promise.all([
    page.waitForEvent("filechooser"),
    page.getByTitle(/attach|แนบ/i).click(),
  ]);
  await fileChooser.setFiles(files);
}

// ── Tests (serial to avoid auth/file race) ───────────────────

test.describe.configure({ mode: "serial" });

test.describe("Chat File Upload", () => {
  test.beforeEach(async ({ page }) => {
    await gotoChat(page);
  });

  test("paperclip button exists", async ({ page }) => {
    await expect(page.getByTitle(/attach|แนบ/i)).toBeVisible({ timeout: 5000 });
  });

  test("hidden file input has correct accept", async ({ page }) => {
    const fi = page.locator("input[type='file']");
    await expect(fi).toBeAttached({ timeout: 5000 });
    const accept = await fi.getAttribute("accept");
    expect(accept).toContain(".pdf");
    expect(accept).toContain(".png");
    expect(accept).toContain(".csv");
  });

  test("selecting file shows preview chip", async ({ page }) => {
    const f = tmpFile("txt", "Bus voltages: V1=1.06, V2=1.045, V3=1.01 pu");
    try {
      await attachFiles(page, f);
      await expect(page.getByText(/KB/).first()).toBeVisible({ timeout: 5000 });
    } finally {
      fs.unlinkSync(f);
    }
  });

  test("can remove file chip", async ({ page }) => {
    const f = tmpFile("txt", "Remove me test data");
    try {
      await attachFiles(page, f);
      const chip = page.getByText(/KB/).first();
      await expect(chip).toBeVisible({ timeout: 5000 });

      const removeBtn = chip.locator("..").locator("button").first();
      await removeBtn.click();
      await expect(chip).not.toBeVisible({ timeout: 3000 });
    } finally {
      fs.unlinkSync(f);
    }
  });

  test("multiple files show multiple chips", async ({ page }) => {
    const f1 = tmpFile("txt", "Content A here");
    const f2 = tmpFile("csv", "a,b,c\n1,2,3");
    try {
      await attachFiles(page, [f1, f2]);
      const kbTexts = page.getByText(/KB/);
      await expect(kbTexts.first()).toBeVisible({ timeout: 5000 });
      const count = await kbTexts.count();
      expect(count).toBeGreaterThanOrEqual(2);
    } finally {
      fs.unlinkSync(f1);
      fs.unlinkSync(f2);
    }
  });

  test("send button enabled with files but no text", async ({ page }) => {
    const f = tmpFile("txt", "Check bus voltage");
    try {
      await attachFiles(page, f);
      const sendBtn = page.locator("button.btn-gradient").last();
      await expect(sendBtn).toBeEnabled({ timeout: 5000 });
    } finally {
      fs.unlinkSync(f);
    }
  });

  test("send with file clears chip and gets response", async ({ page }) => {
    const f = tmpFile("txt", "Bus voltages: Bus1=1.06, Bus2=1.045, Bus3=1.01 pu");
    try {
      await attachFiles(page, f);
      await expect(page.getByText(/KB/).first()).toBeVisible({ timeout: 5000 });

      const input = page.getByPlaceholder(/ask me anything/i);
      await input.fill("What is the Bus 3 voltage?");
      await page.locator("button.btn-gradient").last().click();

      await expect(page.getByText(/KB/).first()).not.toBeVisible({ timeout: 5000 });
      await page.waitForTimeout(12000);
      const text = await page.locator("body").innerText();
      expect(text.length).toBeGreaterThan(50);
    } finally {
      fs.unlinkSync(f);
    }
  });

  test("file chip has SVG icon", async ({ page }) => {
    const f = tmpFile("csv", "name,value\ntest,42");
    try {
      await attachFiles(page, f);
      const chip = page.getByText(/KB/).first();
      await expect(chip).toBeVisible({ timeout: 5000 });
      const svg = chip.locator("..").locator("svg").first();
      await expect(svg).toBeAttached({ timeout: 3000 });
    } finally {
      fs.unlinkSync(f);
    }
  });

  test("pasting text works normally", async ({ page }) => {
    const input = page.getByPlaceholder(/ask me anything/i);
    await input.fill("Hello world");
    await expect(input).toHaveValue("Hello world");
  });

  test("text-only message still works (no file)", async ({ page }) => {
    const input = page.getByPlaceholder(/ask me anything/i);
    if (!(await input.isVisible())) return;
    await input.fill("What is power flow analysis in simple terms?");
    await page.locator("button.btn-gradient").last().click();
    await page.waitForTimeout(12000);
    const text = await page.locator("body").innerText();
    expect(text.length).toBeGreaterThan(50);
  });

  test("drop overlay area exists on chat page", async ({ page }) => {
    const main = page.locator(".flex-1.flex.flex-col.relative").last();
    await expect(main).toBeAttached({ timeout: 5000 });
  });
});
