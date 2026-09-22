import { ChevronLeft, ChevronRight, Plus, Trash2, X } from 'lucide-react';
import { useEffect, useRef, useState, type FormEvent, type JSX } from 'react';
import type { ApiClient } from '../api/client';
import { createRequestId } from '../api/client';
import type { LedgerEntry, LedgerEntryType, LedgerSummary, WorkspaceSnapshot } from '../api/types';
import { InlineError } from '../components/status/InlineError';
import { Button } from '../components/ui/Button';
import { IconButton } from '../components/ui/IconButton';
import { SectionHeading } from '../components/ui/SectionHeading';

type LedgerApi = Pick<ApiClient, 'getLedgerSummary' | 'listLedger' | 'createLedger' | 'patchLedger' | 'deleteLedger'>;
type Member = WorkspaceSnapshot['members'][number];
type LedgerFilter = 'ALL' | LedgerEntryType;

export interface LedgerPageProps {
  api: LedgerApi;
  members: Member[];
  viewerId?: string | null;
  canWrite: boolean;
  snapshotEntries?: LedgerEntry[];
}

export function LedgerPage({ api, members, viewerId, canWrite, snapshotEntries }: LedgerPageProps): JSX.Element {
  const [month, setMonth] = useState(() => monthKey(new Date()));
  const [filter, setFilter] = useState<LedgerFilter>('ALL');
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [summary, setSummary] = useState<LedgerSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editor, setEditor] = useState<LedgerEntry | null | undefined>(undefined);

  const loadEntries = async (): Promise<void> => {
    setLoading(true);
    setError(null);
    try {
      setEntries(snapshotEntries === undefined
        ? await api.listLedger({ month, ...(filter === 'ALL' ? {} : { type: filter }) })
        : filterSnapshotEntries(snapshotEntries, month, filter));
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setLoading(false);
    }
  };

  const refresh = async (forceRest = false): Promise<boolean> => {
    setLoading(true);
    setError(null);
    try {
      const [nextSummary, nextEntries] = await Promise.all([
        api.getLedgerSummary(month),
        forceRest || snapshotEntries === undefined
          ? api.listLedger({ month, ...(filter === 'ALL' ? {} : { type: filter }) })
          : Promise.resolve(filterSnapshotEntries(snapshotEntries, month, filter)),
      ]);
      setSummary(nextSummary);
      setEntries(nextEntries);
      return true;
    } catch (cause) {
      setError(errorMessage(cause));
      return false;
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void refresh(); }, [month, snapshotEntries]);
  const filterMounted = useRef(false);
  useEffect(() => {
    if (!filterMounted.current) {
      filterMounted.current = true;
      return;
    }
    void loadEntries();
  }, [filter, snapshotEntries]);

  const monthDate = new Date(`${month}-01T00:00:00`);
  const moveMonth = (delta: number): void => {
    setMonth(monthKey(new Date(monthDate.getFullYear(), monthDate.getMonth() + delta, 1)));
  };

  return (
    <main className="life-page ledger-page" data-ledger-page>
      <header className="life-page__header">
        <div><p className="life-page__eyebrow">共享账本</p><h1>记账</h1></div>
        {canWrite ? <Button onClick={() => setEditor(null)}><Plus aria-hidden="true" size={16} />记一笔</Button> : null}
      </header>
      <div className="life-page__toolbar" aria-label="账本月份">
        <IconButton label="上个月" icon={<ChevronLeft aria-hidden="true" size={18} />} onClick={() => moveMonth(-1)} />
        <strong>{monthDate.getFullYear()} 年 {monthDate.getMonth() + 1} 月</strong>
        <IconButton label="下个月" icon={<ChevronRight aria-hidden="true" size={18} />} onClick={() => moveMonth(1)} />
      </div>
      <InlineError message={error} onRetry={() => void refresh()} />
      {summary ? <Summary summary={summary} /> : null}
      <section className="life-page__section" aria-label="账目明细">
        <div className="life-page__section-header">
          <SectionHeading>账目明细</SectionHeading>
          <label className="life-page__filter">明细类型<select aria-label="明细类型" value={filter} onChange={(event) => setFilter(event.target.value as LedgerFilter)}><option value="ALL">全部</option><option value="EXPENSE">支出</option><option value="INCOME">收入</option></select></label>
        </div>
        {loading ? <p className="life-page__status" role="status">正在加载</p> : null}
        {!loading && entries.length === 0 ? <p className="life-page__empty">本月暂无账目</p> : null}
        <div className="ledger-list">
          {entries.map((entry) => <LedgerRow key={entry.id} entry={entry} canWrite={canWrite} onEdit={() => setEditor(entry)} onDelete={async () => {
            if (!window.confirm('确认删除这笔账目？')) return;
            try {
              await api.deleteLedger(entry.id, { requestId: createRequestId(), expectedVersion: entry.version, confirm: true });
              await refresh(true);
            } catch (cause) { setError(errorMessage(cause)); }
          }} />)}
        </div>
      </section>
      {editor !== undefined ? <LedgerEditor api={api} members={members} viewerId={viewerId} entry={editor} onClose={() => setEditor(undefined)} onSaved={async () => { setEditor(undefined); await refresh(true); }} /> : null}
    </main>
  );
}

