// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef } from 'react';
import type { Picture } from './DeskRail';

export interface PackDraftProps {
  description: string;
  onDescription: (value: string) => void;
  picture: Picture | null;
  onPicture: (value: Picture | null) => void;
  portrait: string | null;
  portraitLoading: boolean;
  characterName: string;
  characterId?: string;
  lastSaved?: { name: string; url: string } | null;
  frozen: boolean;
  onProblem: (message: string) => void;
  onReloadPortrait?: () => void;
  onPictureLoading?: (loading: boolean) => void;
  edit?: boolean;
  onCraft?: () => void;
  crafting?: boolean;
}

export function PackDraft(props: PackDraftProps) {
  const chooser = useRef<HTMLInputElement>(null);
  const readerRef = useRef<FileReader | null>(null);
  const sequence = useRef(0);
  const frozen = useRef(props.frozen);
  const target = useRef(props.characterId);
  frozen.current = props.frozen;
  target.current = props.characterId;
  const onPictureLoading = props.onPictureLoading;
  useEffect(() => {
    const tickets = sequence;
    const readers = readerRef;
    tickets.current++;
    readers.current?.abort();
    readers.current = null;
    onPictureLoading?.(false);
    return () => {
      tickets.current++;
      readers.current?.abort();
      readers.current = null;
    };
  }, [props.frozen, props.characterId, onPictureLoading]);
  const upload = (file?: File) => {
    if (!file || props.frozen) return;
    if (!file.type.startsWith('image/') || file.size > 12 * 1024 * 1024) {
      props.onProblem('Choose a picture under 12 MB.');
      return;
    }
    readerRef.current?.abort();
    const ticket = ++sequence.current;
    const characterId = props.characterId;
    const reader = new FileReader();
    readerRef.current = reader;
    props.onPictureLoading?.(true);
    const current = () => ticket === sequence.current && !frozen.current && target.current === characterId;
    const finished = () => {
      if (ticket !== sequence.current) return;
      readerRef.current = null;
      props.onPictureLoading?.(false);
    };
    reader.onload = () => {
      if (current()) props.onPicture({ kind: 'file', name: file.name, dataUrl: String(reader.result) });
      finished();
    };
    reader.onerror = () => { if (current()) props.onProblem('Could not read that picture.'); finished(); };
    reader.onabort = finished;
    reader.readAsDataURL(file);
  };
  const source = props.picture?.kind === 'file' ? props.picture.dataUrl
    : props.picture?.kind === 'saved' ? props.picture.url : props.portrait;
  return (
    <fieldset disabled={props.frozen} className="fp-pack-draft">
      <legend>Pack prompt and source</legend>
      {props.edit ? <p>Each expression supplies its own edit instruction. No base prompt is needed.</p> : <>
      <label>Image prompt
        <textarea aria-label="Image prompt" rows={4} value={props.description}
          onChange={(e) => props.onDescription(e.target.value)} />
      </label>
      <button type="button" disabled={props.crafting || !props.characterId} onClick={props.onCraft}>
        {props.crafting ? 'Writing prompt…' : 'Write it for me'}
      </button>
      <p>Leave blank to prepare an image prompt automatically when starting.</p>
      </>}
      <p>{props.picture ? `Source: ${props.picture.name}`
        : `Source: ${props.characterName || 'selected character'} · character portrait`}</p>
      {source ? <img src={source} alt="Expression pack source portrait" width={112} height={112} />
        : <p>{props.portraitLoading ? 'Loading the current portrait…' : 'This character has no portrait. Choose a picture.'}</p>}
      <input type="file" accept="image/*" hidden ref={chooser} aria-label="Pack picture file"
        onChange={(e) => { upload(e.target.files?.[0]); e.target.value = ''; }} />
      <button type="button" onClick={() => chooser.current?.click()}>Choose pack picture</button>
      {props.lastSaved ? <button type="button" onClick={() => { sequence.current++; readerRef.current?.abort(); readerRef.current = null; props.onPictureLoading?.(false); props.onPicture({ kind: 'saved', ...props.lastSaved! }); }}>
        Use last Studio picture for pack
      </button> : null}
      <button type="button" onClick={() => {
        sequence.current++;
        readerRef.current?.abort();
        props.onPictureLoading?.(false);
        props.onPicture(null);
        props.onReloadPortrait?.();
      }}>{props.picture ? 'Use character portrait' : 'Reload character portrait'}</button>
      {props.frozen ? <p>Target, prompt, and source are fixed for this pack. Reset pack clears its results and unlocks these fields. Use Start pack to generate again.</p> : null}
    </fieldset>
  );
}
