// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Lore & continuity (sketch T): the facts the story must keep straight (add,
// edit, retire, forget by hand), the lore behind it (bible entries and
// dropped-in files, with a search tester) and the story so far. Web twin of the
// desktop LoreSection.

import { useRef, useState, type ChangeEvent } from 'react';
import { useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { useStory } from '../hooks/useStory';
import { detachWorldCopy, forgetFactCopy, removeLoreCopy } from './story/confirmCopy';
import { isWorldLore, useStoryWorld, worldLine } from './story/setup/worldPick';
import { editFact, forgetFact, newFact, recordFact, retireFact, type FactFields } from './story/lore/continuity';
import { FactDialog, RetireDialog } from './story/lore/FactDialogs';
import { loreSubtitle } from './story/lore/loreShape';
import { FactsTab, LoreTab, SoFarTab } from './story/lore/LoreTabs';
import { SearchDialog } from './story/lore/SearchDialog';
import { Segmented } from './story/setup/primitives';
import { StudioLoading, StudioShell } from './story/StudioShell';
import { useConfirm } from './story/useConfirm';
import { useNotice } from './story/world/useNotice';

type Tab = 'continuity' | 'lore' | 'sofar';
type Open =
  | { kind: 'fact'; index: number | null }
  | { kind: 'retire'; index: number }
  | { kind: 'search' };

const TABS: Record<Tab, string> = { continuity: 'Continuity', lore: 'Lore', sofar: 'Story so far' };

export function StoryLorePage() {
  const { id = '' } = useParams();
  const { project: p, status, error, stop, save, reload } = useStory(id);
  const [tab, setTab] = useState<Tab>('continuity');
  const [open, setOpen] = useState<Open | null>(null);
  const [failure, setFailure] = useState('');
  const [notice, setNotice] = useNotice();
  const [worldBusy, setWorldBusy] = useState(false);
  const { ask, dialog } = useConfirm();
  const picker = useRef<HTMLInputElement | null>(null);
  const world = useStoryWorld(p?.world_id);

  if (!p) return <StudioLoading error={error} />;

  const facts = p.continuity ?? [];
  const placeNames = Object.fromEntries((world.summary?.places ?? []).map((pl) => [pl.id, pl.name]));
  const copied = p.lore.filter(isWorldLore).length;

  /** Refresh from world: the relay copies the book again and keeps story-grown lore. One write per tap. */
  const refreshWorld = async () => {
    if (worldBusy) return;
    setWorldBusy(true);
    try {
      const r = await api.post<{ ok: boolean; copied: number }>(`/api/stories/${id}/world/refresh`, {});
      if (r.ok) {
        reload();
        setNotice(`${r.copied} ${r.copied === 1 ? 'fact' : 'facts'} from the world, refreshed.`);
      } else {
        setFailure('The world is no longer in the library; nothing to refresh from.');
      }
    } catch (err) {
      setFailure(err instanceof ApiError ? err.message : 'The world could not be read.');
    } finally {
      setWorldBusy(false);
    }
  };

  const detachWorld = () => ask(detachWorldCopy(p.world_name ?? ''), () => {
    if (worldBusy) return;
    setWorldBusy(true);
    void save({ world_id: null, world_name: '' }).finally(() => setWorldBusy(false));
  });

  const addFiles = async (e: ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    e.target.value = '';
    if (files.length === 0) return;
    setFailure('');
    let added = 0;
    for (const f of files) {
      try {
        const r = await api.post<{ added: number }>(`/api/stories/${id}/lore`, { name: f.name, text: await f.text() });
        added += r.added;
      } catch (err) {
        setFailure(`${f.name}: ${err instanceof ApiError ? err.message : 'could not be added'}`);
      }
    }
    reload();
    setTab('lore');
    setNotice(`Added ${added} lore entr${added === 1 ? 'y' : 'ies'}.`);
  };

  const saveFact = (index: number | null, fields: FactFields) => {
    setOpen(null);
    void save({ continuity: index === null ? recordFact(facts, newFact(fields)) : editFact(facts, index, fields) });
  };

  return (
    <StudioShell id={id} project={p} section="lore" status={status} error={error} onStop={stop}>
      <div className="s-muted s-body" data-testid="lore-subtitle">{loreSubtitle(p)}</div>
      <div className="s-row">
        <Segmented testid="lore-tabs" options={TABS} selected={tab} onSelect={(v) => setTab(v as Tab)} />
        <button type="button" className="s-btn-quiet" data-testid="lore-add-fact" onClick={() => setOpen({ kind: 'fact', index: null })}>+ Add fact</button>
        <button type="button" className="s-btn-quiet" data-testid="lore-add-file" onClick={() => picker.current?.click()}>Add lore file</button>
        <input ref={picker} type="file" accept=".txt,.md,text/plain,text/markdown" multiple hidden data-testid="lore-file" onChange={(e) => { void addFiles(e); }} />
        <button type="button" className="s-btn-quiet" data-testid="lore-search" disabled={p.lore.length === 0}
          onClick={() => setOpen({ kind: 'search' })}>Test search</button>
      </div>
      {notice && <p className="s-muted s-small" role="status">{notice}</p>}
      {failure && <p className="s-error">{failure}</p>}

      {tab === 'continuity' && (
        <FactsTab p={p}
          onEdit={(index) => setOpen({ kind: 'fact', index })}
          onRetire={(index) => setOpen({ kind: 'retire', index })}
          onForget={(index) => ask(forgetFactCopy(facts[index].key), () => { void save({ continuity: forgetFact(facts, index) }); })} />
      )}
      {tab === 'lore' && p.world_id && (
        <section className="s-card raise" data-testid="lore-world-card">
          {/* Wraps so a phone puts the two buttons under the text instead of beside a four-word column. */}
          <div className="s-row" style={{ flexWrap: 'wrap', gap: 8 }}>
            <div className="s-col" style={{ gap: 2, flex: '1 1 260px', minWidth: 0 }}>
              <b data-testid="lore-world-line">{worldLine(p, world.summary, world.gone)}</b>
              <span className="s-muted s-small">
                {copied} {copied === 1 ? 'fact' : 'facts'} from this world · the world is read live; its facts were copied when the bible was built
              </span>
            </div>
            <button type="button" className="s-btn-quiet" data-testid="lore-world-refresh" disabled={worldBusy || world.gone}
              onClick={() => { void refreshWorld(); }}>↻ Refresh from world</button>
            <button type="button" className="s-btn-danger" data-testid="lore-world-detach" disabled={worldBusy} onClick={detachWorld}>Detach</button>
          </div>
        </section>
      )}
      {tab === 'lore' && (
        <LoreTab p={p} placeNames={placeNames}
          onRemove={(index) => ask(removeLoreCopy(p.lore[index].topic), () => { void save({ lore: p.lore.filter((_, i) => i !== index) }); })} />
      )}
      {tab === 'sofar' && <SoFarTab p={p} />}

      {open?.kind === 'fact' && (open.index === null || facts[open.index]) && (
        <FactDialog fact={open.index === null ? null : facts[open.index]} onCancel={() => setOpen(null)}
          onSave={(fields) => saveFact(open.index, fields)} />
      )}
      {open?.kind === 'retire' && facts[open.index] && (
        <RetireDialog p={p} fact={facts[open.index]} onCancel={() => setOpen(null)}
          onPick={(sceneId) => { const index = open.index; setOpen(null); void save({ continuity: retireFact(facts, index, sceneId) }); }} />
      )}
      {open?.kind === 'search' && <SearchDialog id={id} onClose={() => setOpen(null)} />}
      {dialog}
    </StudioShell>
  );
}
