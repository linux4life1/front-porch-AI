// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
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
  const [folderId, setFolderId] = useState<string | null>(null);
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
    <div className="page">
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
        <div className="folder-row">
          {subfolders.map((f) => (
            <button key={f.id} className="folder-card" onClick={() => setFolderId(f.id)}>
              <span className="folder-icon">📁</span>
              <span className="folder-name">{f.name}</span>
            </button>
          ))}
        </div>
      )}

      {!searching && folderId === null && groups.length > 0 && (
        <>
          <h3 className="section-label">Group chats</h3>
          <div className="char-grid">
            {groups.map((g) => (
              <div key={g.id} className="char-card group-card">
                <button className="card-open" onClick={() => openGroup(g)}>
                  <div className="group-avatars">
                    {g.members.slice(0, 3).map((m) =>
                      m.hasAvatar ? (
                        <img
                          key={m.id}
                          src={`/api/groups/${g.id}/members/${m.id}/avatar`}
                          alt=""
                          loading="lazy"
                        />
                      ) : (
                        <span key={m.id} className="char-initial small">
                          {m.name.charAt(0).toUpperCase()}
                        </span>
                      ),
                    )}
                  </div>
                  <div className="char-name">{g.name}</div>
                  <div className="char-meta">{g.memberCount} members</div>
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
            <div className="char-grid">
              {chars.map((c) => (
                <button key={c.id} className="char-card" onClick={() => openCharacter(c)}>
                  <div className="char-avatar">
                    {c.hasAvatar ? (
                      <img src={`/api/characters/${c.id}/avatar`} alt="" loading="lazy" />
                    ) : (
                      <span className="char-initial">{c.name.charAt(0).toUpperCase()}</span>
                    )}
                  </div>
                  <div className="char-name">{c.name}</div>
                  {c.messageCount > 0 && <div className="char-meta">{c.messageCount} msgs</div>}
                </button>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
