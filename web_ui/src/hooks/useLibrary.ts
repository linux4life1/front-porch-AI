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
import { useLibraryActions } from './useLibrary.actions';

export interface LibChar {
  id: string;
  name: string;
  tags: string[];
  hasAvatar: boolean;
  /** Avatar file mtime — cache-busts the thumbnail URL when the picture changes. */
  avatarVersion?: number;
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
  /** Avatar file mtime — cache-busts the thumbnail URL when the picture changes. */
  avatarVersion?: number;
}
export interface LibGroup {
  id: string;
  name: string;
  /** Owning folder id, '' at the root — groups folder like characters now. */
  folderId: string;
  memberCount: number;
  members: LibGroupMember[];
}

export type SearchScope = 'currentFolder' | 'folderRecursive' | 'allCharacters';

const GRID_MIN_KEY = 'fpai.lib.gridMin';
const GRID_MIN_DEFAULT = 150;

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

  // Folders + groups load once (the page filters groups by their folderId,
  // mirroring the desktop grid).
  useEffect(() => {
    api.get<{ folders: LibFolder[] }>('/api/folders').then((r) => setFolders(r.folders)).catch(() => {});
    api.get<{ groups: LibGroup[] }>('/api/groups').then((r) => setGroups(r.groups)).catch(() => {});
  }, [reloadKey]);

  // The search box updates `search` on every keystroke; only this debounced
  // mirror drives the fetch, so typing a word costs one request instead of one
  // per letter (the same slow-uplink reasoning as the `library_changed`
  // debounce below). Folder / sort / scope are single events and stay instant.
  const [searchTerm, setSearchTerm] = useState('');
  useEffect(() => {
    const timer = setTimeout(() => setSearchTerm(search), 250);
    return () => clearTimeout(timer);
  }, [search]);

  // Characters reload on folder / search / sort / scope change. We always pass
  // the folder + scope so a search stays folder-scoped unless scope=All.
  // Every run invalidates the one before it: overlapping requests can complete
  // out of order (the server re-scans the library per call, and a broad term
  // returns a far bigger body than a narrow one), and without this the slower
  // earlier response would land last and render results for a query the user
  // has already moved past — with the spinner already cleared.
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    const params = new URLSearchParams();
    const term = searchTerm.trim();
    if (term) params.set('search', term);
    if (folderId) params.set('folder', folderId);
    if (sort !== 'name') params.set('sort', sort);
    if (term) params.set('scope', scope);
    api
      .get<LibChar[]>(`/api/characters?${params.toString()}`)
      .then((r) => {
        if (!cancelled) setChars(r);
      })
      .catch((e) => {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Failed to load characters');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [folderId, searchTerm, sort, scope, reloadKey]);

  // Live sync: the server broadcasts `library_changed` whenever characters /
  // folders / groups change anywhere (the desktop app or another browser).
  // Refetch on it so the library stays current without a manual reload — but
  // debounce, so a burst (e.g. a bulk import or folder reshuffle on the
  // desktop) coalesces into a single refetch instead of hammering a slow uplink
  // with a full 3-endpoint reload per event.
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const socket = new ChatSocket((e) => {
      if (e.event === 'library_changed') {
        if (timer) clearTimeout(timer);
        timer = setTimeout(reload, 400);
      } else if (e.event === 'connected') {
        // (Re)connected — a `library_changed` may have fired while the socket
        // was down (phone sleep, blip). Refetch immediately so the grid can't
        // stay frozen on a stale snapshot until the next unrelated change.
        if (timer) clearTimeout(timer);
        reload();
      }
    });
    socket.connect();
    return () => {
      if (timer) clearTimeout(timer);
      socket.close();
    };
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
      navigate('/chat?opening=1');
      try {
        await api.post('/api/chat/select', { characterId: c.id });
        navigate('/chat', { replace: true });
      } catch (e) {
        navigate('/', { replace: true });
        setError(e instanceof Error ? e.message : 'Could not open chat');
      }
    },
    [navigate],
  );
  const openGroup = useCallback(
    async (g: LibGroup) => {
      navigate('/chat?opening=1');
      try {
        await api.post('/api/chat/select-group', { groupId: g.id });
        navigate('/chat', { replace: true });
      } catch (e) {
        navigate('/', { replace: true });
        setError(e instanceof Error ? e.message : 'Could not open group');
      }
    },
    [navigate],
  );
  const editCharacter = useCallback((id: string) => navigate(`/edit/${id}`), [navigate]);

  /** The personas offered by "Start new chat" step 2 (id/label/active). */
  const loadPersonas = useCallback(
    () =>
      api
        .get<{ personas: { id: string; label: string; name: string; active: boolean }[] }>(
          '/api/personas',
        )
        .then((r) => r.personas)
        .catch(() => []),
    [],
  );

  /** Open a FRESH chat with a character or group under [personaId]. One
   *  server call — the desktop-shared ordering (enter, apply persona, then new
   *  session) lives in ChatService, not here. */
  const startFreshChat = useCallback(
    async (target: { characterId?: string; groupId?: string }, personaId: string) => {
      navigate('/chat?opening=1');
      try {
        await api.post('/api/chat/start-fresh', { ...target, personaId });
        navigate('/chat', { replace: true });
      } catch (e) {
        navigate('/', { replace: true });
        setError(e instanceof Error ? e.message : 'Could not start the chat');
      }
    },
    [navigate],
  );

  const {
    createFolder,
    renameFolder,
    deleteFolder,
    deleteFolderDeep,
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
    nameCollision,
    resolveNameCollision,
  } = useLibraryActions({
    folderId,
    setFolderId,
    reload,
    setError,
    setChars,
    setGroups,
    setImporting,
    cancelSelecting,
  });

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
    loadPersonas,
    startFreshChat,
    createFolder,
    renameFolder,
    deleteFolder,
    deleteFolderDeep,
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
    nameCollision,
    resolveNameCollision,
  };
}
