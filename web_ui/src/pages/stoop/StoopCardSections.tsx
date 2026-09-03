// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Solo / group / world definition bodies for the Stoop card page.
// Desktop parity: group overview + member carousel, world climate/lore.
// Discussion lives in StoopDiscussion (live hub, same as desktop).

import { useState } from 'react';
import {
  type InventoryRecord,
  inventoryToChips,
} from '../../components/realism/realismTypes';
import {
  stoopCardKind,
  stoopGreetings,
  stoopGroupTurnLabel,
  stoopLoreEntries,
  stoopMembers,
  stoopWorldClimate,
  stoopWorldClimateEnabled,
  stoopWorldTraits,
  type CardMap,
} from '../../stoop/stoopCardBody';
import type { StoopCardDetail } from '../../stoop/stoopTypes';

const SOLO_SECTIONS: { key: string; label: string }[] = [
  { key: 'description', label: 'Description' },
  { key: 'personality', label: 'Personality' },
  { key: 'scenario', label: 'Scenario' },
];

function textOf(card: CardMap, key: string): string {
  const v = card[key];
  return typeof v === 'string' ? v.trim() : '';
}

function realismBlock(card: CardMap): CardMap | undefined {
  const ext = card.extensions as CardMap | undefined;
  const fp = ext?.front_porch as CardMap | undefined;
  return fp?.realism_engine as CardMap | undefined;
}

function phrases(card: CardMap, key: string): string[] {
  const raw = realismBlock(card)?.[key];
  if (!Array.isArray(raw)) return [];
  return raw.filter((a): a is string => typeof a === 'string' && a.trim() !== '').map((a) => a.trim());
}

function Section({ title, body }: { title: string; body: string }) {
  if (!body.trim()) return null;
  return (
    <section className="card stoop-section">
      <h4>{title}</h4>
      <p className="stoop-pre">{body}</p>
    </section>
  );
}

function PhraseList({ title, items, mark }: { title: string; items: string[]; mark: string }) {
  if (items.length === 0) return null;
  return (
    <section className="card stoop-section">
      <h4>{title} ({items.length})</h4>
      <ul className="stoop-ambitions">
        {items.map((a, i) => (
          <li key={i}>{mark} {a}</li>
        ))}
      </ul>
    </section>
  );
}

function IdentityExtras({ card }: { card: CardMap }) {
  const ambitions = phrases(card, 'ambitions');
  const likes = phrases(card, 'likes');
  const dislikes = phrases(card, 'dislikes');
  const inventoryRaw = realismBlock(card)?.inventory;
  const wardrobe =
    inventoryRaw && typeof inventoryRaw === 'object' && !Array.isArray(inventoryRaw)
      ? inventoryToChips(inventoryRaw as InventoryRecord)
      : { worn: [] as string[], carrying: [] as string[] };
  return (
    <>
      <PhraseList title="Ambitions" items={ambitions} mark="🧭" />
      {(likes.length > 0 || dislikes.length > 0) && (
        <section className="card stoop-section">
          <h4>Likes &amp; Dislikes ({likes.length + dislikes.length})</h4>
          {likes.length > 0 && (
            <>
              <h5 className="stoop-sublabel">Drawn to</h5>
              <ul className="stoop-ambitions">
                {likes.map((a, i) => (
                  <li key={i}>♥ {a}</li>
                ))}
              </ul>
            </>
          )}
          {dislikes.length > 0 && (
            <>
              <h5 className="stoop-sublabel">Put off by</h5>
              <ul className="stoop-ambitions">
                {dislikes.map((a, i) => (
                  <li key={i}>✕ {a}</li>
                ))}
              </ul>
            </>
          )}
        </section>
      )}
      {(wardrobe.worn.length > 0 || wardrobe.carrying.length > 0) && (
        <section className="card stoop-section">
          <h4>Pockets &amp; Wardrobe ({wardrobe.worn.length + wardrobe.carrying.length})</h4>
          {wardrobe.worn.length > 0 && (
            <>
              <h5 className="stoop-sublabel">Wearing</h5>
              <ul className="stoop-ambitions">
                {wardrobe.worn.map((a, i) => (
                  <li key={i}>🧥 {a}</li>
                ))}
              </ul>
            </>
          )}
          {wardrobe.carrying.length > 0 && (
            <>
              <h5 className="stoop-sublabel">Carrying</h5>
              <ul className="stoop-ambitions">
                {wardrobe.carrying.map((a, i) => (
                  <li key={i}>🎒 {a}</li>
                ))}
              </ul>
            </>
          )}
        </section>
      )}
    </>
  );
}

