// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Porch Life" — the web mirror of the desktop's dedicated settings tab
// (lib/ui/settings/tabs/porch_life_tab.dart + porch_life_groups.dart).
// Every "what makes characters feel alive" switch in one place, grouped and
// nested in a visual dependency tree matching desktop. Groups and detailed
// descriptions start expanded and are collapsible individually or all at once.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';
import { ExistingChatsOffer, type OfferFeature } from './ExistingChatsOffer';
import { FeatureGroup, type ExpandSignal } from './porchLife/FeatureGroup';
import { FeatureRow } from './porchLife/FeatureRow';
import {
  AwayThreshold,
  FolderNoteRow,
  SearchKeyRow,
  WikiUrlList,
} from './porchLife/ToolsAndWikis';
import { NeedsClockOffNote } from './realism/NeedsClockOffNote';

interface PorchLifeState {
  realismAllowed: boolean;
  realismDefault: boolean;
  nsfwCooldownDefault: boolean;
  needsSimDefault: boolean;
  passageOfTimeDefault: boolean;
  timeSkipBridgeEnabled: boolean;
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
  chaosFrequency: 'rare' | 'normal' | 'wild';
  webSearchDefault: boolean;
  hasSearchApiKey?: boolean;
  wikiBaseUrl?: string;
  wikiSavedUrls?: string[];
  sceneGuestDetectionEnabled: boolean;
  sceneSuggestionsEnabled: boolean;
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

const DEFAULTS: PorchLifeState = {
  realismAllowed: true,
  realismDefault: false,
  nsfwCooldownDefault: false,
  needsSimDefault: true,
  passageOfTimeDefault: true,
  timeSkipBridgeEnabled: true,
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
  chaosFrequency: 'normal',
  webSearchDefault: false,
  hasSearchApiKey: false,
  wikiBaseUrl: '',
  wikiSavedUrls: [],
  sceneGuestDetectionEnabled: true,
  sceneSuggestionsEnabled: false,
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

type GroupId = 'engine' | 'time' | 'memory' | 'presence' | 'tools' | 'afterDark';
type TargetId =
  | 'realism'
  | 'needs'
  | 'passage_of_time'
  | 'story_weather'
  | 'journal'
  | 'pockets'
  | 'objectives';

const TARGET_GROUP: Record<TargetId, GroupId> = {
  realism: 'engine',
  needs: 'engine',
  passage_of_time: 'time',
  story_weather: 'time',
  journal: 'memory',
  pockets: 'memory',
  objectives: 'memory',
};

export function PorchLifeSettings({
  adultThemesOverride,
}: {
  adultThemesOverride?: boolean;
}) {
  const [st, setSt] = useState<PorchLifeState | null>(null);
  const [error, setError] = useState('');
  const [offer, setOffer] = useState<OfferFeature | null>(null);

  const [detailsSignal, setDetailsSignal] = useState<ExpandSignal>({
    version: 0,
    expanded: true,
  });
  const [forceExpand, setForceExpand] = useState<Record<string, number>>({});
  const [highlightedId, setHighlightedId] = useState<TargetId | null>(null);
  const rowRefs = useRef<Partial<Record<TargetId, HTMLDivElement | null>>>({});
  const highlightTimer = useRef<number | null>(null);

  useEffect(() => {
    // Live: the 18+ master switch now lives in General (AdultThemesCard)
    // and any surface can write the realism keys; the server broadcasts
    // `settings_changed` on every write, so this card re-reads instead of
    // showing an After Dark group whose master switch just went off.
    let alive = true;
    const read = () => {
      void api
        .get<{ realism?: Partial<PorchLifeState> }>('/api/settings')
        .then((r) => {
          if (alive) setSt({ ...DEFAULTS, ...r.realism });
        })
        .catch(() => {
          if (alive) setSt({ ...DEFAULTS });
        });
    };
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' || e.event === 'connected') read();
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
      if (highlightTimer.current !== null) {
        window.clearTimeout(highlightTimer.current);
      }
    };
  }, []);

  if (!st) return null;

  const set = <K extends keyof PorchLifeState>(
    key: K,
    value: PorchLifeState[K],
  ) => {
    const prev = st;
    const next = { ...st, [key]: value };
    setSt(next);
    setError('');
    const adult =
      adultThemesOverride !== undefined
        ? adultThemesOverride
        : next.adultThemesEnabled;
    const prevAdult =
      adultThemesOverride !== undefined
        ? adultThemesOverride
        : prev.adultThemesEnabled;
    const allowed = (s: PorchLifeState, isAdult: boolean) =>
      isAdult && s.nsfwCooldownDefault;
    api
      .post('/api/settings', { realism: { [key]: value } })
      .then(() => {
        const realism = next.realismAllowed;
        if (!prev.realismAllowed && realism) setOffer('realism');
        else if (
          realism &&
          !allowed(prev, prevAdult) &&
          allowed(next, adult)
        ) {
          setOffer('afterglow');
        } else if (realism && !prev.needsSimDefault && next.needsSimDefault) {
          setOffer('needs');
        }
      })
      .catch((e) => {
        setSt(prev);
        setError(
          e instanceof ApiError ? e.message : 'Could not save that change',
        );
      });
  };

  const jumpTo = (target: TargetId) => {
    const group = TARGET_GROUP[target];
    setForceExpand((prev) => ({ ...prev, [group]: (prev[group] ?? 0) + 1 }));
    setHighlightedId(target);
    if (highlightTimer.current !== null) {
      window.clearTimeout(highlightTimer.current);
    }
    highlightTimer.current = window.setTimeout(() => {
      setHighlightedId(null);
    }, 1600);
    window.requestAnimationFrame(() => {
      const el = rowRefs.current[target];
      if (el && typeof el.scrollIntoView === 'function') {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    });
  };

  const setRowRef = (id: TargetId) => (el: HTMLDivElement | null) => {
    rowRefs.current[id] = el;
  };

  const engineOn = st.realismAllowed;
  const timeOn = st.passageOfTimeDefault;
  const weatherOn = st.weatherEnabled;
  const journalOn = st.journalEnabled;
  const objectivesOn = st.objectivesEnabled;
  const pocketsOn = st.pocketsEnabled;
  const adultOn =
    adultThemesOverride !== undefined
      ? adultThemesOverride
      : st.adultThemesEnabled;

  const engineCard = (
    <FeatureGroup
      title="The Engine"
      subtitle="feelings about what you do"
      accentTone="amber"
      forceExpandVersion={forceExpand.engine ?? 0}
    >
      <FeatureRow
        rowRef={setRowRef('realism')}
        icon="🎭"
        label="Realism Engine"
        subtitle="Tracks bond, trust, physical state, and lingering moods across turns."
        need="core"
        highlighted={highlightedId === 'realism'}
        expandDetailsSignal={detailsSignal}
        blurb="Allows bond and trust, moods that carry between turns, physical state — how the character feels about what you just did. Needs and desire read from it; the rest of Porch Life runs with or without it, and every row says which it is. Off: no chat runs the engine, and Needs and Afterglow stop with it. Each chat keeps its own choice for when you turn this back on."
        value={engineOn}
        onChange={(v) => set('realismAllowed', v)}
        featureChildren={
          <FeatureRow
            rowRef={setRowRef('needs')}
            icon="❤️"
            label="Needs"
            subtitle="Sims-style hunger, energy, and comfort that drift and colour mood."
            need="needs"
            dependsOn="the Realism Engine"
            satisfied={engineOn}
            highlighted={highlightedId === 'needs'}
            expandDetailsSignal={detailsSignal}
            blurb="Hunger, energy, comfort and the rest, Sims-style — they drift through a scene and colour how the character feels. The engine is what turns a need into a mood, so needs run with it or not at all. Individual chats can still switch them off in the sidebar."
            value={st.needsSimDefault}
            onChange={(v) => set('needsSimDefault', v)}
            showChildWhenOff
          >
            {!timeOn && <NeedsClockOffNote clockOn={timeOn} />}
          </FeatureRow>
        }
      >
        <div className="pl-subswitch-box">
          <label className="tool-toggle">
            <span>Start every new chat with Realism</span>
            <input
              type="checkbox"
              role="switch"
              className="switch"
              aria-label="Start every new chat with Realism"
              checked={st.realismDefault}
              onChange={(e) => set('realismDefault', e.target.checked)}
            />
          </label>
          <p className="muted small">
            Even when the character&apos;s card doesn&apos;t turn it on, such as
            an imported card. Chats you already have keep their own switch.
          </p>
        </div>
      </FeatureRow>
    </FeatureGroup>
  );

  const timeCard = (
    <FeatureGroup
      title="Time & World"
      subtitle="the story's clock and sky"
      accentTone="honey"
      forceExpandVersion={forceExpand.time ?? 0}
    >
      <FeatureRow
        rowRef={setRowRef('passage_of_time')}
        icon="⏰"
        label="Passage of Time"
        subtitle="Runs the story's live clock across every open chat, pacing turns naturally."
        need="alone"
        highlighted={highlightedId === 'passage_of_time'}
        expandDetailsSignal={detailsSignal}
        blurb={
          'The story keeps its own clock — dawn to morning to evening to night, day after day. This switch is what runs the clock in every open chat. Off pauses them immediately; on starts them again. The AI judges how long each exchange actually took, so a shared meal moves the clock further than a passing hello. A normal send always moves at least a minute or two.'
        }
        value={timeOn}
        onChange={(v) => set('passageOfTimeDefault', v)}
        featureChildren={
          <>
            <FeatureRow
              icon="⏩"
              label="Time-skip bridge"
              subtitle="Fills in multi-day time skips with a short narrator bridge card."
              need="needs"
              dependsOn="Passage of Time"
              satisfied={timeOn}
              expandDetailsSignal={detailsSignal}
              blurb={
                'When a message skips a day or more ("two weeks later"), a short narrator card fills in how those days went before the character replies. One short AI call, only on a turn that skips that far. Off, the skip still happens, just without the card.'
              }
              value={st.timeSkipBridgeEnabled}
              onChange={(v) => set('timeSkipBridgeEnabled', v)}
            />
            <FeatureRow
              icon="🧭"
              label="Scene suggestions"
              subtitle="Offers to move the scene when a reply arrives at a named place."
              need="needs"
              dependsOn="Passage of Time"
              satisfied={timeOn}
              expandDetailsSignal={detailsSignal}
              blurb={
                "When the clock is running, the same turn read that moves time also watches the story's PLACE. If a reply clearly arrives somewhere in your world — up the stairs into the Tea Rooms, out through the gate — the app offers to move the scene there. You confirm or stay; it never moves the scene by itself, and a plan or a passing mention is never a move. Later updates add one more offer under this same switch: saving a newly-named place the story walks into. Off by default — offers in the middle of a scene are welcome to some authors and noise to others."
              }
              value={st.sceneSuggestionsEnabled}
              onChange={(v) => set('sceneSuggestionsEnabled', v)}
            />
            <FeatureRow
              rowRef={setRowRef('story_weather')}
              icon="☁️"
              label="Story Weather"
              subtitle="Date-driven weather fronts felt in character mood and comfort."
              need="needs"
              dependsOn="Passage of Time"
              satisfied={timeOn}
              highlighted={highlightedId === 'story_weather'}
              expandDetailsSignal={detailsSignal}
              blurb={
                'Weather rolls through the story\'s days and is felt in mood and comfort. Characters can see fronts coming ("looks like rain tomorrow"). It costs no extra AI call — the sky is worked out from the date — but it needs days to pass.'
              }
              value={weatherOn}
              onChange={(v) => set('weatherEnabled', v)}
              featureChildren={
                <FeatureRow
                  icon="🌡️"
                  label="Temperature Units"
                  subtitle="Choose Celsius or Fahrenheit for sidebar weather displays."
                  need="needs"
                  dependsOn="Story Weather"
                  satisfied={timeOn && weatherOn}
                  expandDetailsSignal={detailsSignal}
                  blurb={
                    'Display only — characters always experience weather in words ("coat-and-gloves cold"), never numbers. Defaults to °C.'
                  }
                  value={st.weatherFahrenheit}
                  trailing={
                    <div
                      className="pl-seg"
                      role="radiogroup"
                      aria-label="Temperature Units"
                    >
                      <button
                        type="button"
                        role="radio"
                        aria-label="Celsius"
                        aria-checked={!st.weatherFahrenheit}
                        disabled={!(timeOn && weatherOn)}
                        className={`pl-seg-btn${!st.weatherFahrenheit ? ' active' : ''}`}
                        onClick={() => set('weatherFahrenheit', false)}
                      >
                        °C
                      </button>
                      <button
                        type="button"
                        role="radio"
                        aria-label="Fahrenheit"
                        aria-checked={st.weatherFahrenheit}
                        disabled={!(timeOn && weatherOn)}
                        className={`pl-seg-btn${st.weatherFahrenheit ? ' active' : ''}`}
                        onClick={() => set('weatherFahrenheit', true)}
                      >
                        °F
                      </button>
                    </div>
                  }
                />
              }
            />
          </>
        }
      />
    </FeatureGroup>
  );

  const memoryCard = (
    <FeatureGroup
      title="Memory & Heart"
      subtitle="what they keep and carry"
      accentTone="teal"
      forceExpandVersion={forceExpand.memory ?? 0}
    >
      <FeatureRow
        rowRef={setRowRef('journal')}
        icon="📖"
        label="The Journal"
        subtitle='Keeps per-chat memory cards and a "where we are" recap.'
        need="alone"
        highlighted={highlightedId === 'journal'}
        expandDetailsSignal={detailsSignal}
        blurb={
          'Memory cards and the "where we are" recap, kept per chat and never shared between chats. With the Realism Engine on, cards also carry the feeling of the moment; without it they are simply remembered.'
        }
        value={journalOn}
        onChange={(v) => set('journalEnabled', v)}
        featureChildren={
          <>
            <FeatureRow
              icon="🌙"
              label="Dreams"
              subtitle="Generates a hazy dream scene from memories, mood, and weather overnight."
              need="needs"
              dependsOn="Passage of Time"
              satisfied={journalOn && timeOn}
              showDependencyBadge
              expandDetailsSignal={detailsSignal}
              onDependencyTap={() =>
                jumpTo(journalOn ? 'passage_of_time' : 'journal')
              }
              blurb="When a story night passes, the character dreams — a short, hazy scene woven from their memories, mood and the weather."
              value={st.dreamsEnabled}
              onChange={(v) => set('dreamsEnabled', v)}
            />
            <FeatureRow
              icon="🤝"
              label="Promises"
              subtitle="Tracks commitments made in chat so kept or broken promises matter later."
              need="needs"
              dependsOn="the Journal"
              satisfied={journalOn}
              expandDetailsSignal={detailsSignal}
              blurb={
                "Commitments either of you make are remembered, and kept or broken ones come back later. Uses one extra AI request per reply to spot them, so it is slower and costs more on a paid API. You can settle one yourself in the Journal's Promises tab."
              }
              value={st.promiseLedgerEnabled}
              onChange={(v) => set('promiseLedgerEnabled', v)}
            />
          </>
        }
      />
      <FeatureRow
        rowRef={setRowRef('pockets')}
        icon="🧥"
        label="Pockets & Wardrobe"
        subtitle="Remembers carried items and worn clothes, including wear and changes."
        need="alone"
        highlighted={highlightedId === 'pockets'}
        expandDetailsSignal={detailsSignal}
        blurb="What they are wearing and carrying is remembered instead of scrolling out of the conversation — so the keys they picked up an hour ago are still in their pocket, and the coat they took off is still off. Items can change: a candy bar becomes a wrapper, a sword gets notched. Uses one extra AI request per reply to notice what changed, so it is slower and costs more on a paid API. Kept per chat and cleared with it."
        value={pocketsOn}
        onChange={(v) => set('pocketsEnabled', v)}
        featureChildren={
          <FeatureRow
            icon="🔁"
            label="Hand things between characters"
            subtitle="Moves handed-over items between pockets in group chats."
            need="needs"
            dependsOn="Pockets & Wardrobe"
            satisfied={pocketsOn}
            expandDetailsSignal={detailsSignal}
            blurb="In a group chat, when one character hands something to another it actually moves — out of their pocket and into theirs, keeping whatever condition it was in. Without this, a handed-over item simply leaves the giver and reaches no one. Costs nothing extra; it rides the check Pockets is already doing. Best with a frontier model (Claude, GPT, Gemini): it has to name WHO received the thing, which is harder than noticing what changed, and smaller local models often get the name wrong. When the name does not match somebody in the chat, the app declines to guess — the item leaves the giver and goes nowhere, exactly as before."
            value={st.pocketTransfersEnabled}
            onChange={(v) => set('pocketTransfersEnabled', v)}
          />
        }
      />
      <FeatureRow
        icon="🌱"
        label="Growth Rings"
        subtitle="Adds lived experience as slow layers without rewriting who they are."
        need="alone"
        expandDetailsSignal={detailsSignal}
        blurb="Slow character evolution — rings, not rewrites. What they live through is added as a new layer instead of overwriting who they were."
        value={st.characterEvolutionEnabled}
        onChange={(v) => set('characterEvolutionEnabled', v)}
      />
      <FeatureRow
        rowRef={setRowRef('objectives')}
        icon="🎯"
        label="Objectives"
        subtitle="Short-lived quests checked every few messages and after time skips."
        need="alone"
        highlighted={highlightedId === 'objectives'}
        expandDetailsSignal={detailsSignal}
        blurb="Short-lived quests a character works toward — set your own, or let them decide what they want. Needs nothing else to run, but it does check in with the AI every few messages (and after a time skip) to see where each goal stands. Switching this off is the way to stop that cost — your quests are kept either way."
        value={objectivesOn}
        onChange={(v) => set('objectivesEnabled', v)}
        featureChildren={
          <>
            <FeatureRow
              icon="🚩"
              label="Ambitions"
              subtitle="Long-term card goals nudged forward whenever an objective finishes."
              need="needs"
              dependsOn="Objectives"
              satisfied={objectivesOn}
              expandDetailsSignal={detailsSignal}
              blurb={
                "Long-term goals written on the character's card colour how they steer a scene, and finishing an objective moves them a little closer. Costs nothing extra — the goals are already on the card — but finishing a quest is the only thing that moves them, so they need Objectives running."
              }
              value={st.ambitionsEnabled}
              onChange={(v) => set('ambitionsEnabled', v)}
            />
            <FeatureRow
              icon="📝"
              label="Planner"
              subtitle="Characters plan ahead from personality and recall what got done."
              need="needs"
              dependsOn="Passage of Time and the Journal"
              satisfied={timeOn && objectivesOn && journalOn}
              showDependencyBadge
              expandDetailsSignal={detailsSignal}
              onDependencyTap={() =>
                jumpTo(
                  !timeOn
                    ? 'passage_of_time'
                    : !journalOn
                      ? 'journal'
                      : 'objectives',
                )
              }
              blurb="They plan from personality; you only add or delete the line. The character will later remember if it got done (needs time, objectives, journal)."
              value={st.plannerEnabled}
              onChange={(v) => set('plannerEnabled', v)}
            />
          </>
        }
      />
      <FeatureRow
        icon="🌤️"
        label="Standing Mood"
        subtitle="Gives characters a baseline mood from their own tracked day, free."
        need="alone"
        expandDetailsSignal={detailsSignal}
        blurb="Lets them arrive already in a mood you had nothing to do with — tired, hungry, worn down by a week of rain, or cheerful after a good night. Everything else in the app reacts to YOU, which slowly makes you the centre of their world; this is the part that is just their day. It is never invented: it comes from what the app already tracks, and the mood chip tells you exactly what they walked in carrying, so you can always tell their day from your doing. Costs nothing — no extra AI request."
        value={st.standingMoodEnabled}
        onChange={(v) => set('standingMoodEnabled', v)}
      />
    </FeatureGroup>
  );

  const presenceCard = (
    <FeatureGroup
      title="Presence"
      subtitle="noticing you, nothing more"
      accentTone="terracotta"
    >
      <FeatureRow
        icon="🎲"
        label="Chaos Mode"
        subtitle="Builds quiet tension for occasional unplanned events in a scene."
        need="alone"
        expandDetailsSignal={detailsSignal}
        blurb="Pressure builds quietly as a scene goes on, and every so often something happens that neither of you planned — a knock at the door, a spilled drink, weather turning. It works with or without the Realism Engine. Switching it on here turns it on for new chats and groups; each chat can still overrule it in the sidebar."
        value={st.chaosModeDefault}
        onChange={(v) => set('chaosModeDefault', v)}
        showChildWhenOff
      >
        <label className="pl-substitch">
          <span className="pl-sub-body">
            <span className="pl-sub-label">How often</span>
            <span className="pl-sub-blurb">
              How often Chance Time pops on its own: Rare is about one event
              every twelve messages, Normal one every six or seven, Wild one
              every three. After an event there is a short breather before
              pressure builds again.
            </span>
          </span>
          <select
            aria-label="How often"
            value={st.chaosFrequency}
            onChange={(e) =>
              set(
                'chaosFrequency',
                e.target.value as PorchLifeState['chaosFrequency'],
              )
            }
          >
            <option value="rare">Rare</option>
            <option value="normal">Normal</option>
            <option value="wild">Wild</option>
          </select>
        </label>
      </FeatureRow>
      <FeatureRow
        icon="🔎"
        label="Notice new characters"
        subtitle="Offers to bring newly named characters in the story into the cast."
        need="alone"
        expandDetailsSignal={detailsSignal}
        blurb="Every few messages the app reads what was just narrated and, if a new named character has turned up in the story, offers to bring them in so they can speak for themselves. Switch this off and it stops asking — you can still invite someone in yourself at any time with the /scan command or the guest button. On by default; turn it off if the offers interrupt more than they help."
        value={st.sceneGuestDetectionEnabled}
        onChange={(v) => set('sceneGuestDetectionEnabled', v)}
      />
      <FeatureRow
        icon="🕰️"
        label="Welcome-back recap"
        subtitle='Shows a brief "where we left off" banner after you have been away.'
        need="alone"
        expandDetailsSignal={detailsSignal}
        blurb={
          'After you have been away a while, opening a chat shows a small "where we left off" banner. Uses the time of your last message, already saved with your chat. Nothing new is collected and nothing leaves your device.'
        }
        value={st.absenceBannerEnabled}
        onChange={(v) => set('absenceBannerEnabled', v)}
      />
      <FeatureRow
        icon="👋"
        label="Character notices your absence"
        subtitle="Lets the character briefly acknowledge a long gap using local timestamps."
        need="alone"
        expandDetailsSignal={detailsSignal}
        blurb={
          'The character briefly acknowledges a long gap ("it\'s been a few days") — once, in coarse words, never guessing what you were doing. Same local-only timestamp as the recap banner.'
        }
        value={st.absenceAckEnabled}
        onChange={(v) => set('absenceAckEnabled', v)}
      >
        <AwayThreshold
          value={st.absenceThresholdHours}
          onChange={(v) => set('absenceThresholdHours', v)}
        />
      </FeatureRow>
    </FeatureGroup>
  );

  const toolsCard = (
    <FeatureGroup
      title="Web Search and extra tools"
      subtitle="looking things up, and recipe cards from your library"
      accentTone="slate"
    >
      <FeatureRow
        icon="🔎"
        label="Web Search"
        subtitle="Lets characters look up unfamiliar words via Wikipedia or Tavily."
        need="alone"
        expandDetailsSignal={detailsSignal}
        blurb="When they hit a word or event they don't know, they can look it up and react as themselves — not reciting a wiki. Only the first reply to a message you send can search on its own. To force one lookup, end the line with /search -- the name, or type the words when you regenerate. Continue, guests, group follow-ups, and Dynamic Responses stay offline. Works with no key: search falls back to Wikipedia (encyclopedia lookups). Add a Tavily API key below for full web coverage. Off by default. Turning this on or off applies to every chat, including ones already open."
        value={st.webSearchDefault}
        onChange={(v) => set('webSearchDefault', v)}
        showChildWhenOff
      >
        <SearchKeyRow
          alreadySet={!!st.hasSearchApiKey}
          onStoredChange={(stored) =>
            setSt((current) =>
              current ? { ...current, hasSearchApiKey: stored } : current,
            )
          }
        />
      </FeatureRow>
      <WikiUrlList
        saved={st.wikiSavedUrls ?? []}
        onSaved={(urls) =>
          setSt((current) =>
            current ? { ...current, wikiSavedUrls: urls } : current,
          )
        }
      />
      <FolderNoteRow
        icon="📁"
        title="Extra Tools"
        subtitle="JSON HTTP recipe cards shared by character chat and Waifu Coder."
        testId="user-tools-folder-note"
        expandDetailsSignal={detailsSignal}
        body="Extra tools are JSON recipe cards in the desktop library tools folder — the same drawer character chat and Waifu Coder share (next to chats and worlds). Phone and browser use built-in web search — there is no file picker here."
      />
      <FolderNoteRow
        icon="📘"
        title="Agent Skills"
        subtitle="OpenCode SKILL.md folders read only by Waifu Coder."
        testId="user-skills-folder-note"
        expandDetailsSignal={detailsSignal}
        body="Waifu Coder also reads OpenCode skill folders from the desktop library skills folder (skills/<name>/SKILL.md). Character chat does not use them. Phone and browser have no file picker here."
      />
    </FeatureGroup>
  );

  const afterDarkCard = adultOn ? (
    <FeatureGroup
      title="After Dark"
      subtitle="shown only when 18+ themes are on"
      accentTone="lust"
    >
      <FeatureRow
        icon="🔥"
        label="Afterglow"
        subtitle="Models lingering intimacy and cooldown rhythm instead of instant resets."
        need="needs"
        dependsOn="Realism's arousal"
        satisfied={engineOn}
        showDependencyBadge
        expandDetailsSignal={detailsSignal}
        onDependencyTap={() => jumpTo('realism')}
        blurb="Desire builds through a scene and settles afterwards instead of resetting — so intimacy keeps a believable rhythm and a character is not instantly ready to go again. The engine is what scores desire, so this cannot run without it. Uses one short extra AI request per reply to notice a climax, so it costs a little more on a paid API. Multiorgasmic characters feel a tenderness window instead of a lock. Off: no chat tracks Lust, and the Afterglow switches on characters and chats are hidden. Each chat keeps its own choice for when you turn this back on."
        value={st.nsfwCooldownDefault}
        onChange={(v) => set('nsfwCooldownDefault', v)}
      />
      <FeatureRow
        icon="💗"
        label="Acts on desires"
        subtitle="Lets characters proactively voice and pursue intimate card preferences."
        need="needs"
        dependsOn="the Realism Engine"
        satisfied={engineOn}
        showDependencyBadge
        expandDetailsSignal={detailsSignal}
        onDependencyTap={() => jumpTo('realism')}
        blurb="A character with intimate preferences on their card acts on them instead of only reacting: they ask for what they want, in their own voice — a dominant character presses where a soft-spoken one hints — and turn down what they are not interested in rather than going along with it. Being refused something they wanted shows in their mood afterwards, sharper or quieter as fits who they are. Needs the engine because that is what scores the answer they get; without it they would ask and nothing would ever come of it. Costs nothing extra — no AI request, just two more lines in the prompt."
        value={st.intimateAgencyEnabled}
        onChange={(v) => set('intimateAgencyEnabled', v)}
      />
    </FeatureGroup>
  ) : null;

  return (
    <section className="card pl-section" data-testid="porch-life-card">
      {offer && (
        <ExistingChatsOffer
          key={offer}
          feature={offer}
          onClose={() => setOffer(null)}
        />
      )}
      <div className="pl-header-bar">
        <div className="pl-header-copy">
          <h3>Porch Life</h3>
          <p className="muted small pl-intro">
            Everything that makes a character feel like they live somewhere.
            Click any group to collapse it, or click an item title to toggle
            its explanation.
          </p>
        </div>
        <div className="pl-toolbar">
          <button
            type="button"
            className="pl-toolbar-btn"
            onClick={() =>
              setDetailsSignal((s) => ({
                version: s.version + 1,
                expanded: !s.expanded,
              }))
            }
          >
            {detailsSignal.expanded
              ? 'Collapse all details'
              : 'Expand all details'}
          </button>
        </div>
      </div>

      <div className="pl-columns">
        <div className="pl-col">
          {engineCard}
          {timeCard}
          {toolsCard}
        </div>
        <div className="pl-col">
          {memoryCard}
          {presenceCard}
          {afterDarkCard}
        </div>
      </div>

      {error && <p className="error pl-error">{error}</p>}

      <div className="pl-note">
        These are the defaults new chats start from. Any single chat can
        overrule most of them from its sidebar — Chaos Mode, Needs, Objectives
        and Growth Rings all have a switch there for that one story. Passage of
        Time is the exception: that row is the live clock switch for every open
        chat.
      </div>
    </section>
  );
}
