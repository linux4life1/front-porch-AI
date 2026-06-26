// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Install to your phone" affordance. Android/Chromium fire a
// `beforeinstallprompt` we can trigger from a button; iOS Safari NEVER fires
// one (Apple has no install prompt), so there we just show the manual
// Share -> "Add to Home Screen" steps. Renders nothing once installed.

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

function isIos(): boolean {
  return /iphone|ipad|ipod/i.test(window.navigator.userAgent);
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

  if (installed || dismissed) return null;

  // Only meaningful over a secure origin (Tailscale/ngrok HTTPS or localhost).
  if (!window.isSecureContext) return null;

  const ios = isIos();
  if (!ios && !deferred) return null; // Android with no prompt yet / desktop

  const install = async () => {
    if (!deferred) return;
    await deferred.prompt();
    await deferred.userChoice;
    setDeferred(null);
  };

  return (
    <div className="install-hint">
      <div className="install-hint-body">
        <strong>Install Front Porch on your phone</strong>
        {ios ? (
          <p className="muted small">
            Tap the <span aria-label="Share">Share</span> button below, then choose
            <strong> “Add to Home Screen.”</strong> It opens like a real app.
          </p>
        ) : (
          <p className="muted small">
            Add it to your home screen for a full-screen, app-like experience.
          </p>
        )}
      </div>
      <div className="install-hint-actions">
        {!ios && deferred && (
          <button className="primary" onClick={install}>
            Install
          </button>
        )}
        <button className="link-btn" onClick={() => setDismissed(true)}>
          Dismiss
        </button>
      </div>
    </div>
  );
}