function GreetingSection({ card }: { card: CardMap }) {
  const greetings = stoopGreetings(card);
  if (greetings.length === 0) return null;
  return (
    <section className="card stoop-section">
      <h4>{greetings.length > 1 ? `Greeting (${greetings.length})` : 'Greeting'}</h4>
      {greetings.map((g, i) => (
        <p key={i} className="stoop-pre">
          {i > 0 ? `\n———\n\n${g}` : g}
        </p>
      ))}
    </section>
  );
}

function LoreSection({ card, title }: { card: CardMap; title: string }) {
  const entries = stoopLoreEntries(card);
  if (entries.length === 0) return null;
  return (
    <section className="card stoop-section">
      <h4>{title} ({entries.length})</h4>
      {entries.map((e, i) => (
        <div key={i} className="stoop-lore-entry">
          <h5 className="stoop-sublabel">{e.name}</h5>
          <p className="stoop-pre">{e.content}</p>
        </div>
      ))}
    </section>
  );
}

function SoloBody({ card }: { card: CardMap }) {
  return (
    <>
      {SOLO_SECTIONS.map(({ key, label }) => (
        <Section key={key} title={label} body={textOf(card, key)} />
      ))}
      <GreetingSection card={card} />
      <IdentityExtras card={card} />
      <LoreSection card={card} title="Lorebook" />
    </>
  );
}

function GroupBody({ card, name }: { card: CardMap; name: string }) {
  const members = stoopMembers(card);
  const [idx, setIdx] = useState(0);
  const i = members.length === 0 ? 0 : Math.min(idx, members.length - 1);
  const member = members[i] ?? {};
  const memberName = textOf(member, 'name') || 'Member';
  return (
    <>
      <Section title="Group" body={stoopGroupTurnLabel(card, members.length)} />
      <Section title="Group scenario" body={textOf(card, 'scenario')} />
      <Section title="Group greeting" body={textOf(card, 'first_message') || textOf(card, 'first_mes')} />
      <LoreSection card={card} title="Group lore" />
      <Section title="Group system prompt" body={textOf(card, 'system_prompt')} />
      {members.length > 0 && (
        <section className="card stoop-section">
          <div className="stoop-member-nav">
            <h4 style={{ margin: 0, flex: 1 }}>{name} · {memberName}</h4>
            {members.length > 1 && (
              <>
                <button
                  className="icon-btn"
                  title="Previous member"
                  disabled={i === 0}
                  onClick={() => setIdx(i - 1)}
                >
                  ◀
                </button>
                <span className="muted small">{i + 1}/{members.length}</span>
                <button
                  className="icon-btn"
                  title="Next member"
                  disabled={i === members.length - 1}
                  onClick={() => setIdx(i + 1)}
                >
                  ▶
                </button>
              </>
            )}
          </div>
          <SoloBody card={member} />
        </section>
      )}
    </>
  );
}

function WorldBody({ card }: { card: CardMap }) {
  const climateEnabled = stoopWorldClimateEnabled(card);
  const traits = stoopWorldTraits(card);
  return (
    <>
      <Section title="About this place" body={textOf(card, 'description')} />
      {climateEnabled ? (
        <>
          <Section title="Climate" body={stoopWorldClimate(card)} />
          {traits.length > 0 && (
            <section className="card stoop-section">
              <h4>Traits</h4>
              <ul className="stoop-ambitions">
                {traits.map((t, i) => (
                  <li key={i}>{t}</li>
                ))}
              </ul>
            </section>
          )}
        </>
      ) : (
        <section className="card stoop-section">
          <p className="muted">
            Lore only -- no climate, weather, or place traits.
          </p>
        </section>
      )}
      <LoreSection card={card} title="Lore" />
    </>
  );
}

export function StoopCardSections({ detail }: { detail: StoopCardDetail }) {
  const card = detail.card as CardMap;
  const kind = stoopCardKind(detail.type, card);
  if (kind === 'GROUP') return <GroupBody card={card} name={detail.name} />;
  if (kind === 'WORLD') return <WorldBody card={card} />;
  return <SoloBody card={card} />;
}
