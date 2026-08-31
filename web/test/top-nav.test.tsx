import { fireEvent, screen, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { AppShell } from '../src/components/layout/AppShell';
import { TopNav } from '../src/components/layout/TopNav';
import type { Route } from '../src/app/routes';
import { render } from './react-test-helpers';

describe('TopNav', () => {
  it('renders exactly four primary links and marks the current route', () => {
    const onNavigate = vi.fn();
    const route: Route = { kind: 'approvals' };

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
    expect(links.map((link) => link.textContent)).toEqual(['今天', '所有任务', '审批3', '动态']);

    const activeLink = within(nav).getByRole('link', { name: /审批/ });
    expect(activeLink).toHaveAttribute('aria-current', 'page');
    expect(activeLink).toHaveClass('top-nav__link--active');
    expect(activeLink).toHaveAttribute('data-active-indicator', 'true');

    fireEvent.click(within(nav).getByRole('link', { name: '今天' }));
    expect(onNavigate).toHaveBeenCalledWith({ kind: 'today' });
  });

  it('keeps the approval badge text readable and makes actions functional', () => {
    const onCreateTask = vi.fn();
    const onLogout = vi.fn();
    const onNavigate = vi.fn();

    render(
      <AppShell
        route={{ kind: 'today' }}
        onNavigate={onNavigate}
        onLogout={onLogout}
        onCreateTask={onCreateTask}
        pendingApprovalCount={2}
      >
        <p>页面内容</p>
      </AppShell>,
    );

    expect(screen.getByLabelText('2 个待处理审批')).toHaveTextContent('2');
    expect(screen.getByRole('button', { name: '搜索' })).toHaveAttribute('title', '搜索');
    expect(screen.getByRole('button', { name: '新建任务' })).toHaveAttribute('title', '新建任务');
    expect(screen.getByRole('button', { name: '用户菜单' })).toHaveAttribute('title', '用户菜单');

    fireEvent.click(screen.getByRole('button', { name: '新建任务' }));
    expect(onCreateTask).toHaveBeenCalledOnce();

    fireEvent.click(screen.getByRole('button', { name: '搜索' }));
    const searchDialog = screen.getByRole('dialog', { name: '搜索' });
    expect(within(searchDialog).getByRole('searchbox', { name: '搜索任务' })).toBeVisible();
    fireEvent.change(within(searchDialog).getByRole('searchbox', { name: '搜索任务' }), { target: { value: '周报' } });
    expect(within(searchDialog).getByRole('searchbox', { name: '搜索任务' })).toHaveValue('周报');

    fireEvent.click(screen.getByRole('button', { name: '用户菜单' }));
    fireEvent.click(screen.getByRole('button', { name: '退出登录' }));
    expect(onLogout).toHaveBeenCalledOnce();
  });
});
