// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-chat theme settings — the web mirror of the desktop's theme panel in
// ChatSettingsDialog. Lets the user pick a theme preset and customize per-chat
// colors, font, background, and border style. Saves to the active session via
// POST /api/chat/theme-overrides.

import { useState, useEffect } from 'react';
import type { ChatThemeOverrides, ChatThemePreset } from './chatTypes';

// Mirror of the 10 desktop presets (ChatThemePreset.presets).
const PRESETS: ChatThemePreset[] = [
  { id: 'fantasy', displayName: 'Fantasy', description: 'Rich purples and soft gold', defaultUserBubbleColor: 0xFF332054, defaultUserTextColor: 0xFFF5E7C4, defaultAiBubbleColor: 0xFF332054, defaultAiTextColor: 0xFFF5E7C4, defaultDialogueColor: 0xFFFFD54F, defaultActionColor: 0xFFCBB4EC, defaultBorderColor: 0xFFD4AF37, defaultFontFamily: 'serif', defaultBackgroundKey: 'fantasy', defaultBorderStyle: 'vine' },
  { id: 'galactic', displayName: 'Galactic', description: 'Deep space blues and cyan', defaultUserBubbleColor: 0xFF0D1B2A, defaultUserTextColor: 0xFF00D4FF, defaultAiBubbleColor: 0xFF0D1B2A, defaultAiTextColor: 0xFFE0E0FF, defaultDialogueColor: 0xFF80DEEA, defaultActionColor: 0xFF7C4DFF, defaultBorderColor: 0xFF00D4FF, defaultFontFamily: 'sans-serif', defaultBackgroundKey: 'space_station', defaultBorderStyle: 'dualLine' },
  { id: 'neon_grid', displayName: 'Neon Grid', description: 'Black backdrop with neon glow', defaultUserBubbleColor: 0xFF0A0A0A, defaultUserTextColor: 0xFFFF00FF, defaultAiBubbleColor: 0xFF0A0A0A, defaultAiTextColor: 0xFF00FFFF, defaultDialogueColor: 0xFFFFFF00, defaultActionColor: 0xFFFF00FF, defaultBorderColor: 0xFFFF00FF, defaultFontFamily: 'monospace', defaultBackgroundKey: 'grid', defaultBorderStyle: 'glitch' },
  { id: 'sakura', displayName: 'Sakura', description: 'Soft pinks and pale tones', defaultUserBubbleColor: 0xFFFCE4EC, defaultUserTextColor: 0xFF5D2A3E, defaultAiBubbleColor: 0xFFFCE4EC, defaultAiTextColor: 0xFF5D2A3E, defaultDialogueColor: 0xFFAD1457, defaultActionColor: 0xFF33691E, defaultBorderColor: 0xFF880E4F, defaultFontFamily: 'serif', defaultBackgroundKey: 'cherry_blossom', defaultBorderStyle: 'wavy' },
  { id: 'noir', displayName: 'Noir', description: 'Monochrome shadows', defaultUserBubbleColor: 0xFF2D2D2D, defaultUserTextColor: 0xFFF5F5F5, defaultAiBubbleColor: 0xFF1A1A1A, defaultAiTextColor: 0xFFCCCCCC, defaultDialogueColor: 0xFFBDBDBD, defaultActionColor: 0xFF78909C, defaultBorderColor: 0xFF888888, defaultFontFamily: 'sans-serif', defaultBackgroundKey: 'noir', defaultBorderStyle: 'shadow' },
  { id: 'enchanted_forest', displayName: 'Enchanted Forest', description: 'Deep greens and warm earth', defaultUserBubbleColor: 0xFF2D5A27, defaultUserTextColor: 0xFFF0E6D3, defaultAiBubbleColor: 0xFF4A7C3F, defaultAiTextColor: 0xFFFFF8E7, defaultDialogueColor: 0xFFA5D6A7, defaultActionColor: 0xFFD7CCC8, defaultBorderColor: 0xFF5E3D04, defaultFontFamily: 'serif', defaultBackgroundKey: 'enchanted_wood', defaultBorderStyle: 'vine' },
  { id: 'ocean_depths', displayName: 'Ocean Depths', description: 'Deep blues and teal', defaultUserBubbleColor: 0xFF003049, defaultUserTextColor: 0xFFE0F7FA, defaultAiBubbleColor: 0xFF006D77, defaultAiTextColor: 0xFFE0F7FA, defaultDialogueColor: 0xFF80DEEA, defaultActionColor: 0xFF80CBC4, defaultBorderColor: 0xFF00BCD4, defaultFontFamily: 'sans-serif', defaultBackgroundKey: 'ocean_depth', defaultBorderStyle: 'dualLine' },
  { id: 'cyberpunk', displayName: 'Cyberpunk', description: 'Neon on dark', defaultUserBubbleColor: 0xFF0A0A23, defaultUserTextColor: 0xFF00FF41, defaultAiBubbleColor: 0xFF1A0A2E, defaultAiTextColor: 0xFFFF00FF, defaultDialogueColor: 0xFF00FF41, defaultActionColor: 0xFFFF00FF, defaultBorderColor: 0xFF00FF41, defaultFontFamily: 'monospace', defaultBackgroundKey: 'futuristic_city', defaultBorderStyle: 'glitch' },
  { id: 'roman_empire', displayName: 'Roman Empire', description: 'Rich browns and warm cream', defaultUserBubbleColor: 0xFFEFE1C0, defaultUserTextColor: 0xFF4A2C1A, defaultAiBubbleColor: 0xFFEFE1C0, defaultAiTextColor: 0xFF3B2410, defaultDialogueColor: 0xFF9C1C1C, defaultActionColor: 0xFF6B4E1A, defaultBorderColor: 0xFF6B1414, defaultFontFamily: 'serif', defaultBackgroundKey: 'roman_market', defaultBorderStyle: 'greekKey' },
  { id: 'steampunk', displayName: 'Steampunk', description: 'Brass and copper tones', defaultUserBubbleColor: 0xFF3E2723, defaultUserTextColor: 0xFFFFD54F, defaultAiBubbleColor: 0xFF5D4037, defaultAiTextColor: 0xFFE0C9A6, defaultDialogueColor: 0xFFFFE082, defaultActionColor: 0xFFD7CCC8, defaultBorderColor: 0xFFFFD54F, defaultFontFamily: 'serif', defaultBackgroundKey: 'steampunk_bg', defaultBorderStyle: 'gear' },
];

