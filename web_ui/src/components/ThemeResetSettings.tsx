// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → the desktop's "Reset accent, font and corners"
// button: one host write that clears the three customisations and leaves the
// theme and mode alone (appearance_settings.dart resetCustomisations).

import { useState } from 'react';
import { api } from '../api/client';

export function ThemeResetSettings() {
  const [error, setError] = useState('');

  const reset = () => {
    setError('');
    api.post('/api/settings', { resetAppearance: true }).catch((e: unknown) => {
      setError(`Could not reset the appearance: ${String(e)}`);
    });
  };

  return (
    <div className="appearance-reset" data-testid="appearance-reset-card">
      <button type="button" className="ghost" onClick={reset}>
        Reset accent, font and corners
      </button>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
