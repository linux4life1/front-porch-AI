// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character ↔ persona conversion, the web twin of the desktop library's
// "Use as Persona" and the Persona page's "Make a Character" (Manual or AI
// Assist). Both talk to /api/persona-convert/*, which calls the same
// PersonaConversion the desktop does.

import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../../api/client';

const MACRO_RE = /\{\{(char|user)\}\}/i;

/** Where a "Make a Character" wizard reads its persona from. */
export function personaSeedPath(personaId: string, swap: boolean) {
  return `/api/persona-convert/persona/${encodeURIComponent(personaId)}${swap ? '' : '?swap=0'}`;
}

/** The wizard URL for a character made from a persona. */
export function makeCharacterUrl(mode: 'manual' | 'ai', personaId: string, swap: boolean) {
  const q = `fromPersona=${encodeURIComponent(personaId)}${swap ? '' : '&swap=0'}`;
  return mode === 'manual' ? `/create?${q}` : `/create-ai?${q}`;
}

function SwapToggle({ swap, onChange }: { swap: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="tool-toggle">
      <span>
        Swap {'{{char}}'} and {'{{user}}'}
        <span className="muted"> · keeps lines like "{'{{char}}'} is {'{{user}}'}'s neighbour" pointing at the right people</span>
      </span>
      <input type="checkbox" checked={swap} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

/** Library "Use as persona": confirm, then save a persona copy of a character. */
export function UseAsPersonaDialog({
  characterId,
  characterName,
  onDone,
  onClose,
}: {
  characterId: string;
  characterName: string;
  onDone: (personaName: string) => void;
  onClose: () => void;
}) {
  const [hasMacros, setHasMacros] = useState(false);
  const [swap, setSwap] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api
      .get<{ hasMacros: boolean }>(`/api/persona-convert/character/${encodeURIComponent(characterId)}`)
      .then((r) => setHasMacros(r.hasMacros))
      .catch(() => setHasMacros(false));
  }, [characterId]);

  const convert = () => {
    setBusy(true);
    setError('');
    api
      .post<{ persona: { id: string; name: string } }>(
        `/api/persona-convert/character/${encodeURIComponent(characterId)}`,
        { swapMacros: swap },
      )
      .then((r) => {
        onDone(r.persona.name);
        onClose();
      })
      .catch((e) => {
        setError(e instanceof ApiError ? e.message : 'Could not create the persona');
        setBusy(false);
      });
  };

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal" role="dialog" aria-label="Use as persona" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Use as persona</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="muted dialog-msg">
          Save "{characterName}" as a persona you can play as. The name, description, personality and portrait are
          copied, plus the birthday when the character has one. Greetings, scenario, lorebook and Porch Life stay with the character, which is not
          changed.
        </p>
        {hasMacros && <SwapToggle swap={swap} onChange={setSwap} />}
        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button className="primary" disabled={busy} onClick={convert}>
            {busy ? 'Creating…' : 'Create persona'}
          </button>
        </div>
      </div>
    </div>
  );
}

/** Persona "Make a character": pick Manual or AI Assist, then open that wizard. */
export function MakeCharacterDialog({
  personaId,
  personaName,
  personaText,
  onClose,
}: {
  personaId: string;
  personaName: string;
  personaText: string;
  onClose: () => void;
}) {
  const navigate = useNavigate();
  const [swap, setSwap] = useState(true);
  const go = (mode: 'manual' | 'ai') => navigate(makeCharacterUrl(mode, personaId, swap));

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal" role="dialog" aria-label="Make a character" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Make a character</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="muted dialog-msg">
          Start a character from "{personaName}". Manual opens the character wizard with the name, description and
          picture filled in, plus the birthday when the persona has one. AI Assist hands the persona to the AI creator, which writes the personality,
          scenario and greetings around it. The persona stays.
        </p>
        {MACRO_RE.test(personaText) && <SwapToggle swap={swap} onChange={setSwap} />}
        <div className="modal-actions">
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button className="primary" onClick={() => go('manual')}>
            Manual
          </button>
          <button className="primary" onClick={() => go('ai')}>
            AI Assist
          </button>
        </div>
      </div>
    </div>
  );
}

/** The persona seed a "Make a Character" wizard was opened with, or null. */
export interface PersonaSeed {
  personaId: string;
  name: string;
  description: string;
  /** Older apps don't send it. */
  personality?: string;
  birthday: string;
  aiConcept: string;
  hasPortrait: boolean;
}

/** The persona's picture as the relay serves it. */
export function personaPortraitUrl(personaId: string) {
  return `/api/persona-convert/persona/${encodeURIComponent(personaId)}/portrait`;
}

/** The wizards' "Starting from the persona…" line, with its picture. */
export function PersonaSeedNote({ seed }: { seed: PersonaSeed }) {
  return (
    <div className="persona-seed-note" data-testid="persona-seed-note">
      {seed.hasPortrait && (
        <img
          className="persona-seed-portrait"
          src={personaPortraitUrl(seed.personaId)}
          alt={`${seed.name}'s picture`}
          data-testid="persona-seed-portrait"
        />
      )}
      <p className="muted small">
        Starting from the persona "{seed.name}"
        {seed.hasPortrait ? '; its picture becomes the portrait.' : '.'}
      </p>
    </div>
  );
}

export function usePersonaSeed(params: URLSearchParams): { seed: PersonaSeed | null; error: string } {
  const personaId = params.get('fromPersona') ?? '';
  const swap = params.get('swap') !== '0';
  const [seed, setSeed] = useState<PersonaSeed | null>(null);
  const [error, setError] = useState('');
  useEffect(() => {
    if (!personaId) return;
    api
      .get<PersonaSeed>(personaSeedPath(personaId, swap))
      .then(setSeed)
      .catch(() => setError('Could not load that persona'));
  }, [personaId, swap]);
  return { seed, error };
}
