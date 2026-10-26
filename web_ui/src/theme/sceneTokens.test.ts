// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { beforeEach, describe, expect, it } from 'vitest';
import { parseSceneWire, sceneCssVars } from './sceneTokens';
import { currentThemeMode, receiveThemeWire, saveThemeChoice } from './appTheme';

const dark = {
  layers: ['rgba(10, 14, 20, 0.05)', 'rgba(18, 42, 74, 0.32)', 'rgba(201, 206, 211, 0.22)', 'rgba(158, 197, 232, 0.08)'],
  haze: 0.8,
  hazeCentre: 'rgba(205, 210, 216, 0.128)',
  hazeEdge: 'rgba(205, 210, 216, 0.4)',
};
const light = {
  layers: ['rgba(10, 14, 20, 0.023)', 'rgba(18, 42, 74, 0.144)'],
  haze: 0.36,
  hazeCentre: 'rgba(205, 210, 216, 0.029)',
  hazeEdge: 'rgba(205, 210, 216, 0.09)',
};
const wire = { daypart: 'night', condition: 'fog', temp: 'cold', dark, light };

describe('scene wire', () => {
  it('accepts what the desktop sends and nothing else', () => {
    expect(parseSceneWire(wire)).toEqual(wire);
    expect(parseSceneWire(null)).toBeNull();
    expect(parseSceneWire({ ...wire, dark: { ...dark, layers: ['red'] } })).toBeNull();
    expect(parseSceneWire({ ...wire, light: { ...light, haze: 'thick' } })).toBeNull();
    expect(parseSceneWire({ ...wire, dark: { ...dark, hazeEdge: 'url(x)' } })).toBeNull();
    expect(parseSceneWire({ ...wire, daypart: 7 })).toBeNull();
  });

  it('rejects a wire missing either brightness', () => {
    const { light: _l, ...noLight } = wire;
    const { dark: _d, ...noDark } = wire;
    expect(parseSceneWire(noLight)).toBeNull();
    expect(parseSceneWire(noDark)).toBeNull();
    // The single-mode shape an earlier build sent is not a scene either.
    expect(parseSceneWire({ daypart: 'night', condition: 'fog', temp: 'cold', ...dark })).toBeNull();
  });

  it('paints the desktop order: haze on top, shade at the bottom', () => {
    const vars = sceneCssVars(parseSceneWire(wire), 'dark');
    const list = vars['--scene-layers'];
    expect(list.startsWith('radial-gradient(circle at center, rgba(205, 210, 216, 0.128) 15%')).toBe(true);
    expect(list.endsWith('linear-gradient(rgba(10, 14, 20, 0.05), rgba(10, 14, 20, 0.05))')).toBe(true);
    expect(list.indexOf('rgba(158, 197, 232, 0.08)')).toBeLessThan(list.indexOf('rgba(18, 42, 74, 0.32)'));
    expect(Object.keys(vars)).toEqual(['--scene-layers']);
  });

  it('paints nothing for no scene or an empty one', () => {
    expect(sceneCssVars(null, 'dark')).toEqual({});
    const none = { layers: [], haze: 0, hazeCentre: '#000000', hazeEdge: '#000000' };
    expect(
      sceneCssVars({ daypart: 'late_morning', condition: 'clear', temp: 'mild', dark: none, light: none }, 'light'),
    ).toEqual({});
  });
});

describe('scene in the mode this page paints', () => {
  beforeEach(() => {
    localStorage.clear();
    // The desktop is dark; this device may choose otherwise.
    receiveThemeWire({ mode: 'dark', dark: { bg: '#1b1611' }, light: { bg: '#f8f4ed' } });
  });

  const painted = () => sceneCssVars(parseSceneWire(wire), currentThemeMode())['--scene-layers'];

  it("paints the light washes under this device's Light choice", () => {
    saveThemeChoice('light');
    expect(currentThemeMode()).toBe('light');
    expect(painted()).toContain('rgba(18, 42, 74, 0.144)');
    expect(painted()).not.toContain('rgba(18, 42, 74, 0.32)');
  });

  it("paints the dark washes under this device's Dark choice", () => {
    saveThemeChoice('dark');
    expect(currentThemeMode()).toBe('dark');
    expect(painted()).toContain('rgba(18, 42, 74, 0.32)');
    expect(painted()).not.toContain('rgba(18, 42, 74, 0.144)');
  });

  it("follows the desktop's mode by default", () => {
    saveThemeChoice('desktop');
    expect(currentThemeMode()).toBe('dark');
    receiveThemeWire({ mode: 'light', dark: { bg: '#1b1611' }, light: { bg: '#f8f4ed' } });
    expect(currentThemeMode()).toBe('light');
  });
});
