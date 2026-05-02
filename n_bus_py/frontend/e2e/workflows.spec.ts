import { test, expect } from "@playwright/test";

test.describe("Solver workflow separation", () => {
  test("left sidebar separates PF, CPF, and Optimization workflows", async ({ page }) => {
    await page.goto("/");

    await expect(page.getByRole("link", { name: /power flow/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /cpf stability/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /optimization/i })).toBeVisible();
  });

  test("CPF workflow uses P-V curve results", async ({ page }) => {
    await page.goto("/solve?group=cpf");

    await expect(page.getByRole("heading", { name: /cpf voltage stability/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /cpf pc/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /nr full jacobian/i })).toHaveCount(0);

    await page.getByRole("button", { name: /^run$/i }).click();
    await expect(page.getByRole("button", { name: /p-v curve/i })).toBeVisible({ timeout: 10000 });
    await expect(page.getByText(/final lambda|nose lambda/i).first()).toBeVisible();
  });

  test("Optimization workflow uses dispatch results", async ({ page }) => {
    await page.goto("/solve?group=opt");

    await expect(page.getByRole("heading", { name: /dispatch and opf/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /ed/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /opf/i })).toBeVisible();

    await page.getByRole("button", { name: /^run$/i }).click();
    await expect(page.getByRole("button", { name: /dispatch/i })).toBeVisible({ timeout: 10000 });
    await expect(page.getByText(/total cost|p dispatched/i).first()).toBeVisible();
  });
});
