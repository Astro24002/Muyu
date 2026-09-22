import { CalendarDays, Check, Pause, Play, Plus, RotateCcw, Trash2, X } from 'lucide-react';
import { useEffect, useState, type FormEvent, type JSX } from 'react';
import type { ApiClient } from '../api/client';
import { createRequestId } from '../api/client';
import type { Anniversary, Habit, HabitFrequency } from '../api/types';
import { InlineError } from '../components/status/InlineError';
import { Button } from '../components/ui/Button';
import { IconButton } from '../components/ui/IconButton';
import { SectionHeading } from '../components/ui/SectionHeading';

type CheckinsApi = Pick<ApiClient, 'listHabits' | 'createHabit' | 'patchHabit' | 'habitAction' | 'deleteHabit' | 'listAnniversaries' | 'createAnniversary' | 'patchAnniversary' | 'deleteAnniversary' | 'prepareAnniversary'>;
type CheckinsTab = 'habits' | 'anniversaries';
type EditorState = { kind: 'habit'; value: Habit | null } | { kind: 'anniversary'; value: Anniversary | null } | null;

export interface CheckinsPageProps {
  api: CheckinsApi;
  viewerId?: string | null;
  canWrite: boolean;
  snapshotHabits?: Habit[];
  snapshotAnniversaries?: Anniversary[];
}

export function CheckinsPage({ api, viewerId, canWrite, snapshotHabits, snapshotAnniversaries }: CheckinsPageProps): JSX.Element {
  const [tab, setTab] = useState<CheckinsTab>('habits');
  const [owner, setOwner] = useState<'mine' | 'other' | 'all'>('mine');
  const [habits, setHabits] = useState<Habit[]>([]);
  const [anniversaries, setAnniversaries] = useState<Anniversary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editor, setEditor] = useState<EditorState>(null);

  const refresh = async (forceRest = false): Promise<boolean> => {
    setLoading(true); setError(null);
    try {
      const [nextHabits, nextAnniversaries] = await Promise.all([
        forceRest || snapshotHabits === undefined ? api.listHabits(owner) : Promise.resolve(filterHabits(snapshotHabits, owner, viewerId)),
        forceRest || snapshotAnniversaries === undefined ? api.listAnniversaries() : Promise.resolve(snapshotAnniversaries),
      ]);
      setHabits(nextHabits); setAnniversaries(nextAnniversaries);
      return true;
    } catch (cause) { setError(errorMessage(cause)); return false; }
    finally { setLoading(false); }
  };

  useEffect(() => { void refresh(); }, [owner, snapshotHabits, snapshotAnniversaries, viewerId]);

  const runHabitAction = async (habit: Habit, action: 'checkin' | 'undo' | 'pause' | 'resume'): Promise<void> => {
    try {
      await api.habitAction(habit.id, action, { requestId: createRequestId(), expectedVersion: habit.version });
      await refresh(true);
    } catch (cause) { setError(errorMessage(cause)); }
  };

  const prepare = async (anniversary: Anniversary): Promise<void> => {
    try {
      await api.prepareAnniversary(anniversary.id, createRequestId());
      setError(null);
    } catch (cause) { setError(errorMessage(cause)); }
  };

  return <main className="life-page checkins-page" data-checkins-page>
    <header className="life-page__header">
      <div><p className="life-page__eyebrow">日常节奏</p><h1>打卡</h1></div>
      {canWrite ? <Button onClick={() => setEditor(tab === 'habits' ? { kind: 'habit', value: null } : { kind: 'anniversary', value: null })}><Plus aria-hidden="true" size={16} />{tab === 'habits' ? '新增习惯' : '新增纪念日'}</Button> : null}
    </header>
    <div className="life-page__tabs" role="tablist" aria-label="打卡视图">
      <button type="button" role="tab" aria-selected={tab === 'habits'} onClick={() => setTab('habits')}>日常打卡</button>
      <button type="button" role="tab" aria-selected={tab === 'anniversaries'} onClick={() => setTab('anniversaries')}>纪念日</button>
    </div>
    <InlineError message={error} onRetry={() => void refresh()} />
    {loading ? <p className="life-page__status" role="status">正在加载</p> : null}
    {tab === 'habits' ? <HabitsSection habits={habits} owner={owner} viewerId={viewerId} canWrite={canWrite} onOwnerChange={setOwner} onAction={(habit, action) => void runHabitAction(habit, action)} onEdit={(habit) => setEditor({ kind: 'habit', value: habit })} /> : <AnniversariesSection anniversaries={anniversaries} canWrite={canWrite} onPrepare={(item) => void prepare(item)} onEdit={(item) => setEditor({ kind: 'anniversary', value: item })} />}
    {editor?.kind === 'habit' ? <HabitEditor api={api} entry={editor.value} onClose={() => setEditor(null)} onSaved={async () => { setEditor(null); await refresh(true); }} /> : null}
    {editor?.kind === 'anniversary' ? <AnniversaryEditor api={api} entry={editor.value} onClose={() => setEditor(null)} onSaved={async () => { setEditor(null); await refresh(true); }} /> : null}
  </main>;
}

