// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useRef, useState } from 'react';
import { ApiError } from '../../../api/client';
import { writePrompt } from './deskApi';
import { PackPanel } from './PackPanel';
import type { Mode } from './types';

export type Subject = 'free' | 'char' | 'persona';

/** The picture an Edit works on, or a Create varies. */
export type Picture =
  | { kind: 'file'; name: string; dataUrl: string }
  | { kind: 'saved'; name: string; url: string };

const SUBJECTS: [Subject, string][] = [
  ['free', 'Freeform'],
  ['char', 'Character'],
  ['persona', 'Your persona'],
];

const MAX_PICTURE_BYTES = 12 * 1024 * 1024;

function readAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}

/** Subject, prompt, the picture, and the expression pack. */
export function DeskRail(props: {
  mode: Mode;
  subject: Subject;
  onSubject: (subject: Subject) => void;
  prompt: string;
  onPrompt: (value: string) => void;
  picture: Picture | null;
  onPicture: (picture: Picture | null) => void;
  /** The picture the last generate made, if it was saved. */
  lastSaved: { name: string; url: string } | null;
  onNote: (message: string) => void;
}) {
  const { mode, prompt } = props;
  const [writing, setWriting] = useState(false);
  const [pack, setPack] = useState(false);
  const chooser = useRef<HTMLInputElement>(null);

  const write = () => {
    setWriting(true);
    void writePrompt(props.subject, prompt)
      .then((r) => props.onPrompt(r.prompt))
      .catch((e: unknown) =>
        props.onNote(e instanceof ApiError ? e.message : 'Could not write a prompt.'),
      )
      .finally(() => setWriting(false));
  };

  const choose = (file: File | undefined) => {
    if (!file) return;
    if (file.size > MAX_PICTURE_BYTES) {
      props.onNote('That picture is too large. Pick one under 12 MB.');
      return;
    }
    if (!file.type.startsWith('image/')) {
      props.onNote('That is not a picture.');
      return;
    }
    void readAsDataUrl(file)
      .then((dataUrl) => props.onPicture({ kind: 'file', name: file.name, dataUrl }))
      .catch(() => props.onNote('Could not read that picture.'));
  };

  return (
    <div className="fp-desk-rail" data-region="rail">
      <div>Subject</div>
      {SUBJECTS.map(([id, label]) => (
        <button
          key={id}
          type="button"
          className="fp-pill"
          aria-pressed={props.subject === id}
          onClick={() => props.onSubject(id)}
        >
          {label}
        </button>
      ))}
      <div>
        <span>Prompt</span>
        <button type="button" disabled={writing} onClick={write}>
          {writing ? 'Writing…' : 'Write it for me'}
        </button>
      </div>
      <textarea
        aria-label="Prompt"
        rows={4}
        value={prompt}
        onChange={(e) => props.onPrompt(e.target.value)}
      />
      <p>
        {mode === 'edit'
          ? 'Edit sends an instruction with this picture.'
          : 'Start from a picture — optional. A reference here varies the Create model. It does not switch you to Edit.'}
      </p>
      <input
        ref={chooser}
        aria-label="Picture file"
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          choose(e.target.files?.[0]);
          e.target.value = '';
        }}
      />
      <button type="button" onClick={() => chooser.current?.click()}>
        Choose picture
      </button>
      {props.lastSaved ? (
        <button
          type="button"
          onClick={() =>
            props.onPicture({ kind: 'saved', name: props.lastSaved!.name, url: props.lastSaved!.url })
          }
        >
          Use the last picture I made
        </button>
      ) : null}
      {props.picture ? (
        <div>
          <img
            alt=""
            src={props.picture.kind === 'file' ? props.picture.dataUrl : props.picture.url}
            style={{ maxWidth: 96, maxHeight: 96, objectFit: 'contain' }}
          />
          <span>{props.picture.name}</span>
          <button type="button" onClick={() => props.onPicture(null)}>
            Remove picture
          </button>
        </div>
      ) : mode === 'edit' ? (
        <p>Pick a picture to edit.</p>
      ) : null}
      <button type="button" aria-expanded={pack} onClick={() => setPack((open) => !open)}>
        Expression pack
      </button>
      {pack ? (
        <PackPanel prompt={prompt} picture={props.picture} />
      ) : null}
    </div>
  );
}
