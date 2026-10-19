// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The web leaf-mirror must agree with the Dart engine
// (lib/services/chat/chat_search_engine.dart) on every locked semantic:
// plain substring, word-anchored globs, escaped stars, regex mode, case
// toggling, and image-span invisibility. Same matrix as the engine test.

import { describe, expect, it } from 'vitest';
import { compileFindQuery, findRanges } from './chatSearch';

const r = (text: string, q: string, opts?: { regex?: boolean; caseSensitive?: boolean }) =>
  findRanges(text, compileFindQuery(q, opts));

describe('compileFindQuery', () => {
  it('no star is a plain needle', () => {
    const spec = compileFindQuery('lantern');
    expect(spec.bad).toBe(false);
    expect(spec.mode).toBe('plain');
    expect(spec.needle).toBe('lantern');
    expect(spec.wordBounded).toBe(false);
  });

  it('\\* is a literal star, not a glob', () => {
    const spec = compileFindQuery('\\*');
    expect(spec.mode).toBe('plain');
    expect(spec.needle).toBe('*');
  });

  it('invalid regex reports bad, never throws', () => {
    expect(compileFindQuery('lantern[', { regex: true }).bad).toBe(true);
  });
});

describe('plain matching', () => {
  it('hits never overlap, so marks cannot repeat text', () => {
    expect(r('aaaa', 'aa')).toEqual([[0, 2], [2, 4]]);
    expect(r('aaa', 'aa')).toEqual([[0, 2]]);
  });

  it('a case fold that changes length does not shift later hits', () => {
    // 'İ'.toLowerCase() is two code units in JS; ranges index the original.
    expect(r('İstanbul lantern', 'lantern')).toEqual([[9, 16]]);
  });

  it('substring counts, case-insensitive by default', () => {
    expect(r('A lantern answers. Lantern-light and dogwood.', 'lantern')).toHaveLength(2);
  });

  it('case-sensitive needle misses other case', () => {
    expect(r('a lantern lit', 'Lantern', { caseSensitive: true })).toHaveLength(0);
    expect(r('a Lantern lit', 'Lantern', { caseSensitive: true })).toHaveLength(1);
  });
});

describe('word-anchored glob', () => {
  it('*dog matches words ENDING in dog', () => {
    expect(r('a bulldog and a dog.', '*dog')).toHaveLength(2);
    expect(r('the dogs and dogwood', '*dog')).toHaveLength(0);
  });

  it('cook* matches words STARTING with cook', () => {
    expect(r('cookware and cooking and cook.', 'cook*')).toHaveLength(3);
    expect(r('undercook it', 'cook*')).toHaveLength(0);
  });

  it('middle star stays inside one word', () => {
    expect(r('pure cookware', 'cook*ware')).toHaveLength(1);
    expect(r('cooking ware', 'cook*ware')).toHaveLength(0);
  });

  it('star spans unicode letters, not spaces', () => {
    expect(r('pure caféine', 'caf*e')).toHaveLength(1);
    expect(r('caf éine', 'caf*e')).toHaveLength(0);
  });
});

describe('regex mode', () => {
  it('span crosses spaces', () => {
    const spec = compileFindQuery('lantern.*storm', { regex: true });
    const text = 'a lantern answers a storm.';
    const hits = findRanges(text, spec);
    expect(hits).toHaveLength(1);
    expect(text.slice(hits[0][0], hits[0][1])).toBe('lantern answers a storm');
  });

  it('glob star in regex mode is a bad pattern input guard: raw regex compiles', () => {
    // In regex mode `*dog` is raw regex (a lone quantifier) → bad.
    expect(compileFindQuery('*dog', { regex: true }).bad).toBe(true);
  });
});

describe('image spans are invisible', () => {
  it('matches inside ![alt](url) are dropped', () => {
    expect(r('![lantern photo](https://x.io/l.png) no match here', 'lantern')).toHaveLength(0);
    expect(r('a lantern ![lantern](https://x.io/l.png)', 'lantern')).toHaveLength(1);
  });
});
