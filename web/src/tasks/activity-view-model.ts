import type { ActivityEvent, TaskItem } from '../api/types';

export type GetTaskActivity = (taskId: string) => Promise<ActivityEvent[]>;

export interface WorkspaceActivityResult {
  events: ActivityEvent[];
  failedTaskIds: string[];
}

const MAX_ACTIVITY_EVENTS = 50;
const MAX_CONCURRENT_REQUESTS = 4;

interface IndexedEvent {
  event: ActivityEvent;
  order: number;
}

/** Load task activity with bounded fan-out while preserving successful results. */
export async function loadWorkspaceActivity(
  tasks: TaskItem[],
  getTaskActivity: GetTaskActivity,
): Promise<WorkspaceActivityResult> {
  const activeTasks = tasks.filter((task) => !task.deleted_at);
  if (activeTasks.length === 0) return { events: [], failedTaskIds: [] };

  const taskEvents: Array<ActivityEvent[] | undefined> = new Array(activeTasks.length);
  const failed = new Array<boolean>(activeTasks.length).fill(false);
  let nextTaskIndex = 0;

  const loadNext = async (): Promise<void> => {
    while (true) {
      const taskIndex = nextTaskIndex;
      nextTaskIndex += 1;
      if (taskIndex >= activeTasks.length) return;

      try {
        taskEvents[taskIndex] = await getTaskActivity(activeTasks[taskIndex].id);
      } catch {
        failed[taskIndex] = true;
        taskEvents[taskIndex] = [];
      }
    }
  };

  const workerCount = Math.min(MAX_CONCURRENT_REQUESTS, activeTasks.length);
  await Promise.all(Array.from({ length: workerCount }, () => loadNext()));

  const indexedEvents: IndexedEvent[] = [];
  taskEvents.forEach((events, taskIndex) => {
    (events ?? []).forEach((event, eventIndex) => {
      indexedEvents.push({ event, order: taskIndex * 1_000_000 + eventIndex });
    });
  });

  indexedEvents.sort(compareIndexedEvents);

  return {
    events: indexedEvents.slice(0, MAX_ACTIVITY_EVENTS).map(({ event }) => event),
    failedTaskIds: activeTasks.filter((_task, index) => failed[index]).map((task) => task.id),
  };
}

function compareIndexedEvents(left: IndexedEvent, right: IndexedEvent): number {
  const leftTime = Date.parse(left.event.created_at);
  const rightTime = Date.parse(right.event.created_at);
  if (Number.isFinite(leftTime) && Number.isFinite(rightTime) && leftTime !== rightTime) {
    return rightTime - leftTime;
  }

  if (!Number.isFinite(leftTime) || !Number.isFinite(rightTime)) {
    const createdAtOrder = right.event.created_at.localeCompare(left.event.created_at);
    if (createdAtOrder !== 0) return createdAtOrder;
  }

  const idOrder = right.event.id.localeCompare(left.event.id);
  return idOrder === 0 ? left.order - right.order : idOrder;
}
