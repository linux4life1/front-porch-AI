// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Mode step's three cards. Copy is the desktop's (mode_select_step.dart);
// the look is the spec's mode card: an amber icon tile, title and subtitle,
// and on wide screens the description and feature list (the phone draws a row
// card without them).

import type { ReactNode } from 'react';
import type { ChargenMode } from './chargenForm';
import { BoltIcon, BubblesIcon, PenIcon } from './creatorIcons';

const MODES: {
  id: ChargenMode;
  icon: ReactNode;
  title: string;
  subtitle: string;
  description: string;
  features: string[];
}[] = [
  {
    id: 'quick',
    icon: <BoltIcon />,
    title: 'Quick Create',
    subtitle: 'Name it, describe it, done — AI does the rest',
    description:
      'Fastest path to a finished character. Just give a name and a one-liner. ' +
      'The full AI pipeline (interview, lorebook, greetings) runs automatically.',
    features: ['Name + concept only', 'NSFW toggle', 'Full pipeline in ~2 min'],
  },
  {
    id: 'guided',
    icon: <PenIcon />,
    title: 'Guided Creator',
    subtitle: 'Write your vision, AI helps you flesh it out',
    description:
      'Best when you already have a character in mind but need help getting it on paper. ' +
      'Describe your idea in your own words — guided prompts and suggestions help you express your vision.',
    features: ['Free-form text with guided prompts', 'Suggestion chips for inspiration'],
  },
  {
    id: 'automated',
    icon: <BubblesIcon />,
    title: 'Automated Creator',
    subtitle: 'Pick traits from bubbles, let AI fill the gaps',
    description:
      'Best when you want to explore and discover. Select from archetypes, appearance options, ' +
      'backstory presets, and personality keywords. The AI handles the rest.',
    features: ['Archetype presets', 'Bubble selectors for every trait', 'AI generates description from selections'],
  },
];

export function ModeCards({ mode, onPick }: { mode: ChargenMode; onPick: (m: ChargenMode) => void }) {
  return (
    <div className="cg-mode-cards">
      {MODES.map((m) => (
        <button
          type="button"
          key={m.id}
          className={`cg-mode-card${mode === m.id ? ' on' : ''}`}
          aria-pressed={mode === m.id}
          onClick={() => onPick(m.id)}
        >
          <span className="cg-mode-tile">{m.icon}</span>
          <span className="cg-mode-text">
            <span className="cg-mode-title">{m.title}</span>
            <span className="cg-mode-sub">{m.subtitle}</span>
            <span className="cg-mode-desc">{m.description}</span>
            <span className="cg-mode-features">
              {m.features.map((f) => (
                <span key={f}>✓ {f}</span>
              ))}
            </span>
          </span>
        </button>
      ))}
    </div>
  );
}
