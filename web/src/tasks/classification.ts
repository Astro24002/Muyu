import type { WorkspaceClassification } from '../api/types';

/** Return approved classifications in a stable display order without duplicates. */
export function classificationNames(classifications: WorkspaceClassification[] | undefined): string[] {
  const names = new Map<string, string>();
  for (const classification of classifications ?? []) {
    const name = classification.name.trim();
    if (name && !names.has(name.toLocaleLowerCase())) names.set(name.toLocaleLowerCase(), name);
  }
  return [...names.values()].sort((left, right) => left.localeCompare(right, 'zh-CN'));
}

export function classificationNameSet(classifications: WorkspaceClassification[] | undefined): Set<string> {
  return new Set(classificationNames(classifications).map((name) => name.toLocaleLowerCase()));
}

/** Keep legacy labels visible while editing old tasks, without enabling free-text additions. */
export function editableClassificationNames(
  classifications: WorkspaceClassification[] | undefined,
  currentNames: string[] = [],
): string[] {
  const names = classificationNames(classifications);
  if (names.length > 0) return names;
  const fallback = new Map<string, string>();
  for (const name of currentNames) {
    const trimmed = name.trim();
    if (trimmed && !fallback.has(trimmed.toLocaleLowerCase())) fallback.set(trimmed.toLocaleLowerCase(), trimmed);
  }
  return [...fallback.values()].sort((left, right) => left.localeCompare(right, 'zh-CN'));
}
