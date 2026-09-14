import type { JSX } from 'react';
import type { TaskApprovalRequest, TaskItem } from '../api/types';
import { ApprovalRequestRow } from '../components/approvals/ApprovalRequestRow';

const previewTask: TaskItem = {
  id: 'preview-task', workspace_id: 'preview-workspace', parent_task_id: null,
  task_number: '26090001', title: '完成发布检查', description: '',
  due_at: '2026-09-10T10:00:00Z', status: 'IN_PROGRESS', current_handler_id: 'user-a',
  blocked_reason: null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null,
  planned_start_at: null, estimated_minutes: 45, completed_at: null, created_by: 'user-a',
  created_at: '2026-09-09T01:00:00Z', updated_at: '2026-09-09T04:00:00Z', delay_count: 0,
  total_delay_minutes: 0, version: 3, status_version: 2, field_versions: { title: 3 },
  lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: ['工作'], progress: 60,
};

const incomingRequest: TaskApprovalRequest = {
  id: 'preview-incoming', workspace_id: previewTask.workspace_id, task_id: previewTask.id,
  comment_id: null, requester_id: 'user-b', approver_id: 'user-a', request_type: 'TASK_UPDATE',
  proposed_changes: {
    title: '完成生产发布检查', due_at: '2026-09-11T10:00:00Z', quadrant: 'Q1',
    current_handler_id: 'user-a',
  }, base_field_versions: { title: 2, due_at: 2, quadrant: 2, current_handler_id: 2 },
  request_id: 'preview-request-incoming', status: 'PENDING', created_at: '2026-09-09T04:32:00Z',
  reviewed_at: null, reviewed_by: null, rejection_reason: null, resolved_cursor: null,
};

const outgoingRequest: TaskApprovalRequest = {
  ...incomingRequest,
  id: 'preview-outgoing', requester_id: 'user-a', approver_id: 'user-b',
  request_type: 'CLASSIFICATION_CREATE', task_id: null,
  proposed_changes: { name: '客户交付' }, base_field_versions: {},
  request_id: 'preview-request-outgoing', status: 'APPROVED',
};

export function ApprovalPreviewPage(): JSX.Element {
  const memberLabel = (userId: string): string => userId === 'user-a' ? '林木' : '溪岸';
  const noOp = (): void => undefined;

  return (
    <div data-testid="muyu-app">
      <main className="approvals-page approval-preview-page" data-approvals-page>
      <header className="approvals-page__intro">
        <p className="approval-preview-page__eyebrow">Muyu · 视觉预览</p>
        <h1>审批中心</h1>
        <p>把每一条请求拆成审批事项、发起人和变更内容，先确认信息再执行操作。</p>
      </header>
      <section className="approvals-page__section approvals-page__section--incoming">
        <div className="approvals-page__section-heading"><h2 className="ui-section-heading">需要我确认</h2><p className="approvals-page__pending-count">待确认：1</p></div>
        <div className="approvals-page__list">
          <ApprovalRequestRow request={incomingRequest} task={previewTask} incoming busy={false} memberLabel={memberLabel} onApprove={noOp} onReject={noOp} onCancel={noOp} />
        </div>
      </section>
      <section className="approvals-page__section approvals-page__section--outgoing">
        <div className="approvals-page__section-heading"><h2 className="ui-section-heading">等待对方确认</h2></div>
        <div className="approvals-page__list">
          <ApprovalRequestRow request={outgoingRequest} incoming={false} busy={false} memberLabel={memberLabel} onApprove={noOp} onReject={noOp} onCancel={noOp} />
        </div>
      </section>
      </main>
    </div>
  );
}
