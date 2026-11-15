// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's portrait rail (desktop avatar_generation_panel.dart +
// portrait_section.dart + expressions_section.dart): the three sources, the
// no-engine banner, the portrait upload with its crop, extra uploads tagged as
// a look or an expression, the ZIP sprite pack, the portrait prompt and its
// veto card, and the expression pack's run. Vision QC is deliberately absent
// (maintainer ruling, 2026-11-15): the web runs the pack straight to import.

import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ApiError } from '../../api/client';
import { ImageCropModal } from '../ImageCropModal';
import {
  cancelPack,
  fetchPack,
  fetchPromptDefaults,
  importPack,
  savePromptDefaults,
  startPack,
  type PackStart,
  type PackView,
  type PromptRules,
} from '../models/studio/packApi';
import { PromptRulesEditor } from '../models/studio/PromptRulesEditor';
import { AvatarExpressions } from './AvatarExpressions';
import { AvatarTagDialog } from './AvatarTagDialog';
import {
  dataUrlToFile,
  generatePortrait,
  importExpressionZip,
  listAvatars,
  portraitUrl,
  studioReady,
  uploadExpression,
  uploadLook,
  uploadPortrait,
  type AvatarItem,
  type StudioReady,
} from './avatarRailApi';

type Source = 'upload' | 'generate' | 'none';

const messageOf = (err: unknown, fallback: string) =>
  err instanceof ApiError && err.message ? err.message : fallback;

