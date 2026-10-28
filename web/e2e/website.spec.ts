import { test, expect } from "@playwright/test";

test("官网独立展示、功能切换、窄屏与原应用入口", async ({ page }) => {
  const apiRequests: string[] = [];
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.startsWith("/api/"))
      apiRequests.push(request.url());
  });
  await page.goto("/about/");
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "跳到正文" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#main$/);
  await expect(page.getByRole("heading", { level: 1 })).toContainText(
    "一起，把日子",
  );
  await page.getByRole("button", { name: "记账", exact: true }).click();
  await expect(page.getByRole("region", { name: "功能预览" })).toContainText(
    "每一笔，都心里有数",
  );
  await page.getByRole("button", { name: "打卡", exact: true }).click();
  await expect(page.getByRole("region", { name: "功能预览" })).toContainText(
    "小小坚持，彼此看见",
  );
  await page.getByRole("button", { name: "纪念日", exact: true }).click();
  await expect(page.getByRole("region", { name: "功能预览" })).toContainText(
    "把重要的日子，放在心上",
  );
  await page.getByRole("button", { name: "事项", exact: true }).click();
  await expect(page.getByRole("region", { name: "功能预览" })).toContainText(
    "下一步，清清楚楚",
  );
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
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  }
  await page.getByRole("link", { name: "了解 Muyu" }).click();
  await expect(page).toHaveURL(/#features$/);
  await expect(
    page.getByRole("link", { name: "下载 Android" }).first(),
  ).toHaveAttribute("href", "https://github.com/Astro24002/Muyu/releases");
  expect(apiRequests).toEqual([]);
  await page
    .getByRole("link", { name: "打开 Web", exact: true })
    .first()
    .click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator("#app")).not.toBeEmpty();
});
