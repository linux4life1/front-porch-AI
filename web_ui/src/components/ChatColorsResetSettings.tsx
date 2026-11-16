// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → "Use the theme's chat colors": the desktop's own
// button, which forgets the picks for the brightness on screen so the app
// theme's colours apply. It sits after Chat Font, as on the desktop.

import { useState } from 'react';
import { api } from '../api/client';

export function ChatColorsResetSettings() {
  const [error, setError] = useState('');

  const reset = () => {
    setError('');
    api.post('/api/settings', { resetChatColors: true }).catch((e: unknown) => {
      setError(`Could not reset the chat colors: ${String(e)}`);
    });
  };

  return (
    <div className="appearance-reset" data-testid="chat-colors-reset-card">
      <button type="button" className="ghost" onClick={reset}>
        Use the theme&apos;s chat colors
      </button>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
