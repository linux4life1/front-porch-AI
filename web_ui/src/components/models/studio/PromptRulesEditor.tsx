// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef, useState } from "react";
import { ApiError } from "../../../api/client";
import {
  fetchPromptDefaults,
  previewPrompts,
  savePromptDefaults,
  type PromptRules,
  type PromptPreview,
} from "./packApi";

export function PromptRulesEditor(props: {
  rules: PromptRules;
  prompt: string;
  full: boolean;
  activePack: boolean;
  onUse: (rules: PromptRules) => Promise<void>;
  onClose: () => void;
  loadPreview?: typeof previewPrompts;
  loadDefaults?: typeof fetchPromptDefaults;
  onSaveDefaults?: typeof savePromptDefaults;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [accepted, setAccepted] = useState<PromptRules | null>(null);
  const [rules, setRules] = useState<PromptRules>(() =>
    structuredClone(props.rules),
  );
  const [previews, setPreviews] = useState<PromptPreview[]>([]);
  const [problem, setProblem] = useState("");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  useEffect(() => {
    setStatus("");
  }, [rules]);
  useEffect(() => {
    const previous = document.activeElement;
    dialog.current?.showModal();
    return () => {
      if (previous instanceof HTMLElement) previous.focus();
    };
  }, []);
  useEffect(() => {
    let live = true;
    const timer = window.setTimeout(() => {
      (props.loadPreview ?? previewPrompts)({
        promptRules: rules,
        prompt: props.prompt,
        set: props.full ? "full" : "starter",
        activePack: props.activePack,
      })
        .then((result) => {
          if (live) {
            setPreviews(result.previews);
            setAccepted(rules);
            setProblem("");
          }
        })
        .catch((e: unknown) => {
          if (live) {
            setAccepted(null);
            setPreviews([]);
            setProblem(
              e instanceof ApiError ? e.message : "Could not preview prompts.",
            );
          }
        });
    }, 150);
    return () => {
      live = false;
      window.clearTimeout(timer);
    };
  }, [rules, props.prompt, props.full, props.activePack, props.loadPreview]);
  const change = (
    i: number,
    value: Partial<PromptRules["replacements"][number]>,
  ) =>
    setRules((r) => ({
      ...r,
      replacements: r.replacements.map((row, n) =>
        n === i ? { ...row, ...value } : row,
      ),
    }));
  const move = (i: number, next: number) =>
    setRules((r) => {
      const rows = [...r.replacements];
      const row = rows.splice(i, 1)[0];
      rows.splice(next, 0, row);
      return { ...r, replacements: rows };
    });
  const action = async (run: () => Promise<void>) => {
    setBusy(true);
    setStatus("");
    try {
      await run();
    } catch (e: unknown) {
      setProblem(
        e instanceof ApiError ? e.message : "Could not update prompt rules.",
      );
    } finally {
      setBusy(false);
    }
  };
  const invalid = accepted !== rules;
  return (
    <dialog
      ref={dialog}
      aria-label="Prompt rules"
      className="fp-prompt-rules"
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) props.onClose();
      }}
    >
      <h3>Prompt rules</h3>
      <p>
        Positive prompts only. Replacements run in order, then prefix and suffix
        are added. Prompts edited for a single expression keep their own
        wording.
      </p>
      <label>
        Text before each prompt
        <textarea
          disabled={busy}
          aria-label="Prefix"
          maxLength={4096}
          value={rules.prefix}
          onChange={(e) => setRules((r) => ({ ...r, prefix: e.target.value }))}
        />
      </label>
      <label>
        Text after each prompt
        <textarea
          disabled={busy}
          aria-label="Suffix"
          maxLength={4096}
          value={rules.suffix}
          onChange={(e) => setRules((r) => ({ ...r, suffix: e.target.value }))}
        />
      </label>
      {rules.replacements.map((row, i) => (
        <div key={i}>
          <label>
            Find
            <input
              disabled={busy}
              aria-label={`Find ${i + 1}`}
              maxLength={2048}
              value={row.find}
              onChange={(e) => change(i, { find: e.target.value })}
            />
          </label>
          <label>
            Replace with
            <input
              disabled={busy}
              aria-label={`Replace with ${i + 1}`}
              maxLength={2048}
              value={row.replace}
              onChange={(e) => change(i, { replace: e.target.value })}
            />
          </label>
          <label>
            <input
              disabled={busy}
              type="checkbox"
              checked={row.caseSensitive}
              onChange={(e) => change(i, { caseSensitive: e.target.checked })}
            />
            Case sensitive
          </label>
          <button
            type="button"
            aria-label={`Move replacement ${i + 1} up`}
            disabled={busy || i === 0}
            onClick={() => move(i, i - 1)}
          >
            Up
          </button>
          <button
            type="button"
            aria-label={`Move replacement ${i + 1} down`}
            disabled={busy || i === rules.replacements.length - 1}
            onClick={() => move(i, i + 1)}
          >
            Down
          </button>
          <button
            type="button"
            aria-label={`Delete replacement ${i + 1}`}
            disabled={busy}
            onClick={() =>
              setRules((r) => ({
                ...r,
                replacements: r.replacements.filter((_, n) => n !== i),
              }))
            }
          >
            Delete
          </button>
        </div>
      ))}
      <button
        type="button"
        disabled={busy || rules.replacements.length >= 32}
        onClick={() =>
          setRules((r) => ({
            ...r,
            replacements: [
              ...r.replacements,
              { find: "", replace: "", caseSensitive: true },
            ],
          }))
        }
      >
        Add replacement
      </button>
      {problem ? <p role="alert">{problem}</p> : null}
      {status ? <p role="status">{status}</p> : null}
      {previews.map((p) => (
        <details key={p.emotion}>
          <summary>{p.emotion}</summary>
          <p>Original</p>
          <pre>{p.original}</pre>
          <p>Effective</p>
          <pre>{p.effective}</pre>
        </details>
      ))}
      <button
        type="button"
        disabled={busy}
        onClick={() =>
          void action(async () => {
            setRules(await (props.loadDefaults ?? fetchPromptDefaults)());
          })
        }
      >
        Reset to global defaults
      </button>
      <button
        type="button"
        disabled={busy || invalid}
        onClick={() =>
          void action(async () => {
            await (props.onSaveDefaults ?? savePromptDefaults)(rules);
            setStatus("Global defaults saved.");
          })
        }
      >
        Save as global defaults
      </button>
      <button type="button" disabled={busy} onClick={props.onClose}>
        Cancel
      </button>
      <button
        type="button"
        disabled={busy || invalid}
        onClick={() =>
          void action(async () => {
            await props.onUse(rules);
            props.onClose();
          })
        }
      >
        Use for this pack
      </button>
    </dialog>
  );
}
