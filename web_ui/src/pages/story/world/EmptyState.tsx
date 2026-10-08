// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A section with nothing in it yet: a bold title and one muted line of what to
// do about it. Web twin of the desktop's StoryEmptyState.

export function EmptyState({ title, detail, testid }: { title: string; detail: string; testid?: string }) {
  return (
    <section className="s-card" data-testid={testid}>
      <div className="s-bold">{title}</div>
      <div className="s-muted s-body">{detail}</div>
    </section>
  );
}
