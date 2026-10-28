import { test, expect } from './fixtures';
import type { Page, TestInfo } from '@playwright/test';

test.describe('行动工作台视觉工作流', () => {
  test('二维码登录保持确定性且不暴露凭据', async ({ page, workbench }, testInfo) => {
    await workbench.setup({ authenticated: false });
    await workbench.goto('#/today');

    await expect(page.getByTestId('qr-login-page')).toBeVisible();
    await expect(page.getByRole('heading', { name: '二维码登录' })).toBeVisible();
    await expect(page.locator('canvas[aria-label="登录二维码"]')).toBeVisible();
    await expect(page.getByText('请在手机上确认登录。')).toBeVisible();
    await expect(page.locator('body')).not.toContainText('browser_proof');
    await expect(page.locator('body')).not.toContainText('session_token');
    await assertNoHorizontalOverflow(page);
    await capture(page, testInfo, 'qr-login.png');
  });

  test('旧 /today 路由兼容到此刻并保留当前事项', async ({ page, workbench }, testInfo) => {
    await workbench.setup({ todayFocus: true });
    await workbench.goto('#/today');

    await expect(page.locator('[data-matters-page][data-matters-view="moment"]')).toBeVisible();
    await expect(page.getByRole('button', { name: '此刻' })).toBeVisible();
    await expect(page.locator('[data-task-row="task-focus"]')).toContainText('整理周末晚餐');
    await assertMigratedSurface(page);
    await capture(page, testInfo, 'today-with-focus.png');
  });

  test('旧 /today 路由在任务待开始时仍展示事项列表', async ({ page, workbench }, testInfo) => {
    await workbench.setup({ todayFocus: false });
    await workbench.goto('#/today');

    await expect(page.locator('[data-matters-page][data-matters-view="moment"]')).toBeVisible();
    await expect(page.getByRole('button', { name: '此刻' })).toBeVisible();
    await expect(page.locator('[data-task-row="task-next"]')).toBeVisible();
    await assertMigratedSurface(page);
    await capture(page, testInfo, 'today-without-focus.png');
  });

  test('事项视图支持标题菜单、指标入口、负责人筛选和月历', async ({ page, workbench }, testInfo) => {
    await page.clock.install({ time: new Date('2026-09-01T12:00:00Z') });
    await workbench.setup();
    await workbench.goto('#/matters/moment');

    await expect(page.getByRole('button', { name: '此刻' })).toBeVisible();
    await page.getByRole('button', { name: /即将到期/ }).click();
    await expect(page.getByRole('region', { name: '即将到期' })).toContainText('整理周末晚餐');
    await page.getByRole('button', { name: '收起指标详情' }).click();
    await expect(page.getByRole('region', { name: '已完成/已归档' })).toContainText('已完成的整理');
    await expect(page.locator('[data-task-row="task-done"]')).toHaveCount(1);

    await page.getByRole('button', { name: '此刻' }).click();
    await expect(page.getByRole('menuitemradio', { name: '清单' })).toBeFocused();
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Enter');
    await expect(page.locator('[data-matters-view="quadrant"]')).toBeVisible();
    await page.getByRole('button', { name: 'TA 负责' }).click();
    await expect(page.getByRole('region', { name: '紧急不重要' })).toContainText('等待书单确认');

    await page.getByRole('button', { name: '四象限' }).click();
    await page.getByRole('menuitemradio', { name: '日程' }).click();
    await expect(page.getByRole('heading', { name: '2026年9月' })).toBeVisible();
    await page.getByRole('button', { name: /2026年9月2日/ }).click();
    await expect(page.getByRole('region', { name: /9月2日.*到期事项/ })).toContainText('整理周末晚餐');
    await expect(page.getByRole('button', { name: '2026年9月2日' })).toHaveAttribute('aria-pressed', 'true');

    await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name: '我的' }).click();
    await page.getByRole('button', { name: '全部事情' }).click();
    await expect(page.getByRole('heading', { name: '全部事情' })).toBeVisible();
    await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name: '事项' }).click();
    await expect(page.locator('[data-matters-view="schedule"]')).toBeVisible();
    await expect(page.getByRole('button', { name: '2026年9月2日' })).toHaveAttribute('aria-pressed', 'true');

    const originalViewport = page.viewportSize();
    for (const width of [320, 360, 393, 412]) {
      await page.setViewportSize({ width, height: 851 });
      await assertNoHorizontalOverflow(page);
      await expect(page.getByRole('heading', { name: '2026年9月' })).toBeVisible();
      await expect(page.getByRole('button', { name: '回到今天' })).toBeVisible();
    }
    if (originalViewport) await page.setViewportSize(originalViewport);
    await capture(page, testInfo, 'matters-schedule-workflow.png');
  });

  test('所有任务筛选保持线性列表布局', async ({ page, workbench }, testInfo) => {
    await workbench.setup();
    await workbench.goto('#/tasks');

    await expect(page.getByRole('heading', { name: '全部事情' })).toBeVisible();
    await page.getByRole('combobox', { name: '状态', exact: true }).selectOption('BLOCKED');
    await expect(page.locator('[data-task-row="task-waiting"]')).toBeVisible();
    await expect(page.locator('[data-task-row="task-focus"]')).toHaveCount(0);
    await assertMigratedSurface(page);
    await capture(page, testInfo, 'all-tasks-filter.png');
  });

  test('审批页展示 incoming/outgoing 和待处理数量', async ({ page, workbench }, testInfo) => {
    await workbench.setup();
    await workbench.goto('#/approvals');

    await expect(page.getByRole('heading', { name: '审批', exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: '需要我确认' })).toBeVisible();
    await expect(page.getByRole('heading', { name: '等待对方确认' })).toBeVisible();
    await expect(page.getByText('待确认：1')).toBeVisible();
    await expect(page.getByText('伙伴提出的新标题')).toBeVisible();
    await expect(page.getByRole('button', { name: '批准' })).toBeVisible();
    await expect(page.getByRole('button', { name: '拒绝' })).toBeVisible();
    await expect(page.getByRole('button', { name: '取消请求' })).toBeVisible();
    await assertMigratedSurface(page);
    await capture(page, testInfo, 'approvals.png');
  });

  test('动态页按需加载固定活动记录', async ({ page, workbench }, testInfo) => {
    await workbench.setup();
    await workbench.goto('#/activity');

    await expect(page.getByRole('heading', { name: '动态' })).toBeVisible();
    await expect(page.getByText('最近记录')).toBeVisible();
    await expect(page.getByText('已更新任务信息')).toBeVisible();
    await expect(page.locator('.activity-row').filter({ hasText: '整理周末晚餐' }).first()).toBeVisible();
    await assertMigratedSurface(page);
    await capture(page, testInfo, 'activity.png');
  });

  test('任务详情在列表上下文中展示冲突和活动', async ({ page, workbench }, testInfo) => {
    await workbench.setup({ conflicts: true });
    await workbench.goto('#/tasks');
    const taskOpen = page.locator('[data-task-row="task-focus"] .task-row__open');
    await expect(taskOpen).toBeVisible();
    await taskOpen.click();

    const panel = page.locator('.task-detail-panel');
    await expect(panel).toBeVisible();
    await expect(panel).toContainText('整理周末晚餐');
    await expect(page.locator('.conflict-panel')).toContainText('待处理冲突');
    await expect(page.getByRole('button', { name: '保留当前' })).toBeVisible();
    await expect(page.getByRole('button', { name: '采用提议' })).toBeVisible();
    await expect(page.getByText('已更新任务信息')).toBeVisible();
    await expect(page.locator('[data-all-tasks-page]')).toBeVisible();

    const viewport = page.viewportSize();
    if (viewport && viewport.width < 1024) {
      await expect(panel).toHaveAttribute('data-panel-mode', 'bottom-sheet');
      const sheetLayout = await panel.evaluate((element) => {
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return {
          position: style.position,
          width: rect.width,
          viewportWidth: window.innerWidth,
          viewportHeight: window.innerHeight,
          bottom: style.bottom,
          maxHeight: style.maxHeight,
        };
      });
      expect(sheetLayout.position).toBe('fixed');
      expect(sheetLayout.width).toBe(sheetLayout.viewportWidth);
      expect(sheetLayout.bottom).toBe('0px');
      expect(Number.parseFloat(sheetLayout.maxHeight)).toBeLessThanOrEqual(sheetLayout.viewportHeight * 0.88 + 1);
    } else {
      await expect(panel).toHaveAttribute('data-panel-mode', 'drawer');
      await expect(panel).toHaveCSS('position', 'fixed');
    }
    if (viewport && viewport.width < 640) {
      const stacked = await page.locator('.task-edit-form__secondary .task-detail-field').evaluateAll((fields) => {
        const boxes = fields.map((field) => {
          const rect = field.getBoundingClientRect();
          return { top: rect.top, bottom: rect.bottom };
        });
        return boxes.every((box, index) => index === 0 || box.top >= boxes[index - 1].bottom - 1);
      });
      expect(stacked).toBe(true);
      const inlineLayout = await page.locator('.task-detail-inline-form').first().evaluate((element) => getComputedStyle(element).gridTemplateColumns);
      expect(inlineLayout.split(' ').length).toBe(1);
    }

    await assertNoHorizontalOverflow(page);
    await capture(page, testInfo, 'task-detail-conflict.png');
  });

  test('迁移路由满足基础键盘和语义契约', async ({ page, workbench }) => {
    await workbench.setup();
    for (const route of ['#/today', '#/tasks', '#/approvals', '#/activity', '#/tasks/task-focus']) {
      await workbench.goto(route);
      if (route === '#/today') await expect(page.locator('[data-matters-page][data-matters-view="moment"]')).toBeVisible();
      if (route === '#/tasks') await expect(page.locator('[data-all-tasks-page]')).toBeVisible();
      if (route === '#/approvals') await expect(page.locator('[data-approvals-page]')).toBeVisible();
      if (route === '#/activity') await expect(page.locator('[data-activity-page]')).toBeVisible();
      if (route === '#/tasks/task-focus') await expect(page.locator('.task-detail-panel')).toBeVisible();
      await assertAccessibilityContract(page);
    }

    await page.goto('/#/today');
    await expect(page.locator('[data-matters-page][data-matters-view="moment"]')).toBeVisible();
    const userMenuButton = page.getByRole('button', { name: '用户菜单' });
    await userMenuButton.click();
    const userDialog = page.getByRole('dialog', { name: '用户菜单' });
    await expect(userDialog).toBeVisible();
    await expect(userDialog).toHaveAttribute('aria-modal', 'false');
    await expect(userMenuButton).toHaveAttribute('aria-haspopup', 'dialog');
    await page.keyboard.press('Escape');
    await expect(userDialog).toHaveCount(0);
    await expect(userMenuButton).toBeFocused();
  });
});

