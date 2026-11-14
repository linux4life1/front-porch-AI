// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A 1:1 host reply buried under Scene Guest chimes gets the desktop's second
// ⟳ — "Regenerate main character (removes the NPC’s reply)" — on its bubble,
// gated by the host's `regenerableHostBelowGuests` chat-state index
// (regen_controller.dart). Both action surfaces carry it: ReplyActions is
// what every width renders (ChatPage passes isDesktop), MessageActions is the
// legacy twin. The host index is a real number — never truthiness.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MessageActions, ReplyActions } from './MessageActions';
import { type Message } from './chatTypes';

vi.mock('../api/client', () => ({
  api: { post: vi.fn(async () => ({})), avatarUrl: (p: string) => p },
}));

const TITLE = 'Regenerate main character (removes the NPC’s reply)';

// The buried host: not last (a guest spoke after it), index 1.
const buriedHost: Message = {
  index: 1,
  text: 'She sets the mug down.',
  sender: 'Mara',
  isUser: false,
  swipeIndex: 0,
  swipeCount: 1,
};

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function render(
  Comp: typeof MessageActions | typeof ReplyActions,
  onRegenerate = vi.fn(),
  extra: Record<string, unknown> = {},
) {
  const base = {
    m: buriedHost,
    isLast: false,
    busy: false,
    onSwipe: vi.fn(),
    onRegenerate,
    onContinue: vi.fn(),
    onVariantPicked: undefined,
    onActionFailed: undefined,
  };
  const props =
    Comp === MessageActions
      ? { ...base, canSpeak: false, onFork: vi.fn(), onEdit: vi.fn(), onDelete: vi.fn(), ...extra }
      : { ...base, ...extra };
  act(() => {
    root.render(createElement(Comp, props as never));
  });
  return onRegenerate;
}

const mainButton = () =>
  container.querySelector(`button[title="${TITLE}"]`) as HTMLButtonElement | null;
const plainButton = () =>
  container.querySelector('button[title="Regenerate"]') as HTMLButtonElement | null;

for (const [name, Comp] of [
  ['MessageActions', MessageActions],
  ['ReplyActions', ReplyActions],
] as const) {
  describe(`${name} buried-host regen`, () => {
    it(`shows the ⟳ with the desktop's exact title on the matching index`, () => {
      render(Comp, vi.fn(), { regenerableHostBelowGuests: 1 });
      expect(mainButton()).not.toBeNull();
    });

    it('stays hidden when the index is another bubble, null, or absent', () => {
      render(Comp, vi.fn(), { regenerableHostBelowGuests: 4 });
      expect(mainButton()).toBeNull();
      render(Comp, vi.fn(), { regenerableHostBelowGuests: null });
      expect(mainButton()).toBeNull();
      render(Comp);
      expect(mainButton()).toBeNull();
    });

    it('shows the button at index 0 — never truthiness', () => {
      act(() => {
        root.render(
          createElement(ReplyActions, {
            m: { ...buriedHost, index: 0 },
            isLast: false,
            busy: false,
            onSwipe: vi.fn(),
            onRegenerate: vi.fn(),
            onContinue: vi.fn(),
            regenerableHostBelowGuests: 0,
          } as never),
        );
      });
      expect(mainButton()).not.toBeNull();
    });

    it('disables with the busy prop', () => {
      render(Comp, vi.fn(), { regenerableHostBelowGuests: 1, busy: true });
      expect(mainButton()!.disabled).toBe(true);
    });

    it('opens the shared critique dialog and sends the note with the target', () => {
      const onRegenerate = render(Comp, vi.fn(), { regenerableHostBelowGuests: 1 });
      act(() => mainButton()!.click());
      const field = container.querySelector(
        'textarea[data-testid="regen-critique-field"]',
      ) as HTMLTextAreaElement;
      expect(field).not.toBeNull();
      const setter = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
        'value',
      )!.set!;
      act(() => {
        setter.call(field, 'too cautious');
        field.dispatchEvent(new Event('input', { bubbles: true }));
      });
      const form = field.closest('form')!;
      act(() => {
        form.dispatchEvent(
          new Event('submit', { bubbles: true, cancelable: true }),
        );
      });
      expect(onRegenerate).toHaveBeenCalledWith('too cautious', undefined, 'mainCharacter');
    });

    it('carries the lookup selection with the target too', () => {
      const onRegenerate = render(Comp, vi.fn(), {
        regenerableHostBelowGuests: 1,
        lookupWeb: true,
      });
      act(() => mainButton()!.click());
      const field = container.querySelector(
        'textarea[data-testid="regen-critique-field"]',
      ) as HTMLTextAreaElement;
      const lookup = container.querySelector(
        '[data-testid="regen-lookup-query"]',
      ) as HTMLInputElement;
      expect(lookup).not.toBeNull();
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        'value',
      )!.set!;
      act(() => {
        setter.call(lookup, 'herbal teas');
        lookup.dispatchEvent(new Event('input', { bubbles: true }));
      });
      void field;
      const form = lookup.closest('form')!;
      act(() => {
        form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
      });
      expect(onRegenerate).toHaveBeenCalledWith(
        '',
        { source: 'web', query: 'herbal teas' },
        'mainCharacter',
      );
    });

    it('a plain regen after a cancelled main-character dialog sends no target', () => {
      // Both ⟳ on one row (a contraption the state makes possible) so the
      // submit states meet: main first, then plain must clear the target.
      const onRegenerate = render(Comp, vi.fn(), {
        regenerableHostBelowGuests: 1,
        isLast: true,
      });
      act(() => mainButton()!.click());
      act(() => {
        (container.querySelector('button[aria-label="Close"]') as HTMLButtonElement).click();
      });
      const plain = plainButton();
      expect(plain).not.toBeNull();
      act(() => plain!.click());
      const form = container
        .querySelector('textarea[data-testid="regen-critique-field"]')!
        .closest('form')!;
      act(() => {
        form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
      });
      // The plain path's exact original shape — two trailing undefineds must
      // not appear, that is the arity contract older tests pin.
      expect(onRegenerate).toHaveBeenCalledWith('');
    });
  });
}
