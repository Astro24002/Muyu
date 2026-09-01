import type { WebSessionSummary } from '../../api/types';

export interface WebSessionApi {
  listWebSessions: () => Promise<WebSessionSummary[]>;
  revokeWebSession: (id: string) => Promise<void>;
  revokeAllWebSessions: () => Promise<unknown>;
}
