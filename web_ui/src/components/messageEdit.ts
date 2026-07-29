// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure helpers for the fullscreen message editor — mirror of
// lib/utils/think_tags.dart splitMessageForEdit / joinMessageEdit so the web
// UI never shows raw <think> tags while editing.

export type MessageEditParts = { thinking: string; body: string };

/** Pull thinking + body out of a stored message string for the editor. */
export function splitMessageForEdit(text: string): MessageEditParts {
  const closed = /<think>([\s\S]*?)<\/think>\s*/i.exec(text);
  if (closed && closed.index !== undefined) {
    const thinking = (closed[1] ?? '').trim();
    const body =
      text.slice(0, closed.index) + text.slice(closed.index + closed[0].length);
    return { thinking, body };
  }
  const open = /<think>([\s\S]*)$/i.exec(text);
  if (open && open.index !== undefined) {
    const thinking = (open[1] ?? '').trim();
    const body = text.slice(0, open.index);
    return { thinking, body };
  }
  if (/<\/think>/i.test(text)) {
    return { thinking: '', body: text.replace(/<\/think>\s*/gi, '') };
  }
  return { thinking: '', body: text };
}

/** Reassemble editor fields into the stored message format. */
export function joinMessageEdit(thinking: string, body: string): string {
  const t = thinking.trim();
  if (!t) return body;
  const prefix = `<think>\n${t}\n</think>\n`;
  return body ? `${prefix}${body}` : prefix.trimEnd();
}
