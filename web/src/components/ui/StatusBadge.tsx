import type { HTMLAttributes, ReactElement, ReactNode } from 'react';

export interface StatusBadgeProps extends HTMLAttributes<HTMLSpanElement> {
  status: string;
  children?: ReactNode;
}

export function StatusBadge({ status, children, className, ...props }: StatusBadgeProps): ReactElement {
  const statusToken = status.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-') || 'neutral';

  return (
    <span
      {...props}
      data-status={status}
      className={['ui-status-badge', `ui-status-badge--${statusToken}`, className].filter(Boolean).join(' ')}
    >
      {children ?? status}
    </span>
  );
}
