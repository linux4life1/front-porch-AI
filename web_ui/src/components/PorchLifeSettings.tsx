// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Porch Life" — the web mirror of the desktop's dedicated settings tab
// (lib/ui/settings/tabs/porch_life_tab.dart + widgets/feature_row.dart).
// Every "what makes characters feel alive" switch in one place, grouped by
// what it is, each saying plainly what it needs. The chips ("works alone" /
// "needs X" / "core") report the verified dependency matrix from
// docs/design/feature-independence.md rather than a guess — a feature that
// used to be hidden inside the Realism Engine's card (like the welcome-back
// recap or Story Weather) now says outright whether it actually needs the
// engine or was just filed under it.
//
// Self-contained and auto-saving, same pattern as PersonaManager: every
// switch applies the instant it's flipped — same feel as the desktop
// Switch — so there is no separate "Save settings" step for this card.
// Rides the same /api/settings `realism` object the app's other
// story-feature flags (ambitions, promises) already live in; a POST here
// only ever sends the one key that changed, so it can't clobber anything
// else queued in the page's big Save button.
//
// Scope note (mirrors the desktop doc comment): this card holds the GLOBAL
// defaults; every one of them can still be overruled by a single chat from
// its sidebar (ChatTools), which is what the closing note now says. Chaos
// Mode gained its global default on 2026-08-08 and moved into this card with
// it, so the note no longer has to apologise for a switch living elsewhere.

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { api, ApiError } from '../api/client';

interface PorchLifeState {
  realismDefault: boolean;
  nsfwCooldownDefault: boolean;
  needsSimDefault: boolean;
  passageOfTimeDefault: boolean;
  standaloneClockEnabled: boolean;
  objectivesEnabled: boolean;
  weatherEnabled: boolean;
  weatherFahrenheit: boolean;
  journalEnabled: boolean;
  characterEvolutionEnabled: boolean;
  pocketsEnabled: boolean;
  standingMoodEnabled: boolean;
  pocketTransfersEnabled: boolean;
  intimateAgencyEnabled: boolean;
  chaosModeDefault: boolean;
  sceneGuestDetectionEnabled: boolean;
  adultThemesEnabled: boolean;
  dreamsEnabled: boolean;
  promiseLedgerEnabled: boolean;
  ambitionsEnabled: boolean;
  plannerEnabled: boolean;
  absenceBannerEnabled: boolean;
  absenceAckEnabled: boolean;
  absenceThresholdHours: number;
  preferTextEvals: boolean;
}

// Same fallbacks as the Dart RealismSettings field defaults, so a field an
// older host build hasn't started returning yet still renders something sane
// rather than a false "off".
const DEFAULTS: PorchLifeState = {
  realismDefault: false,
  nsfwCooldownDefault: false,
  needsSimDefault: true,
  passageOfTimeDefault: true,
  standaloneClockEnabled: false,
  objectivesEnabled: true,
  weatherEnabled: true,
  weatherFahrenheit: false,
  journalEnabled: true,
  characterEvolutionEnabled: false,
  pocketsEnabled: false,
  standingMoodEnabled: false,
  pocketTransfersEnabled: false,
  intimateAgencyEnabled: false,
  chaosModeDefault: false,
  sceneGuestDetectionEnabled: true,
  adultThemesEnabled: false,
  dreamsEnabled: true,
  promiseLedgerEnabled: true,
  ambitionsEnabled: true,
  plannerEnabled: false,
  absenceBannerEnabled: true,
  absenceAckEnabled: false,
  absenceThresholdHours: 24,
  preferTextEvals: false,
};

type Need = 'alone' | 'needs' | 'core';

function chipText(need: Need, dependsOn?: string): string {
  if (need === 'alone') return 'works alone';
  if (need === 'core') return 'CORE';
  return `needs ${dependsOn ?? ''}`;
}

