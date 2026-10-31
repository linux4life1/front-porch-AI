// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a group member's editor shows of their group — the web twin of the
// desktop member_group_view.dart / group_wide_line.dart. The group's own
// switches are read-only lines (a group never has two switches for one
// thing), and where the member starts in the group's new chats is the
// group's seed for them, sent back as `groupStart` (never their card's own
// bonds). Parsed defensively: an older app sends none of these fields.

import { Slider, SelectRow } from './controls';
import { INTENSITY_OPTIONS, longTermTier, shortTermTier, titleCase, trustTier } from './realismTypes';

/** The group's own switches, as the relay reads them (the open chat's, or
 *  the group's for new chats). */
export interface GroupLines {
  realism: boolean;
  needs: boolean;
  chaos: boolean;
  afterglow: boolean;
  timeLabel: string;
  settingName: string | null;
  readsMemberLorebooks: boolean;
  /** The group is open in the chat: the lines are that chat's own switches. */
  open: boolean;
}

/** Where the member starts in new chats of the group. */
export interface MemberStart {
  shortTermBond: number;
  longTermBond: number;
  trustLevel: number;
  characterEmotion: string;
  emotionIntensity: string;
}

const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

export function parseGroupLines(raw: unknown): GroupLines | null {
  if (!isObj(raw)) return null;
  const b = (k: string) => raw[k] === true;
  return {
    realism: b('realism'),
    needs: b('needs'),
    chaos: b('chaos'),
    afterglow: b('afterglow'),
    timeLabel: typeof raw.timeLabel === 'string' ? raw.timeLabel : '',
    settingName: typeof raw.settingName === 'string' ? raw.settingName : null,
    readsMemberLorebooks: b('readsMemberLorebooks'),
    open: b('open'),
  };
}

export function parseMemberStart(raw: unknown): MemberStart | null {
  if (!isObj(raw)) return null;
  const n = (k: string, d: number) => (typeof raw[k] === 'number' ? (raw[k] as number) : d);
  const s = (k: string, d: string) => (typeof raw[k] === 'string' ? (raw[k] as string) : d);
  return {
    shortTermBond: n('shortTermBond', 35),
    longTermBond: n('longTermBond', 35),
    trustLevel: n('trustLevel', 40),
    characterEmotion: s('characterEmotion', 'neutral'),
    emotionIntensity: s('emotionIntensity', 'mild'),
  };
}

/** "Close / Trusting · Afterglow on", after the member's name. */
export function memberSummaryDetail(
  start: MemberStart | null,
  afterglow: boolean | null,
  lite: boolean,
): string {
  if (lite) return 'Realism starts when promoted';
  return [
    start ? `${longTermTier(start.longTermBond)} / ${trustTier(start.trustLevel)}` : null,
    afterglow === null ? null : `Afterglow ${afterglow ? 'on' : 'off'}`,
  ]
    .filter(Boolean)
    .join(' · ');
}

const onOff = (v: boolean) => (v ? 'On' : 'Off');

export interface LineText {
  text: string;
  /** Where the phone sets it. */
  where: string;
}

/** One of the group's own switches, read-only, and where it is set. */
export function GroupLine({ line, testId }: { line: LineText; testId?: string }) {
  return (
    <p className="card muted small group-line" data-testid={testId}>
      {line.text} <span className="muted">· {line.where}</span>
    </p>
  );
}

/** The lines and where each is set on the phone: the open chat's own
 *  switches are in its tools; a closed group's settings for new chats are
 *  in Group settings, and its Chaos and clock only in a chat of the group. */
export function groupLineTexts(g: GroupLines): Record<'realism' | 'time' | 'chaos' | 'afterglow' | 'needs', LineText> {
  const chat = "set in this chat's tools";
  const settings = g.open ? chat : 'set in Group settings, in a chat of this group';
  const inChat = g.open ? chat : 'set in a chat of this group';
  return {
    realism: { text: `Realism Engine · ${onOff(g.realism)} for this group`, where: settings },
    time: { text: `Time & Day · shared by the group: ${g.timeLabel}`, where: inChat },
    chaos: { text: `Chaos Mode · ${onOff(g.chaos)} for this group`, where: inChat },
    afterglow: { text: `Afterglow · ${onOff(g.afterglow)} for this group`, where: settings },
    needs: { text: `Needs · ${onOff(g.needs)} for this group`, where: settings },
  };
}

/** Relationship and Starting emotion, over any holder of the five values
 *  (the card's own in a 1:1 editor, the group's seed in a member's). */
export function RelationshipFields({
  v,
  set,
  note,
}: {
  v: MemberStart;
  set: (patch: Partial<MemberStart>) => void;
  note?: string;
}) {
  return (
    <>
      <h4 className="realism-head">Relationship</h4>
      {note && (
        <p className="muted small" data-testid="member-start-note">
          {note}
        </p>
      )}
      <div className="card realism-card">
        <Slider
          label="Short-term bond"
          min={-300}
          max={300}
          value={v.shortTermBond}
          badge={`${shortTermTier(v.shortTermBond)} (${v.shortTermBond})`}
          onChange={(n) => set({ shortTermBond: n })}
        />
        <Slider
          label="Long-term bond"
          min={-300}
          max={300}
          value={v.longTermBond}
          badge={`${longTermTier(v.longTermBond)} (${v.longTermBond})`}
          onChange={(n) => set({ longTermBond: n })}
        />
        <Slider
          label="Trust level"
          min={-100}
          max={100}
          value={v.trustLevel}
          badge={`${trustTier(v.trustLevel)} (${v.trustLevel})`}
          onChange={(n) => set({ trustLevel: n })}
        />
      </div>

      <h4 className="realism-head">Starting emotion</h4>
      <div className="realism-grid-2">
        <label className="realism-field">
          <span>Emotion</span>
          <input
            value={v.characterEmotion}
            placeholder="e.g. curious, guarded, amused"
            onChange={(e) => set({ characterEmotion: e.target.value })}
          />
        </label>
        <SelectRow
          label="Intensity"
          value={v.emotionIntensity}
          options={INTENSITY_OPTIONS.map((i) => ({ value: i, label: titleCase(i) }))}
          onChange={(s) => set({ emotionIntensity: s })}
        />
      </div>
    </>
  );
}

/** What the Alternate greetings, Lorebook and Worlds sections say a group
 *  does with a member's own greeting seeds, lorebook and worlds. */
export function memberSectionNotes(name: string, g: GroupLines) {
  return {
    greeting: 'Used when a greeting opens a chat of this group.',
    lorebook:
      `${name}'s lorebook. The group reads it when Group settings has ` +
      `"Inherit character & world lorebooks" on; it is ${g.readsMemberLorebooks ? 'on' : 'off'} for this group.`,
    worlds:
      `${g.settingName ? `This group meets in ${g.settingName}.` : 'This group has no Setting world yet.'} ` +
      "A member's own worlds aren't used in a group; the group's world is set in Group settings.",
  };
}
