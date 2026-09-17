import { fireEvent, screen, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { AppShell } from '../src/components/layout/AppShell';
import { TopNav } from '../src/components/layout/TopNav';
import type { Route } from '../src/app/routes';
import { render } from './react-test-helpers';

describe('TopNav', () => {
  it('renders exactly four primary links and marks the current route', () => {
    const onNavigate = vi.fn();
    const route: Route = { kind: 'me' };

    render(
      <TopNav
        route={route}
        onNavigate={onNavigate}
        onCreateTask={vi.fn()}
        pendingApprovalCount={3}
      />,
    );

    const nav = screen.getByRole('navigation', { name: '主导航' });
    const links = within(nav).getAllByRole('link');
    expect(links).toHaveLength(4);
    expect(links.map((link) => link.textContent)).toEqual(['事项', '记账', '打卡', '我的']);

    const activeLink = within(nav).getByRole('link', { name: '我的' });
    expect(activeLink).toHaveAttribute('aria-current', 'page');
    expect(activeLink).toHaveClass('top-nav__link--active');
    expect(activeLink).toHaveAttribute('data-active-indicator', 'true');

    fireEvent.click(within(nav).getByRole('link', { name: '事项' }));
    expect(onNavigate).toHaveBeenCalledWith({ kind: 'matters', view: 'moment' });
  });

  it('keeps actions functional and makes the task action contextual', () => {
    const onCreateTask = vi.fn();
    const onLogout = vi.fn();
    const onNavigate = vi.fn();

    render(
      <AppShell
        route={{ kind: 'matters', view: 'moment' }}
        onNavigate={onNavigate}
        onLogout={onLogout}
        onCreateTask={onCreateTask}
        pendingApprovalCount={2}
      >
        <p>页面内容</p>
      </AppShell>,
    );

    expect(screen.getByRole('button', { name: '搜索' })).toHaveAttribute('title', '搜索');
    expect(screen.getByRole('button', { name: '新建任务' })).toHaveAttribute('title', '新建任务');
    expect(screen.getByRole('button', { name: '用户菜单' })).toHaveAttribute('title', '用户菜单');

    fireEvent.click(screen.getByRole('button', { name: '新建任务' }));
    expect(onCreateTask).toHaveBeenCalledOnce();

    fireEvent.click(screen.getByRole('button', { name: '搜索' }));
    const searchDialog = screen.getByRole('dialog', { name: '搜索' });
    expect(searchDialog).toHaveAttribute('aria-modal', 'true');
    expect(within(searchDialog).getByRole('searchbox', { name: '搜索任务' })).toBeVisible();
    fireEvent.change(within(searchDialog).getByRole('searchbox', { name: '搜索任务' }), { target: { value: '周报' } });
    expect(within(searchDialog).getByRole('searchbox', { name: '搜索任务' })).toHaveValue('周报');

    fireEvent.click(screen.getByRole('button', { name: '用户菜单' }));
    fireEvent.click(screen.getByRole('button', { name: '退出登录' }));
    expect(onLogout).toHaveBeenCalledOnce();
  });

  it('restores focus to the search trigger after Escape and close-button dismissal', () => {
    render(
      <TopNav
        route={{ kind: 'ledger' }}
        onNavigate={vi.fn()}
      />,
    );

    const searchTrigger = screen.getByRole('button', { name: '搜索' });
    fireEvent.click(searchTrigger);
    expect(screen.getByRole('searchbox', { name: '搜索任务' })).toHaveFocus();

    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('dialog', { name: '搜索' })).toBeNull();
    expect(searchTrigger).toHaveFocus();

    fireEvent.click(searchTrigger);
    fireEvent.click(screen.getByRole('button', { name: '关闭搜索' }));
    expect(screen.queryByRole('dialog', { name: '搜索' })).toBeNull();
    expect(searchTrigger).toHaveFocus();
  });
});
