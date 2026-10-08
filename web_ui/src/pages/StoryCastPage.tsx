// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Cast (sketch R): one dossier per character. Add, edit and remove are here, so
// the New Story's Cast step and this screen are the same list. Two columns on
// wide screens, one under 900px. Web twin of the desktop CastSection.

import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { useStory } from '../hooks/useStory';
import { CastCard } from './story/cast/CastCard';
import { InterviewDialog, VoiceDialog } from './story/cast/CastDialogs';
import { castFields, removeMember, saveMember, setVoice } from './story/cast/castEdits';
import { useCastData } from './story/cast/useCastData';
import { interviewAgainCopy, removeFromCastCopy } from './story/confirmCopy';
import { FieldsDialog } from './story/FieldsDialog';
import { StudioLoading, StudioShell } from './story/StudioShell';
import { useConfirm } from './story/useConfirm';
import { EmptyState } from './story/world/EmptyState';

type Open =
  | { kind: 'edit'; index: number | null }
  | { kind: 'read'; index: number }
  | { kind: 'voice'; index: number };

export function StoryCastPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, run, stop, save, reload } = useStory(id);
  const { voices, art, canPaint } = useCastData();
  const [open, setOpen] = useState<Open | null>(null);
  const [painting, setPainting] = useState<ReadonlySet<string>>(new Set());
  // When each portrait was last painted: the address changes, so the browser fetches the new one.
  const [painted, setPainted] = useState<Record<string, number>>({});
  const [failure, setFailure] = useState('');
  const { ask, dialog } = useConfirm();

  if (!p) return <StudioLoading error={error} />;

  const running = status?.running ?? false;
  const studio = p.engine_mode === 'studio';
  const count = p.cast.length;

  const interview = (index: number) => {
    const name = p.cast[index].name;
    if (p.cast[index].interview) ask(interviewAgainCopy(name), () => { void run('interview', { name }); });
    else void run('interview', { name });
  };
  const paint = async (name: string) => {
    setFailure('');
    setPainting((prev) => new Set(prev).add(name));
    try {
      await api.post(`/api/stories/${id}/portrait`, { name });
      setPainted((prev) => ({ ...prev, [name]: Date.now() }));
      reload();
    } catch (e) {
      setFailure(e instanceof ApiError ? e.message : 'The portrait could not be painted');
    } finally {
      setPainting((prev) => {
        const next = new Set(prev);
        next.delete(name);
        return next;
      });
    }
  };
  const portraitOf = (name: string, hasOwn: boolean): string | undefined => {
    if (!hasOwn) return art[name];
    const stamp = painted[name];
    return `/api/stories/${id}/portrait?name=${encodeURIComponent(name)}${stamp ? `&v=${stamp}` : ''}`;
  };

  const target = open && open.kind !== 'edit' ? p.cast[open.index] : null;
  const editing = open?.kind === 'edit' ? open : null;

  return (
    <StudioShell id={id} project={p} section="cast" status={status} error={error} onStop={stop}>
      <div className="s-row nowrap">
        <span className="s-grow s-muted s-body">{count} character{count === 1 ? '' : 's'}</span>
        <button type="button" className="s-btn-quiet" data-testid="cast-add" onClick={() => setOpen({ kind: 'edit', index: null })}>
          + Add character
        </button>
      </div>
      {failure && <p className="s-error">{failure}</p>}

      {count === 0 ? (
        <EmptyState title="No cast yet" detail="The story bible creates it, or add someone yourself." testid="cast-empty" />
      ) : (
        <div className="s-over-cols">
          {p.cast.map((m, i) => (
            <CastCard key={`${m.name}-${i}`} member={m} studio={studio} running={running} canPaint={canPaint} voices={voices}
              painting={painting.has(m.name)} portrait={portraitOf(m.name, !!m.portrait)}
              actions={{
                interview: () => interview(i),
                paint: () => { void paint(m.name); },
                edit: () => setOpen({ kind: 'edit', index: i }),
                remove: () => ask(removeFromCastCopy(m.name), () => { void save(removeMember(p, i)); }),
                readInterview: () => setOpen({ kind: 'read', index: i }),
                pickVoice: () => setOpen({ kind: 'voice', index: i }),
              }} />
          ))}
        </div>
      )}

      {editing && (
        <FieldsDialog wide title={editing.index === null ? 'Add character' : `Edit ${p.cast[editing.index].name}`}
          confirmLabel={editing.index === null ? 'Add' : 'Save'} required="name"
          onCancel={() => setOpen(null)}
          onSubmit={(values) => {
            setOpen(null);
            void save(saveMember(p, editing.index, {
              name: values.name, role: values.role, description: values.description, desire: values.desire, flaw: values.flaw,
            }));
          }}
          fields={(() => {
            const f = castFields(editing.index === null ? null : p.cast[editing.index]);
            return [
              { key: 'name', hint: 'Name', value: f.name, testid: 'cast-edit-name' },
              { key: 'role', hint: 'Role (Protagonist, Mentor…)', value: f.role, testid: 'cast-edit-role' },
              { key: 'description', hint: 'Who they are', value: f.description, multiline: true, rows: 3, testid: 'cast-edit-description' },
              { key: 'desire', hint: 'What they want', value: f.desire, testid: 'cast-edit-desire' },
              { key: 'flaw', hint: 'Their flaw', value: f.flaw, testid: 'cast-edit-flaw' },
            ];
          })()} />
      )}
      {open?.kind === 'read' && target && <InterviewDialog member={target} onClose={() => setOpen(null)} />}
      {open?.kind === 'voice' && target && (
        <VoiceDialog current={target.voice_model ?? ''} voices={voices} onCancel={() => setOpen(null)}
          onPick={(voiceId) => { const index = open.index; setOpen(null); void save(setVoice(p, index, voiceId)); }} />
      )}
      {dialog}
    </StudioShell>
  );
}
