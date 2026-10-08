// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, expect, it } from "vitest";
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { PromptRulesEditor } from "./PromptRulesEditor";
import type { PromptRules, PromptPreview } from "./packApi";

// This exercises the form callbacks, not the network adapter.
Object.defineProperty(HTMLDialogElement.prototype, "showModal", {
  configurable: true,
  value() {
    this.open = true;
  },
});
(
  globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
).IS_REACT_ACT_ENVIRONMENT = true;
let root: Root;
let host: HTMLDivElement;
afterEach(() => {
  act(() => root.unmount());
  host.remove();
});
const sleep = () =>
  act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 180));
  });
const click = (label: string) => {
  const b = [...host.querySelectorAll("button")].find(
    (b) => b.textContent === label,
  )!;
  act(() => b.click());
};
it("waits for current preview; ordered edits, use, explicit save and reset call separate form callbacks", async () => {
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  const initial: PromptRules = {
    prefix: "",
    suffix: "",
    replacements: [
      { find: "one", replace: "two", caseSensitive: true },
      { find: "two", replace: "three", caseSensitive: true },
    ],
  };
  let used: PromptRules | null = null;
  let saved: PromptRules | null = null;
  let close = 0;
  let resolvePreview: ((v: { previews: PromptPreview[] }) => void) | null =
    null;
  const loadPreview = async (_: unknown) =>
    new Promise<{ previews: PromptPreview[] }>((resolve) => {
      resolvePreview = resolve;
    });
  act(() =>
    root.render(
      createElement(PromptRulesEditor, {
        rules: initial,
        prompt: "one",
        full: false,
        activePack: false,
        loadPreview,
        loadDefaults: async () => ({
          prefix: "global",
          suffix: "",
          replacements: [],
        }),
        onSaveDefaults: async (rules) => {
          saved = rules;
          return rules;
        },
        onUse: async (rules) => {
          used = rules;
        },
        onClose: () => {
          close++;
        },
      }),
    ),
  );
  const use = () =>
    [...host.querySelectorAll("button")].find(
      (b) => b.textContent === "Use for this pack",
    )!;
  expect(use().disabled).toBe(true);
  await sleep();
  await act(async () => {
    resolvePreview!({
      previews: [{ emotion: "joy", original: "one", effective: "three" }],
    });
  });
  expect(use().disabled).toBe(false);
  act(() =>
    host
      .querySelector<HTMLButtonElement>(
        '[aria-label="Move replacement 1 down"]',
      )!
      .click(),
  );
  expect(use().disabled).toBe(true);
  await sleep();
  await act(async () => {
    resolvePreview!({
      previews: [{ emotion: "joy", original: "one", effective: "two" }],
    });
  });
  click("Save as global defaults");
  await act(async () => {});
  expect(saved!.replacements[0].find).toBe("two");
  expect(used).toBe(null);
  click("Reset to global defaults");
  await act(async () => {});
  expect(
    (host.querySelector('[aria-label="Prefix"]') as HTMLTextAreaElement).value,
  ).toBe("global");
  expect(host.textContent).not.toContain("Global defaults saved.");
  expect(use().disabled).toBe(true);
  await sleep();
  await act(async () => {
    resolvePreview!({
      previews: [{ emotion: "joy", original: "one", effective: "global one" }],
    });
  });
  click("Use for this pack");
  await act(async () => {});
  expect(used!.prefix).toBe("global");
  expect(close).toBe(1);
  expect(initial.replacements[0].find).toBe("one");
});