function HabitsSection({ habits, owner, viewerId, canWrite, onOwnerChange, onAction, onEdit }: { habits: Habit[]; owner: 'mine' | 'other' | 'all'; viewerId?: string | null; canWrite: boolean; onOwnerChange: (value: 'mine' | 'other' | 'all') => void; onAction: (habit: Habit, action: 'checkin' | 'undo' | 'pause' | 'resume') => void; onEdit: (habit: Habit) => void }): JSX.Element {
  return <section className="life-page__section" aria-label="习惯列表">
    <div className="life-page__section-header"><SectionHeading>日常打卡</SectionHeading><label className="life-page__filter">范围<select aria-label="习惯范围" value={owner} onChange={(event) => onOwnerChange(event.target.value as typeof owner)}><option value="mine">我的</option><option value="other">TA 的</option><option value="all">全部</option></select></label></div>
    {habits.length === 0 ? <p className="life-page__empty">暂无习惯</p> : null}
    <div className="habit-list">{habits.map((habit) => {
      const owns = habit.owner_id === viewerId;
      const canAct = canWrite && owns && habit.status !== 'DELETED';
      return <article className="habit-row" key={habit.id} data-habit={habit.id}>
        <button type="button" className="habit-row__main" onClick={() => onEdit(habit)} disabled={!owns || !canWrite}><strong>{habit.title}</strong><span>{frequencyLabel(habit.frequency)} · {habit.status === 'PAUSED' ? '已暂停' : habit.checked_in ? '本期已完成' : '本期未完成'}</span></button>
        <div className="habit-row__actions">
          {canAct ? <IconButton label={habit.checked_in ? '撤销本期打卡' : '打卡'} icon={habit.checked_in ? <RotateCcw aria-hidden="true" size={16} /> : <Check aria-hidden="true" size={16} />} onClick={() => onAction(habit, habit.checked_in ? 'undo' : 'checkin')} /> : null}
          {canAct ? <IconButton label={habit.status === 'PAUSED' ? '恢复习惯' : '暂停习惯'} icon={habit.status === 'PAUSED' ? <Play aria-hidden="true" size={16} /> : <Pause aria-hidden="true" size={16} />} onClick={() => onAction(habit, habit.status === 'PAUSED' ? 'resume' : 'pause')} /> : null}
        </div>
      </article>;
    })}</div>
  </section>;
}

