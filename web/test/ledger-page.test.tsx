import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { LedgerEntry, LedgerSummary } from '../src/api/types';
import { LedgerPage } from '../src/pages/LedgerPage';
import { render } from './react-test-helpers';

const summary: LedgerSummary = {
  month: '2026-09', currency: 'CNY', expense_minor: 1200, income_minor: 0, balance_minor: -1200,
  categories: [], payer_totals: [],
};
const entry = (type: LedgerEntry['type']): LedgerEntry => ({
  id: `entry-${type.toLowerCase()}`, workspace_id: 'workspace-1', type, amount_minor: 1200,
  amount: '12.00', currency: 'CNY', title: type === 'EXPENSE' ? '早餐' : '报销', category: '餐饮',
  payer_or_payee_id: 'viewer', payer_or_payee_name: '我', date: '2026-09-17', note: null,
  created_by: 'viewer', updated_by: 'viewer', version: 1, deleted_at: null,
});

describe('LedgerPage', () => {
  it('loads the summary once and filters only the visible detail list', async () => {
    vi.setSystemTime(new Date('2026-09-17T12:00:00.000Z'));
    const api = {
      getLedgerSummary: vi.fn().mockResolvedValue(summary),
      listLedger: vi.fn().mockImplementation(({ type }: { type?: LedgerEntry['type'] }) => (
        Promise.resolve(type === 'INCOME' ? [entry('INCOME')] : [entry('EXPENSE'), entry('INCOME')])
      )),
    };
    render(<LedgerPage api={api as never} members={[]} viewerId="viewer" canWrite={false} />);
    await waitFor(() => expect(screen.getByText('早餐')).toBeInTheDocument());
    expect(screen.getByText('¥-12.00')).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('明细类型'), { target: { value: 'INCOME' } });
    await waitFor(() => expect(api.listLedger).toHaveBeenLastCalledWith({ month: '2026-09', type: 'INCOME' }));
    expect(api.getLedgerSummary).toHaveBeenCalledTimes(1);
    expect(screen.queryByText('早餐')).not.toBeInTheDocument();
    expect(screen.getByText('报销')).toBeInTheDocument();
    expect(screen.getByText('¥-12.00')).toBeInTheDocument();
  });
});