function Summary({ summary }: { summary: LedgerSummary }): JSX.Element {
  return <section className="life-page__summary" aria-label="月度汇总">
    <Metric label="支出" value={summary.expense_minor} />
    <Metric label="收入" value={summary.income_minor} />
    <Metric label="结余" value={summary.balance_minor} />
    {summary.categories.length > 0 ? <div className="life-page__summary-detail"><strong>支出分类</strong>{summary.categories.map((item) => <span key={item.category}>{item.category} ¥{formatMinor(item.amount_minor)}</span>)}</div> : null}
    {summary.payer_totals.length > 0 ? <div className="life-page__summary-detail"><strong>付款人</strong>{summary.payer_totals.map((item) => <span key={item.user_id}>{item.display_name} ¥{formatMinor(item.amount_minor)}</span>)}</div> : null}
  </section>;
}

function Metric({ label, value }: { label: string; value: number }): JSX.Element {
  return <div className="life-page__metric"><span>{label}</span><strong>¥{formatMinor(value)}</strong></div>;
}

function LedgerRow({ entry, canWrite, onEdit, onDelete }: { entry: LedgerEntry; canWrite: boolean; onEdit: () => void; onDelete: () => void }): JSX.Element {
  return <article className="ledger-row" data-ledger-entry={entry.id}>
    <button type="button" className="ledger-row__main" onClick={onEdit} disabled={!canWrite}>
      <span className="ledger-row__title">{entry.title}</span>
      <span className="ledger-row__meta">{entry.category} · {entry.payer_or_payee_name ?? entry.payer_or_payee_id} · {entry.date}</span>
    </button>
    <strong className={entry.type === 'EXPENSE' ? 'ledger-row__amount ledger-row__amount--expense' : 'ledger-row__amount'}>{entry.type === 'EXPENSE' ? '-' : '+'}¥{formatMinor(entry.amount_minor)}</strong>
    {canWrite ? <IconButton label="删除账目" icon={<Trash2 aria-hidden="true" size={16} />} onClick={onDelete} /> : null}
  </article>;
}

function LedgerEditor({ api, members, viewerId, entry, onClose, onSaved }: { api: LedgerApi; members: Member[]; viewerId?: string | null; entry: LedgerEntry | null; onClose: () => void; onSaved: () => Promise<void> }): JSX.Element {
  const [type, setType] = useState<LedgerEntryType>(entry?.type ?? 'EXPENSE');
  const [title, setTitle] = useState(entry?.title ?? '');
  const [amount, setAmount] = useState(entry?.amount ?? '');
  const [category, setCategory] = useState(entry?.category ?? '');
  const [date, setDate] = useState(entry?.date ?? dateKey(new Date()));
  const [payer, setPayer] = useState(entry?.payer_or_payee_id ?? viewerId ?? members[0]?.user_id ?? '');
  const [note, setNote] = useState(entry?.note ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    if (!title.trim() || !amount.trim() || !category.trim() || !payer) { setError('请填写标题、金额、分类和付款人。'); return; }
    setBusy(true); setError(null);
    try {
      if (entry) {
        await api.patchLedger(entry.id, { requestId: createRequestId(), expectedVersion: entry.version, changes: { type, amount, title: title.trim(), category: category.trim(), payer_or_payee_id: payer, date, note: note.trim() || null } });
      } else {
        await api.createLedger({ requestId: createRequestId(), type, amount, title: title.trim(), category: category.trim(), payerOrPayeeId: payer, date, note: note.trim() || undefined });
      }
      await onSaved();
    } catch (cause) { setError(errorMessage(cause)); } finally { setBusy(false); }
  };

  return <div className="life-page__overlay" role="presentation"><section className="life-page__dialog" role="dialog" aria-modal="true" aria-labelledby="ledger-editor-title">
    <header className="life-page__dialog-header"><h2 id="ledger-editor-title">{entry ? '编辑账目' : '记一笔'}</h2><IconButton label="关闭" icon={<X aria-hidden="true" size={18} />} onClick={onClose} /></header>
    <form onSubmit={(event) => void submit(event)}>
      <label>收支<select value={type} onChange={(event) => setType(event.target.value as LedgerEntryType)}><option value="EXPENSE">支出</option><option value="INCOME">收入</option></select></label>
      <label>标题<input value={title} onChange={(event) => setTitle(event.target.value)} /></label>
      <label>金额（元）<input inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} /></label>
      <label>分类<input value={category} onChange={(event) => setCategory(event.target.value)} /></label>
      <label>付款/收款人<select value={payer} onChange={(event) => setPayer(event.target.value)}>{members.map((member) => <option key={member.user_id} value={member.user_id}>{member.display_name ?? member.user_id}</option>)}</select></label>
      <label>日期<input type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label>
      <label>备注<textarea value={note} onChange={(event) => setNote(event.target.value)} /></label>
      {error ? <p className="life-page__form-error" role="alert">{error}</p> : null}
      <div className="life-page__dialog-actions"><Button tone="quiet" type="button" onClick={onClose}>取消</Button><Button type="submit" disabled={busy}>{busy ? '保存中' : '保存'}</Button></div>
    </form>
  </section></div>;
}

function monthKey(value: Date): string { return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}`; }
function dateKey(value: Date): string { return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`; }
function formatMinor(value: number): string { return (value / 100).toFixed(2); }
function errorMessage(cause: unknown): string { return cause instanceof Error ? cause.message : '操作失败，请检查网络后重试。'; }
function filterSnapshotEntries(entries: LedgerEntry[], month: string, filter: LedgerFilter): LedgerEntry[] {
  return entries.filter((entry) => entry.date.startsWith(month) && (filter === 'ALL' || entry.type === filter));
}
