import { fireEvent, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { MattersPreviewPage } from '../src/pages/MattersPreviewPage';
import { render } from './react-test-helpers';

afterEach(() => {
  vi.unstubAllGlobals();
  window.history.replaceState(null, '', '/');
});

describe('MattersPreviewPage', () => {
  it('shows example data and lets the user switch views without calling an API', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    render(<MattersPreviewPage />);

    expect(screen.getByText('示例数据 · 操作仅在当前页面有效 · 不连接生产 API')).toBeInTheDocument();
    expect(screen.getByLabelText('事项入口指标')).toHaveTextContent('需要我处理');
    expect(screen.getByLabelText('事项入口指标')).toHaveTextContent('3');
    fireEvent.click(screen.getByRole('button', { name: /即将到期/ }));
    expect(screen.getByRole('button', { name: '开始' })).toBeDisabled();

    fireEvent.click(screen.getByRole('button', { name: '此刻' }));
    fireEvent.click(screen.getByRole('menuitemradio', { name: '四象限' }));

    expect(await screen.findByRole('group', { name: '负责人筛选' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'TA 负责' }));
    expect(screen.getByRole('heading', { name: '确认周末出行路线' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: '安排周末晚餐' })).not.toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('previews all four primary sections with in-memory life-domain interactions', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    render(<MattersPreviewPage />);

    fireEvent.click(screen.getByRole('link', { name: '记账' }));
    expect(await screen.findByRole('heading', { name: '记账' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '记一笔' }));
    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '公交出行' } });
    fireEvent.change(screen.getByLabelText('金额（元）'), { target: { value: '15.00' } });
    fireEvent.change(screen.getByLabelText('分类'), { target: { value: '交通' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));
    expect(await screen.findByText('公交出行')).toBeInTheDocument();
    expect(screen.getByLabelText('月度汇总')).toHaveTextContent('¥170.30');

    fireEvent.click(screen.getByRole('link', { name: '打卡' }));
    expect(await screen.findByRole('heading', { name: '打卡' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '打卡' }));
    expect(await screen.findByText('本期已完成 2 / 2 项')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('link', { name: '我的' }));
    expect(await screen.findByRole('heading', { name: '我的' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '全部事情' }));
    expect(await screen.findByRole('heading', { name: '全部事情' })).toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
