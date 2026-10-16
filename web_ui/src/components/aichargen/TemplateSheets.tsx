// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's template dialogs (docs/design/creator-ui-spec.md: Dialog and
// Save-as-template dialog): Save, Rename, the Delete confirm and the
// built-ins picker, in one shell that is a 520px dialog on wide screens and
// a bottom sheet with a handle on the phone.

import { useEffect, useId, useRef, useState, type FormEvent, type KeyboardEvent, type ReactNode } from 'react';
import { ApiError } from '../../api/client';
import { useLayout } from '../../hooks/useBreakpoint';
import type { ChargenForm } from './chargenForm';
import { BookmarkIcon, TrashIcon } from './creatorIcons';
import { formToTemplate } from './templateForm';
import {
  REPLACES_CAPTION,
  TAKEN_PROBLEM,
  builtInLine,
  deleteTemplate,
  renameTemplate,
  saveTemplate,
  templateNameProblem,
  templateSlug,
  type CreatorTemplate,
  type TemplateStart,
} from './templatesApi';

const SAVE_BODY =
  "Keeps every box on this form the way it is now, in every step. Not the character's name. It shows on the desktop too.";

/** What a failed call says: the relay's own words, else a plain line (never
 *  the browser's "Failed to fetch"). */
function failure(e: unknown, fallback: string): string {
  console.warn('[creator] a template call failed', e);
  return e instanceof ApiError && e.message ? e.message : fallback;
}

