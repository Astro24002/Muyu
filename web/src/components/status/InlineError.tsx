import { AlertCircle } from 'lucide-react';
import type { JSX } from 'react';
import { Button } from '../ui/Button';

export interface InlineErrorProps {
  message: string | null | undefined;
  onRetry?: () => void;
  retryLabel?: string;
  id?: string;
  className?: string;
}

export function InlineError({
  message,
  onRetry,
  retryLabel = '重试',
  id,
  className,
}: InlineErrorProps): JSX.Element | null {
  if (!message) return null;

  return (
    <div id={id} className={['inline-error', className].filter(Boolean).join(' ')} role="alert" aria-live="assertive">
      <AlertCircle aria-hidden="true" size={16} strokeWidth={1.9} />
      <span>{message}</span>
      {onRetry ? <Button tone="quiet" onClick={onRetry}>{retryLabel}</Button> : null}
    </div>
  );
}
