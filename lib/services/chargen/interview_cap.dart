// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The most of the creator's interview transcript any prompt or stamp reads.
/// One answer runs about 900 characters with its question, so every answer
/// fits whole; this only stops a runaway model from flooding a prompt.
/// Every reader of the transcript goes through [capInterview].
const kInterviewTranscriptCap = 12000;

/// [transcript] cut to [kInterviewTranscriptCap], with `...` when cut.
String capInterview(String transcript) =>
    transcript.length > kInterviewTranscriptCap
    ? '${transcript.substring(0, kInterviewTranscriptCap)}...'
    : transcript;
