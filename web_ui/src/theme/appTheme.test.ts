// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { beforeEach, describe, expect, it } from 'vitest';
import {
  applyCachedTheme, loadThemeWire, parseThemeWire, receiveThemeWire, saveThemeChoice,
} from './appTheme';

const wire = {
  mode: 'light',
  dark: { bg: '#1b1611', surface: '#1f1913' },
  light: { bg: '#f8f4ed', surface: '#f0ebe3' },
};

const themeRule = () => document.getElementById('fpai-theme')?.textContent ?? '';

describe('app theme from the desktop', () => {
  beforeEach(() => {
    localStorage.clear();
    document.getElementById('fpai-theme')?.remove();
    delete document.documentElement.dataset.theme;
    document.head.innerHTML = '<meta name="theme-color" content="#1f1913">';
  });

  it("paints the desktop's mode and remembers it for the next load", () => {
    receiveThemeWire(wire);
    expect(document.documentElement.dataset.theme).toBe('light');
    expect(themeRule()).toContain('--bg: #f8f4ed;');
    expect(document.querySelector('meta[name="theme-color"]')?.getAttribute('content')).toBe('#f0ebe3');

    document.getElementById('fpai-theme')?.remove();
    applyCachedTheme();
    expect(themeRule()).toContain('--bg: #f8f4ed;');
  });

  it("a device's own choice wins over the desktop's mode, from both maps", () => {
    receiveThemeWire(wire);
    saveThemeChoice('dark');
    expect(document.documentElement.dataset.theme).toBe('dark');
    expect(themeRule()).toContain('--bg: #1b1611;');
    receiveThemeWire({ ...wire, mode: 'dark' });
    saveThemeChoice('desktop');
    expect(document.documentElement.dataset.theme).toBe('dark');
  });

  it('ignores a payload that is not a theme and keeps the last one', () => {
    receiveThemeWire(wire);
    expect(receiveThemeWire({ mode: 'sepia' })).toBeNull();
    expect(receiveThemeWire(undefined)).toBeNull();
    expect(loadThemeWire()?.mode).toBe('light');
    expect(parseThemeWire({ mode: 'dark', dark: { bg: 1 }, light: {} })).toBeNull();
  });

  it('never writes a token that could break out of the rule', () => {
    receiveThemeWire({ ...wire, light: { bg: 'red; } body { display: none', 'x}y': '#fff', ok: '#fff' } });
    expect(themeRule()).toBe(':root { --ok: #fff; }');
  });

  it('stays on the stylesheet defaults until the desktop has spoken', () => {
    saveThemeChoice('light');
    expect(document.documentElement.dataset.theme).toBe('dark');
    expect(document.getElementById('fpai-theme')).toBeNull();
  });
});
