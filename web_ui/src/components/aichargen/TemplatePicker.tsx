// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Mode step's Start from a template (docs/design/creator-ui-spec.md,
// Template picker card): your templates newest first, then the two featured
// built-ins, then the tile for all of them ("All 15 built in"). Each of
// yours has a ⋯ menu (Load, Rename, Delete); a file that cannot be read
// offers only Delete. Wide: a card whose tiles wrap; the phone: a heading
// and a row that scrolls sideways.

import { useState, type MouseEvent } from 'react';
import { useLayout } from '../../hooks/useBreakpoint';
import { CardMenu, type MenuState } from '../library/CardMenu';
import { BookmarkIcon, ChevronIcon, MoreIcon } from './creatorIcons';
import { BuiltInsSheet, DeleteTemplateSheet, RenameTemplateSheet } from './TemplateSheets';
import {
  builtInLabel,
  builtInLine,
  savedLabel,
  summaryLine,
  type CreatorTemplate,
  type TemplateStart,
} from './templatesApi';

/** Built-ins shown as tiles before the All tile (the relay puts Tsundere
 *  and Kuudere first). */
const FEATURED = 2;
const MENU_WIDTH = 150;

type Sheet = { kind: 'rename' | 'delete'; t: CreatorTemplate } | { kind: 'builtIns' } | null;

export function TemplatePicker({
  templates,
  error,
  onRetry,
  selected,
  onLoad,
  onRenamed,
  onDeleted,
}: {
  templates: CreatorTemplate[] | null;
  error: string;
  onRetry: () => void;
  /** The slug the form was loaded from. */
  selected: string | null;
  onLoad: (t: CreatorTemplate) => void;
  onRenamed: (from: string, to: TemplateStart) => void;
  onDeleted: (slug: string) => void;
}) {
  const { wide } = useLayout();
  const [menu, setMenu] = useState<(MenuState & { slug: string }) | null>(null);
  const [sheet, setSheet] = useState<Sheet>(null);
  const all = templates ?? [];
  const mine = all.filter((t) => !t.builtIn);
  const builtIns = all.filter((t) => t.builtIn);
  const rest = builtIns.slice(FEATURED, FEATURED + 3).map((t) => t.name);

  const openMenu = (e: MouseEvent<HTMLButtonElement>, t: CreatorTemplate) => {
    const r = e.currentTarget.getBoundingClientRect();
    const items = [
      ...(t.broken
        ? []
        : [
            { label: 'Load', onClick: () => onLoad(t) },
            { label: 'Rename', onClick: () => setSheet({ kind: 'rename', t }) },
          ]),
      { label: 'Delete', danger: true, onClick: () => setSheet({ kind: 'delete', t }) },
    ];
    setMenu({ x: r.right + 10 - MENU_WIDTH, y: r.bottom, items, slug: t.slug });
  };

  const tileClass = (t: CreatorTemplate) => `cg-tpl-tile${selected === t.slug ? ' on' : ''}`;

  return (
    <section className="cg-tpl" aria-labelledby="cg-tpl-title" data-testid="template-picker">
      <div className="cg-tpl-head">
        <BookmarkIcon size={20} />
        <h3 id="cg-tpl-title">Start from a template</h3>
        {wide && (
          <span className="cg-tpl-sub">
            Every box filled the way you saved it. Pick one, or choose a mode below to start blank.
          </span>
        )}
      </div>

      {error && (
        <p className="cg-tpl-error">
          {error}{' '}
          <button type="button" className="cg-tpl-retry" onClick={onRetry}>
            Try again
          </button>
        </p>
      )}
      {templates === null ? (
        !error && <p className="cg-tpl-loading">Loading templates…</p>
      ) : (
        <div className="cg-tpl-tiles">
          {mine.map((t) => (
            <div key={t.slug} className={tileClass(t)} data-testid="template-tile">
              <div className="cg-tpl-top">
                {t.broken ? (
                  <span className="cg-tpl-name">{t.name}</span>
                ) : (
                  <button type="button" className="cg-tpl-name" onClick={() => onLoad(t)}>
                    {t.name}
                  </button>
                )}
                <button
                  type="button"
                  className={`cg-tpl-more${menu?.slug === t.slug ? ' on' : ''}`}
                  aria-label={`More for ${t.name}`}
                  aria-haspopup="menu"
                  aria-expanded={menu?.slug === t.slug}
                  onClick={(e) => openMenu(e, t)}
                >
                  <MoreIcon />
                </button>
              </div>
              {t.broken ? (
                <div className="cg-tpl-broken">This file can't be read</div>
              ) : (
                <>
                  <div className="cg-tpl-line">{summaryLine(t.summary, wide)}</div>
                  {t.savedAt && <div className="cg-tpl-saved">{savedLabel(t.savedAt)}</div>}
                </>
              )}
            </div>
          ))}
          {builtIns.slice(0, FEATURED).map((t) => (
            <div key={t.slug} className={tileClass(t)} data-testid="template-tile">
              <button type="button" className="cg-tpl-name" onClick={() => onLoad(t)}>
                {t.name}
              </button>
              <div className="cg-tpl-line">{builtInLine(t, wide)}</div>
              <div>
                <span className="cg-tpl-pill">Built in</span>
              </div>
            </div>
          ))}
          {builtIns.length > 0 && (
            <div className="cg-tpl-tile cg-tpl-all" data-testid="template-tile">
              <button type="button" className="cg-tpl-all-btn" onClick={() => setSheet({ kind: 'builtIns' })}>
                {builtInLabel(builtIns.length)}
                {wide && <ChevronIcon open={false} />}
              </button>
              {wide && rest.length > 0 && <div className="cg-tpl-line">{rest.join(', ')} and the rest</div>}
            </div>
          )}
        </div>
      )}

      {menu && <CardMenu menu={menu} width={MENU_WIDTH} onClose={() => setMenu(null)} />}
      {sheet?.kind === 'rename' && (
        <RenameTemplateSheet
          template={sheet.t}
          templates={all}
          onRenamed={(to) => {
            setSheet(null);
            onRenamed(sheet.t.slug, to);
          }}
          onClose={() => setSheet(null)}
        />
      )}
      {sheet?.kind === 'delete' && (
        <DeleteTemplateSheet
          template={sheet.t}
          onDeleted={() => {
            setSheet(null);
            onDeleted(sheet.t.slug);
          }}
          onClose={() => setSheet(null)}
        />
      )}
      {sheet?.kind === 'builtIns' && (
        <BuiltInsSheet
          builtIns={builtIns}
          onPick={(t) => {
            setSheet(null);
            onLoad(t);
          }}
          onClose={() => setSheet(null)}
        />
      )}
    </section>
  );
}
