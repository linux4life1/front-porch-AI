// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Password (+ optional TOTP) step-up fields shared by Remote Access, Settings,
// and Image Gen — the same credential-grade confirm the desktop already uses.

/** True when a preview POST would use a host or key other than the saved pair. */
export function remotePreviewNeedsStepUp(
  apiUrl: string,
  apiKey: string,
  savedApiUrl: string,
): boolean {
  const url = apiUrl.trim();
  if (url && url !== savedApiUrl.trim()) return true;
  return !!apiKey.trim();
}

export function attachStepUp(
  body: Record<string, unknown>,
  password: string,
  totpEnabled: boolean,
  totpCode: string,
): void {
  body.currentPassword = password;
  if (totpEnabled && totpCode.trim()) body.totpCode = totpCode.trim();
}

export function StepUpFields({
  password,
  onPassword,
  totpEnabled,
  totpCode,
  onTotp,
  reason,
}: {
  password: string;
  onPassword: (v: string) => void;
  totpEnabled: boolean;
  totpCode: string;
  onTotp: (v: string) => void;
  reason: string;
}) {
  return (
    <>
      <p className="muted small">{reason}</p>
      <label>
        Web login password
        <input
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => onPassword(e.target.value)}
        />
      </label>
      {totpEnabled && (
        <label>
          Two-factor code
          <input
            inputMode="numeric"
            placeholder="123456"
            value={totpCode}
            onChange={(e) => onTotp(e.target.value)}
          />
        </label>
      )}
    </>
  );
}
