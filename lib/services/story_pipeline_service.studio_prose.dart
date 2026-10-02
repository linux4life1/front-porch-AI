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

part of 'story_pipeline_service.dart';

/// Studio prose: write one beat, check it against the beat before it, and
/// patch only the lines that broke continuity.
extension StoryPipelineStudioProse on StoryPipelineService {
  /// A beat shorter than this is a refusal or a stub, not prose.
  static const _minBeatWords = 60;

  /// More banned phrases than this in one beat earns a cleanup call.
  static const _bannedTolerance = 2;

  Future<String> _loreFor(
    StoryProject project,
    int act,
    int index,
    int beat,
  ) async {
    final scene = project.scenes[act]![index];
    final plan = project.beats[StoryProjectShape.sceneKey(act, index)]![beat];
    final hits = await _loreIndex.search(
      '${scene.title}. ${scene.location}. ${plan.description}',
      StoryLoreIndex.knownAt(project, act, index),
      limit: 4,
    );
    return hits.map((h) => '- ${h.entry.topic}: ${h.entry.detail}').join('\n');
  }

  /// Write beat [beat] of scene ([act], [index]). [directive] is an extra
  /// instruction from the user or the Director for this one beat.
  Future<void> _studioWriteBeat(
    StoryProject project,
    int act,
    int index,
    int beat, {
    String directive = '',
  }) async {
    _isRunning = true;
    final key = StoryProjectShape.sceneKey(act, index);
    try {
      // Reads stay inside the try: only `finally` clears `_isRunning`, and a
      // stale index (a deep link, a beat list that just changed) must not
      // latch the flag on.
      final beats = project.beats[key];
      final scenes = project.scenes[act];
      if (beats == null ||
          scenes == null ||
          index < 0 ||
          index >= scenes.length ||
          beat < 0 ||
          beat >= beats.length) {
        _setStatus('Writing', 'That beat is no longer part of this scene.');
        return;
      }
      final label = project.sceneLabel(act, index);
      final stage = 'Writing $label · beat ${beat + 1}';
      final previousProse = _proseBefore(project, act, index, beat);
      final lore = await _loreFor(project, act, index, beat);
      final small = project.promptTier == PromptTier.smallLocal;

      String writePrompt(String? previous, String? feedback) =>
          StudioProsePrompts.write(
            project,
            act,
            index,
            beat,
            previousProse: previousProse,
            lore: lore,
            directive: directive,
            previous: previous,
            feedback: feedback,
          );

      final raw = await _agent(
        project,
        stage: stage,
        status: 'Writing beat ${beat + 1} of ${beats.length}…',
        role: StoryRole.prose,
        params: StoryStageParams.prose,
        maxLength: small ? 2048 : 3072,
        attempts: 2,
        validate: (output) =>
            countWords(StudioParseProse.prose(output)) < _minBeatWords
            ? 'The passage is far too short. Write the full beat, about '
                  '${StoryPacing.wordsPerBeat} words, inside <prose_text>.'
            : null,
        prompt: writePrompt,
      );
      final draft = StudioParseProse.prose(raw);
      var text = draft;
      ContinuityFix? fix;

      if (project.reviewEnabled) {
        _setStatus(stage, 'Checking continuity…');
        final check = await _call(
          StudioProsePrompts.continuityReview(
            project,
            act,
            index,
            beat,
            previousProse: previousProse,
            prose: text,
          ),
          maxLength: 1536,
          project: project,
          role: StoryRole.review,
          label: 'Continuity $label · beat ${beat + 1}',
        );
        final verdict = StoryReview.parse(check.text);
        check.entry
          ..verdict = verdict.pass ? 'PASS' : 'FAIL'
          ..note = verdict.feedback;
        await _log(project, check.entry);
        if (!verdict.pass && verdict.reasons.isNotEmpty) {
          final patched = await _studioFix(
            project,
            stage: stage,
            prose: text,
            previousProse: previousProse,
            verdict: verdict,
          );
          if (patched != null) {
            fix = patched.fix;
            text = patched.text;
          } else {
            // The patch could not be applied cleanly; one informed rewrite.
            _setStatus(stage, 'Rewriting the beat with the fixes…');
            final again = StudioParseProse.prose(
              await _callLLM(
                writePrompt(draft, verdict.feedback),
                maxLength: small ? 2048 : 3072,
                stage: StoryStageParams.prose,
                project: project,
                role: StoryRole.prose,
                label: '$stage (rewrite)',
              ),
            );
            if (countWords(again) >= _minBeatWords) text = again;
          }
        }
        text = await _studioScrubBanned(project, stage, text);
      }

      project.prose['$key-$beat'] = BeatProse(
        draft: draft,
        final_: text,
        fix: fix,
      );
      await _repository.saveProject(project);
      _setStatus(stage, 'Beat ${beat + 1} complete!');
    } catch (e) {
      _setStatus('Writing', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Ask for find → replace edits that fix [verdict]'s problems. Null when
  /// no edit landed or the "patch" rewrote the passage.
  Future<({String text, ContinuityFix fix})?> _studioFix(
    StoryProject project, {
    required String stage,
    required String prose,
    required String previousProse,
    required ReviewVerdict verdict,
  }) async {
    _setStatus(stage, 'Patching a continuity slip…');
    final call = await _call(
      StudioProsePrompts.fix(
        prose: prose,
        problems: verdict.feedback,
        previousProse: previousProse,
      ),
      maxLength: 1536,
      stage: StoryStageParams.editing,
      project: project,
      role: StoryRole.review,
      label: '$stage (continuity fix)',
    );
    final report = StoryEdits.apply(prose, StoryEdits.parse(call.text));
    final ok =
        report.changed &&
        StoryEdits.changeRatio(prose, report.text) <= StoryEdits.maxChangeRatio;
    call.entry
      ..verdict = ok ? 'PASS' : 'FAIL'
      ..note = ok
          ? '${report.applied.length} edit(s) applied.'
          : 'No usable edit (${report.failed.length} could not be placed).';
    await _log(project, call.entry);
    if (!ok) return null;
    return (
      text: report.text,
      fix: ContinuityFix(
        reason:
            (verdict.problems.isNotEmpty ? verdict.problems : verdict.reasons)
                .join(' '),
        before: prose,
        edits: report.applied,
      ),
    );
  }

  /// Replace worn-out phrases when a beat leans on more than a couple.
  Future<String> _studioScrubBanned(
    StoryProject project,
    String stage,
    String text,
  ) async {
    final banned = [...project.bannedPhrases, ...project.autoBannedPhrases];
    final found = StoryQuality.analyze(text, bannedPhrases: banned);
    if (found.bannedCount <= _bannedTolerance) return text;
    _setStatus(stage, 'Freshening worn-out phrases…');
    final call = await _call(
      StudioProsePrompts.bannedFix(prose: text, phrases: found.bannedMatches),
      maxLength: 1536,
      stage: StoryStageParams.editing,
      project: project,
      role: StoryRole.review,
      label: '$stage (phrase cleanup)',
    );
    final report = StoryEdits.apply(text, StoryEdits.parse(call.text));
    final ok =
        report.changed &&
        StoryEdits.changeRatio(text, report.text) <= StoryEdits.maxChangeRatio;
    call.entry
      ..verdict = ok ? 'PASS' : 'FAIL'
      ..note = '${report.applied.length} edit(s) applied.';
    await _log(project, call.entry);
    return ok ? report.text : text;
  }

  /// Write every unwritten beat of a scene, then archive what it
  /// established.
  Future<void> _studioWriteScene(
    StoryProject project,
    int act,
    int index,
  ) async {
    final key = StoryProjectShape.sceneKey(act, index);
    final count = project.beats[key]?.length ?? 0;
    if (count == 0) return;
    final scene = project.scenes[act]![index];

    project.autoBannedPhrases = StoryQuality.overusedPhrases(
      StoryQuality.recentProse(project, act, index),
      exclude: [...project.cast.map((c) => c.name), ...project.bannedPhrases],
    );

    var wrote = false;
    for (var beat = 0; beat < count; beat++) {
      if (project.beatText(act, index, beat) != null) continue;
      await _studioWriteBeat(project, act, index, beat);
      wrote = true;
    }
    if (project.beatsWritten(act, index) == count &&
        (wrote || scene.summary.isEmpty)) {
      await _studioArchive(project, act, index);
    }
  }

  /// Put a beat back the way it was before the continuity fix.
  Future<void> undoContinuityFix(
    StoryProject project,
    int act,
    int index,
    int beat,
  ) async {
    final prose = project.prose[StoryProjectShape.beatKey(act, index, beat)];
    final fix = prose?.fix;
    if (prose == null || fix == null) return;
    prose.final_ = fix.before;
    prose.fix = null;
    await _repository.saveProject(project);
    _notify();
  }
}
