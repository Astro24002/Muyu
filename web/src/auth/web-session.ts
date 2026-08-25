import { ApiError } from '../api/client';

export type WebSessionState = 'signed_out' | 'signed_in' | 'expired';

export function isSessionExpiredError(error: unknown): boolean {
  return error instanceof ApiError && error.status === 401 && error.code === 'web_session_expired';
}
