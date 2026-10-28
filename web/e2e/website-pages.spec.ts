import { test, expect } from "@playwright/test";

test("Pages 仓库子路径直接显示官网，资源完整且 Web 链接指向正式应用", async ({
  page,
}) => {
  const failed: string[] = [];
  const apis: string[] = [];
  page.on("pageerror", (error) => failed.push(error.message));
  page.on("response", (response) => {
    if (response.status() >= 400) failed.push(response.url());
  });
  page.on("requestfailed", (request) => failed.push(request.url()));
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.startsWith("/api/"))
      apis.push(request.url());
  });
  await page.goto("./");
  await expect(page.getByRole("heading", { level: 1 })).toContainText(
    "一起，把日子",
  );
  await expect(
    page.getByRole("link", { name: "打开 Web", exact: true }).first(),
  ).toHaveAttribute("href", "https://muyu.bkverse.space/");
  for (const width of [320, 360, 393, 412, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    for (const label of ["事项", "记账", "打卡", "纪念日"]) {
      await page.getByRole("button", { name: label, exact: true }).click();
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      ).toBe(true);
    }
  }
  await page.getByRole("link", { name: "了解 Muyu" }).click();
  await expect(page).toHaveURL(/\/Muyu\/#features$/);
  await page.reload();
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  expect(failed).toEqual([]);
  expect(apis).toEqual([]);
});

test.describe("手机阅读与触控", () => {
  test.use({ isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

  test("手机正文可读、操作易点且大字模式完整重排", async ({ page }) => {
    await page.goto("./");
    for (const width of [320, 360, 393, 412]) {
      await page.setViewportSize({ width, height: 851 });
      for (const selector of [
        ".hero-description",
        ".feature-copy p",
        ".section-heading > p",
        ".step p",
      ]) {
        const sizes = await page
          .locator(selector)
          .evaluateAll((elements) =>
            elements.map((e) => parseFloat(getComputedStyle(e).fontSize)),
          );
        expect(Math.min(...sizes), selector).toBeGreaterThanOrEqual(16);
      }
      const controls = page.locator(
        ".header-inner a, .hero-actions a, .feature-picker button, .start-actions a, .footer a",
      );
      for (const control of await controls.all()) {
        if (await control.isVisible())
          expect((await control.boundingBox())!.height).toBeGreaterThanOrEqual(
            44,
          );
      }
      for (const name of ["事项", "记账", "打卡", "纪念日"]) {
        await page.getByRole("button", { name, exact: true }).tap();
        await expect(
          page.getByRole("button", { name, exact: true }),
        ).toHaveAttribute("aria-pressed", "true");
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth,
          ),
        ).toBe(true);
      }
      await page.evaluate(
        () => (document.documentElement.style.fontSize = "200%"),
      );
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      ).toBe(true);
      await page.evaluate(() => (document.documentElement.style.fontSize = ""));
    }
    await page.setViewportSize({ width: 851, height: 393 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  });
});
