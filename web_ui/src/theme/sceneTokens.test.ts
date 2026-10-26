// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { parseSceneWire, sceneCssVars } from './sceneTokens';

const wire = {
  daypart: 'night',
  condition: 'fog',
  temp: 'cold',
  layers: ['rgba(10, 14, 20, 0.05)', 'rgba(18, 42, 74, 0.32)', 'rgba(201, 206, 211, 0.22)', 'rgba(158, 197, 232, 0.08)'],
  haze: 0.85,
  hazeCentre: 'rgba(205, 210, 216, 0.128)',
  hazeEdge: 'rgba(205, 210, 216, 0.383)',
};

describe('scene wire', () => {
  it('accepts what the desktop sends and nothing else', () => {
    expect(parseSceneWire(wire)).toEqual(wire);
    expect(parseSceneWire(null)).toBeNull();
    expect(parseSceneWire({ ...wire, layers: ['red'] })).toBeNull();
    expect(parseSceneWire({ ...wire, haze: 'thick' })).toBeNull();
    expect(parseSceneWire({ ...wire, hazeEdge: 'url(x)' })).toBeNull();
    expect(parseSceneWire({ ...wire, daypart: 7 })).toBeNull();
  });

  it('paints the desktop order: haze on top, shade at the bottom', () => {
    const vars = sceneCssVars(parseSceneWire(wire));
    const list = vars['--scene-layers'];
    expect(list.startsWith('radial-gradient(')).toBe(true);
    expect(list.endsWith('linear-gradient(rgba(10, 14, 20, 0.05), rgba(10, 14, 20, 0.05))')).toBe(true);
    expect(list.indexOf('rgba(158, 197, 232, 0.08)')).toBeLessThan(list.indexOf('rgba(18, 42, 74, 0.32)'));
    expect(Object.keys(vars)).toEqual(['--scene-layers']);
  });

  it('paints nothing for no scene or an empty one', () => {
    expect(sceneCssVars(null)).toEqual({});
    expect(
      sceneCssVars({ daypart: 'late_morning', condition: 'clear', temp: 'mild', layers: [], haze: 0, hazeCentre: '#000000', hazeEdge: '#000000' }),
    ).toEqual({});
  });
});