export function AvatarRail({
  characterId: id,
  seed,
  description,
  onBusyChange,
}: {
  characterId: string;
  /** The Review's portrait prompt (GET /api/chargen/review). */
  seed: string;
  /** The card's description, the expression pack's direction. */
  description: string;
  onBusyChange?: (busy: boolean) => void;
}) {
  const navigate = useNavigate();
  const [ready, setReady] = useState<StudioReady | null>(null);
  const [source, setSource] = useState<Source>('upload');
  const [prompt, setPrompt] = useState(seed);
  const [preview, setPreview] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const [portraitVersion, setPortraitVersion] = useState(0);
  const [avatars, setAvatars] = useState<AvatarItem[]>([]);
  const [pendingPortrait, setPendingPortrait] = useState<File | null>(null);
  const [pendingExtra, setPendingExtra] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');
  const [packOn, setPackOn] = useState(false);
  const [full, setFull] = useState(false);
  const [rules, setRules] = useState<PromptRules | null>(null);
  const [editingRules, setEditingRules] = useState(false);
  const [pack, setPack] = useState<PackView | null>(null);
  const [packError, setPackError] = useState('');
  const [importing, setImporting] = useState(false);
  const portraitRef = useRef<HTMLInputElement>(null);
  const extraRef = useRef<HTMLInputElement>(null);
  const zipRef = useRef<HTMLInputElement>(null);
  const seeded = useRef(false);

  useEffect(() => {
    let alive = true;
    Promise.all([
      studioReady().catch(() => null),
      listAvatars(id).catch(() => ({ avatars: [] as AvatarItem[] })),
      fetchPack().catch(() => null),
    ]).then(([r, a, p]) => {
      if (!alive) return;
      setReady(r);
      setAvatars(Array.isArray(a?.avatars) ? a.avatars : []);
      setPack(p);
    });
    return () => {
      alive = false;
    };
  }, [id]);

  useEffect(() => {
    if (!seed || seeded.current) return;
    seeded.current = true;
    setPrompt(seed);
  }, [seed]);

  useEffect(() => {
    onBusyChange?.(busy || generating || importing || pack?.running === true);
  }, [busy, generating, importing, pack, onBusyChange]);

  // The pack runs on the host; the rail shows its progress and imports the
  // finished slots once, as the desktop's runner does with QC off.
  useEffect(() => {
    if (!pack?.running) return;
    const timer = window.setInterval(() => {
      fetchPack()
        .then(setPack)
        .catch(() => {});
    }, 1500);
    return () => window.clearInterval(timer);
  }, [pack?.running]);

  useEffect(() => {
    if (!pack || pack.running || !pack.canImport || pack.imported != null || importing) return;
    const keep = (pack.slots ?? [])
      .filter((s) => s.state === 'done' && s.keep)
      .map((s) => s.emotion);
    if (keep.length === 0) return;
    setImporting(true);
    importPack(keep)
      .then((view) => {
        setPack(view);
        setNote(`Imported ${keep.length} expression image${keep.length === 1 ? '' : 's'}.`);
        return listAvatars(id).then((a) => setAvatars(a.avatars));
      })
      .catch((err) => setPackError(messageOf(err, 'The pack could not be imported.')))
      .finally(() => setImporting(false));
  }, [pack, importing, id]);

  const engineReady = ready?.ready === true;

  const applyPortrait = async (blob: Blob) => {
    setBusy(true);
    setError('');
    try {
      await uploadPortrait(id, blob);
      setPortraitVersion((v) => v + 1);
      setPendingPortrait(null);
    } catch (err) {
      setError(messageOf(err, 'The portrait could not be saved.'));
    } finally {
      setBusy(false);
    }
  };

  const addExtra = async (label: string | null) => {
    const file = pendingExtra;
    if (!file) return;
    setBusy(true);
    setError('');
    try {
      const r = label ? await uploadExpression(id, file, label) : await uploadLook(id, file);
      setAvatars(Array.isArray(r?.avatars) ? r.avatars : []);
      setPortraitVersion((v) => v + 1); // a look may bootstrap a missing portrait
      setPendingExtra(null);
    } catch (err) {
      setError(messageOf(err, 'That image could not be added.'));
    } finally {
      setBusy(false);
    }
  };

  const addZip = async (file: File) => {
    setBusy(true);
    setError('');
    try {
      const r = await importExpressionZip(id, file);
      setAvatars(Array.isArray(r?.avatars) ? r.avatars : []);
      setNote(
        `Imported ${r.added} expression image${r.added === 1 ? '' : 's'}` +
          (r.unrecognized > 0 ? `; ${r.unrecognized} file${r.unrecognized === 1 ? '' : 's'} not recognised.` : '.'),
      );
    } catch (err) {
      setError(messageOf(err, 'That ZIP could not be imported.'));
    } finally {
      setBusy(false);
    }
  };

  const runPortrait = async () => {
    setGenerating(true);
    setError('');
    try {
      const r = await generatePortrait(prompt);
      setPreview(r.image);
    } catch (err) {
      setError(messageOf(err, 'The portrait could not be generated.'));
    } finally {
      setGenerating(false);
    }
  };

  const keepPreview = async () => {
    if (!preview) return;
    setBusy(true);
    setError('');
    try {
      await uploadPortrait(id, await dataUrlToFile(preview));
      setPreview(null);
      setPortraitVersion((v) => v + 1);
      if (packOn) await runPack();
    } catch (err) {
      setError(messageOf(err, 'The portrait could not be saved.'));
    } finally {
      setBusy(false);
    }
  };

  const runPack = async () => {
    setPackError('');
    setImporting(false);
    try {
      const body: PackStart = {
        characterId: id,
        set: full ? 'full' : 'starter',
        skipExisting: false,
        replaceExisting: false,
        denoise: 0.7,
        prompt: description || prompt,
        workspace: false,
        baseSource: 'currentPortrait',
      };
      if (rules) body.promptRules = rules;
      setPack(await startPack(body));
    } catch (err) {
      setPackError(messageOf(err, 'Could not start the pack.'));
    }
  };

  const openRules = async () => {
    if (!rules) {
      try {
        setRules(await fetchPromptDefaults());
      } catch (err) {
        setPackError(messageOf(err, 'Could not load prompt rules.'));
        return;
      }
    }
    setEditingRules(true);
  };

  const count = full ? 28 : 8;
  const cta =
    source === 'generate' && packOn
      ? `Generate 1 portrait · ${count} expressions`
      : source === 'generate'
        ? 'Generate 1 portrait'
        : packOn
          ? `Generate ${count} expressions`
          : null;

  const run = () => {
    if (source === 'generate') {
      void runPortrait();
      return;
    }
    void runPack();
  };

  return (
    <div className="cg-r-avatar">
      <h3 className="cg-r-rail-head">PORTRAIT — PICK A SOURCE</h3>
      <div className="cg-r-sources" role="group" aria-label="Portrait source">
        <button
          type="button"
          className={`cg-r-source${source === 'upload' ? ' active' : ''}`}
          aria-pressed={source === 'upload'}
          onClick={() => setSource('upload')}
        >
          ⇪ Upload my own
        </button>
        <button
          type="button"
          className={`cg-r-source${source === 'generate' ? ' active' : ''}`}
          aria-pressed={source === 'generate'}
          disabled={ready !== null && !engineReady}
          onClick={() => setSource('generate')}
        >
          ✨ Generate
        </button>
        <button
          type="button"
          className={`cg-r-source${source === 'none' ? ' active' : ''}`}
          aria-pressed={source === 'none'}
          onClick={() => setSource('none')}
        >
          ⊘ None for now
        </button>
      </div>

      {ready !== null && !engineReady && (
        <div className="cg-r-note">
          <span>
            Generate is unavailable — no image engine is set up. Configure one, or upload images
            instead.
          </span>
          <button type="button" className="cg-p-text-btn" onClick={() => navigate('/settings')}>
            Set up
          </button>
        </div>
      )}

      {source === 'upload' && (
        <div className="cg-r-uploads">
          <button
            type="button"
            className="cg-r-well cg-r-well-portrait"
            title="Upload the portrait"
            disabled={busy}
            onClick={() => portraitRef.current?.click()}
          >
            {portraitVersion > 0 ? (
              <img src={portraitUrl(id, portraitVersion)} alt="Portrait" />
            ) : (
              <span className="cg-r-well-icon">⇪</span>
            )}
          </button>
          {!packOn && (
            <button
              type="button"
              className="cg-r-well cg-r-well-add"
              title="Add another image"
              aria-label="Add another image"
              disabled={busy}
              onClick={() => extraRef.current?.click()}
            >
              ＋
            </button>
          )}
          <p className="cg-r-caption">
            First image is the portrait; add more as gallery looks, or tag one with an emotion to
            make it an expression image.
          </p>
        </div>
      )}

      {source === 'generate' && (
        <div className="cg-r-generate">
          <div className="cg-r-engine">
            {ready?.line || ready?.primary || 'Image engine'}
          </div>
          <label className="cg-field">
            <span className="cg-field-label">PORTRAIT PROMPT</span>
            <textarea
              rows={4}
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              aria-label="Portrait prompt"
            />
          </label>
          {preview ? (
            <div className="cg-r-preview">
              <img src={preview} alt="Generated portrait" />
              <div className="cg-r-preview-actions">
                <button type="button" className="ghost" onClick={() => void runPortrait()}>
                  Regenerate
                </button>
                <button type="button" className="primary" disabled={busy} onClick={() => void keepPreview()}>
                  Continue
                </button>
              </div>
            </div>
          ) : (
            <button
              type="button"
              className="primary cg-r-generate-btn"
              disabled={generating || !engineReady || !prompt.trim()}
              onClick={() => void runPortrait()}
            >
              {generating ? 'Generating…' : 'Generate portrait'}
            </button>
          )}
        </div>
      )}

      {source === 'none' && (
        <p className="cg-r-caption">
          No portrait for now — later, open Avatar Gallery and use Set portrait (or Add avatar + ★)
          on the home screen.
        </p>
      )}

      <AvatarExpressions
        packOn={packOn}
        onPackOnChange={setPackOn}
        full={full}
        onFullChange={setFull}
        pack={pack}
        packError={packError}
        note={note}
        error={error}
        engineReady={engineReady}
        busy={busy}
        generating={generating}
        cta={cta}
        onRun={run}
        onCancel={() => void cancelPack().then(setPack)}
        onPickZip={() => zipRef.current?.click()}
        onOpenRules={() => void openRules()}
        expressionCount={avatars.filter((a) => !a.isLook).length}
      />

      <input
        ref={portraitRef}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.currentTarget.value = '';
          if (file) setPendingPortrait(file);
        }}
      />
      <input
        ref={extraRef}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.currentTarget.value = '';
          if (file) setPendingExtra(file);
        }}
      />
      <input
        ref={zipRef}
        type="file"
        accept=".zip,application/zip"
        hidden
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.currentTarget.value = '';
          if (file) void addZip(file);
        }}
      />

      {pendingPortrait && (
        <ImageCropModal
          file={pendingPortrait}
          onCancel={() => setPendingPortrait(null)}
          onCropped={(blob) => void applyPortrait(blob)}
        />
      )}
      {pendingExtra && (
        <AvatarTagDialog
          busy={busy}
          onClose={() => setPendingExtra(null)}
          onConfirm={(label) => void addExtra(label)}
        />
      )}
      {editingRules && rules && (
        <PromptRulesEditor
          rules={rules}
          prompt={description || prompt}
          full={full}
          activePack={false}
          onUse={async (next) => {
            setRules(next);
            setEditingRules(false);
            await savePromptDefaults(next).catch(() => {});
          }}
          onClose={() => setEditingRules(false)}
        />
      )}
    </div>
  );
}
