// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
// @vitest-environment jsdom
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { IntensityPicker, SlotIntensityEditor } from './ExpressionIntensity';
import type { PackSlot, PackView } from './packApi';
let root: Root | undefined;
let host: HTMLDivElement;
function render(value: ReactNode) {
  host = document.createElement('div'); document.body.append(host);
  root = createRoot(host); act(() => root!.render(value));
}
afterEach(() => {act(() => root?.unmount()); host?.remove();});
describe('expression intensity controls', () => {
  it('keeps the disabled pack control visible and names the legacy default', () => {
    render(<IntensityPicker value="current" disabled onChange={vi.fn()} />);
    const select = host.querySelector('select')!;
    expect(select.disabled).toBe(true);
    expect(select.getAttribute('aria-label')).toBe('Expression intensity');
    expect(select.selectedOptions[0].textContent).toBe('Default (original)');
  });
  it('follows the pack until overridden and preserves custom wording', () => {
    const slot: PackSlot = {emotion:'anger',state:'failed',keep:true,error:null,prompt:'my exact wording',customPrompt:true};
    const pack: PackView = {running:false,intensity:'subtle',mode:'edit',origin:'phone',characterId:'synthetic',characterName:'Synthetic',total:1,done:0,kept:0,imported:null,canImport:false,slots:[slot]};
    render(<SlotIntensityEditor slot={slot} pack={pack} disabled={false} onBegin={vi.fn()} onDone={vi.fn()} onEnd={vi.fn()} />);
    const select=host.querySelector('select')!;
    expect(select.value).toBe('pack');
    act(() => {select.value='strong';select.dispatchEvent(new Event('change',{bubbles:true}));});
    expect(select.value).toBe('strong');
    expect(host.querySelector('textarea')!.value).toBe('my exact wording');
    expect(host.textContent).toContain('A custom prompt overrides intensity');
    act(() => {select.value='pack';select.dispatchEvent(new Event('change',{bubbles:true}));});
    expect(select.value).toBe('pack');
  });
});
