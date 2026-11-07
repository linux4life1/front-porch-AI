// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Pockets panel's chat switch (docs/design/pockets-wardrobe-chat-toggle.md,
// web twin of the desktop PocketsGateLine test): the panel STAYS UP when the
// feature is off (the switch is how it comes back), turning off confirms
// FIRST and a dismissed confirm posts nothing, and a group focus routes the
// flip at `memberPockets` with the member's id. An older host that sends no
// switch keys keeps the old absent-when-off shape.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { ChatToolsPockets } from './ChatToolsRealism';
import type { ToolsState } from './ChatToolsShared';

let container: HTMLDivElement;
let root: Root;
let confirmSpy: ReturnType<typeof vi.spyOn>;

const base = {
  wikiBaseUrl: '',
  wikiSavedUrls: [],
  realismEnabled: true,
  needsEnabled: false,
  realismOneShotEval: false,
  focusedId: null,
  memory: { ragEnabled: false, journalEnabled: false },
  ambitions: [],
  objectives: { primary: null, secondary: [], isChecking: false },
  time: { timeOfDay: 'morning', dayCount: 1, weekday: 'Mon', passageEnabled: true },
};

function mount(t: Partial<ToolsState>, toggle = vi.fn()) {
  const state = { ...base, ...t } as unknown as ToolsState;
  const noToggle = vi.fn();
  void noToggle;
  act(() => {
    root.render(
      createElement(ChatToolsPockets, {
        t: state,
        toggle,
        pocketRemove: vi.fn(),
        pocketAdd: vi.fn(),
      }),
    );
  });
  return toggle;
}

const checkbox = () =>
  container.querySelector('input[type="checkbox"]') as HTMLInputElement | null;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  confirmSpy.mockRestore();
});

describe('Pockets chat switch (web)', () => {
  it('stays up when off, with the retained-not-tracked note', () => {
    mount({ pockets: null, pocketsSwitch: false, pocketsAllowed: true, pocketsName: 'Ben' });
    const box = checkbox();
    expect(box).not.toBeNull();
    expect(box!.checked).toBe(false);
    expect(container.textContent).toContain('retained, not tracked');
  });

  it('an older host without the switch keys keeps the panel absent when off', () => {
    mount({ pockets: null });
    expect(container.querySelector('details')).toBeNull();
    expect(checkbox()).toBeNull();
  });

  it('turning on is instant — no confirm, posts pockets=true', () => {
    const toggle = mount({
      pockets: null,
      pocketsSwitch: false,
      pocketsAllowed: true,
      pocketsName: 'Ben',
    });
    act(() => {
      checkbox()!.click();
    });
    expect(confirmSpy).not.toHaveBeenCalled();
    expect(toggle).toHaveBeenCalledWith('pockets', true, undefined);
  });

  it('turning off confirms first; a dismissed confirm posts nothing', () => {
    confirmSpy.mockReturnValue(false);
    const toggle = mount({
      pockets: { worn: [], carrying: [{ name: 'house keys' }] },
      pocketsSwitch: true,
      pocketsAllowed: true,
      pocketsName: 'Ben',
    });
    act(() => {
      checkbox()!.click();
    });
    expect(confirmSpy).toHaveBeenCalledTimes(1);
    expect(confirmSpy.mock.calls[0][0]).toContain('no catch-up');
    expect(confirmSpy.mock.calls[0][0]).toContain('Ben');
    expect(confirmSpy.mock.calls[0][0]).toContain('retained');
    expect(toggle).not.toHaveBeenCalled();
  });

  it('a confirmed off posts pockets=false', () => {
    const toggle = mount({
      pockets: { worn: [], carrying: [] },
      pocketsSwitch: true,
      pocketsAllowed: true,
      pocketsName: 'Ben',
    });
    act(() => {
      checkbox()!.click();
    });
    expect(toggle).toHaveBeenCalledWith('pockets', false, undefined);
  });

  it('a group focus routes the flip at memberPockets with the member id', () => {
    const toggle = mount({
      pockets: { worn: [], carrying: [] },
      pocketsSwitch: true,
      pocketsAllowed: true,
      pocketsName: 'Ben',
      pocketsMemberId: 'mem-ben',
      focusedId: 'mem-ben',
    });
    act(() => {
      checkbox()!.click();
    });
    expect(toggle).toHaveBeenCalledWith('memberPockets', false, { id: 'mem-ben' });
  });

  it('a Porch Life veto greys the line at the chat choice and says so', () => {
    mount({
      pockets: null,
      pocketsSwitch: true,
      pocketsAllowed: false,
      pocketsName: 'Ben',
    });
    const box = checkbox()!;
    expect(box.checked).toBe(true);
    expect(box.disabled).toBe(true);
    expect(container.textContent).toContain('Off in Porch Life');
  });
});