function AnniversariesSection({ anniversaries, canWrite, onPrepare, onEdit }: { anniversaries: Anniversary[]; canWrite: boolean; onPrepare: (item: Anniversary) => void; onEdit: (item: Anniversary) => void }): JSX.Element {
  return <section className="life-page__section" aria-label="纪念日列表"><div className="life-page__section-header"><SectionHeading>纪念日</SectionHeading></div>{anniversaries.length === 0 ? <p className="life-page__empty">暂无纪念日</p> : null}<div className="anniversary-list">{anniversaries.map((item) => <article className="anniversary-row" key={item.id} data-anniversary={item.id}><button type="button" className="anniversary-row__main" onClick={() => onEdit(item)} disabled={!canWrite}><strong><CalendarDays aria-hidden="true" size={16} />{item.title}</strong><span>{kindLabel(item.kind)} · {item.next_occurrence} · {item.is_today ? '就是今天' : `还有 ${item.days_until} 天`}</span></button><div className="anniversary-row__actions">{canWrite && item.prepare_days > 0 ? <Button tone="quiet" onClick={() => onPrepare(item)}>生成准备事项</Button> : null}</div></article>)}</div></section>;
}

function HabitEditor({ api, entry, onClose, onSaved }: { api: CheckinsApi; entry: Habit | null; onClose: () => void; onSaved: () => Promise<void> }): JSX.Element {
  const [title, setTitle] = useState(entry?.title ?? ''); const [frequency, setFrequency] = useState<HabitFrequency>(entry?.frequency ?? 'DAILY'); const [startDate, setStartDate] = useState(entry?.start_date ?? dateKey(new Date())); const [note, setNote] = useState(entry?.note ?? ''); const [error, setError] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>): Promise<void> => { event.preventDefault(); if (!title.trim()) { setError('请输入习惯名称。'); return; } setBusy(true); setError(null); try { if (entry) await api.patchHabit(entry.id, { requestId: createRequestId(), expectedVersion: entry.version, changes: { title: title.trim(), frequency, start_date: startDate, note: note.trim() || null } }); else await api.createHabit({ requestId: createRequestId(), title: title.trim(), frequency, startDate, note: note.trim() || undefined }); await onSaved(); } catch (cause) { setError(errorMessage(cause)); } finally { setBusy(false); } };
  const remove = async (): Promise<void> => { if (!entry || !window.confirm('确认删除习惯？关联打卡记录也会删除，历史审计会保留。')) return; setBusy(true); setError(null); try { await api.deleteHabit(entry.id, { requestId: createRequestId(), expectedVersion: entry.version, confirm: true }); await onSaved(); } catch (cause) { setError(errorMessage(cause)); } finally { setBusy(false); } };
  return <Editor title={entry ? '编辑习惯' : '新增习惯'} onClose={onClose} error={error}><form onSubmit={(event) => void submit(event)}><label>习惯名称<input value={title} onChange={(event) => setTitle(event.target.value)} /></label><label>频率<select value={frequency} onChange={(event) => setFrequency(event.target.value as HabitFrequency)}><option value="DAILY">每日</option><option value="WEEKLY">每周</option><option value="MONTHLY">每月</option></select></label><label>开始日期<input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} /></label><label>备注<textarea value={note} onChange={(event) => setNote(event.target.value)} /></label><EditorActions busy={busy} onClose={onClose} onDelete={entry ? () => void remove() : undefined} /></form></Editor>;
}

