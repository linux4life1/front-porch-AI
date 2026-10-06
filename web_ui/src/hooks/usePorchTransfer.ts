// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// .porch / .porchpack (issue #348): export the selected characters (one
// .porch, or one .porchpack for two or more) and import those files. The
// Dart relay runs the same exporter and importer as the desktop library.

import { useCallback, useState } from 'react';
import { api } from '../api/client';
import { downloadBlob } from '../pages/story/storyUtil';

/** What the relay reports for one imported file. */
export type PorchImportReport = {
  imported: string[];
  skipped: string[];
  refused: string[];
  chats: number;
  message: string;
};

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;

function names(list: string[]): string {
  const shown = 8;
  if (list.length <= shown) return list.join(', ');
  return `${list.slice(0, shown).join(', ')} and ${list.length - shown} more`;
}

/** One summary across every file, in the desktop's words. */
export function porchSummary(reports: PorchImportReport[], failures: string[]): string {
  const imported = reports.flatMap((r) => r.imported);
  const skipped = reports.flatMap((r) => r.skipped);
  const chats = reports.reduce((n, r) => n + r.chats, 0);
  const lines = [
    ...(imported.length > 0
      ? [`Imported ${plural(imported.length, 'character')}${chats > 0 ? ` with ${plural(chats, 'chat')}` : ''}.`]
      : []),
    ...(skipped.length > 0 ? [`Skipped ${skipped.length} you already have: ${names(skipped)}.`] : []),
    ...reports.flatMap((r) => r.refused),
    ...failures,
  ];
  return lines.length > 0 ? lines.join('\n') : 'Those files held no characters.';
}

export function usePorchTransfer(opts: {
  reload: () => void;
  setError: (msg: string) => void;
  cancelSelecting: () => void;
}) {
  const { reload, setError, cancelSelecting } = opts;
  const [busy, setBusy] = useState(false);

  const exportPorch = useCallback(
    async (ids: string[]) => {
      if (ids.length === 0) return;
      setBusy(true);
      setError('');
      try {
        const file = await api.postForFile('/api/porch/export', { ids }, 'characters.porch');
        downloadBlob(file.blob, file.fileName);
        cancelSelecting();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'The export didn’t finish. Try again.');
      } finally {
        setBusy(false);
      }
    },
    [cancelSelecting, setError],
  );

  const importPorch = useCallback(
    async (files: FileList | null) => {
      if (!files || files.length === 0) return;
      setBusy(true);
      setError('');
      const reports: PorchImportReport[] = [];
      const failures: string[] = [];
      for (const file of Array.from(files)) {
        try {
          reports.push(await api.upload<PorchImportReport>('/api/porch/import', file));
        } catch (e) {
          failures.push(
            e instanceof Error ? e.message : `“${file.name}” couldn’t be imported. Try again.`,
          );
        }
      }
      setBusy(false);
      if (reports.some((r) => r.imported.length > 0)) reload();
      setError(porchSummary(reports, failures));
    },
    [reload, setError],
  );

  return { busy, exportPorch, importPorch };
}
