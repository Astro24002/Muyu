import { describe, expect, it, vi } from 'vitest';
import { ApiClient } from '../src/api/client';

describe('life API client', () => {
  it('keeps ledger summary independent from the filtered entry list', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
      const path = String(input);
      if (path.includes('/ledger/summary')) {
        return new Response(JSON.stringify({ month: '2026-09', expense_minor: 1200, income_minor: 0, balance_minor: -1200, categories: [], payer_totals: [] }), { status: 200 });
      }
      return new Response(JSON.stringify({ items: [] }), { status: 200 });
    });

    const api = new ApiClient();
    await api.getLedgerSummary('2026-09');
    await api.listLedger({ month: '2026-09', type: 'INCOME' });

    expect(fetchMock.mock.calls.map(([input]) => String(input))).toEqual([
      '/api/v1/ledger/summary?month=2026-09',
      '/api/v1/ledger?month=2026-09&type=INCOME',
    ]);
    fetchMock.mockRestore();
  });

  it('sends life mutations with request ids and expected versions', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementation(async () => (
      new Response(JSON.stringify({ id: 'entry-1', cursor: 4 }), { status: 200 })
    ));
    const api = new ApiClient();
    await api.patchLedger('entry-1', { requestId: 'request-1', expectedVersion: 2, changes: { title: '晚餐' } });
    await api.deleteLedger('entry-1', { requestId: 'request-2', expectedVersion: 3, confirm: true });
    await api.habitAction('habit-1', 'checkin', { requestId: 'request-3', expectedVersion: 1 });
    await api.prepareAnniversary('anniversary-1', 'request-4');

    expect(fetchMock.mock.calls.map(([input, init]) => [String(input), init?.method, init?.body])).toEqual([
      ['/api/v1/ledger/entry-1', 'PATCH', JSON.stringify({ request_id: 'request-1', expected_version: 2, changes: { title: '晚餐' } })],
      ['/api/v1/ledger/entry-1', 'DELETE', JSON.stringify({ request_id: 'request-2', expected_version: 3, confirm: true })],
      ['/api/v1/habits/habit-1/checkin', 'POST', JSON.stringify({ request_id: 'request-3', expected_version: 1 })],
      ['/api/v1/anniversaries/anniversary-1/prepare', 'POST', JSON.stringify({ request_id: 'request-4' })],
    ]);
    fetchMock.mockRestore();
  });
});