function FeatureRow({
  icon,
  label,
  blurb,
  need = 'alone',
  dependsOn,
  satisfied = true,
  value,
  onChange,
  children,
}: {
  icon: string;
  label: string;
  blurb: string;
  need?: Need;
  dependsOn?: string;
  satisfied?: boolean;
  value: boolean;
  onChange: (v: boolean) => void;
  children?: ReactNode;
}) {
  // An unmet requirement GATES the row (dead switch + dimmed + indented),
  // matching the desktop widget. The first draft left dependants live and
  // stacked warning banners instead, which read as a wall of nags
  // (maintainer, 2026-08-07).
  const gated = need === 'needs' && !satisfied;
  return (
    <div className={`pl-row${need === 'needs' ? ' pl-row-dependent' : ''}${gated ? ' pl-row-gated' : ''}`}>
      <div className="pl-row-main">
        <span className="pl-row-icon" aria-hidden="true">{icon}</span>
        <div className="pl-row-body">
          <div className="pl-row-label-line">
            <span className="pl-label">{label}</span>
            <span className={`pl-chip pl-chip-${need}`}>{chipText(need, dependsOn)}</span>
          </div>
          <p className="pl-blurb">{blurb}</p>
        </div>
        <label className="pl-switch">
          <input
            type="checkbox"
            checked={value}
            onChange={(e) => onChange(e.target.checked)}
            disabled={gated}
            aria-label={label}
          />
        </label>
      </div>
      {children && value && !gated && <div className="pl-child">{children}</div>}
    </div>
  );
}

function FeatureGroup({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: ReactNode;
}) {
  return (
    <div className="pl-group">
      <div className="pl-group-head">
        <span className="pl-group-title">{title}</span>
        <span className="pl-group-subtitle">{subtitle}</span>
      </div>
      {children}
    </div>
  );
}

const AWAY_OPTIONS: { value: number; label: string }[] = [
  { value: 12, label: '12 hours' },
  { value: 24, label: 'a day' },
  { value: 72, label: '3 days' },
  { value: 168, label: 'a week' },
];

/** The "away for at least" dropdown riding the absence-acknowledgement row.
 *  Values are clamped to a known option so a hand-edited preference can't
 *  assert the dropdown (carried over from the desktop widget). */