async function assertMigratedSurface(page: Page): Promise<void> {
  await expect(page.locator('.app-shell')).toBeVisible();
  await expect(page.locator('header.top-nav')).toBeVisible();
  await expect(page.locator('nav[aria-label="主导航"]')).toBeVisible();
  await assertNoHorizontalOverflow(page);
  const darkSidebars = await page.evaluate(() => Array.from(document.querySelectorAll<HTMLElement>('*')).filter((element) => {
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    const channels = style.backgroundColor.match(/\d+(?:\.\d+)?/g)?.map(Number) ?? [];
    return style.position === 'fixed'
      && rect.height >= window.innerHeight * 0.7
      && rect.width >= Math.min(240, window.innerWidth * 0.3)
      && channels.length >= 3
      && channels[0] < 80 && channels[1] < 90 && channels[2] < 90;
  }).map((element) => element.className));
  expect(darkSidebars).toEqual([]);
}

async function assertNoHorizontalOverflow(page: Page): Promise<void> {
  const result = await page.evaluate(() => {
    const visible = (element: HTMLElement): boolean => {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
    };
    const textOverflow = Array.from(document.querySelectorAll<HTMLElement>('h1,h2,h3,p,span,strong,a,button,label'))
      .filter((element) => visible(element) && element.textContent?.trim() && element.scrollWidth > element.clientWidth + 1)
      .filter((element) => getComputedStyle(element).whiteSpace !== 'nowrap')
      .map((element) => element.textContent?.trim().slice(0, 80) ?? '');
    return {
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
      documentOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
      textOverflow,
      rightOverflow: Array.from(document.querySelectorAll<HTMLElement>('body *'))
        .filter(visible)
        .map((element) => ({ element, rect: element.getBoundingClientRect() }))
        .filter(({ rect }) => rect.right > document.documentElement.clientWidth + 1)
        .slice(0, 8)
        .map(({ element, rect }) => ({
          node: `${element.tagName.toLowerCase()}.${typeof element.className === 'string' ? element.className : ''}`,
          id: element.id,
          left: rect.left,
          right: rect.right,
          width: rect.width,
        })),
    };
  });
  expect(result.documentOverflow, JSON.stringify(result)).toBe(false);
  expect(result.textOverflow).toEqual([]);
}

