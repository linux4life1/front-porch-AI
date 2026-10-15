// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The most of the creator's interview transcript any prompt or stamp reads.
/// Twelve questions (the cap the editor allows) at about 1,150 characters
/// each with their answers run past 12,000, and the cut falls on the tail:
/// the appearance answer, which the image prompt and the outfit read, would
/// go first. 16,000 keeps every answer whole; this only stops a runaway
/// model from flooding a prompt. Every reader goes through [capInterview].
const kInterviewTranscriptCap = 16000;

/// [transcript] cut to [kInterviewTranscriptCap], with `...` when cut.
String capInterview(String transcript) =>
    transcript.length > kInterviewTranscriptCap
    ? '${transcript.substring(0, kInterviewTranscriptCap)}...'
    : transcript;
