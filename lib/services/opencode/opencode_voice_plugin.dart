// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

/// OpenCode 1.18 path plugin: default export `{ id, server }`.
/// Coding idle starts the no-tool `voice` agent once. Claim the session
/// before any await so a duplicate idle cannot prompt twice. promptAsync
/// so the idle hook cannot deadlock. An aborted coding message gets no
/// wrap-up, so a send right after Stop never sees a late voice turn.
///
/// The wrap-up prompt carries data only: a recap of what the turn did and
/// the character's last few spoken lines. How to speak lives in the voice
/// agent's own prompt (`kWaifuVoicePreamble`), so there is one source.
const kWaifuVoicePluginSource = r'''
function waifuTurnRecap(list) {
  const msgs = Array.isArray(list) ? list : []
  let start = 0
  for (let i = msgs.length - 1; i >= 0; i--) {
    const info = msgs[i].info || msgs[i]
    if (info && info.role === "user") { start = i + 1; break }
  }
  const changed = [], ran = [], failed = []
  for (const m of msgs.slice(start)) {
    for (const p of m.parts || []) {
      if (!p || p.type !== "tool") continue
      const st = p.state || {}
      const input = st.input || {}
      const what = String(input.filePath || input.path || input.command || st.title || "").trim()
      if (st.status === "error") failed.push(p.tool + (what ? " " + what : ""))
      else if (["edit", "write", "patch", "multiedit"].includes(p.tool) && what) changed.push(what)
      else if (p.tool === "bash" && what) ran.push(what)
    }
  }
  const said = []
  for (let i = start - 1; i >= 0 && said.length < 3; i--) {
    const info = msgs[i].info || msgs[i]
    if (!info || info.role !== "assistant" || info.agent !== "voice") continue
    const text = (msgs[i].parts || [])
      .filter((p) => p && p.type === "text" && p.text)
      .map((p) => p.text).join(" ").replace(/\s+/g, " ").trim()
    if (text) said.unshift(text.length > 300 ? text.slice(0, 299) + "…" : text)
  }
  const uniq = (a) => [...new Set(a)].slice(0, 8)
  const lines = ["Turn recap:"]
  lines.push(changed.length ? "Files changed: " + uniq(changed).join(", ") : "Files changed: none")
  if (ran.length) lines.push("Commands run: " + uniq(ran).join(" | "))
  if (failed.length) lines.push("Failed: " + uniq(failed).join(" | "))
  if (said.length) {
    lines.push("", "Your last lines to the user (match the voice, do not repeat them):")
    for (const s of said) lines.push("- " + s)
  }
  return lines.join("\n")
}

export default {
  id: "waifu-voice",
  server: async function waifuVoice({ client }) {
    const g = globalThis
    if (!g.__waifuVoiceWrapping) g.__waifuVoiceWrapping = new Set()
    const wrapping = g.__waifuVoiceWrapping
    async function messages(sessionID) {
      try {
        const res = await client.session.messages({ path: { id: sessionID } })
        return (res && res.data) || res || []
      } catch (_) {
        return []
      }
    }
    function lastAssistantAgent(list) {
      for (let i = list.length - 1; i >= 0; i--) {
        const info = list[i].info || list[i]
        if (!info || info.role !== "assistant") continue
        // Stop aborts the coding message. No wrap-up after the user said stop.
        const err = info.error || {}
        if (err.name === "MessageAbortedError") return "aborted"
        return info.agent || ""
      }
      return ""
    }
    return {
      event: async ({ event }) => {
        if (!event || event.type !== "session.idle") return
        const props = event.properties || event.data || {}
        const sessionID = props.sessionID || props.sessionId || ""
        if (!sessionID) return
        if (wrapping.has(sessionID)) {
          const agent = lastAssistantAgent(await messages(sessionID))
          if (agent === "voice" || agent === "aborted") wrapping.delete(sessionID)
          return
        }
        wrapping.add(sessionID)
        const list = await messages(sessionID)
        const agent = lastAssistantAgent(list)
        if (agent === "voice" || agent === "aborted") {
          wrapping.delete(sessionID)
          return
        }
        try {
          await client.session.promptAsync({
            path: { id: sessionID },
            body: {
              agent: "voice",
              parts: [{ type: "text", text: waifuTurnRecap(list) }],
            },
          })
        } catch (err) {
          wrapping.delete(sessionID)
          console.error("[waifu-voice]", err)
        }
      },
    }
  },
}
''';