function AwayThreshold({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const known = AWAY_OPTIONS.some((o) => o.value === value) ? value : 24;
  return (
    <label className="pl-away row-label">
      <span>Away for at least</span>
      <select value={known} onChange={(e) => onChange(Number(e.target.value))}>
        {AWAY_OPTIONS.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </label>
  );
}

export function PorchLifeSettings() {
  const [st, setSt] = useState<PorchLifeState | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    void api
      .get<{ realism?: Partial<PorchLifeState> }>('/api/settings')
      .then((r) => setSt({ ...DEFAULTS, ...r.realism }))
      .catch(() => setSt({ ...DEFAULTS }));
  }, []);

  if (!st) return null;

  const set = <K extends keyof PorchLifeState>(key: K, value: PorchLifeState[K]) => {
    const prev = st;
    setSt({ ...st, [key]: value });
    setError('');
    api.post('/api/settings', { realism: { [key]: value } }).catch((e) => {
      setSt(prev);
      setError(e instanceof ApiError ? e.message : 'Could not save that change');
    });
  };

  const engineOn = st.realismDefault;
  const timeOn = st.passageOfTimeDefault;
  const weatherOn = st.weatherEnabled;
  const journalOn = st.journalEnabled;
  // Objectives depend on nothing but their own eval cost; Ambitions hang off
  // them, since finishing a quest is the only thing that moves progress.
  const objectivesOn = st.objectivesEnabled;
  const adultOn = st.adultThemesEnabled;
  // Weather and dreams gate on the Passage of Time FLAG, deliberately not on
  // whether the clock is currently moving — gating on the latter greys Story
  // Weather out again with the engine off, which is the dead-switch problem
  // this tab exists to end. Same reasoning as the desktop tab; see the comment
  // there. The "left off, the clock holds still" fact lives on the row above.

  return (
    <section className="card pl-section">
      <h3>Porch Life</h3>
      <p className="muted small pl-intro">
        Everything that makes a character feel like they live somewhere. Each switch says plainly what it needs — many need nothing at all.
      </p>

      {/* 18+ master switch — always visible (desktop Settings → General).
          After Dark is hidden when this is off, so the switch cannot live
          inside that group or there is no way back on (audit P2.14). */}
      <FeatureGroup title="Content" subtitle="what surfaces are allowed to appear">
        <FeatureRow
          icon="🔞"
          label="18+ themes"
          need="alone"
          blurb="Shows the adult features — the After Dark group below, and intimate preferences in the character editor. Off means they are simply not there. Turning this off never erases what you already set; it only hides the switches."
          value={adultOn}
          onChange={(v) => set('adultThemesEnabled', v)}
        />
      </FeatureGroup>

      <FeatureGroup title="The Engine" subtitle="feelings about what you do">
        <FeatureRow
          icon="🎭"
          label="Realism Engine"
          need="core"
          blurb="Bond and trust, moods that carry between turns, physical state — how the character feels about what you just did. Needs, the story clock and desire all read from it; the rest of Porch Life runs with or without it, and every row says which it is."
          value={engineOn}
          onChange={(v) => set('realismDefault', v)}
        />
        <FeatureRow
          icon="❤️"
          label="Needs"
          need="needs"
          dependsOn="the Realism Engine"
          satisfied={engineOn}
          blurb="Hunger, energy, comfort and the rest, Sims-style — they drift through a scene and colour how the character feels. The engine is what turns a need into a mood, so needs run with it or not at all. Individual chats can still switch them off in the sidebar."
          value={st.needsSimDefault}
          onChange={(v) => set('needsSimDefault', v)}
        />
      </FeatureGroup>

      <FeatureGroup title="Time & World" subtitle="the story's clock and sky">
        <FeatureRow
          icon="⏰"
          label="Passage of Time"
          need="alone"
          blurb="The story keeps its own clock — dawn to morning to evening to night, day after day. The AI judges how long each exchange actually took, so a shared meal moves the clock further than a passing hello."
          value={timeOn}
          onChange={(v) => set('passageOfTimeDefault', v)}
        >
          {/* Shown only with the engine off — with it on the clock already
              rides the engine's reading of the scene and costs nothing extra,
              so a switch there would be a choice about nothing. Mirrors the
              desktop `_StandaloneClockSwitch`. */}
          {!engineOn && (
            <label className="pl-substitch">
              <span className="pl-sub-body">
                <span className="pl-sub-label">Keep the clock running without the engine</span>
                <span className="pl-sub-blurb">
                  The engine normally judges how long each exchange took as part of work it is
                  already doing. With it off, the clock needs one short AI call of its own each
                  turn — so this costs a little speed. Left off, the clock simply holds still.
                </span>
              </span>
              <input
                type="checkbox"
                checked={st.standaloneClockEnabled}
                onChange={(e) => set('standaloneClockEnabled', e.target.checked)}
                aria-label="Keep the clock running without the engine"
              />
            </label>
          )}
        </FeatureRow>
        <FeatureRow
          icon="☁️"
          label="Story Weather"
          need="needs"
          dependsOn="Passage of Time"
          satisfied={timeOn}
          blurb={'Weather rolls through the story\'s days and is felt in mood and comfort. Characters can see fronts coming ("looks like rain tomorrow"). It costs no extra AI call — the sky is worked out from the date — but it needs days to pass.'}
          value={weatherOn}
          onChange={(v) => set('weatherEnabled', v)}
        />
        <FeatureRow
          icon="🌡️"
          label="Temperatures in °F"
          need="needs"
          dependsOn="Story Weather"
          satisfied={weatherOn}
          blurb={'Display only — characters always experience weather in words ("coat-and-gloves cold"), never numbers.'}
          value={st.weatherFahrenheit}
          onChange={(v) => set('weatherFahrenheit', v)}
        />
      </FeatureGroup>

      <FeatureGroup title="Memory & Heart" subtitle="what they keep and carry">
        <FeatureRow
          icon="📖"
          label="The Journal"
          blurb={'Memory cards and the "where we are" recap, kept per chat and never shared between chats. With the Realism Engine on, cards also carry the feeling of the moment; without it they are simply remembered.'}
          value={journalOn}
          onChange={(v) => set('journalEnabled', v)}
        />
        <FeatureRow
          icon="🌙"
          label="Dreams"
          need="needs"
          dependsOn="the Journal and Passage of Time"
          satisfied={journalOn && timeOn}
          blurb="When a story night passes, the character dreams — a short, hazy scene woven from their memories, mood and the weather."
          value={st.dreamsEnabled}
          onChange={(v) => set('dreamsEnabled', v)}
        />
        <FeatureRow
          icon="🤝"
          label="Promises"
          need="needs"
          dependsOn="the Journal"
          satisfied={journalOn}
          blurb={"Commitments either of you make are remembered, and kept or broken ones come back later. Uses one extra AI request per reply to spot them, so it is slower and costs more on a paid API. You can settle one yourself in the Journal's Promises tab."}
          value={st.promiseLedgerEnabled}
          onChange={(v) => set('promiseLedgerEnabled', v)}
        />
        <FeatureRow
          icon="🧥"
          label="Pockets & Wardrobe"
          need="alone"
          blurb="What they are wearing and carrying is remembered instead of scrolling out of the conversation — so the keys they picked up an hour ago are still in their pocket, and the coat they took off is still off. Items can change: a candy bar becomes a wrapper, a sword gets notched. Uses one extra AI request per reply to notice what changed, so it is slower and costs more on a paid API. Kept per chat and cleared with it."
          value={st.pocketsEnabled}
          onChange={(v) => set('pocketsEnabled', v)}
        />
        <FeatureRow
          icon="🔁"
          label="Hand things between characters"
          need="needs"
          dependsOn="Pockets & Wardrobe"
          satisfied={st.pocketsEnabled}
          blurb="In a group chat, when one character hands something to another it actually moves — out of their pocket and into theirs, keeping whatever condition it was in. Without this, a handed-over item simply leaves the giver and reaches no one. Costs nothing extra; it rides the check Pockets is already doing. Best with a frontier model (Claude, GPT, Gemini): it has to name WHO received the thing, which is harder than noticing what changed, and smaller local models often get the name wrong. When the name does not match somebody in the chat, the app declines to guess — the item leaves the giver and goes nowhere, exactly as before."
          value={st.pocketTransfersEnabled}
          onChange={(v) => set('pocketTransfersEnabled', v)}
        />
        <FeatureRow
          icon="🌤️"
          label="Standing Mood"
          need="alone"
          blurb="Lets them arrive already in a mood you had nothing to do with — tired, hungry, worn down by a week of rain, or cheerful after a good night. Everything else in the app reacts to YOU, which slowly makes you the centre of their world; this is the part that is just their day. It is never invented: it comes from what the app already tracks, and the mood chip tells you exactly what they walked in carrying, so you can always tell their day from your doing. Costs nothing — no extra AI request."
          value={st.standingMoodEnabled}
          onChange={(v) => set('standingMoodEnabled', v)}
        />
        <FeatureRow
          icon="🌱"
          label="Growth Rings"
          need="alone"
          blurb="Slow character evolution — rings, not rewrites. What they live through is added as a new layer instead of overwriting who they were."
          value={st.characterEvolutionEnabled}
          onChange={(v) => set('characterEvolutionEnabled', v)}
        />
        <FeatureRow
          icon="🎯"
          label="Objectives"
          need="alone"
          blurb="Short-lived quests a character works toward — set your own, or let them decide what they want. Needs nothing else to run, but it does check in with the AI to see whether a task got done: every turn while the Realism Engine is on, and every few messages while it is off. Switching this off is the way to stop that cost — your quests are kept either way."
          value={objectivesOn}
          onChange={(v) => set('objectivesEnabled', v)}
        />
        <FeatureRow
          icon="🚩"
          label="Ambitions"
          need="needs"
          dependsOn="Objectives"
          satisfied={objectivesOn}
          blurb={"Long-term goals written on the character's card colour how they steer a scene, and finishing an objective moves them a little closer. Costs nothing extra — the goals are already on the card — but finishing a quest is the only thing that moves them, so they need Objectives running."}
          value={st.ambitionsEnabled}
          onChange={(v) => set('ambitionsEnabled', v)}
        />
        <FeatureRow
          icon="📝"
          label="Planner"
          need="needs"
          dependsOn="Passage of Time, Objectives, and the Journal"
          satisfied={timeOn && objectivesOn && journalOn}
          blurb="They plan from personality; you only add or delete the line. The character will later remember if it got done (needs time, objectives, journal)."
          value={st.plannerEnabled}
          onChange={(v) => set('plannerEnabled', v)}
        />
      </FeatureGroup>

      <FeatureGroup title="Presence" subtitle="noticing you, nothing more">
        <FeatureRow
          icon="🔎"
          label="Notice new characters"
          need="alone"
          blurb="Every few messages the app reads what was just narrated and, if a new named character has turned up in the story, offers to bring them in so they can speak for themselves. Switch this off and it stops asking — you can still invite someone in yourself at any time with the /scan command or the guest button. On by default; turn it off if the offers interrupt more than they help."
          value={st.sceneGuestDetectionEnabled}
          onChange={(v) => set('sceneGuestDetectionEnabled', v)}
        />
        <FeatureRow
          icon="🎲"
          label="Chaos Mode"
          need="alone"
          blurb="Pressure builds quietly as a scene goes on, and every so often something happens that neither of you planned — a knock at the door, a spilled drink, weather turning. The 2026-08-07 audit confirmed it runs perfectly well with the Realism Engine off; it was only ever filed next to it. Switching it on here turns it on for new chats and groups; each chat can still overrule it in the sidebar."
          value={st.chaosModeDefault}
          onChange={(v) => set('chaosModeDefault', v)}
        />
        <FeatureRow
          icon="🕰️"
          label="Welcome-back recap"
          blurb={'After you have been away a while, opening a chat shows a small "where we left off" banner. Uses the time of your last message, already saved with your chat. Nothing new is collected and nothing leaves your device.'}
          value={st.absenceBannerEnabled}
          onChange={(v) => set('absenceBannerEnabled', v)}
        />
        <FeatureRow
          icon="👋"
          label="Character notices your absence"
          blurb={'The character briefly acknowledges a long gap ("it\'s been a few days") — once, in coarse words, never guessing what you were doing. Same local-only timestamp as the recap banner.'}
          value={st.absenceAckEnabled}
          onChange={(v) => set('absenceAckEnabled', v)}
        >
          <AwayThreshold
            value={st.absenceThresholdHours}
            onChange={(v) => set('absenceThresholdHours', v)}
          />
        </FeatureRow>
      </FeatureGroup>

      {error && <p className="error pl-error">{error}</p>}

      <div className="pl-note">
        These are the defaults new chats start from. Any single chat can overrule them from its sidebar — Chaos Mode, Needs, Objectives and Growth Rings all have a switch there for that one story.
      </div>
      {/* After Dark — the approved sketch gives the 18+ feature its own group,
          "shown only when 18+ themes are enabled": absent, not greyed out, for
          anyone who has not asked for adult content. The master switch is in
          desktop Settings → General so it stays reachable while this is hidden. */}
      {adultOn && (
        <FeatureGroup title="After Dark" subtitle="shown only when 18+ themes are on">
          <FeatureRow
            icon="🔥"
            label="Afterglow"
            need="needs"
            dependsOn="Realism's arousal"
            satisfied={engineOn}
            blurb="Desire builds through a scene and settles afterwards instead of resetting — so intimacy keeps a believable rhythm and a character is not instantly ready to go again. The engine is what scores desire, so this cannot run without it."
            value={st.nsfwCooldownDefault}
            onChange={(v) => set('nsfwCooldownDefault', v)}
          />
          <FeatureRow
            icon="💗"
            label="Acts on desires"
            need="needs"
            dependsOn="the Realism Engine"
            satisfied={engineOn}
            blurb="A character with intimate preferences on their card acts on them instead of only reacting: they ask for what they want, in their own voice — a dominant character presses where a soft-spoken one hints — and turn down what they are not interested in rather than going along with it. Being refused something they wanted shows in their mood afterwards, sharper or quieter as fits who they are. Needs the engine because that is what scores the answer they get; without it they would ask and nothing would ever come of it. Costs nothing extra — no AI request, just two more lines in the prompt."
            value={st.intimateAgencyEnabled}
            onChange={(v) => set('intimateAgencyEnabled', v)}
          />
        </FeatureGroup>
      )}

    </section>
  );
}
