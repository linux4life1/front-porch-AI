// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useRef, useState } from 'react';
import { civitaiBaseGroups, civitaiBaseLabel, filterCivitaiBases } from '../civitaiBases';

/**
 * One searchable base picker, the same rules as the desktop one. The sheet
 * holds the pick, the typed words and "Only installed": typing only narrows
 * the menu, the field shows the pick once it is left, and the pick is what a
 * search sends.
 */
export function CivitaiBasePicker(props: {
  base: string;
  onBase: (api: string) => void;
  query: string;
  onQuery: (query: string) => void;
  installedOnly: boolean;
  onInstalledOnly: (on: boolean) => void;
  /** Installed bases; null while the computer is still looking. */
  installedBases: string[] | null;
  note: string;
}) {
  const [open, setOpen] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const shown = filterCivitaiBases(
    civitaiBaseGroups,
    props.query,
    props.installedOnly ? props.installedBases ?? [] : null,
  );
  const label = props.base ? civitaiBaseLabel(props.base) : 'Any base';
  // Keeps the field focused while an option or Clear is pressed.
  const keep = (e: { preventDefault: () => void }) => e.preventDefault();
  const pick = (api: string) => {
    props.onBase(api);
    input.current?.blur();
  };
  const option = (api: string, text: string) => (
    <button
      key={api || 'any'}
      type="button"
      role="option"
      aria-selected={api === props.base}
      onMouseDown={keep}
      onClick={() => pick(api)}
      style={{ display: 'block', width: '100%', textAlign: 'left' }}
    >
      {text}
    </button>
  );

  return (
    <div style={{ marginTop: 16 }}>
      <label>
        Base model
        <input
          ref={input}
          aria-label="Base model"
          placeholder="Type to narrow: Qwen, Flux, SDXL"
          value={open ? props.query : label}
          onFocus={() => {
            setOpen(true);
            props.onQuery('');
          }}
          onBlur={() => {
            setOpen(false);
            props.onQuery('');
          }}
          onChange={(e) => props.onQuery(e.target.value)}
        />
      </label>
      {open && props.query ? (
        <button type="button" aria-label="Clear" onMouseDown={keep} onClick={() => props.onQuery('')}>
          Clear
        </button>
      ) : null}
      {open ? (
        <div role="listbox" aria-label="Bases" style={{ maxHeight: 320, overflowY: 'auto' }}>
          {option('', 'Any base')}
          {shown.map((group) => (
            <div key={group.title} role="group" aria-label={group.title}>
              <small>{group.title}</small>
              {group.choices.map((choice) => option(choice.api, choice.label))}
            </div>
          ))}
          {shown.length === 0 ? <p>No base matches that.</p> : null}
        </div>
      ) : null}
      {props.note ? <p>{props.note}</p> : null}
      <label>
        <input
          type="checkbox"
          checked={props.installedOnly}
          onChange={(e) => props.onInstalledOnly(e.target.checked)}
        />
        Only installed models
      </label>
      {props.installedOnly && !props.installedBases ? <p>Looking through the models folder…</p> : null}
      {props.installedOnly && props.installedBases && !props.query && shown.length === 0 ? (
        <p>No installed model matches a CivitAI base.</p>
      ) : null}
    </div>
  );
}
