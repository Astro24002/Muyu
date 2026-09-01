import { ClipboardCheck } from 'lucide-react';
import type { JSX } from 'react';
import { Button } from '../ui/Button';

export interface InlineApprovalNoticeProps {
  count: number;
  onOpen: () => void;
}

export function InlineApprovalNotice({ count, onOpen }: InlineApprovalNoticeProps): JSX.Element | null {
  if (count <= 0) return null;

  return (
    <div className="inline-approval-notice" data-inline-approval-notice role="status">
      <ClipboardCheck aria-hidden="true" size={17} strokeWidth={1.9} />
      <p>
        <strong>有 {count} 个变更等你确认</strong>
        <span>来自伙伴的任务变更需要你的回应。</span>
      </p>
      <Button tone="quiet" onClick={onOpen}>去处理</Button>
    </div>
  );
}
