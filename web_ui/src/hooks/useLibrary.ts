// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library state + actions for the Characters page. Owns the data (characters /
// folders / groups), the current-folder URL param, search/sort/scope, the grid
// size (a web-local view pref), multi-select state, and every write action —
// each a thin call to the Dart web server which delegates to the same desktop
// services (FolderService / CharacterRepository / V2CardService / GroupCard*).
// The page + components stay presentational so no file exceeds the size cap.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';

export interface LibChar {
  id: string;
  name: string;
  description: string;
  tags: string[];
  hasAvatar: boolean;
  messageCount: number;
  folderId: string;
}
export interface LibFolder {
  id: string;
  name: string;
  parentId?: string;
}
export interface LibGroupMember {
  id: string;
  name: string;
  hasAvatar: boolean;
}
export interface LibGroup {
  id: string;
  name: string;
  memberCount: number;
  members: LibGroupMember[];
}

export type SearchScope = 'currentFolder' | 'folderRecursive' | 'allCharacters';

const GRID_MIN_KEY = 'fpai.lib.gridMin';
const GRID_MIN_DEFAULT = 150;

/** Trigger a same-origin authenticated download (cookies ride automatically). */
function download(url: string) {
  const a = document.createElement('a');
  a.href = url;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

export function useLibrary() {
  const navigate = useNavigate();
  const [chars, setChars] = useState<LibChar[]>([]);
  const [folders, setFolders] = useState<LibFolder[]>([]);
  const [groups, setGroups] = useState<LibGroup[]>([]);

  // Current folder lives in the URL (?folder=<id>) so the app title (a link to
  // "/") returns to the root and browser back/forward walks folder history.
  const [searchParams, setSearchParams] = useSearchParams();
  const folderId = searchParams.get('folder');
  const setFolderId = useCallback(
    (id: string | null) =>
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        if (id) next.set('folder', id);
        else next.delete('folder');
        return next;
      }),
    [setSearchParams],
  );

  const [search, setSearch] = useState('');
  const [sort, setSort] = useState('name');
  const [scope, setScope] = useState<SearchScope>('currentFolder');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [importing, setImporting] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);
  const reload = useCallback(() => setReloadKey((k) => k + 1), []);

  const [gridMin, setGridMinState] = useState<number>(() => {
    const v = Number(localStorage.getItem(GRID_MIN_KEY));
    return Number.isFinite(v) && v >= 110 && v <= 320 ? v : GRID_MIN_DEFAULT;
  });
  const setGridMin = useCallback((v: number) => {
    setGridMinState(v);
    localStorage.setItem(GRID_MIN_KEY, String(v));
  }, []);

  // Multi-select (covers the desktop "select" + "organize" bulk-move flows).
  const [selecting, setSelecting] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const toggleSelect = useCallback((id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);
  const startSelecting = useCallback(() => {
    setSelecting(true);
    setSelectedIds(new Set());
  }, []);
  const cancelSelecting = useCallback(() => {
    setSelecting(false);
    setSelectedIds(new Set());
  }, []);

  const searching = search.trim().length > 0;

  // Folders + groups load once (groups are shown at the library root only).
  useEffect(() => {
    api.get<{ folders: LibFolder[] }>('/api/folders').then((r) => setFolders(r.folders)).catch(() => {});
    api.get<{ groups: LibGroup[] }>('/api/groups').then((r) => setGroups(r.groups)).catch(() => {});
  }, [reloadKey]);

  // Characters reload on folder / search / sort / scope change. We always pass
  // the folder + scope so a search stays folder-scoped unless scope=All.
  useEffect(() => {
    setLoading(true);
    const params = new URLSearchParams();
    const term = search.trim();
    if (term) params.set('search', term);
    if (folderId) params.set('folder', folderId);
    if (sort !== 'name') params.set('sort', sort);
    if (term) params.set('scope', scope);
    api
      .get<LibChar[]>(`/api/characters?${params.toString()}`)
      .then(setChars)
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load characters'))
      .finally(() => setLoading(false));
  }, [folderId, search, sort, scope, reloadKey]);

  // Live sync: the server broadcasts `library_changed` whenever characters /
  // folders / groups change anywhere (the desktop app or another browser).
  // Refetch on it so the library stays current without a manual reload.
  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.event === 'library_changed') reload();
    });
    socket.connect();
    return () => socket.close();
  }, [reload]);

  const subfolders = useMemo(
    () => folders.filter((f) => (f.parentId ?? null) === folderId),
    [folders, folderId],
  );

  const trail = useMemo(() => {
    const byId = new Map(folders.map((f) => [f.id, f]));
    const out: LibFolder[] = [];
    let cur = folderId ? byId.get(folderId) : undefined;
    while (cur) {
      out.unshift(cur);
      cur = cur.parentId ? byId.get(cur.parentId) : undefined;
    }
    return out;
  }, [folders, folderId]);

  // ── Navigation ──────────────────────────────────────────────────────────
  const openCharacter = useCallback(
    async (c: LibChar) => {
      try {
        await api.post('/api/chat/select', { characterId: c.id });
        navigate('/chat');
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not open chat');
      }
    },
    [navigate],
  );
  const openGroup = useCallback(
    async (g: LibGroup) => {
      try {
        await api.post('/api/chat/select-group', { groupId: g.id });
        navigate('/chat');
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not open group');
      }
    },
    [navigate],
  );
  const editCharacter = useCallback((id: string) => navigate(`/edit/${id}`), [navigate]);

  // ── Folder CRUD ─────────────────────────────────────────────────────────
  const createFolder = useCallback(
    async (name: string, parentId: string | null) => {
      try {
        await api.post('/api/folders', { name, parentId: parentId ?? undefined });
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not create folder');
      }
    },
    [reload],
  );
  const renameFolder = useCallback(
    async (id: string, name: string) => {
      try {
        await api.post(`/api/folders/${id}/rename`, { name });
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not rename folder');
      }
    },
    [reload],
  );
  const deleteFolder = useCallback(
    async (id: string) => {
      try {
        await api.post(`/api/folders/${id}/delete`);
        if (folderId === id) setFolderId(null);
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not delete folder');
      }
    },
    [folderId, reload, setFolderId],
  );

  // ── Character actions ─────────────────────────────────────────────────────
  const duplicateCharacter = useCallback(
    async (id: string) => {
      try {
        await api.post(`/api/characters/${id}/duplicate`);
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not duplicate');
      }
    },
    [reload],
  );
  const deleteCharacter = useCallback(
    async (id: string) => {
      try {
        await api.post(`/api/characters/${id}/delete`);
        setChars((cs) => cs.filter((c) => c.id !== id));
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not delete');
      }
    },
    [],
  );
  const exportPng = useCallback((id: string) => download(`/api/characters/${id}/export.png`), []);
  const exportJson = useCallback((id: string) => download(`/api/characters/${id}/export.json`), []);

  /** Move one or many characters into a folder (null = back to the root). */
  const moveToFolder = useCallback(
    async (ids: string[], targetFolderId: string | null) => {
      if (ids.length === 0) return;
      try {
        if (ids.length === 1) {
          await api.post(`/api/characters/${ids[0]}/move`, {
            folderId: targetFolderId ?? '',
          });
        } else {
          await api.post('/api/characters/move', {
            ids,
            folderId: targetFolderId ?? '',
          });
        }
        cancelSelecting();
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not move');
      }
    },
    [cancelSelecting, reload],
  );

  const bulkDelete = useCallback(
    async (ids: string[]) => {
      try {
        await Promise.all(ids.map((id) => api.post(`/api/characters/${id}/delete`)));
        const drop = new Set(ids);
        setChars((cs) => cs.filter((c) => !drop.has(c.id)));
        cancelSelecting();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not delete selection');
      }
    },
    [cancelSelecting],
  );

  // ── Group actions ─────────────────────────────────────────────────────────
  const deleteGroup = useCallback(async (g: LibGroup) => {
    try {
      await api.post(`/api/groups/${g.id}/delete`);
      setGroups((gs) => gs.filter((x) => x.id !== g.id));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete group');
    }
  }, []);
  const exportGroupPng = useCallback((g: LibGroup) => download(`/api/groups/${g.id}/export.png`), []);
  const extractGroup = useCallback(
    async (g: LibGroup) => {
      try {
        const r = await api.post<{ extracted: number }>(`/api/groups/${g.id}/extract`);
        setError(
          r.extracted === 1
            ? 'Extracted 1 character into your library.'
            : `Extracted ${r.extracted} characters into your library.`,
        );
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not extract characters');
      }
    },
    [reload],
  );

  // ── Import (multi-file + whole folder) ─────────────────────────────────────
  const importFiles = useCallback(
    async (files: FileList | null) => {
      if (!files || files.length === 0) return;
      setImporting(true);
      setError('');
      let ok = 0;
      let failed = 0;
      for (const file of Array.from(files)) {
        const lower = file.name.toLowerCase();
        if (!/\.(png|byaf|json)$/.test(lower)) continue;
        try {
          await api.upload('/api/characters/import', file);
          ok++;
        } catch {
          failed++;
        }
      }
      setImporting(false);
      if (ok > 0) reload();
      if (failed > 0) {
        setError(`Imported ${ok}, failed ${failed}. PNG (V2), .json and .byaf are supported.`);
      } else if (ok === 0) {
        setError('No PNG (V2), .json or .byaf cards found to import.');
      }
    },
    [reload],
  );

  return {
    // data
    chars,
    folders,
    groups,
    subfolders,
    trail,
    folderId,
    setFolderId,
    // query
    search,
    setSearch,
    sort,
    setSort,
    scope,
    setScope,
    searching,
    // view
    gridMin,
    setGridMin,
    loading,
    error,
    setError,
    importing,
    // selection
    selecting,
    selectedIds,
    toggleSelect,
    startSelecting,
    cancelSelecting,
    // actions
    openCharacter,
    openGroup,
    editCharacter,
    createFolder,
    renameFolder,
    deleteFolder,
    duplicateCharacter,
    deleteCharacter,
    exportPng,
    exportJson,
    moveToFolder,
    bulkDelete,
    deleteGroup,
    exportGroupPng,
    extractGroup,
    importFiles,
  };
}
