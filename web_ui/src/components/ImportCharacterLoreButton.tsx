// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// From character, for a place: pick a card, then tick entries. The whole
// book is never copied.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import type { LoreEntry } from './LoreEntriesEditor';
import {
  filterByName,
  loreEntryLabel,
  matchingEntryIndexes,
  tickedEntries,
} from './importCharacterLore';

interface ListedCharacter {
  id: string;
  name: string;
  hasAvatar?: boolean;
  avatarVersion?: number;
}

interface DetailLore {
  name?: string;
  key?: string;
  content?: string;
  enabled?: boolean;
  constant?: boolean;
  stickyDepth?: number;
}

function toEntry(raw: DetailLore): LoreEntry {
  return {
    name: raw.name ?? '',
    key: raw.key ?? '',
    content: raw.content ?? '',
    enabled: raw.enabled ?? true,
    constant: raw.constant ?? false,
    stickyDepth: raw.stickyDepth ?? 1,
  };
}

export function ImportCharacterLoreButton({
  onImport,
}: {
  onImport: (entries: LoreEntry[]) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className="ghost" onClick={() => setOpen(true)}>
        From character
      </button>
      {open && (
        <ImportCharacterLoreModal
          onClose={() => setOpen(false)}
          onImport={(entries) => {
            onImport(entries);
            setOpen(false);
          }}
        />
      )}
    </>
  );
}

function ImportCharacterLoreModal({
  onClose,
  onImport,
}: {
  onClose: () => void;
  onImport: (entries: LoreEntry[]) => void;
}) {
  const [characters, setCharacters] = useState<ListedCharacter[] | null>(null);
  const [query, setQuery] = useState('');
  const [character, setCharacter] = useState<ListedCharacter | null>(null);
  const [entries, setEntries] = useState<LoreEntry[] | null>(null);
  const [checked, setChecked] = useState<number[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    api
      .get<ListedCharacter[]>('/api/characters?scope=allCharacters')
      .then((list) => {
        if (!cancelled) setCharacters(list ?? []);
      })
      .catch((e) => {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Could not load characters');
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const openCharacter = (card: ListedCharacter) => {
    setCharacter(card);
    setEntries(null);
    setChecked([]);
    setQuery('');
    setError('');
    api
      .get<{ lorebook?: { entries?: DetailLore[] } | null }>(`/api/characters/${card.id}/detail`)
      .then((detail) => {
        setEntries((detail.lorebook?.entries ?? []).map(toEntry));
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load lore'));
  };

  const visible = entries ? matchingEntryIndexes(entries, query) : [];
  const picked = tickedEntries(entries ?? [], checked);

  const toggle = (index: number) => {
    setChecked((prev) =>
      prev.includes(index) ? prev.filter((i) => i !== index) : [...prev, index],
    );
  };

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{character ? 'Choose entries' : 'From character'}</h3>
        <p className="muted small">
          {character
            ? `Tick what to copy from ${character.name}. The rest stays on the card.`
            : 'Pick a character, then choose entries for this place.'}
        </p>
        {error && <p className="error">{error}</p>}
        <input
          value={query}
          placeholder={character ? 'Search entries…' : 'Search characters…'}
          onChange={(e) => setQuery(e.target.value)}
        />
        {!character && characters === null && !error && <p className="muted">Loading characters…</p>}
        {!character &&
          filterByName(characters ?? [], query).map((card) => (
            <button
              key={card.id}
              type="button"
              onClick={() => openCharacter(card)}
              style={{ display: 'flex', alignItems: 'center', gap: 10, textAlign: 'left' }}
            >
              <span className="char-avatar compact">
                {card.hasAvatar ? (
                  <img
                    src={api.avatarUrl(`/api/characters/${card.id}/avatar`, 96, card.avatarVersion)}
                    alt=""
                  />
                ) : (
                  <span className="char-initial">
                    {card.name.trim().charAt(0).toUpperCase() || '?'}
                  </span>
                )}
              </span>
              <span>{card.name}</span>
            </button>
          ))}
        {character && entries === null && !error && <p className="muted">Loading lore…</p>}
        {character && entries !== null && entries.length === 0 && (
          <p className="muted">This character has no lore entries.</p>
        )}
        {character &&
          entries !== null &&
          visible.map((index) => {
            const entry = entries[index];
            return (
              <label className="tool-toggle" key={index}>
                <span>
                  {loreEntryLabel(entry)}
                  {entry.key ? <span className="muted small"> {entry.key}</span> : null}
                </span>
                <input
                  type="checkbox"
                  checked={checked.includes(index)}
                  onChange={() => toggle(index)}
                />
              </label>
            );
          })}
        <div className="modal-actions">
          {character && (
            <button
              type="button"
              onClick={() => {
                setCharacter(null);
                setEntries(null);
                setChecked([]);
                setQuery('');
              }}
            >
              Characters
            </button>
          )}
          {character && (
            <button
              type="button"
              onClick={() =>
                setChecked((prev) => [...new Set([...prev, ...visible])])
              }
              disabled={visible.length === 0}
            >
              Select all
            </button>
          )}
          <button type="button" onClick={onClose}>
            Cancel
          </button>
          {character && (
            <button
              type="button"
              className="primary"
              disabled={picked.length === 0}
              onClick={() => onImport(picked)}
            >
              {picked.length === 0
                ? 'Add selected'
                : `Add ${picked.length} ${picked.length === 1 ? 'entry' : 'entries'}`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
