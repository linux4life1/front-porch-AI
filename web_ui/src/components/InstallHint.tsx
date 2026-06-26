// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Install to your phone" affordance — shown ONLY when the browser actually
// offers an install prompt (Android/Chromium fire `beforeinstallprompt`). iOS
// Safari has no such prompt, and nagging someone who is *already* using the web
// app on their phone to "connect / add to home screen" is just noise — so on
// iOS (and anywhere without a real prompt) this renders nothing.

import { useEffect, useState } from 'react';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

function isStandalone(): boolean {
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    // iOS Safari exposes this non-standard flag when launched from the home screen.
    (window.navigator as unknown as { standalone?: boolean }).standalone === true
  );
}

export function InstallHint() {
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null);
  const [dismissed, setDismissed] = useState(false);
  const [installed, setInstalled] = useState(isStandalone());

  useEffect(() => {
    const onPrompt = (e: Event) => {
      e.preventDefault();
      setDeferred(e as BeforeInstallPromptEvent);
    };
    const onInstalled = () => setInstalled(true);
    window.addEventListener('beforeinstallprompt', onPrompt);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onPrompt);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  // Render nothing unless the browser handed us a real, actionable install
  // prompt (so no iOS nag, no desktop no-op banner).
  if (installed || dismissed || !deferred) return null;

  const install = async () => {
    await deferred.prompt();
    await deferred.userChoice;
    setDeferred(null);
  };

  return (
    <div className="install-hint">
      <div className="install-hint-body">
        <strong>Install Front Porch</strong>
        <p className="muted small">
          Add it to your home screen for a full-screen, app-like experience.
        </p>
      </div>
      <div className="install-hint-actions">
        <button className="primary" onClick={install}>Install</button>
        <button className="link-btn" onClick={() => setDismissed(true)}>Dismiss</button>
      </div>
    </div>
  );
}
