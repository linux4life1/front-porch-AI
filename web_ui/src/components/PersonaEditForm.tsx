// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The persona create / edit form: the web twin of the desktop's
// PersonaEditForm (lib/ui/pages/user_persona/persona_edit_form.dart). Same
// fields in the same order with the same labels and hints: Title, Name,
// Birthday, Persona Text, then Cancel / Save Persona. The manager shows it
// IN PLACE OF the persona list, as the desktop's page does, so the form is
// always where the user is looking — not under a grid of thirty cards.

export interface PersonaDraft {
  id: string | null;
  title: string;
  name: string;
  persona: string;
  birthday: string;
}

export function PersonaEditForm({
  draft,
  busy,
  onChange,
  onCancel,
  onSave,
}: {
  draft: PersonaDraft;
  busy: boolean;
  onChange: (d: PersonaDraft) => void;
  onCancel: () => void;
  onSave: () => void;
}) {
  return (
    <div className="persona-edit">
      <label>
        Title
        <input
          value={draft.title}
          placeholder="Label to distinguish this persona (optional)"
          onChange={(e) => onChange({ ...draft, title: e.target.value })}
        />
      </label>
      <label>
        Name
        <input
          value={draft.name}
          placeholder="Name sent to the AI"
          onChange={(e) => onChange({ ...draft, name: e.target.value })}
        />
      </label>
      <label>
        Birthday
        <input
          type="date"
          value={draft.birthday}
          onChange={(e) => {
            const raw = e.target.value;
            if (/^\d{4}-02-29$/.test(raw)) return;
            onChange({ ...draft, birthday: raw });
          }}
        />
        <span className="small muted">
          The story calendar uses this so they know how old you are and when your birthday is.
          February 29 is not allowed.
        </span>
      </label>
      <label>
        Persona Text (injected into AI context)
        <textarea
          rows={6}
          value={draft.persona}
          onChange={(e) => onChange({ ...draft, persona: e.target.value })}
          placeholder="Detailed persona info the AI will know about you — appearance, traits, background, preferences..."
        />
        <span className="small muted">
          This text is sent to the AI in every conversation. Import from SillyTavern or Backyard AI
          auto-populates this.
        </span>
      </label>
      <div className="tool-row persona-edit-actions">
        <button onClick={onCancel}>Cancel</button>
        <button className="primary" disabled={busy || !draft.name.trim()} onClick={onSave}>
          {busy ? 'Saving…' : 'Save Persona'}
        </button>
      </div>
    </div>
  );
}
