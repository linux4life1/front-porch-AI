// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web new-group Realism step carries the desktop step's controls: Group
// Chaos with its 18+ sub-switch, the Story Calendar start, the Neutral and
// High Bond presets, and each member's emotion, verification and needs with
// Reset to character defaults.

import { act, createElement, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { EMPTY_DRAFT, NEUTRAL_MEMBER, memberRealism, type GroupDraft } from './groupDraft';
import type { MemberRealism } from './groupDraft';

let adult = false;
vi.mock('../../api/client', () => ({
  api: {
    get: async () => ({ realism: { adultThemesEnabled: adult, passageOfTimeDefault: true } }),
  },
}));
vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

const { RealismStep } = await import('./RealismStep');

const MEMBERS = [
  { id: 'j', name: 'Juniper' },
  { id: 'm', name: 'Marlow' },
];
let draft: GroupDraft = EMPTY_DRAFT;
function Host() {
  const [d, setD] = useState<GroupDraft>(EMPTY_DRAFT);
  draft = d;
  return createElement(RealismStep, {
    draft: d,
    set: (p: Partial<GroupDraft>) => setD((prev) => ({ ...prev, ...p })),
    members: MEMBERS,
    // Changed: a member is editable once their card has loaded. These two
    // cards say what the neutral seed says, so the checks below hold.
    cards: { j: NEUTRAL_MEMBER, m: NEUTRAL_MEMBER },
  });
}

let container: HTMLDivElement;
let root: Root;
async function mount() {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(createElement(Host));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  adult = false;
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const toggle = (label: string, scope: ParentNode = container) => {
  const row = [...scope.querySelectorAll('label.realism-toggle')].find((l) =>
    l.textContent?.startsWith(label),
  );
  if (!row) throw new Error(`no toggle "${label}"`);
  act(() => row.querySelector('input')!.click());
};
const button = (label: string, scope: ParentNode = container) => {
  const b = [...scope.querySelectorAll('button')].find((el) => el.textContent === label);
  if (!b) throw new Error(`no button "${label}"`);
  act(() => b.click());
};
function type(input: HTMLInputElement | HTMLSelectElement, value: string) {
  const proto = input instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value')!.set!.call(input, value);
  act(() => {
    input.dispatchEvent(new Event(input instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true }));
  });
}
const card = (id: string) => container.querySelector(`[data-testid="group-realism-member-${id}"]`)!;

it('Group Chaos switches on, and its adult events show only with 18+ on', async () => {
  await mount();
  toggle('Group Chaos (Chance Time)');
  expect(draft.chaosModeEnabled).toBe(true);
  expect(container.textContent).not.toContain('Include NSFW events');
  act(() => root.unmount());
  container.remove();

  adult = true;
  await mount();
  toggle('Group Chaos (Chance Time)');
  toggle('Include NSFW events');
  expect(draft).toMatchObject({ chaosModeEnabled: true, chaosNsfwEnabled: true });
});

it('sets where the story clock starts', async () => {
  await mount();
  type(container.querySelector('input[aria-label="Story begins"]')!, '1887-06-01');
  type(container.querySelector('input[aria-label="Opens at"]')!, '07:30');
  expect(draft).toMatchObject({ storyStartDate: '1887-06-01', storyStartTime: '07:30' });
});

it('High Bond and Neutral set every member, as the desktop presets do', async () => {
  await mount();
  button('High Bond');
  for (const m of MEMBERS) {
    expect(memberRealism(draft, m.id)).toMatchObject({
      affection: 75,
      trust: 70,
      emotion: 'affection',
      emotionIntensity: 'moderate',
    });
  }
  button('Neutral');
  // Changed: a preset sets Long-Term Bond to its Short-Term Bond, as the
  // desktop's does, so the slider shows what saves.
  for (const m of MEMBERS) expect(memberRealism(draft, m.id)).toEqual({ ...NEUTRAL_MEMBER, longTermScore: 35 });
});

it("edits one member's emotion, verification and needs, and resets them", async () => {
  await mount();
  const c = card('j');
  type(c.querySelector('input[placeholder="e.g. curious, guarded, amused"]')!, 'wistful');
  type(c.querySelector('select')!, 'strong');
  toggle('Realism Verification (Director/Verifier)', c);
  const sliders = [...c.querySelectorAll('.realism-slider')];
  const slider = (label: string) =>
    sliders.find((s) => s.textContent?.startsWith(label))!.querySelector('input')!;
  type(slider('Max reprocess passes'), '4');
  type(slider('Strictness'), '5');
  type(slider('Hunger'), '20');
  button('Fast', c);
  act(() => (c.querySelectorAll('.needs-row input[type="checkbox"]')[1] as HTMLInputElement).click());
  toggle('Enjoys low hygiene', c);
  expect(memberRealism(draft, 'j')).toMatchObject({
    emotion: 'wistful',
    emotionIntensity: 'strong',
    verificationEnabled: true,
    verificationMaxReprocesses: 4,
    verificationStrictness: 5,
    needsBaselineHunger: 20,
    needsPace: 'fast',
    needsOff: ['bladder'],
    enjoysLowHygiene: true,
  });
  expect(memberRealism(draft, 'm')).toEqual(NEUTRAL_MEMBER);

  toggle('Needs simulation', c);
  expect(draft.needsEnabled, "the member card's needs switch is the group's").toBe(false);

  button('Reset to character defaults', c);
  expect(memberRealism(draft, 'j')).toEqual(NEUTRAL_MEMBER);
});

it('bonds and trust use the desktop scales; each slider sets its own engine key', async () => {
  await mount();
  const c = card('j');
  const slider = (label: string) =>
    [...c.querySelectorAll('.realism-slider')]
      .find((s) => s.querySelector('.realism-slider-head > span')?.textContent === label)!
      .querySelector('input')!;
  expect([slider('Short-Term Bond').min, slider('Short-Term Bond').max]).toEqual(['-300', '300']);
  expect([slider('Long-Term Bond').min, slider('Long-Term Bond').max]).toEqual(['-300', '300']);
  expect([slider('Trust Level').min, slider('Trust Level').max]).toEqual(['-100', '100']);
  type(slider('Short-Term Bond'), '-200');
  expect(slider('Long-Term Bond').value, 'unset, it follows Short-Term Bond').toBe('-200');
  type(slider('Long-Term Bond'), '250');
  expect(memberRealism(draft, 'j')).toMatchObject({ affection: -200, longTermScore: 250, trust: 40 });
  type(slider('Trust Level'), '-50');
  expect(memberRealism(draft, 'j')).toMatchObject({ longTermScore: 250, trust: -50 });
});

it("Neutral, High Bond and Reset clear the member's Group Dynamics, as on the desktop", async () => {
  await mount();
  const feel = (from: string) =>
    [...container.querySelectorAll('[data-testid="group-dynamics"] label.gw-slider')]
      .find((l) => l.textContent?.startsWith(from))!
      .querySelector('input')!;
  const seedBoth = () => {
    type(feel('Juniper → Marlow'), '120');
    type(feel('Marlow → Juniper'), '-40');
  };
  seedBoth();
  expect(draft.relationships).toEqual({ j: { m: 120 }, m: { j: -40 } });
  button('High Bond');
  expect(draft.relationships).toEqual({});
  seedBoth();
  button('Neutral');
  expect(draft.relationships).toEqual({});
  seedBoth();
  button('Reset to character defaults', card('j'));
  expect(draft.relationships, "only Juniper's own feelings go").toEqual({ m: { j: -40 } });
});

// Each member's card starts them: the step shows the card's bonds and
// mood, Reset goes back to the card, the presets keep its Needs, and an
// edit keeps only what it changed. The step used to show, reset to and
// preset from the neutral seed, and posted all of it.
const JUNIPER_CARD: MemberRealism = {
  ...NEUTRAL_MEMBER,
  affection: -60,
  longTermScore: 140,
  trust: -25,
  emotion: 'guarded',
  needsPace: 'fast',
};
const MARLOW_CARD: MemberRealism = { ...NEUTRAL_MEMBER, affection: 0, longTermScore: 0, trust: 0 };
let retried: string[] = [];
async function mountWithCards(cards: Record<string, MemberRealism>, failedCards: string[] = []) {
  retried = [];
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  function CardHost() {
    const [d, setD] = useState<GroupDraft>(EMPTY_DRAFT);
    draft = d;
    return createElement(RealismStep, {
      draft: d,
      set: (p: Partial<GroupDraft>) => setD((prev) => ({ ...prev, ...p })),
      members: MEMBERS,
      cards,
      failedCards,
      onRetryCard: (id: string) => retried.push(id),
    });
  }
  await act(async () => {
    root.render(createElement(CardHost));
  });
}

it('starts each member at their card; an edit keeps only what it changed; Reset goes back', async () => {
  await mountWithCards({ j: JUNIPER_CARD, m: MARLOW_CARD });
  expect(card('j').querySelector('summary')!.textContent).toContain('guarded • Bond -60 / Trust -25');
  expect(card('m').querySelector('summary')!.textContent).toContain('neutral • Bond 0 / Trust 0');
  type(card('j').querySelector('input[placeholder="e.g. curious, guarded, amused"]')!, 'fond');
  expect(draft.members.j, 'nothing the member did not change is kept').toEqual({ emotion: 'fond' });
  expect(memberRealism(draft, 'j', JUNIPER_CARD)).toMatchObject({ emotion: 'fond', affection: -60, needsPace: 'fast' });
  button('Reset to character defaults', card('j'));
  expect(draft.members, 'back to the card: nothing of the wizard is left').not.toHaveProperty('j');
  expect(card('j').querySelector('summary')!.textContent).toContain('guarded • Bond -60 / Trust -25');
});

it("Neutral and High Bond set Long-Term Bond with Short-Term Bond and keep each card's Needs", async () => {
  await mountWithCards({ j: JUNIPER_CARD, m: MARLOW_CARD });
  button('High Bond');
  expect(draft.members.j).toEqual({
    affection: 75,
    longTermScore: 75,
    trust: 70,
    emotion: 'affection',
    emotionIntensity: 'moderate',
  });
  expect(memberRealism(draft, 'j', JUNIPER_CARD)).toMatchObject({ longTermScore: 75, needsPace: 'fast' });
  const longTerm = [...card('j').querySelectorAll('.realism-slider')]
    .find((s) => s.querySelector('.realism-slider-head > span')?.textContent === 'Long-Term Bond')!
    .querySelector('input')!;
  expect(longTerm.value, 'the slider shows what saves').toBe('75');
  button('Neutral');
  expect(memberRealism(draft, 'j', JUNIPER_CARD)).toMatchObject({
    affection: 35,
    longTermScore: 35,
    trust: 40,
    emotion: 'neutral',
    needsPace: 'fast',
  });
});

it("a member can't be edited, nor the presets used, until their card loads", async () => {
  await mountWithCards({ j: JUNIPER_CARD });
  expect(container.querySelector('[data-testid="group-realism-member-m"]'), 'no editor for Marlow yet').toBeNull();
  expect(container.querySelector('[data-testid="group-realism-member-m-pending"]')!.textContent).toContain(
    "Loading Marlow's card",
  );
  const preset = (label: string) =>
    [...container.querySelectorAll('button')].find((b) => b.textContent === label) as HTMLButtonElement;
  expect(preset('High Bond').disabled).toBe(true);
  expect(preset('Neutral').disabled).toBe(true);
  act(() => preset('High Bond').click());
  expect(draft.members, 'a preset pressed early sets nothing').toEqual({});
});

it("a card that failed to load says so and can be asked for again", async () => {
  await mountWithCards({ j: JUNIPER_CARD }, ['m']);
  const pending = container.querySelector('[data-testid="group-realism-member-m-pending"]')!;
  expect(pending.textContent).toContain("Couldn't load Marlow's card.");
  button('Retry', pending);
  expect(retried).toEqual(['m']);
});
