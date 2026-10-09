// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Your story so far": the summary rail beside the steps, or the phone's final
// "Ready?" page when `asPage`. Web twin of lib/ui/story_setup/setup_rail.dart.

import { POV_LABELS, TARGET_LENGTHS, type StoryJob } from '../../../storyTypes';
import { fallbackLaneLabel, JOBS, type CharacterRow, type Draft } from './draft';

const lengthLabel = (key: string) => TARGET_LENGTHS.find((t) => t.key === key)?.label ?? key;

/** "Same as chat · Kimi K2.6" → "Kimi K2.6". */
const shortLabel = (label: string) => label.split(' · ').pop() ?? label;

/**
 * The rail's Shape line: "Novel · 80k · third person, close". The length label
 * already names the form (Novella / Novel / Epic), so only an audio drama is
 * called out. Desktop twin: storyShapeSummary in setup_rail.dart.
 */
export function shapeSummary(d: Draft): string {
  return [
    lengthLabel(d.proseLength),
    ...(d.storyFormat === 'audioDrama' ? ['audio drama'] : []),
    (POV_LABELS[d.pov] ?? d.pov).toLowerCase(),
    ...(d.genres.length > 0 ? [d.genres.join(', ').toLowerCase()] : []),
    ...(d.moods.length > 0 ? [d.moods.join(', ').toLowerCase()] : []),
    ...(d.writingStyle ? [d.writingStyle.toLowerCase()] : []),
  ].join(' · ');
}

/** One summary row per line of the rail: [key, value (null when not filled in yet), the step it belongs to]. */
function summaryRows(
  d: Draft,
  step: number,
  chars: CharacterRow[],
  personaName: string,
  laneLabels: Partial<Record<StoryJob, string>>,
): [string, string | null, number][] {
  const cast = [
    ...d.castIds.flatMap((id) => {
      const c = chars.find((x) => x.id === id);
      return c ? [`${c.name} (${(d.roles[id] ?? 'Supporting').toLowerCase()})`] : [];
    }),
    ...(d.includePersona ? [`you as ${personaName} (${d.personaRole.toLowerCase()})`] : []),
  ];
  const shape = shapeSummary(d);
  const lanes = JOBS.map(({ job }) => shortLabel(laneLabels[job] ?? fallbackLaneLabel(d.lanes[job]))).join(' / ');
  const studio = d.engineMode === 'studio';
  const engine = [
    studio ? 'Studio' : 'Quick',
    ...(studio ? [`checks ${d.reviewEnabled ? 'on' : 'off'}`, `lenses ${d.lensesEnabled ? 'on' : 'off'}`] : [`${d.actCount} acts`]),
    lanes,
  ].join(' · ');
  const chat = d.chatSource;
  return [
    ['Title', d.title.trim() || null, 0],
    ['Idea', d.concept.trim() || null, 0],
    ...(chat ? [['From chat', `${chat.characterName} · ${chat.faithful ? 'faithful' : 'inspired by'}`, 0] as [string, string, number]] : []),
    ['Cast', cast.length === 0 ? null : cast.join(', '), 1],
    ['Shape', step >= 2 ? shape : null, 2],
    ['Engine', step >= 3 ? engine : null, 3],
  ];
}

export function SetupRail({ draft, step, chars, personaName, laneLabels, asPage }: {
  draft: Draft;
  step: number;
  chars: CharacterRow[];
  personaName: string;
  laneLabels: Partial<Record<StoryJob, string>>;
  asPage?: boolean;
}) {
  const rows = summaryRows(draft, step, chars, personaName, laneLabels);
  const empty = (key: string, at: number) =>
    key === 'Title' ? 'Suggested later' : key === 'Cast' ? (step > 1 ? 'The bible invents the cast' : 'Step 2') : `Step ${at + 1}`;
  const body = (
    <div className={`wiz-sum${asPage ? ' page' : ''}`} data-testid={asPage ? 'story-ready' : 'story-rail'}>
      <span className="s-key">{asPage ? 'Ready?' : 'Your story so far'}</span>
      {rows.map(([key, value, at]) => (
        <div key={key} className="r">
          <span className="k">{key}</span>
          <span className={`v${value === null ? ' mut' : ''}`}>{value ?? empty(key, at)}</span>
        </div>
      ))}
      {step >= 3 && (
        <span className="note">
          {draft.engineMode === 'studio'
            ? 'Build the bible takes a few minutes with Studio. You can keep using the app.'
            : 'Build the bible takes a minute or two.'}
        </span>
      )}
    </div>
  );
  return asPage ? <div className="s-card">{body}</div> : <aside className="wiz-rail" aria-label="Your story so far">{body}</aside>;
}
