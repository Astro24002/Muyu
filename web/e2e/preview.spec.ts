import { test, expect } from './fixtures';

test('本地示例预览覆盖四个主入口且不访问 API', async ({ page, workbench }) => {
  const apiRequests: string[] = [];
  const originalViewport = page.viewportSize();
  page.on('request', (request) => {
    if (new URL(request.url()).pathname.startsWith('/api/')) apiRequests.push(request.url());
  });
  await workbench.goto('/?preview=matters#/matters/moment');

  await expect(page.getByText('示例数据 · 操作仅在当前页面有效 · 不连接生产 API')).toBeVisible();
  await expect(page.getByRole('button', { name: /即将到期/ })).toBeVisible();
  await expect(page.getByRole('region', { name: '已完成/已归档' })).toContainText('完成周末行程初稿');
  const nav = page.getByRole('navigation', { name: '主导航' });
  for (const [label, heading] of [['记账', '记账'], ['打卡', '打卡'], ['我的', '我的']] as const) {
    await nav.getByRole('link', { name: label }).click();
    await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
    await assertNoHorizontalOverflow(page);
  }
  await page.getByRole('button', { name: '全部事情' }).click();
  await expect(page.getByRole('heading', { name: '全部事情' })).toBeVisible();
  await expect(page.getByRole('searchbox', { name: '搜索全部事情' })).toBeVisible();
  await page.getByLabel('任务范围').selectOption('done');
  await expect(page.getByRole('heading', { name: '完成周末行程初稿' })).toBeVisible();
  await expect(page.getByRole('button', { name: '开始' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: '记下一件事' })).toHaveCount(0);
  for (const width of [320, 360, 393, 412]) {
    await page.setViewportSize({ width, height: 851 });
    await assertNoHorizontalOverflow(page);
  }
  if (originalViewport) await page.setViewportSize(originalViewport);
  await page.getByRole('button', { name: '返回我的' }).click();
  await expect(page.getByRole('heading', { name: '我的', exact: true })).toBeVisible();
  await nav.getByRole('link', { name: '事项' }).click();

  for (const width of [320, 360, 393, 412]) {
    await page.setViewportSize({ width, height: 851 });
    for (const [label, heading] of [['记账', '记账'], ['打卡', '打卡'], ['我的', '我的']] as const) {
      await nav.getByRole('link', { name: label }).click();
      await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
      await assertNoHorizontalOverflow(page);
    }
    await nav.getByRole('link', { name: '事项' }).click();
    await expect(page.getByRole('button', { name: '此刻' })).toBeVisible();
    await assertNoHorizontalOverflow(page);
  }
  if (originalViewport) await page.setViewportSize(originalViewport);
  expect(apiRequests).toEqual([]);
});

async function assertNoHorizontalOverflow(page: import('@playwright/test').Page): Promise<void> {
  const widths = await page.evaluate(() => ({
    viewport: document.documentElement.clientWidth,
    page: document.documentElement.scrollWidth,
  }));
  expect(widths.page).toBeLessThanOrEqual(widths.viewport);
}
