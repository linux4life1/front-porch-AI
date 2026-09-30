// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../../../api/client';
import type { Picture } from './DeskRail';
import {
  cancelPack,
  fetchPack,
  importPack,
  packPicture,
  startPack,
  type PackStart,
  type PackView,
} from './packApi';

interface CharacterRow {
  id: string;
  name: string;
}

const REMEMBER = 'fpai.pack.character';

function remembered(): string {
  try {
    return window.localStorage.getItem(REMEMBER) ?? '';
  } catch {
    return '';
  }
}

function remember(id: string) {
  try {
    window.localStorage.setItem(REMEMBER, id);
  } catch {
    /* private window: the choice just is not remembered */
  }
}

const message = (e: unknown, fallback: string) => (e instanceof ApiError ? e.message : fallback);

/**
 * Expression packs: pick a character, start one, watch it, stop it, and
 * import what it made. The pictures are made on the computer, by the Edit
 * graph or with the reason it cannot; nothing here decides that.
 */
export function PackPanel(props: {
  prompt: string;
  picture: Picture | null;
}) {
  const [pack, setPack] = useState<PackView | null>(null);
  const [characters, setCharacters] = useState<CharacterRow[]>([]);
  const [character, setCharacter] = useState('');
  const [full, setFull] = useState(false);
  const [skipExisting, setSkipExisting] = useState(true);
  const [replaceExisting, setReplaceExisting] = useState(true);
  const [denoise, setDenoise] = useState(0.7);
  const [left, setLeft] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  // Why the last thing pressed did not work, shown beside the button that was
  // pressed (the desk's own note is far down the screen).
  const [startProblem, setStartProblem] = useState('');
  const [packProblem, setPackProblem] = useState('');

  const refresh = useCallback(() => {
    fetchPack()
      .then(setPack)
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 404) setPack(null);
      });
  }, []);

  useEffect(() => {
    refresh();
    const timer = window.setInterval(refresh, 2000);
    return () => window.clearInterval(timer);
  }, [refresh]);

  useEffect(() => {
    let live = true;
    api
      .get<CharacterRow[]>('/api/characters')
      .then((rows) => {
        if (!live) return;
        setCharacters(rows);
        const saved = remembered();
        setCharacter(rows.some((r) => r.id === saved) ? saved : (rows[0]?.id ?? ''));
      })
      .catch(() => {
        if (live) setCharacters([]);
      });
    return () => {
      live = false;
    };
  }, []);

  const start = () => {
    const body: PackStart = {
      characterId: character,
      set: full ? 'full' : 'starter',
      skipExisting,
      replaceExisting,
      denoise,
      prompt: props.prompt,
    };
    if (props.picture?.kind === 'file') body.referenceImage = props.picture.dataUrl;
    if (props.picture?.kind === 'saved') body.referenceFilename = props.picture.name;
    setBusy(true);
    setLeft(new Set());
    setStartProblem('');
    startPack(body)
      .then(setPack)
      .catch((e: unknown) => setStartProblem(message(e, 'Could not start the pack.')))
      .finally(() => setBusy(false));
  };

  const stop = () => {
    setPackProblem('');
    cancelPack()
      .then(setPack)
      .catch((e: unknown) => setPackProblem(message(e, 'Could not stop the pack.')));
  };

  const doImport = () => {
    if (!pack) return;
    const keep = pack.slots
      .filter((s) => s.state === 'done' && !left.has(s.emotion))
      .map((s) => s.emotion);
    setBusy(true);
    setPackProblem('');
    importPack(keep)
      .then(setPack)
      .catch((e: unknown) => setPackProblem(message(e, 'Could not import the pack.')))
      .finally(() => setBusy(false));
  };

  const toggle = (emotion: string) =>
    setLeft((prev) => {
      const next = new Set(prev);
      if (next.has(emotion)) next.delete(emotion);
      else next.add(emotion);
      return next;
    });

  const running = pack?.running === true;
  const kept = pack ? pack.slots.filter((s) => s.state === 'done' && !left.has(s.emotion)).length : 0;
  return (
    <div className="fp-pack" data-region="pack">
      <p>
        A pack makes each expression from a portrait, one after another. On ComfyUI it runs your Edit
        graph; if that graph is not ready it stops and says what is missing.
      </p>
      <label>
        Character
        <select
          aria-label="Character"
          value={character}
          disabled={running}
          onChange={(e) => {
            setCharacter(e.target.value);
            remember(e.target.value);
          }}
        >
          {characters.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </label>
      <div>
        <button type="button" className="fp-pill" aria-pressed={!full} onClick={() => setFull(false)}>
          Starter (8)
        </button>
        <button type="button" className="fp-pill" aria-pressed={full} onClick={() => setFull(true)}>
          Full (28)
        </button>
      </div>
      <label>
        <input
          type="checkbox"
          checked={skipExisting}
          onChange={(e) => setSkipExisting(e.target.checked)}
        />
        Keep the ones it already has
      </label>
      <label>
        <input
          type="checkbox"
          checked={replaceExisting}
          onChange={(e) => setReplaceExisting(e.target.checked)}
        />
        Replace old images when one is made again
      </label>
      <label>
        Variation strength {denoise.toFixed(2)}
        <input
          type="range"
          aria-label="Variation strength"
          min={0.3}
          max={0.85}
          step={0.05}
          value={denoise}
          onChange={(e) => setDenoise(Number(e.target.value))}
        />
      </label>
      <p>
        {props.picture
          ? `Built from ${props.picture.name}.`
          : 'Built from the character’s portrait. Choose a picture above to use another.'}
      </p>
      <button type="button" disabled={busy || running || !character} onClick={start}>
        Start pack
      </button>
      {startProblem ? <p role="alert">{startProblem}</p> : null}
      {pack ? (
        <div data-region="pack-status">
          <p>
            {pack.characterName}: {pack.done} of {pack.total} made
            {running ? ' — working…' : ''}
          </p>
          <p>
            {pack.mode === 'edit'
              ? 'Made with the Edit graph.'
              : 'This engine has no Edit path, so the pack varies the portrait (img2img).'}
          </p>
          {pack.origin === 'desktop' ? <p>Started on the computer.</p> : null}
          <ul>
            {pack.slots.map((slot) => (
              <li key={slot.emotion}>
                {slot.state === 'done' ? (
                  <img alt={slot.emotion} src={packPicture(slot.emotion)} width={64} height={64} />
                ) : null}
                <span>
                  {slot.emotion}: {slot.state === 'generating' ? 'making' : slot.state}
                </span>
                {slot.error ? <span> — {slot.error}</span> : null}
                {slot.verdict && !(slot.verdict.samePerson && slot.verdict.expressionMatches) ? (
                  <span> — check{slot.verdict.note ? `: ${slot.verdict.note}` : ''}</span>
                ) : null}
                {pack.canImport && slot.state === 'done' ? (
                  <label>
                    <input
                      type="checkbox"
                      aria-label={`Keep ${slot.emotion}`}
                      checked={!left.has(slot.emotion)}
                      onChange={() => toggle(slot.emotion)}
                    />
                    Keep
                  </label>
                ) : null}
              </li>
            ))}
          </ul>
          {running ? (
            <button type="button" onClick={stop}>
              Cancel pack
            </button>
          ) : null}
          {pack.canImport ? (
            <button type="button" disabled={busy || kept === 0} onClick={doImport}>
              Import {kept} to {pack.characterName}
            </button>
          ) : null}
          {packProblem ? <p role="alert">{packProblem}</p> : null}
          {pack.imported != null ? (
            <p>
              Imported {pack.imported} for {pack.characterName}.
            </p>
          ) : null}
          {!running && pack.origin === 'desktop' && pack.done > 0 ? (
            <p>Import it from Image Studio on the computer.</p>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
