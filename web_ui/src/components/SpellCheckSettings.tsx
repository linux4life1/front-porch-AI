// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → Spell Check Language. Moved out of the Generation
// fields so the web page matches the desktop's General tab, where it sits
// under the update row (one-chat-ux PR 7a). It still saves with the
// page's Save button, like the rest of the form.

import { spellCheckLabel, sortedByLabel } from '../spellCheckLabels';

export function SpellCheckSettings({
  spellCheckLanguage,
  spellCheckLanguages,
  onChange,
}: {
  spellCheckLanguage?: string;
  spellCheckLanguages?: string[];
  onChange: (tag: string) => void;
}) {
  if (spellCheckLanguage === undefined) return null;
  return (
    <section className="card" data-testid="spell-check-card">
      <label>
        Spell check language
        <select
          value={spellCheckLanguage}
          onChange={(e) => onChange(e.target.value)}
        >
          <option value="off">Off</option>
          {sortedByLabel([
            ...(spellCheckLanguages ?? []),
            ...(spellCheckLanguage !== 'off' ? [spellCheckLanguage] : []),
          ]).map((tag) => (
            <option key={tag} value={tag}>{spellCheckLabel(tag)}</option>
          ))}
        </select>
        <p className="muted small">
          The language you write in — not your device&apos;s language. If your phone or
          computer is set to one language but you chat with characters in another,
          set this to the one you chat in.
        </p>
      </label>
    </section>
  );
}
