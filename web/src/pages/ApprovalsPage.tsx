import { useCallback, useState, type JSX } from 'react';
import type { TaskApprovalRequest, TaskItem } from '../api/types';
import { useWorkspaceState } from '../app/use-external-state';
import { ApprovalRequestRow } from '../components/approvals/ApprovalRequestRow';
import { SyncStatus } from '../components/status/SyncStatus';
import { SectionHeading } from '../components/ui/SectionHeading';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

export interface ApprovalsPageProps {
  sync: WorkspaceSyncController;
}

type ApprovalAction = 'approve' | 'reject' | 'cancel';

export function ApprovalsPage({ sync }: ApprovalsPageProps): JSX.Element {
  const state = useWorkspaceState(sync);
  const [busyRequestId, setBusyRequestId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const approvals = state.approvals ?? state.snapshot?.approval_requests ?? [];
  const tasks = state.snapshot?.tasks ?? [];
  const viewerId = state.snapshot?.viewer_user_id ?? '';
  const members = state.snapshot?.members ?? [];
  const incoming = approvals.filter((request) => request.approver_id === viewerId);
  const outgoing = approvals.filter((request) => request.requester_id === viewerId);
  const pendingCount = incoming.filter((request) => request.status === 'PENDING').length;
  const tasksById = new Map(tasks.map((task) => [task.id, task]));
  const memberLabel = useCallback((userId: string): string => {
    if (userId === viewerId) return '我';
    const member = members.find((item) => item.user_id === userId);
    const displayName = member?.display_name?.trim();
    if (displayName) return displayName;
    if (member?.member_slot) return `协作者 ${member.member_slot}`;
    return '协作者';
  }, [members, viewerId]);
  const busy = state.loading || state.stale || state.authRequired || busyRequestId !== null;
  const error = actionError ?? state.error;

  const runAction = useCallback(async (
    requestId: string,
    action: ApprovalAction,
    reason?: string,
  ): Promise<void> => {
    if (busyRequestId !== null) return;
    setBusyRequestId(requestId);
    setActionError(null);
    try {
      const result = action === 'approve'
        ? await sync.approveApproval(requestId)
        : action === 'reject'
          ? await sync.rejectApproval(requestId, reason)
          : await sync.cancelApproval(requestId);
      if (result === undefined && !sync.state.error) setActionError('审批未确认，请检查同步状态后重试。');
    } catch (caught) {
      setActionError(toErrorMessage(caught));
    } finally {
      setBusyRequestId((current) => current === requestId ? null : current);
    }
  }, [busyRequestId, sync]);

  return (
    <main className="approvals-page" data-approvals-page>
      <header className="approvals-page__intro" data-approvals-section="intro">
        <h1>审批</h1>
        <p>处理需要双方确认的任务变更。</p>
      </header>

      <div className="approvals-page__sync" data-approvals-section="sync">
        <SyncStatus loading={state.loading} stale={state.stale} error={error} />
      </div>

      <ApprovalBox
        heading="需要我确认"
        headingId="approvals-incoming-heading"
        requests={incoming}
        tasksById={tasksById}
        memberLabel={memberLabel}
        incoming
        pendingCount={pendingCount}
        busy={busy}
        onApprove={(requestId) => runAction(requestId, 'approve')}
        onReject={(requestId, reason) => runAction(requestId, 'reject', reason)}
        onCancel={(requestId) => runAction(requestId, 'cancel')}
      />

      <ApprovalBox
        heading="等待对方确认"
        headingId="approvals-outgoing-heading"
        requests={outgoing}
        tasksById={tasksById}
        memberLabel={memberLabel}
        incoming={false}
        busy={busy}
        onApprove={(requestId) => runAction(requestId, 'approve')}
        onReject={(requestId, reason) => runAction(requestId, 'reject', reason)}
        onCancel={(requestId) => runAction(requestId, 'cancel')}
      />
    </main>
  );
}

interface ApprovalBoxProps {
  heading: string;
  headingId: string;
  requests: TaskApprovalRequest[];
  tasksById: Map<string, TaskItem>;
  memberLabel: (userId: string) => string;
  incoming: boolean;
  pendingCount?: number;
  busy: boolean;
  onApprove: (requestId: string) => void | Promise<void>;
  onReject: (requestId: string, reason?: string) => void | Promise<void>;
  onCancel: (requestId: string) => void | Promise<void>;
}

function ApprovalBox({
  heading,
  headingId,
  requests,
  tasksById,
  memberLabel,
  incoming,
  pendingCount,
  busy,
  onApprove,
  onReject,
  onCancel,
}: ApprovalBoxProps): JSX.Element {
  return (
    <section
      className={['approvals-page__section', incoming ? 'approvals-page__section--incoming' : 'approvals-page__section--outgoing'].join(' ')}
      data-approvals-section={incoming ? 'incoming' : 'outgoing'}
      aria-labelledby={headingId}
    >
      <div className="approvals-page__section-heading">
        <SectionHeading id={headingId}>{heading}</SectionHeading>
        {pendingCount !== undefined ? <p className="approvals-page__pending-count">待确认：{pendingCount}</p> : null}
      </div>

      {requests.length === 0 ? (
        <p className="approvals-page__empty" role="status">暂无审批请求</p>
      ) : (
        <div className="approvals-page__list">
          {requests.map((request) => (
            <ApprovalRequestRow
              key={request.id}
              request={request}
              task={request.task_id ? tasksById.get(request.task_id) : undefined}
              memberLabel={memberLabel}
              incoming={incoming}
              busy={busy}
              onApprove={onApprove}
              onReject={onReject}
              onCancel={onCancel}
            />
          ))}
        </div>
      )}
    </section>
  );
}

function toErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === 'string' && error) return error;
  return '无法处理审批请求，请检查网络后重试。';
}
