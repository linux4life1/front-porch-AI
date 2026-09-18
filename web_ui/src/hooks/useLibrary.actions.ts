// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Folder / character / group writes and card import. Load, search, and
// navigation stay in useLibrary.ts.

import { useCallback, useRef, useState, type Dispatch, type SetStateAction } from 'react';
import { api, ApiError } from '../api/client';
import type { LibChar, LibGroup } from './useLibrary';

/** Trigger a same-origin authenticated download (cookies ride automatically). */
function download(url: string) {
  const a = document.createElement('a');
  a.href = url;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

export function useLibraryActions(opts: {
  folderId: string | null;
  setFolderId: (id: string | null) => void;
  reload: () => void;
  setError: (msg: string) => void;
  setChars: Dispatch<SetStateAction<LibChar[]>>;
  setGroups: Dispatch<SetStateAction<LibGroup[]>>;
  setImporting: (v: boolean) => void;
  cancelSelecting: () => void;
}) {
  const {
    folderId,
    setFolderId,
    reload,
    setError,
    setChars,
    setGroups,
    setImporting,
    cancelSelecting,
  } = opts;

  const createFolder = useCallback(
    async (name: string, parentId: string | null) => {
      try {
        await api.post('/api/folders', { name, parentId: parentId ?? undefined });
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not create folder');
      }
    },
    [reload, setError],
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
    [reload, setError],
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
    [folderId, reload, setFolderId, setError],
  );

  const duplicateCharacter = useCallback(
    async (id: string) => {
      try {
        await api.post(`/api/characters/${id}/duplicate`);
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not duplicate');
      }
    },
    [reload, setError],
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
    [setChars, setError],
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
    [cancelSelecting, reload, setError],
  );

  const bulkDelete = useCallback(
    async (ids: string[]) => {
      try {
        // One severe-delete endpoint (was N parallel single deletes) — matches
        // the desktop mass-delete pipeline and keeps the confirm gate
        // meaningful. The server routes `group_…` ids to the group delete, so
        // a mixed character + group selection deletes in one call.
        await api.post('/api/characters/bulk-delete', { ids });
        const drop = new Set(ids);
        setChars((cs) => cs.filter((c) => !drop.has(c.id)));
        setGroups((gs) => gs.filter((g) => !drop.has(g.id)));
        cancelSelecting();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not delete selection');
      }
    },
    [cancelSelecting, setChars, setGroups, setError],
  );

  /** The nuclear folder delete: folder + subfolders + every character inside. */
  const deleteFolderDeep = useCallback(
    async (id: string) => {
      try {
        await api.post(`/api/folders/${id}/delete-deep`);
        if (folderId === id) setFolderId(null);
        reload();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not delete folder');
      }
    },
    [folderId, reload, setFolderId, setError],
  );

  const deleteGroup = useCallback(
    async (g: LibGroup) => {
      try {
        await api.post(`/api/groups/${g.id}/delete`);
        setGroups((gs) => gs.filter((x) => x.id !== g.id));
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not delete group');
      }
    },
    [setGroups, setError],
  );
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
    [reload, setError],
  );

  // Single-file name collision: server returns 409 when collision=ask; we park
  // a pending prompt so the page can render Keep both / Replace / Cancel.
  type NameCollisionPending = {
    name: string;
    existing: { id: string; name: string }[];
    resolve: (choice: 'keepBoth' | 'replace' | 'cancel', replaceId?: string) => void;
  };
  const [nameCollision, setNameCollision] = useState<{
    name: string;
    existing: { id: string; name: string }[];
  } | null>(null);
  const collisionWaiter = useRef<NameCollisionPending | null>(null);

  const promptNameCollision = useCallback(
    (name: string, existing: { id: string; name: string }[]) => {
      return new Promise<{
        choice: 'keepBoth' | 'replace' | 'cancel';
        replaceId?: string;
      }>((resolve) => {
        const pending: NameCollisionPending = {
          name,
          existing,
          resolve: (choice, replaceId) => {
            collisionWaiter.current = null;
            setNameCollision(null);
            resolve({ choice, replaceId });
          },
        };
        collisionWaiter.current = pending;
        setNameCollision({ name, existing });
      });
    },
    [],
  );

  const resolveNameCollision = useCallback(
    (choice: 'keepBoth' | 'replace' | 'cancel', replaceId?: string) => {
      collisionWaiter.current?.resolve(choice, replaceId);
    },
    [],
  );

  const importFiles = useCallback(
    async (files: FileList | null) => {
      if (!files || files.length === 0) return;
      setImporting(true);
      setError('');
      const list = Array.from(files).filter((f) =>
        /\.(png|byaf|json)$/i.test(f.name),
      );
      const single = list.length === 1;
      let ok = 0;
      let failed = 0;
      let cancelled = 0;
      for (const file of list) {
        try {
          if (single) {
            try {
              await api.upload('/api/characters/import?collision=ask', file);
              ok++;
            } catch (e) {
              if (
                e instanceof ApiError &&
                e.status === 409 &&
                (e.payload.error === 'name_collision' ||
                  e.payload.status === 'name_collision')
              ) {
                const name = String(e.payload.name ?? file.name);
                const existing = (Array.isArray(e.payload.existing)
                  ? e.payload.existing
                  : []) as { id: string; name: string }[];
                const { choice, replaceId } = await promptNameCollision(
                  name,
                  existing,
                );
                if (choice === 'cancel') {
                  cancelled++;
                  continue;
                }
                if (choice === 'keepBoth') {
                  await api.upload(
                    '/api/characters/import?collision=keepBoth',
                    file,
                  );
                  ok++;
                } else {
                  const rid = replaceId || existing[0]?.id || '';
                  await api.upload(
                    `/api/characters/import?collision=replace&replaceId=${encodeURIComponent(rid)}`,
                    file,
                  );
                  ok++;
                }
              } else {
                failed++;
              }
            }
          } else {
            await api.upload(
              '/api/characters/import?collision=keepBoth',
              file,
            );
            ok++;
          }
        } catch {
          failed++;
        }
      }
      setImporting(false);
      if (ok > 0) reload();
      if (failed > 0) {
        setError(
          `Imported ${ok}, failed ${failed}. PNG (V2), .json and .byaf are supported.`,
        );
      } else if (ok === 0 && cancelled === 0 && list.length === 0) {
        setError('No PNG (V2), .json or .byaf cards found to import.');
      }
    },
    [reload, promptNameCollision, setError, setImporting],
  );

  return {
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