const FONT_OPTIONS = ['sans-serif', 'serif', 'monospace'];

const BORDER_STYLES = ['vine', 'dualLine', 'glitch', 'wavy', 'shadow', 'greekKey', 'gear'];

const COLOR_LABELS: { key: keyof ChatThemeOverrides; label: string; defaultKey?: keyof ChatThemePreset }[] = [
  { key: 'userBubbleColor', label: 'Your bubble', defaultKey: 'defaultUserBubbleColor' },
  { key: 'userTextColor', label: 'Your text', defaultKey: 'defaultUserTextColor' },
  { key: 'aiBubbleColor', label: 'AI bubble', defaultKey: 'defaultAiBubbleColor' },
  { key: 'aiTextColor', label: 'AI text', defaultKey: 'defaultAiTextColor' },
  { key: 'dialogueColor', label: 'Dialogue (quoted)', defaultKey: 'defaultDialogueColor' },
  { key: 'actionColor', label: 'Actions (*text*)', defaultKey: 'defaultActionColor' },
  { key: 'borderColor', label: 'Border', defaultKey: 'defaultBorderColor' },
];

// Convert a Dart int color (0xAARRGGBB or 0xRRGGBB) to a CSS hex string.
function dartColorToCss(color: number): string {
  const hex = color.toString(16).padStart(8, '0');
  return '#' + hex.substring(2);
}