function AnniversaryEditor({ api, entry, onClose, onSaved }: { api: CheckinsApi; entry: Anniversary | null; onClose: () => void; onSaved: () => Promise<void> }): JSX.Element {
  const [title, setTitle] = useState(entry?.title ?? ''); const [date, setDate] = useState(entry?.anchor_date ?? dateKey(new Date())); const [kind, setKind] = useState<Anniversary['kind']>(entry?.kind ?? 'ANNIVERSARY'); const [prepareDays, setPrepareDays] = useState(String(entry?.prepare_days ?? 0)); const [note, setNote] = useState(entry?.note ?? ''); const [error, setError] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>): Promise<void> => { event.preventDefault(); if (!title.trim()) { setError('请输入纪念日名称。'); return; } setBusy(true); setError(null); try { if (entry) await api.patchAnniversary(entry.id, { requestId: createRequestId(), expectedVersion: entry.version, changes: { title: title.trim(), anchor_date: date, kind, prepare_days: Number(prepareDays), note: note.trim() || null } }); else await api.createAnniversary({ requestId: createRequestId(), title: title.trim(), anchorDate: date, kind, prepareDays: Number(prepareDays), note: note.trim() || undefined }); await onSaved(); } catch (cause) { setError(errorMessage(cause)); } finally { setBusy(false); } };
  const remove = async (): Promise<void> => { if (!entry || !window.confirm('确认删除这个纪念日？已经生成的准备事项会保留。')) return; setBusy(true); setError(null); try { await api.deleteAnniversary(entry.id, { requestId: createRequestId(), expectedVersion: entry.version, confirm: true }); await onSaved(); } catch (cause) { setError(errorMessage(cause)); } finally { setBusy(false); } };
  return <Editor title={entry ? '编辑纪念日' : '新增纪念日'} onClose={onClose} error={error}><form onSubmit={(event) => void submit(event)}><label>名称<input value={title} onChange={(event) => setTitle(event.target.value)} /></label><label>日期<input type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label><label>类型<select value={kind} onChange={(event) => setKind(event.target.value as Anniversary['kind'])}><option value="ANNIVERSARY">纪念日</option><option value="BIRTHDAY">生日</option><option value="IMPORTANT_DAY">重要日子</option></select></label><label>提前准备天数<select value={prepareDays} onChange={(event) => setPrepareDays(event.target.value)}>{[0, 1, 3, 7, 14, 30].map((value) => <option key={value} value={value}>{value} 天</option>)}</select></label><label>备注<textarea value={note} onChange={(event) => setNote(event.target.value)} /></label><EditorActions busy={busy} onClose={onClose} onDelete={entry ? () => void remove() : undefined} /></form></Editor>;
}

function Editor({ title, error, onClose, children }: { title: string; error: string | null; onClose: () => void; children: JSX.Element }): JSX.Element { return <div className="life-page__overlay"><section className="life-page__dialog" role="dialog" aria-modal="true" aria-label={title}><header className="life-page__dialog-header"><h2>{title}</h2><IconButton label="关闭" icon={<X aria-hidden="true" size={18} />} onClick={onClose} /></header>{children}{error ? <p className="life-page__form-error" role="alert">{error}</p> : null}</section></div>; }
function EditorActions({ busy, onClose, onDelete }: { busy: boolean; onClose: () => void; onDelete?: () => void }): JSX.Element { return <div className="life-page__dialog-actions">{onDelete ? <Button tone="quiet" type="button" onClick={onDelete} disabled={busy}><Trash2 aria-hidden="true" size={16} />删除</Button> : null}<Button tone="quiet" type="button" onClick={onClose} disabled={busy}>取消</Button><Button type="submit" disabled={busy}>{busy ? '保存中' : '保存'}</Button></div>; }
function frequencyLabel(value: HabitFrequency): string { return value === 'DAILY' ? '每日' : value === 'WEEKLY' ? '每周' : '每月'; }
function kindLabel(value: Anniversary['kind']): string { return value === 'BIRTHDAY' ? '生日' : value === 'IMPORTANT_DAY' ? '重要日子' : '纪念日'; }
function dateKey(value: Date): string { return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`; }
function errorMessage(cause: unknown): string { return cause instanceof Error ? cause.message : '操作失败，请检查网络后重试。'; }
function filterHabits(habits: Habit[], owner: 'mine' | 'other' | 'all', viewerId?: string | null): Habit[] {
  if (owner === 'all' || viewerId == null) return habits;
  return habits.filter((habit) => owner === 'mine' ? habit.owner_id === viewerId : habit.owner_id !== viewerId);
}
