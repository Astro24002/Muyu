import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const testDirectory = dirname(fileURLToPath(import.meta.url));
const globalCss = readFileSync(resolve(testDirectory, '../src/styles/global.css'), 'utf8');
const tokensCss = readFileSync(resolve(testDirectory, '../src/styles/tokens.css'), 'utf8');
const legacyRootSelector = ':not([data-testid="legacy-app-root"])';
const legacyDescendantSelector = ':not([data-testid="legacy-app-root"] *)';
const primitiveScopeSelector = '.muyu-react-root > [data-testid="muyu-app"]';
const nonLegacyReactRootSelector = '.muyu-react-root > [data-testid="muyu-app"] > :not([data-testid="legacy-app-root"])';

describe('visual foundation', () => {
  it('scopes React defaults away from the legacy bridge subtree', () => {
    expect(globalCss).toContain('.muyu-react-root');
    expect(globalCss).toContain('[data-testid="legacy-app-root"]');
    expect(globalCss).toMatch(/\.muyu-react-root\s*>\s*\[data-testid="muyu-app"\]\s*>\s*:not\(\[data-testid="legacy-app-root"\]\)/);

    expect(globalCss).not.toMatch(/^body\s*\{/m);
    expect(globalCss).not.toMatch(/^button\s*\{/m);
    expect(globalCss).not.toMatch(/^a\s*\{/m);
    expect(globalCss).not.toMatch(/^:where\(a,/m);
  });

  it('scopes every primitive selector away from the legacy bridge subtree', () => {
    const primitiveRules = cssRules().filter(({ selector }) => /\.ui-(button|icon-button|status-badge|section-heading)/.test(selector));

    expect(primitiveRules.length).toBeGreaterThan(0);
    for (const { selector } of primitiveRules) {
      expect(selector).toContain(primitiveScopeSelector);
      expect(selector).toContain(legacyRootSelector);
      expect(selector).toContain(legacyDescendantSelector);
    }
  });

  it('keeps light color scheme and cursor states inside the non-legacy React root', () => {
    const colorSchemeRules = cssRules().filter(({ body }) => body.includes('color-scheme: light;'));
    expect(colorSchemeRules).toHaveLength(1);
    expect(colorSchemeRules[0].selector).toContain(nonLegacyReactRootSelector);
    expect(colorSchemeRules[0].selector).not.toBe('.muyu-react-root');
    expect(tokensCss).not.toContain('color-scheme:');

    const cursorRules = cssRules().filter(({ body }) => body.includes('cursor:'));
    expect(cursorRules.map(({ body }) => body)).toEqual(expect.arrayContaining([
      expect.stringContaining('cursor: pointer;'),
      expect.stringContaining('cursor: not-allowed;'),
    ]));
    for (const { selector } of cursorRules) {
      expect(selector).toContain(primitiveScopeSelector);
      expect(selector).toContain(legacyRootSelector);
      expect(selector).toContain(legacyDescendantSelector);
    }
  });

  it('keeps coral status text at WCAG AA contrast on its light surface', () => {
    const coral = readColorToken('--color-coral');
    const coralSurface = readColorToken('--color-coral-surface');

    expect(contrastRatio(coral, coralSurface)).toBeGreaterThanOrEqual(4.5);
    for (const status of ['waiting', 'pending', 'blocked', 'warning', 'attention', 'approval']) {
      expect(globalCss).toContain(`.ui-status-badge--${status}`);
    }
  });
});

function readColorToken(name: string): string {
  const match = tokensCss.match(new RegExp(`${name}:\\s*(#[0-9a-f]{6})`, 'i'));
  if (!match) throw new Error(`Missing color token ${name}`);
  return match[1];
}

function cssRules(): Array<{ selector: string; body: string }> {
  return [...globalCss.matchAll(/([^{}]+)\{([^{}]*)\}/gs)].map((match) => ({
    selector: match[1].trim(),
    body: match[2],
  }));
}

function contrastRatio(foreground: string, background: string): number {
  const foregroundLuminance = relativeLuminance(foreground);
  const backgroundLuminance = relativeLuminance(background);
  const lighter = Math.max(foregroundLuminance, backgroundLuminance);
  const darker = Math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

function relativeLuminance(color: string): number {
  const channels = color
    .slice(1)
    .match(/.{2}/g)
    ?.map((channel) => Number.parseInt(channel, 16) / 255);
  if (!channels) throw new Error(`Invalid color ${color}`);

  const linearChannels = channels.map((channel) => (
    channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
  ));
  return linearChannels[0] * 0.2126 + linearChannels[1] * 0.7152 + linearChannels[2] * 0.0722;
}
