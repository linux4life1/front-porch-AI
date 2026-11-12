// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The User Persona page: the nav's "User Persona", as on the desktop (its
// own page, not a section of Settings).

import { useState } from 'react';
import { PersonaManager } from '../components/PersonaManager';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';

export function PersonaPage() {
  const [dirty, setDirty] = useState(false);
  const { prompt } = useUnsavedChanges(dirty);
  return (
    <div className="page">
      {prompt}
      <PersonaManager onDirtyChange={setDirty} />
    </div>
  );
}