// Desktop paints decorative bubble borders (vine/gear/greekKey/glitch/…) with
// CustomPainters that CSS can't reproduce pixel-for-pixel. On web we approximate
// each with the theme's border color + a per-style CSS treatment. Returns
// [border, boxShadow]. `${color}NN` appends an alpha byte (color is #RRGGBB).
function webBorderCss(style: string, color: string): [string, string] {
  switch (style) {
    case 'dualLine':
      return [`3px double ${color}`, 'none'];
    case 'shadow':
      return [`1px solid ${color}`, `0 3px 12px ${color}66`];
    case 'wavy':
      return [`2px dashed ${color}`, 'none'];
    case 'glitch':
      return [`2px solid ${color}`, `2px 0 0 ${color}55, -2px 0 0 ${color}33`];
    case 'greekKey':
      return [`3px solid ${color}`, `inset 0 0 0 2px ${color}`];
    case 'gear':
      return [`2px solid ${color}`, `0 0 0 2px ${color}44`];
    case 'grid':
      return [`2px solid ${color}`, `inset 0 0 0 1px ${color}55`];
    default: // vine, scalloped, wave, and any unknown style
      return [`2px solid ${color}`, 'none'];
  }
}

/** Resolve theme overrides into CSS custom-property values for the chat container. */
export function resolveThemeColors(
  overrides: ChatThemeOverrides | null,
): Record<string, string> {
  if (!overrides?.themeId) return {};
  const preset = PRESETS.find((p) => p.id === overrides.themeId);
  if (!preset) return {};

  const userBubble = overrides.userBubbleColor
    ? `#${overrides.userBubbleColor}`
    : dartColorToCss(preset.defaultUserBubbleColor);
  const userText = overrides.userTextColor
    ? `#${overrides.userTextColor}`
    : dartColorToCss(preset.defaultUserTextColor);
  const aiBubble = overrides.aiBubbleColor
    ? `#${overrides.aiBubbleColor}`
    : dartColorToCss(preset.defaultAiBubbleColor);
  const aiText = overrides.aiTextColor
    ? `#${overrides.aiTextColor}`
    : dartColorToCss(preset.defaultAiTextColor);
  const dialogue = overrides.dialogueColor
    ? `#${overrides.dialogueColor}`
    : dartColorToCss(preset.defaultDialogueColor);
  const action = overrides.actionColor
    ? `#${overrides.actionColor}`
    : dartColorToCss(preset.defaultActionColor);
  const border = overrides.borderColor
    ? `#${overrides.borderColor}`
    : preset.defaultBorderColor
      ? dartColorToCss(preset.defaultBorderColor)
      : dartColorToCss(preset.defaultUserTextColor);

  const vars: Record<string, string> = {
    '--chat-user-bubble': userBubble,
    '--chat-user-text': userText,
    '--chat-ai-bubble': aiBubble,
    '--chat-ai-text': aiText,
    '--chat-dialogue': dialogue,
    '--chat-action': action,
    // Also set the base vars that the CSS .dlg/.act rules consume.
    '--dialogue': dialogue,
    '--action': action,
    '--chat-border': border,
  };
  if (overrides.fontFamily || preset.defaultFontFamily) {
    vars['--chat-font'] = overrides.fontFamily ?? preset.defaultFontFamily;
  }
  // Per-chat background scene (parity with desktop). The app's web server serves
  // these from the shared assets/backgrounds dir as /backgrounds/<key>.png; the
  // CSS layers a dark veil over it (matching the desktop 0.45 black overlay) so
  // message text stays readable.
  const bgKey = overrides.backgroundKey ?? preset.defaultBackgroundKey;
  if (bgKey) {
    vars['--chat-bg-image'] = `url('/backgrounds/${bgKey}.png')`;
  }
  // Decorative bubble border (approximated from the desktop painters).
  const borderStyle = overrides.borderStyle ?? preset.defaultBorderStyle;
  const [bubbleBorder, bubbleShadow] = webBorderCss(borderStyle, border);
  vars['--chat-bubble-border'] = bubbleBorder;
  vars['--chat-bubble-shadow'] = bubbleShadow;
  return vars;
}

