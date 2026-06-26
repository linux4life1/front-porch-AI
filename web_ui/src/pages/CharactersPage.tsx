// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api } from '../api/client';
import { InstallHint } from '../components/InstallHint';

interface Character {
  id: string;
  name: string;
  description: string;
  tags: string[];
  hasAvatar: boolean;
  messageCount: number;
}
interface Folder {
  id: string;
  name: string;
  parentId?: string;
}
interface GroupMember {
  id: string;
  name: string;
  hasAvatar: boolean;
}
interface Group {
  id: string;
  name: string;
  memberCount: number;
  members: GroupMember[];
}

export function CharactersPage() {
  const navigate = useNavigate();
  const [chars, setChars] = useState<Character[]>([]);
  const [folders, setFolders] = useState<Folder[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  // Current folder lives in the URL (?folder=<id>) so tapping the app title /
  // "Front Porch AI" (a link to "/") returns to the library root from anywhere,
  // and browser back/forward walks the folder history.
  const [searchParams, setSearchParams] = useSearchParams();
  const folderId = searchParams.get('folder');
  const setFolderId = (id: string | null) =>
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      if (id) next.set('folder', id);
      else next.delete('folder');
      return next;
    });
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState('name');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [importing, setImporting] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);
  const fileRef = useRef<HTMLInputElement>(null);

  const searching = search.trim().length > 0;

  const onImportFiles = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    setImporting(true);
    setError('');
    let ok = 0;
    let failed = 0;
    for (const file of Array.from(files)) {
      try {
        await api.upload('/api/characters/import', file);
        ok++;
      } catch {
        failed++;
      }
    }
    setImporting(false);
    if (failed > 0) setError(`Imported ${ok}, failed ${failed}. PNG (V2) and .byaf are supported.`);
    setReloadKey((k) => k + 1);
  };

  // Folders + groups load once (groups shown at the library root only).
  useEffect(() => {
    api.get<{ folders: Folder[] }>('/api/folders').then((r) => setFolders(r.folders)).catch(() => {});
    api.get<{ groups: Group[] }>('/api/groups').then((r) => setGroups(r.groups)).catch(() => {});
  }, []);

  // Characters reload when the folder or search changes. A search is global
  // (server-side, ignores folder); otherwise we show the current folder's
  // characters (root = unfoldered, matching the desktop).
  useEffect(() => {
    setLoading(true);
    const params = new URLSearchParams();
    const term = search.trim();
    if (term) params.set('search', term);
    else if (folderId) params.set('folder', folderId);
    if (sort !== 'name') params.set('sort', sort);
    api
      .get<Character[]>(`/api/characters?${params.toString()}`)
      .then(setChars)
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load characters'))
      .finally(() => setLoading(false));
  }, [folderId, search, sort, reloadKey]);

  const subfolders = useMemo(
    () => folders.filter((f) => (f.parentId ?? null) === folderId),
    [folders, folderId],
  );

  // Breadcrumb trail from root to the current folder.
  const trail = useMemo(() => {
    const byId = new Map(folders.map((f) => [f.id, f]));
    const out: Folder[] = [];
    let cur = folderId ? byId.get(folderId) : undefined;
    while (cur) {
      out.unshift(cur);
      cur = cur.parentId ? byId.get(cur.parentId) : undefined;
    }
    return out;
  }, [folders, folderId]);

  const openCharacter = async (c: Character) => {
    try {
      await api.post('/api/chat/select', { characterId: c.id });
      navigate('/chat');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not open chat');
    }
  };

  const openGroup = async (g: Group) => {
    try {
      await api.post('/api/chat/select-group', { groupId: g.id });
      navigate('/chat');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not open group');
    }
  };

  const deleteGroup = async (g: Group) => {
    if (!window.confirm(`Delete group "${g.name}"? This removes the group and its chats.`)) return;
    try {
      await api.post(`/api/groups/${g.id}/delete`);
      setGroups((gs) => gs.filter((x) => x.id !== g.id));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete group');
    }
  };

  return (
    <div className="page library">
      <InstallHint />
      <div className="search-row">
        <input
          className="search"
          placeholder="Search characters…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          className="sort-select"
          value={sort}
          onChange={(e) => setSort(e.target.value)}
          aria-label="Sort characters"
        >
          <option value="name">Name</option>
          <option value="recent">Recent</option>
          <option value="messages">Most messages</option>
        </select>
        <button
          className="primary import-btn"
          onClick={() => navigate('/create')}
          title="Create a new character"
        >
          ＋ Create
        </button>
        <button
          className="ghost import-btn"
          onClick={() => navigate('/create-ai')}
          title="Generate a character with AI"
        >
          ✨ AI Create
        </button>
        <button
          className="ghost import-btn"
          disabled={importing}
          onClick={() => fileRef.current?.click()}
          title="Import character card (PNG / .byaf)"
        >
          {importing ? 'Importing…' : '⬆ Import'}
        </button>
        <input
          ref={fileRef}
          type="file"
          accept=".png,.byaf,image/png,application/json"
          multiple
          hidden
          onChange={(e) => {
            void onImportFiles(e.target.files);
            e.target.value = '';
          }}
        />
      </div>
      {error && <p className="error">{error}</p>}

      {!searching && folderId !== null && (
        <div className="breadcrumb">
          <button className="link-btn" onClick={() => setFolderId(null)}>
            Home
          </button>
          {trail.map((f) => (
            <span key={f.id}>
              <span className="crumb-sep">/</span>
              <button className="link-btn" onClick={() => setFolderId(f.id)}>
                {f.name}
              </button>
            </span>
          ))}
        </div>
      )}

      {!searching && subfolders.length > 0 && (
        <div className="lib-grid">
          {subfolders.map((f) => (
            <button key={f.id} className="lib-card folder-card" onClick={() => setFolderId(f.id)}>
              <span className="folder-glyph" aria-hidden>📁</span>
              <span className="lib-name">{f.name}</span>
            </button>
          ))}
        </div>
      )}

      {!searching && folderId === null && groups.length > 0 && (
        <>
          <h3 className="section-label">Group chats</h3>
          <div className="lib-grid">
            {groups.map((g) => (
              <div key={g.id} className="lib-card group-card">
                <button className="lib-open" onClick={() => openGroup(g)}>
                  <div className="lib-art group-art" data-count={Math.min(g.members.length, 4)}>
                    {g.members.slice(0, 4).map((m) =>
                      m.hasAvatar ? (
                        <img
                          key={m.id}
                          src={`/api/groups/${g.id}/members/${m.id}/avatar`}
                          alt=""
                          loading="lazy"
                        />
                      ) : (
                        <span key={m.id} className="lib-art-fallback">
                          {m.name.charAt(0).toUpperCase()}
                        </span>
                      ),
                    )}
                  </div>
                  <div className="lib-info">
                    <div className="lib-name-row"><span className="lib-name">👥 {g.name}</span></div>
                    <span className="lib-sub">{g.memberCount} members</span>
                  </div>
                </button>
                <button
                  className="icon-btn card-delete"
                  title="Delete group"
                  onClick={() => deleteGroup(g)}
                >
                  🗑
                </button>
              </div>
            ))}
          </div>
        </>
      )}

      {loading ? (
        <div className="centered"><div className="spinner" /></div>
      ) : (
        <>
          {!searching && (subfolders.length > 0 || (folderId === null && groups.length > 0)) && (
            <h3 className="section-label">Characters</h3>
          )}
          {chars.length === 0 ? (
            <p className="muted">No characters here.</p>
          ) : (
            <div className="lib-grid">
              {chars.map((c) => (
                <button key={c.id} className="lib-card" onClick={() => openCharacter(c)}>
                  <div className="lib-art">
                    {c.hasAvatar ? (
                      <img src={`/api/characters/${c.id}/avatar`} alt="" loading="lazy" />
                    ) : (
                      <span className="lib-art-fallback">{c.name.charAt(0).toUpperCase()}</span>
                    )}
                  </div>
                  <div className="lib-info">
                    <div className="lib-name-row">
                      <span className="lib-name">{c.name}</span>
                      {c.messageCount > 0 && <span className="lib-msgs">💬 {c.messageCount}</span>}
                    </div>
                    {c.tags.length > 0 && (
                      <div className="tag-pills">
                        {c.tags.slice(0, 3).map((t) => (
                          <span key={t} className="tag-pill">{t}</span>
                        ))}
                      </div>
                    )}
                  </div>
                </button>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
