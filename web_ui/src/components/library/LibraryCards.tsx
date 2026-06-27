// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Presentational library cards (character / folder / group). All behavior is
// injected by the page; cards never call the API directly. The kebab/context
// menu always routes through the page's single CardMenu via [onMenu].

import { useState, type MouseEvent } from 'react';
import type { LibChar, LibFolder, LibGroup } from '../../hooks/useLibrary';

export function CharacterCard({
  char,
  selecting,
  selected,
  onOpen,
  onToggleSelect,
  onMenu,
  dndEnabled,
  onDragStart,
}: {
  char: LibChar;
  selecting: boolean;
  selected: boolean;
  onOpen: () => void;
  onToggleSelect: () => void;
  onMenu: (e: MouseEvent) => void;
  dndEnabled: boolean;
  onDragStart: () => void;
}) {
  return (
    <div
      className={`lib-card${selected ? ' selected' : ''}`}
      draggable={dndEnabled && !selecting}
      onDragStart={(e) => {
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', char.id);
        onDragStart();
      }}
      onContextMenu={(e) => {
        e.preventDefault();
        onMenu(e);
      }}
    >
      <button className="lib-open" onClick={() => (selecting ? onToggleSelect() : onOpen())}>
        <div className="lib-art">
          {char.hasAvatar ? (
            <img
              src={`/api/characters/${char.id}/avatar`}
              alt=""
              loading="lazy"
              onError={(e) => {
                e.currentTarget.style.display = 'none';
              }}
            />
          ) : (
            <span className="lib-art-fallback">{char.name.charAt(0).toUpperCase()}</span>
          )}
        </div>
        <div className="lib-info">
          <div className="lib-name-row">
            <span className="lib-name">{char.name}</span>
            {char.messageCount > 0 && <span className="lib-msgs">💬 {char.messageCount}</span>}
          </div>
          {char.tags.length > 0 && (
            <div className="tag-pills">
              {char.tags.slice(0, 3).map((t) => (
                <span key={t} className="tag-pill">
                  {t}
                </span>
              ))}
            </div>
          )}
        </div>
      </button>
      {selecting ? (
        <span className={`select-check${selected ? ' on' : ''}`} aria-hidden>
          {selected ? '✓' : ''}
        </span>
      ) : (
        <button
          className="icon-btn card-kebab"
          title="More actions"
          aria-label="More actions"
          onClick={(e) => {
            e.stopPropagation();
            onMenu(e);
          }}
        >
          ⋮
        </button>
      )}
    </div>
  );
}

export function FolderCard({
  folder,
  onOpen,
  onMenu,
  onDropChars,
}: {
  folder: LibFolder;
  onOpen: () => void;
  onMenu: (e: MouseEvent) => void;
  onDropChars: () => void;
}) {
  const [over, setOver] = useState(false);
  return (
    <div
      className={`lib-card folder-card${over ? ' drop-over' : ''}`}
      onContextMenu={(e) => {
        e.preventDefault();
        onMenu(e);
      }}
      onDragOver={(e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
      }}
      onDragEnter={() => setOver(true)}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => {
        e.preventDefault();
        setOver(false);
        onDropChars();
      }}
    >
      <button className="lib-open folder-open" onClick={onOpen}>
        <span className="folder-glyph" aria-hidden>
          📁
        </span>
        <span className="lib-name">{folder.name}</span>
      </button>
      <button
        className="icon-btn card-kebab folder-kebab"
        title="More actions"
        aria-label="More actions"
        onClick={(e) => {
          e.stopPropagation();
          onMenu(e);
        }}
      >
        ⋮
      </button>
    </div>
  );
}

export function GroupCard({
  group,
  onOpen,
  onMenu,
}: {
  group: LibGroup;
  onOpen: () => void;
  onMenu: (e: MouseEvent) => void;
}) {
  return (
    <div
      className="lib-card group-card"
      onContextMenu={(e) => {
        e.preventDefault();
        onMenu(e);
      }}
    >
      <button className="lib-open" onClick={onOpen}>
        <div className="lib-art group-art" data-count={Math.min(group.members.length, 4)}>
          {group.members.slice(0, 4).map((m) =>
            m.hasAvatar ? (
              <img
                key={m.id}
                src={`/api/groups/${group.id}/members/${m.id}/avatar`}
                alt=""
                loading="lazy"
                onError={(e) => {
                  e.currentTarget.style.display = 'none';
                }}
              />
            ) : (
              <span key={m.id} className="lib-art-fallback">
                {m.name.charAt(0).toUpperCase()}
              </span>
            ),
          )}
        </div>
        <div className="lib-info">
          <div className="lib-name-row">
            <span className="lib-name">👥 {group.name}</span>
          </div>
          <span className="lib-sub">{group.memberCount} members</span>
        </div>
      </button>
      <button
        className="icon-btn card-kebab"
        title="More actions"
        aria-label="More actions"
        onClick={(e) => {
          e.stopPropagation();
          onMenu(e);
        }}
      >
        ⋮
      </button>
    </div>
  );
}
