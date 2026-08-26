import { describe, expect, it, vi } from 'vitest';
import { ApiClient, ApiError } from '../src/api/client';

describe('workspace actions', () => {
  it('uses snake_case transition body and preserves errors', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new ApiError(409, 'field_conflict', 'conflict'));
    await expect(new ApiClient().transitionTask('task-1', { requestId: 'r1', targetStatus: 'DONE', baseStatusVersion: 3 })).rejects.toMatchObject({ status: 409 });
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/tasks/task-1/transition', expect.objectContaining({ body: JSON.stringify({ request_id: 'r1', target_status: 'DONE', base_status_version: 3, blocked_reason: undefined, resume_handler_id: undefined, waiting_for_user_id: undefined }) }));
  });
});
