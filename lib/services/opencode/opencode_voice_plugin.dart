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
/// so the idle hook cannot deadlock.
const kWaifuVoicePluginSource = r'''
export default {
  id: "waifu-voice",
  server: async function waifuVoice({ client }) {
    const g = globalThis
    if (!g.__waifuVoiceWrapping) g.__waifuVoiceWrapping = new Set()
    const wrapping = g.__waifuVoiceWrapping
    async function lastAssistantAgent(sessionID) {
      try {
        const res = await client.session.messages({ path: { id: sessionID } })
        const list = (res && res.data) || res || []
        for (let i = list.length - 1; i >= 0; i--) {
          const info = list[i].info || list[i]
          if (info && info.role === "assistant") return info.agent || ""
        }
      } catch (_) {}
      return ""
    }
    return {
      event: async ({ event }) => {
        if (!event || event.type !== "session.idle") return
        const props = event.properties || event.data || {}
        const sessionID = props.sessionID || props.sessionId || ""
        if (!sessionID) return
        if (wrapping.has(sessionID)) {
          const agent = await lastAssistantAgent(sessionID)
          if (agent === "voice") wrapping.delete(sessionID)
          return
        }
        wrapping.add(sessionID)
        const agent = await lastAssistantAgent(sessionID)
        if (agent === "voice") {
          wrapping.delete(sessionID)
          return
        }
        try {
          await client.session.promptAsync({
            path: { id: sessionID },
            body: {
              agent: "voice",
              parts: [
                {
                  type: "text",
                  text: "The coding turn finished. Speak as this character: what got done, and what is left for the user if anything. No tools.",
                },
              ],
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
