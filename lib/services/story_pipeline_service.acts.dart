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

/// Whole-act generation and Autopilot — the Generate-Act path that runs
/// Scene Weaver + Beat Director then writes combined prose beat-by-beat, plus
/// the end-to-end Autopilot orchestrator. Extracted verbatim from
/// `story_pipeline_service.dart` (Cluster H of the god-file split, minus the
/// pure `_getPreviousActsContext` context builder which moved to
/// `story/story_context.dart`) as a public-named extension (see the
/// ChatService-parts precedent — the structure/reader pages call
/// `generateFullAct`/`regenerateSceneProse`/`runAutopilot` directly).
extension StoryPipelineActs on StoryPipelineService {
  /// Generate a complete act end-to-end in minimal LLM calls:
  ///   1. Scene Weaver (scenes + beats in one call)
  ///   2. Combined prose for the entire act (one call)
  /// This reduces ~20+ calls per act down to just 2-3.
  Future<void> _quickFullAct(StoryProject project, int actIndex) async {
    _isRunning = true;
    final act = project.acts[actIndex];

    try {
      // Step 1: Generate scenes (always sequential — single call needed first)
      if (project.scenes[actIndex] == null ||
          project.scenes[actIndex]!.isEmpty) {
        _setStatus(
          'Act ${act.number}: Scenes',
          'Generating scenes for "${act.title}"...',
        );
        await _quickScenes(project, actIndex);
        // Every stage clears _isRunning in its own `finally`, but the act is
        // far from done — the prose phase below is the long part. Without
        // this re-arm the progress overlay vanishes and every Generate
        // button re-enables while the act is still being written.
        _isRunning = true;
      }

      final scenes = project.scenes[actIndex] ?? [];
      if (scenes.isEmpty) {
        throw Exception('No scenes generated for Act ${act.number}');
      }

      // Generate beats for each scene sequentially
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final sId = '$actIndex-$sceneIdx';
        if (project.beats[sId] == null || project.beats[sId]!.isEmpty) {
          _setStatus(
            'Act ${act.number}: Beats',
            'Planning beats for scene ${sceneIdx + 1}/${scenes.length}...',
          );
          await _quickBeats(project, actIndex, sceneIdx);
          _isRunning = true; // same stage-finally reset as above
        }
      }

      // Write prose for each scene sequentially (beats reference previous beats)
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        _setStatus(
          'Act ${act.number}: Writing',
          'Writing scene ${sceneIdx + 1}/${scenes.length}...',
        );
        await _writeSceneProseCombined(project, actIndex, sceneIdx);
      }

