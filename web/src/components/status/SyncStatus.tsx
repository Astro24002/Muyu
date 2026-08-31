import { AlertCircle, LoaderCircle } from 'lucide-react';
import type { JSX } from 'react';

export interface SyncStatusProps {
  loading: boolean;
  stale: boolean;
  error: string | null;
}

export function SyncStatus({ loading, stale, error }: SyncStatusProps): JSX.Element {
  if (error) {
    return (
      <div className="sync-status sync-status--error" role="alert" aria-live="assertive" data-state="error">
        <AlertCircle aria-hidden="true" size={15} strokeWidth={1.9} />
        <span>{error}</span>
      </div>
    );
  }

  if (stale) {
    return (
      <div className="sync-status sync-status--stale" role="status" aria-live="polite" data-state="stale">
        <span className="sync-status__dot" aria-hidden="true" />
        <span>内容可能不是最新</span>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="sync-status sync-status--loading" role="status" aria-live="polite" data-state="loading">
        <LoaderCircle aria-hidden="true" size={15} strokeWidth={1.9} />
        <span>正在同步</span>
      </div>
    );
  }

  return (
    <div className="sync-status sync-status--normal" role="status" aria-live="polite" data-state="normal">
      <span className="sync-status__dot" aria-hidden="true" />
      <span>刚刚同步</span>
    </div>
  );
}