export function CreatorSheet({
  title,
  icon,
  danger = false,
  busy = false,
  onClose,
  confirm,
  children,
}: {
  title: string;
  icon?: ReactNode;
  danger?: boolean;
  busy?: boolean;
  onClose: () => void;
  /** The confirm button; Cancel is always there. */
  confirm?: ReactNode;
  children?: ReactNode;
}) {
  const { isPhone } = useLayout();
  const titleId = useId();
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    // The name field takes the focus; else the dialog, so Escape reaches it.
    const el = box.current;
    (el?.querySelector<HTMLElement>('input') ?? el)?.focus();
  }, []);
  const onKey = (e: KeyboardEvent) => {
    if (e.key !== 'Escape' || busy) return;
    e.stopPropagation();
    onClose();
  };
  const cancel = (
    <button type="button" className="cg-sheet-cancel" disabled={busy} onClick={onClose}>
      Cancel
    </button>
  );
  return (
    <div
      className="cg-sheet-scrim"
      onMouseDown={(e) => e.target === e.currentTarget && !busy && onClose()}
    >
      <div
        ref={box}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className={`cg-sheet${isPhone ? ' phone' : ''}${danger ? ' danger' : ''}`}
        onKeyDown={onKey}
      >
        {isPhone && <div className="cg-sheet-handle" aria-hidden />}
        <div className="cg-sheet-title">
          {icon}
          <h2 id={titleId}>{title}</h2>
        </div>
        {children}
        <div className="cg-sheet-actions">
          {isPhone ? (
            <>
              {confirm}
              {cancel}
            </>
          ) : (
            <>
              {cancel}
              {confirm}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/** Save and Rename: the name field, its problem (`bad`) or caption
 *  (amber), and a confirm that a problem disables. An empty field says
 *  nothing until it is edited or confirmed. */
function NameSheet({
  title,
  body,
  initial,
  confirmLabel,
  problemOf,
  captionOf,
  onSubmit,
  onClose,
}: {
  title: string;
  body?: string;
  initial: string;
  confirmLabel: string;
  problemOf: (name: string) => string | null;
  captionOf?: (name: string) => string | null;
  onSubmit: (name: string) => Promise<void>;
  onClose: () => void;
}) {
  const fieldId = useId();
  const [name, setName] = useState(initial);
  const [touched, setTouched] = useState(initial !== '');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  // Set in the handler, so a second tap before the render cannot pass.
  const busyRef = useRef(false);
  const problem = problemOf(name);
  const shown = touched ? problem : null;
  const caption = problem ? null : (captionOf?.(name) ?? null);

  const submit = async (e?: FormEvent) => {
    e?.preventDefault();
    if (busyRef.current) return;
    if (problem) {
      setTouched(true);
      return;
    }
    busyRef.current = true;
    setBusy(true);
    setError('');
    try {
      await onSubmit(name.trim());
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };

  return (
    <CreatorSheet
      title={title}
      icon={<BookmarkIcon size={22} />}
      busy={busy}
      onClose={onClose}
      confirm={
        <button type="button" className="cg-sheet-confirm" disabled={busy || shown !== null} onClick={() => void submit()}>
          {confirmLabel}
        </button>
      }
    >
      {body && <p className="cg-sheet-body">{body}</p>}
      {/* A form so Enter in the field confirms. */}
      <form className="cg-sheet-field" onSubmit={(e) => void submit(e)}>
        <label htmlFor={fieldId}>TEMPLATE NAME</label>
        <input
          id={fieldId}
          type="text"
          value={name}
          placeholder="e.g. Harbor town, slow burn"
          disabled={busy}
          onChange={(e) => {
            setName(e.target.value);
            setTouched(true);
            setError('');
          }}
        />
        {shown && <div className="cg-sheet-problem">{shown}</div>}
        {!shown && caption && <div className="cg-sheet-caption">{caption}</div>}
        {error && <div className="cg-sheet-problem">{error}</div>}
      </form>
    </CreatorSheet>
  );
}

const builtInsOf = (templates: CreatorTemplate[]) => templates.filter((t) => t.builtIn);
const startOf = (t: CreatorTemplate): TemplateStart => ({ slug: t.slug, name: t.name, builtIn: t.builtIn });

/** Save as a template: prefilled with the started-from name; a name that
 *  exists is replaced, a built-in's is refused. */
export function SaveTemplateSheet({
  form,
  templates,
  startedFrom,
  onSaved,
  onClose,
}: {
  form: ChargenForm;
  templates: CreatorTemplate[];
  startedFrom: TemplateStart | null;
  onSaved: (to: TemplateStart) => void;
  onClose: () => void;
}) {
  const builtIns = builtInsOf(templates);
  return (
    <NameSheet
      title="Save as a template"
      body={SAVE_BODY}
      initial={startedFrom?.name ?? ''}
      confirmLabel="Save template"
      problemOf={(name) => templateNameProblem(name, builtIns)}
      captionOf={(name) =>
        templates.some((t) => !t.builtIn && t.slug === templateSlug(name)) ? REPLACES_CAPTION : null
      }
      onSubmit={async (name) => {
        let saved: CreatorTemplate | null;
        try {
          ({ template: saved } = await saveTemplate(name, formToTemplate(form), startedFrom?.slug));
        } catch (e) {
          throw new Error(failure(e, 'The template could not be saved. Check the connection, then try again.'));
        }
        onSaved(saved ? startOf(saved) : { slug: templateSlug(name), name, builtIn: false });
      }}
      onClose={onClose}
    />
  );
}

/** Rename: the same field; a name another template has is refused. */
export function RenameTemplateSheet({
  template,
  templates,
  onRenamed,
  onClose,
}: {
  template: CreatorTemplate;
  templates: CreatorTemplate[];
  onRenamed: (to: TemplateStart) => void;
  onClose: () => void;
}) {
  const builtIns = builtInsOf(templates);
  const taken = (name: string) =>
    templates.some((t) => !t.builtIn && t.slug !== template.slug && t.slug === templateSlug(name));
  return (
    <NameSheet
      title="Rename template"
      initial={template.name}
      confirmLabel="Rename"
      problemOf={(name) => templateNameProblem(name, builtIns) ?? (taken(name) ? TAKEN_PROBLEM : null)}
      onSubmit={async (name) => {
        if (name === template.name) return onClose();
        let renamed: CreatorTemplate | null;
        try {
          renamed = await renameTemplate(template.slug, name);
        } catch (e) {
          const takenThere = e instanceof ApiError && e.status === 409 && e.payload.reason === 'taken';
          throw new Error(
            takenThere ? TAKEN_PROBLEM : failure(e, 'The template could not be renamed. Check the connection, then try again.'),
          );
        }
        onRenamed(renamed ? startOf(renamed) : { slug: templateSlug(name), name, builtIn: false });
      }}
      onClose={onClose}
    />
  );
}

/** Delete, confirmed in the dialog's destructive form. */
export function DeleteTemplateSheet({
  template,
  onDeleted,
  onClose,
}: {
  template: CreatorTemplate;
  onDeleted: () => void;
  onClose: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [error, setError] = useState('');
  const remove = async () => {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError('');
    try {
      await deleteTemplate(template.slug);
      onDeleted();
    } catch (e) {
      setError(failure(e, 'The template could not be deleted. Check the connection, then try again.'));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  return (
    <CreatorSheet
      title="Delete this template?"
      icon={<TrashIcon />}
      danger
      busy={busy}
      onClose={onClose}
      confirm={
        <button type="button" className="cg-sheet-confirm danger" disabled={busy} onClick={() => void remove()}>
          Delete
        </button>
      }
    >
      <p className="cg-sheet-body">{template.name}</p>
      {error && <div className="cg-sheet-problem">{error}</div>}
    </CreatorSheet>
  );
}

/** The fifteen archetypes, from All 15 built in. */
export function BuiltInsSheet({
  builtIns,
  onPick,
  onClose,
}: {
  builtIns: CreatorTemplate[];
  onPick: (t: CreatorTemplate) => void;
  onClose: () => void;
}) {
  const { wide } = useLayout();
  return (
    <CreatorSheet title="Built-in templates" icon={<BookmarkIcon size={22} />} onClose={onClose}>
      <div className="cg-sheet-list">
        {builtIns.map((t) => (
          <button key={t.slug} type="button" className="cg-sheet-row" onClick={() => onPick(t)}>
            <span className="cg-sheet-row-name">{t.name}</span>
            <span className="cg-sheet-row-line">{builtInLine(t, wide)}</span>
          </button>
        ))}
      </div>
    </CreatorSheet>
  );
}
