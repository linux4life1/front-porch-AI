// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The words of every studio confirm (sketch V): what will happen and what is
// lost. Same copy as the desktop's story_dashboard_page.actions.dart and
// story_structure_page.dart, shared by the header, Overview and Structure.

import type { StoryProject } from '../../storyTypes';
import {
  beatsWritten, countWords, groupThousands, orderedScenes, sceneLabel, scenesWritten, sceneText,
} from './storyShape';

export interface ConfirmCopy {
  title: string;
  body: string;
  confirmLabel: string;
  destructive?: boolean;
}

const plural = (n: number, one: string, many: string) => (n === 1 ? one : many);

/** Autopilot only writes what is left; it never touches the bible or finished scenes. */
export function autopilotCopy(p: StoryProject): ConfirmCopy {
  const total = orderedScenes(p).length;
  const written = scenesWritten(p);
  const left = total - written;
  const reviews = p.review_enabled === false ? '' : ', with reviews on';
  const stop = "You can stop at any time and keep what's done.";
  const body = total === 0
    ? `Autopilot builds the acts, outlines every sequence and writes every scene, one after another${reviews}. ${stop}`
    : `Autopilot writes the ${left} ${plural(left, 'scene that is', 'scenes that are')} left, one after another${reviews}. `
      + `It will not touch ${written > 0 ? `the ${written} already written or ` : ''}the bible. ${stop}`;
  return { title: 'Write the whole story?', body, confirmLabel: 'Start' };
}

export function regenerateBibleCopy(p: StoryProject): ConfirmCopy {
  const written = scenesWritten(p);
  const kept = written > 0
    ? `Your ${written} written ${plural(written, 'scene stays', 'scenes stay')} but may no longer match. `
    : '';
  return {
    title: 'Regenerate the bible?',
    body: `This rewrites the cast, themes, threads and lore from your idea. ${kept}Interviews and portraits are kept.`,
    confirmLabel: 'Regenerate',
    destructive: true,
  };
}

export const redistillCopy: ConfirmCopy = {
  title: 'Redistill the chat?',
  body: 'The timeline is rebuilt from the chat. The bible is not changed; regenerate it afterwards if the timeline moved.',
  confirmLabel: 'Redistill',
};

export function deleteStoryCopy(p: StoryProject, words: number): ConfirmCopy {
  return {
    title: `Delete ${p.title}?`,
    body: words > 0
      ? `${groupThousands(words)} words, its bible and its run log will be removed. This cannot be undone.`
      : 'Its setup and bible will be removed. This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  };
}

export function rewriteSceneCopy(p: StoryProject, act: number, scene: number): ConfirmCopy {
  const sc = p.scenes[String(act)]?.[scene];
  const words = countWords(sceneText(p, act, scene));
  const facts = (p.continuity ?? []).filter((f) => !!sc?.id && f.scene_id === sc.id).length;
  const retired = facts > 0
    ? ` ${facts} continuity ${plural(facts, 'fact', 'facts')} recorded from this scene ${plural(facts, 'is', 'are')} retired first.`
    : '';
  return {
    title: `Rewrite ${sceneLabel(p, act, scene)} · ${sc?.title ?? ''}?`,
    body: `Its ${groupThousands(words)} words will be replaced. The beats stay.${retired}`,
    confirmLabel: 'Rewrite',
    destructive: true,
  };
}

export function deleteSceneCopy(p: StoryProject, act: number, scene: number): ConfirmCopy {
  const sc = p.scenes[String(act)]?.[scene];
  return {
    title: `Delete ${sceneLabel(p, act, scene)} · ${sc?.title ?? ''}?`,
    body: beatsWritten(p, act, scene) > 0
      ? 'Its prose, beats and the continuity facts it recorded are removed. Later scenes renumber.'
      : 'Its beats are removed. Later scenes renumber.',
    confirmLabel: 'Delete',
    destructive: true,
  };
}

// ── World screens: Director, Cast, Relationships, Lore & continuity, Run log ──
// Same words as the desktop's director_section / cast_section /
// relationships_section / lore_section / run_log_section confirms.

export const discardPlanCopy: ConfirmCopy = {
  title: 'Discard this plan?',
  body: 'The proposed changes are dropped. Nothing in the story changes.',
  confirmLabel: 'Discard',
  destructive: true,
};

export function interviewAgainCopy(name: string): ConfirmCopy {
  return {
    title: `Interview ${name} again?`,
    body: 'The current interview is replaced; the voice guide follows it.',
    confirmLabel: 'Interview',
  };
}

export function removeFromCastCopy(name: string): ConfirmCopy {
  return {
    title: `Remove ${name} from the cast?`,
    body: 'Their dossier, interview and relationships are removed. Scenes already written keep their text.',
    confirmLabel: 'Remove',
    destructive: true,
  };
}

export function removePairCopy(from: string, to: string): ConfirmCopy {
  return {
    title: `Remove ${from} → ${to}?`,
    body: 'The feeling and its history are removed. The engine may record it again after the next scene.',
    confirmLabel: 'Remove',
    destructive: true,
  };
}

export function forgetFactCopy(key: string): ConfirmCopy {
  return {
    title: `Forget “${key}”?`,
    body: 'The writer stops being told this. Scenes already written keep their text.',
    confirmLabel: 'Forget',
    destructive: true,
  };
}

export function removeLoreCopy(topic: string): ConfirmCopy {
  return {
    title: `Remove “${topic}”?`,
    body: 'The writer stops seeing this entry.',
    confirmLabel: 'Remove',
    destructive: true,
  };
}

export function clearLogCopy(calls: number): ConfirmCopy {
  return {
    title: 'Clear the run log?',
    body: `${calls} ${plural(calls, 'call', 'calls')} with their prompts and replies are removed. The story is not touched.`,
    confirmLabel: 'Clear',
    destructive: true,
  };
}