      _setStatus('Act ${act.number} Complete', 'Ready for review');
      await _repository.saveProject(project);
    } catch (e) {
      _setStatus('Error', 'Act ${act.number} failed: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Public method to regenerate prose for a single scene (after clearing old prose).
  Future<void> _quickRegenerateScene(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    _isRunning = true;
    _setStatus('Rewriting', 'Regenerating scene ${sceneIndex + 1} prose...');
    try {
      await _writeSceneProseCombined(project, actIndex, sceneIndex);
      _setStatus('Complete', 'Scene rewrite finished!');
    } catch (e) {
      _setStatus('Error', 'Scene rewrite failed: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Write prose for a scene beat-by-beat with individual LLM calls.
  Future<void> _writeSceneProseCombined(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    final sId = '$actIndex-$sceneIndex';
    final scenes = project.scenes[actIndex] ?? [];
    if (sceneIndex >= scenes.length) return;
    final scene = scenes[sceneIndex];
    final beats = project.beats[sId] ?? [];
    if (beats.isEmpty) return;

    // Skip if all beats already have prose
    final allWritten = beats.asMap().entries.every((e) {
      final bId = '$sId-${e.key}';
      return project.prose[bId]?.final_ != null;
    });
    if (allWritten) return;

    final act = project.acts[actIndex];
    final tier = project.promptTier;

    final castInfo = scene.castNames.isNotEmpty
        ? 'Characters present: ${scene.castNames.join(", ")}'
        : '';

    // Build previous scene context for continuity
    String previousSceneText = '';
    if (sceneIndex > 0) {
      // Get the last beat's prose from the previous scene
      final prevSId = '$actIndex-${sceneIndex - 1}';
      final prevBeats = project.beats[prevSId] ?? [];
      for (int b = prevBeats.length - 1; b >= 0; b--) {
        final prevProse = project.prose['$prevSId-$b']?.final_;
        if (prevProse != null && prevProse.isNotEmpty) {
          previousSceneText = prevProse.length > 600
              ? prevProse.substring(prevProse.length - 600)
              : prevProse;
          break;
        }
      }
    } else if (actIndex > 0) {
      // First scene of a new act — get the last scene's last beat from the previous act
      final prevActScenes = project.scenes[actIndex - 1] ?? [];
      if (prevActScenes.isNotEmpty) {
        final lastSceneIdx = prevActScenes.length - 1;
        final prevSId = '${actIndex - 1}-$lastSceneIdx';
        final prevBeats = project.beats[prevSId] ?? [];
        for (int b = prevBeats.length - 1; b >= 0; b--) {
          final prevProse = project.prose['$prevSId-$b']?.final_;
          if (prevProse != null && prevProse.isNotEmpty) {
            previousSceneText = prevProse.length > 600
                ? prevProse.substring(prevProse.length - 600)
                : prevProse;
            break;
          }
        }
      }
    }

    final isFirstScene = actIndex == 0 && sceneIndex == 0;
    final pov = project.pov;
    // Same rolling ban list the Studio writer gets: phrases the model has
    // leaned on in the last few scenes.
    project.autoBannedPhrases = StoryQuality.overusedPhrases(
      StoryQuality.recentProse(project, actIndex, sceneIndex),
      exclude: [...project.cast.map((c) => c.name), ...project.bannedPhrases],
    );
    final bannedBlock = StudioProsePrompts.bannedBlock(project);
    final pace = project.narrativePace;
    final dialogue = project.dialogueDensity;
    final styleGuide = project.writingStyle.isNotEmpty
        ? 'Writing Style: ${project.writingStyle}.'
        : '';
    final maturity = project.maturityRating;

    // Generate each beat individually for maximum prose length
    String runningContext =
        previousSceneText; // Carries forward from scene to scene

    for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
      final bId = '$sId-$beatIdx';

      // Skip if already finalized
      if (project.prose[bId]?.final_ != null) {
        // Still update running context so the next beat stays continuous
        runningContext = project.prose[bId]!.final_!;
        if (runningContext.length > 600) {
          runningContext = runningContext.substring(
            runningContext.length - 600,
          );
        }
        continue;
      }

      final beat = beats[beatIdx];
      final isFirstBeat = beatIdx == 0;
      final isOpeningBeat = isFirstScene && isFirstBeat;

      // Update status so UI shows per-beat progress
      _setStatus(
        'Writing',
        'Scene ${sceneIndex + 1}, Beat ${beatIdx + 1}/${beats.length}: ${beat.type}...',
      );

      // Build forward-context for the last beat so it transitions into the next scene
      String forwardHint = '';
      final isLastBeat = beatIdx == beats.length - 1;
      if (isLastBeat) {
        // Look for the next scene in this act, or the first scene of the next act
        StoryScene? nextScene;
        if (sceneIndex + 1 < scenes.length) {
          nextScene = scenes[sceneIndex + 1];
        } else if (actIndex + 1 < project.acts.length) {
          final nextActScenes = project.scenes[actIndex + 1] ?? [];
          if (nextActScenes.isNotEmpty) nextScene = nextActScenes[0];
        }
        if (nextScene != null) {
          forwardHint =
              '\nTRANSITION HINT — The NEXT scene is: "${nextScene.title}" at ${nextScene.location}.\n${nextScene.description}\nEnd this beat in a way that naturally leads into the next scene. Do NOT start the next scene — just set up the transition.';
        }
      }

      final prompt =
          '''You are a skilled novelist writing one section of a larger scene.

Story: ${project.concept}
Act ${act.number}: ${act.title} -- ${act.description}
Scene ${scene.number}: ${scene.title}
Location: ${scene.location}
$castInfo
Scene description: ${scene.description}
${StoryContext.previousActs(project, actIndex)}

YOUR CURRENT TASK: Write the prose for Beat ${beatIdx + 1} of ${beats.length} in this scene.
Beat type: ${beat.type}
Beat description: ${beat.description}
${isOpeningBeat ? '''

IMPORTANT -- THIS IS THE OPENING OF THE NOVEL:
- Introduce the protagonist naturally through action and description.
- Ground the reader in the world: where are we? what era? what is the atmosphere?
- Do NOT assume the reader knows anything about the characters or setting.
- Open with a hook that draws the reader in immediately.''' : ''}

CONTENT MATURITY: $maturity
${maturity == 'Explicit'
              ? 'This is an UNRESTRICTED adult story. Write graphic violence, sexual content, dark themes, and profanity naturally as the story demands. Do NOT censor, fade to black, or skip over explicit scenes. Write them in full vivid detail.'
              : maturity == 'Mature'
              ? 'This is a mature adult story. Include realistic violence, strong language, and suggestive/sexual themes where appropriate. You may be moderately graphic but avoid excessive gratuitous detail.'
              : 'This is a clean story suitable for all audiences. No graphic violence, sexual content, or strong language.'}

WRITING RULES:
1. Use $pov point of view consistently. ${pov == 'First Person' ? 'The narrator IS the protagonist. Use "I", "my", "me".' : 'NEVER use first person ("I", "my").'}
2. Use SHORT PARAGRAPHS -- 2-4 sentences maximum per paragraph. Separate paragraphs with blank lines.
3. Dialogue density: $dialogue. ${dialogue == 'Dialogue-Heavy'
              ? 'Characters should talk frequently. Dialogue drives the scene.'
              : dialogue == 'Sparse'
              ? 'Minimal dialogue. Focus on internal narrative and action.'
              : 'Balance dialogue with prose.'}
4. Narrative pace: $pace. ${pace == 'Slow Burn'
              ? 'Linger on atmosphere and sensory details.'
              : pace == 'Fast-Paced'
              ? 'Tight sentences. Favor action. No lingering.'
              : 'Balance reflection with momentum.'}
5. Write 400-800 words of rich, detailed prose for this beat.
6. Vary sentence length. Mix short punchy sentences with longer descriptive ones.
$styleGuide
$bannedBlock
${runningContext.isNotEmpty ? '\nCONTINUITY — The story so far ends with:\n"""\n...$runningContext\n"""\nYour prose MUST continue seamlessly from this text. The reader should feel zero discontinuity.' : ''}
$forwardHint

Output ONLY the prose text for this single beat, nothing else. No labels, no headers.''';

      final response = await _callLLM(
        prompt,
        maxLength: tier == PromptTier.smallLocal ? 4096 : 8192,
        stage: StoryStageParams.prose,
        project: project,
        role: StoryRole.prose,
        label: 'Writing',
      );
      final cleanedResponse = StoryJson.stripThinkTags(response).trim();

      project.prose[bId] = BeatProse(
        draft: cleanedResponse,
        final_: cleanedResponse,
      );

      // Update running context for the next beat
      runningContext = cleanedResponse;
      if (runningContext.length > 600) {
        runningContext = runningContext.substring(runningContext.length - 600);
      }

      // Save after each beat so progress isn't lost if something crashes
      await _repository.saveProject(project);
    }
  }

  /// Autopilot: run the entire pipeline from concept to finished prose.
  Future<void> _autopilot(StoryProject project) async {
    try {
      // Writes what is left. The bible and the acts are built only when
      // they do not exist yet; a fresh start is "Regenerate bible" first.
      if (project.cast.isEmpty && project.concept.trim().isNotEmpty) {
        await runStoryArchitect(project);
      }
      if (project.acts.isEmpty) {
        await runActStructurer(project);
      }
      // One scene at a time through the same path as "Continue writing",
      // so Stop lands between scenes and nothing written is touched.
      while (await writeNextScene(project)) {
        if (_stopRequested) break;
      }

      _setStatus('Complete', 'Story generation finished!');
    } catch (e) {
      _setStatus('Error', 'Pipeline failed: $e');
      rethrow;
    }
  }
}