export function ChatThemeSettings({ overrides, onSave }: {
  overrides: ChatThemeOverrides | null;
  onSave: (o: ChatThemeOverrides) => void;
}) {
  const [local, setLocal] = useState<ChatThemeOverrides>(overrides ?? {});
  useEffect(() => setLocal(overrides ?? {}), [overrides]);

  const selectedPreset = local.themeId
    ? PRESETS.find((p) => p.id === local.themeId) ?? null
    : null;

  const set = (patch: Partial<ChatThemeOverrides>) =>
    setLocal((prev) => ({ ...prev, ...patch }));

  return (
    <section className="card theme-settings">
      <h3>Chat theme</h3>
      <p className="muted small">Pick a visual theme for this chat. Customize individual colors below.</p>

      {/* Preset picker */}
      <div className="theme-presets">
        {/* "None" card */}
        <button
          className={`theme-preset-card${!local.themeId ? ' active' : ''}`}
          onClick={() => setLocal({})}
        >
          <span className="theme-preset-none">—</span>
          <span className="theme-preset-name">None</span>
        </button>
        {PRESETS.map((p) => (
          <button
            key={p.id}
            className={`theme-preset-card${local.themeId === p.id ? ' active' : ''}`}
            onClick={() => set({ themeId: p.id })}
          >
            <span className="theme-preset-swatches">
              <span className="theme-swatch" style={{ backgroundColor: dartColorToCss(p.defaultUserBubbleColor) }} />
              <span className="theme-swatch" style={{ backgroundColor: dartColorToCss(p.defaultAiBubbleColor) }} />
            </span>
            <span className="theme-preset-name">{p.displayName}</span>
            <span className="theme-preset-style">{p.defaultBorderStyle}</span>
          </button>
        ))}
      </div>

      {/* Customization fields (only when a preset is selected) */}
      {selectedPreset && <>
        <h4 className="section-label">Colors</h4>
        <div className="color-rows">
          {COLOR_LABELS.map((c) => {
            const val = local[c.key];
            const defaultVal = c.defaultKey && selectedPreset[c.defaultKey] != null
              ? dartColorToCss(selectedPreset[c.defaultKey] as number)
              : dartColorToCss(selectedPreset.defaultUserBubbleColor);
            return (
              <label key={c.key} className="color-row">
                <span>{c.label}</span>
                <input
                  type="color"
                  value={val ? `#${val}` : defaultVal}
                  onChange={(e) => set({ [c.key]: e.target.value.substring(1).toUpperCase() })}
                />
                <button
                  className="ghost small"
                  onClick={() => set({ [c.key]: null })}
                  disabled={!val}
                  title="Reset to preset default"
                >↺</button>
              </label>
            );
          })}
        </div>

        <h4 className="section-label">Font</h4>
        <select
          className="theme-select"
          value={local.fontFamily ?? selectedPreset.defaultFontFamily}
          onChange={(e) => set({ fontFamily: e.target.value === selectedPreset.defaultFontFamily ? null : e.target.value })}
        >
          {FONT_OPTIONS.map((f) => (
            <option key={f} value={f}>{f}</option>
          ))}
        </select>

        <h4 className="section-label">Border style</h4>
        <select
          className="theme-select"
          value={local.borderStyle ?? selectedPreset.defaultBorderStyle}
          onChange={(e) => set({ borderStyle: e.target.value === selectedPreset.defaultBorderStyle ? null : e.target.value })}
        >
          {BORDER_STYLES.map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
      </>}

      <div className="theme-actions">
        <button className="primary" onClick={() => onSave(local)}>Save theme</button>
        {local.themeId && (
          <button className="ghost" onClick={() => setLocal({})}>Remove theme</button>
        )}
      </div>
    </section>
  );
}