async function assertAccessibilityContract(page: Page): Promise<void> {
  const result = await page.evaluate(() => {
    const visible = (element: HTMLElement): boolean => {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
    };
    const unlabeledFields = Array.from(document.querySelectorAll<HTMLElement>('input,select,textarea'))
      .filter(visible)
      .filter((element) => {
        if (element.getAttribute('aria-label') || element.getAttribute('aria-labelledby')) return false;
        const id = element.getAttribute('id');
        return !element.closest('label') && !(id && document.querySelector(`label[for="${CSS.escape(id)}"]`));
      })
      .map((element) => element.outerHTML.slice(0, 120));
    const unlabeledIconButtons = Array.from(document.querySelectorAll<HTMLButtonElement>('button'))
      .filter(visible)
      .filter((element) => !element.getAttribute('aria-label') && !element.title && !(element.textContent ?? '').trim())
      .map((element) => element.outerHTML.slice(0, 120));
    const nestedInteractive = Array.from(document.querySelectorAll<HTMLElement>('a,button,input,select,textarea,[role="button"],[role="link"]'))
      .filter((element) => element.querySelector('a,button,input,select,textarea,[role="button"],[role="link"]'))
      .map((element) => element.outerHTML.slice(0, 120));
    const malformedErrors = Array.from(document.querySelectorAll<HTMLElement>('[class*="error"]'))
      .filter(visible)
      .filter((element) => element.getAttribute('role') !== 'alert')
      .map((element) => element.outerHTML.slice(0, 120));
    const busyWithoutLive = Array.from(document.querySelectorAll<HTMLElement>('[aria-busy="true"]'))
      .filter((element) => !element.getAttribute('aria-live'))
      .map((element) => element.outerHTML.slice(0, 120));
    const currentNavigation = document.querySelectorAll('nav[aria-label="主导航"] [aria-current]').length;
    return { unlabeledFields, unlabeledIconButtons, nestedInteractive, malformedErrors, busyWithoutLive, currentNavigation };
  });

  expect(result.unlabeledFields).toEqual([]);
  expect(result.unlabeledIconButtons).toEqual([]);
  expect(result.nestedInteractive).toEqual([]);
  expect(result.malformedErrors).toEqual([]);
  expect(result.busyWithoutLive).toEqual([]);
  expect(result.currentNavigation).toBe(1);
  await expect(page.locator('[aria-live]')).not.toHaveCount(0);
  const newTaskButton = page.getByRole('button', { name: '新建任务' });
  if (await newTaskButton.count() > 0) {
    await expect(newTaskButton).not.toBeDisabled();
    expect(await newTaskButton.evaluate((element) => (element as HTMLButtonElement).tabIndex)).toBeGreaterThanOrEqual(0);
  }
}

async function capture(page: Page, testInfo: TestInfo, name: string): Promise<void> {
  await page.screenshot({ path: testInfo.outputPath(name), fullPage: true });
}
