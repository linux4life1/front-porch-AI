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

/// The four planning stages — Story Architect, Act Structurer, Scene Weaver,
/// Beat Director. Extracted verbatim from `story_pipeline_service.dart`
/// (Cluster F of the god-file split) as a public-named extension (see the
/// ChatService-parts precedent — these stages are called from the story
/// pages and the web facade, so a private extension would hide them).
extension StoryPipelinePlanning on StoryPipelineService {
  /// Stage 1: Story Architect — concept → story bible.
  Future<void> _quickArchitect(StoryProject project) async {
    _isRunning = true;
    _setStatus('Story Architect', 'Generating story bible from concept...');

    try {
      final chatContext = await _getChatHistoryContext(project);
      final charContext = StoryContext.characterCards(project);
      final systemPrompt =
          StoryPrompts.storyArchitect(project) +
          (project.faithfulMode ? faithfulArchitectDirective : '');

      final prompt =
          '''$systemPrompt

Input Concept: ${project.concept}
$charContext
$chatContext

IMPORTANT: If character definitions are provided above, use them as the CORE CAST of the story. 
Their personalities, descriptions, and relationships should be faithfully reflected in the story 
bible. You are encouraged to create additional supporting characters, antagonists, and NPCs to 
enrich the world -- but the imported characters must remain central to the narrative.
${chatContext.isNotEmpty ? '\nCRITICAL: Chat history is provided above. This is the SOURCE TRUTH for the story. The plot, character arcs, and key events MUST follow what happened in these conversations. The story bible should structure these chat events into a coherent narrative arc -- do NOT invent a completely different plot. You are novelizing what happened, not writing a new story.' : ''}''';

      final response = await _callLLM(
        prompt,
        maxLength: 8192,
        stage: StoryStageParams.bible,
        project: project,
        label: 'Story Architect',
      );
      final json = StoryJson.parseJson(response);

      if (json == null) {
        throw Exception('Failed to parse story bible JSON from AI response');
      }

      // Update project from response
      project.concept = json['concept'] ?? project.concept;
      project.statusQuo = json['status_quo'] ?? '';
      project.incitingIncident = json['inciting_incident'] ?? '';
      project.themes = json['themes'] ?? '';

      if (json['style'] != null) {
        project.style = StoryStyle.fromJson(json['style']);
      }

      if (json['threads'] != null) {
        project.threads = (json['threads'] as List)
            .map((t) => StoryThread.fromJson(t))
            .toList();
      }

      // Pre-populate cast from character card snapshots with user-assigned roles
      if (project.characterCardSnapshots.isNotEmpty) {
        project.cast = project.characterCardSnapshots.map((snap) {
          return StoryCastMember(
            name: snap['name'] ?? 'Unknown',
            role: snap['role'] ?? 'Supporting',
            description: snap['description'] ?? snap['personality'] ?? '',
          );
        }).toList();
      } else if (json['protagonist'] != null) {
        // Fallback: use LLM-generated protagonist only when no snapshots exist
        project.cast = [StoryCastMember.fromJson(json['protagonist'])];
      }

      // Add world lore
      if (json['world_lore'] != null) {
        project.lore = (json['world_lore'] as List)
            .map((l) => StoryLoreEntry.fromJson(l))
            .toList();
      }

      await _repository.saveProject(project);
      _setStatus('Story Architect', 'Story bible created!');
    } catch (e) {
      _setStatus('Story Architect', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Stage 2: Act Structurer — story bible → 3 acts.
  Future<void> _quickActs(StoryProject project) async {
    _isRunning = true;
    _setStatus(
      'Act Structurer',
      'Designing ${project.actCount}-act structure...',
    );

    try {
      final systemPrompt = StoryPrompts.actStructure(
        project.actCount,
        project.promptTier,
      );
      final prompt =
          '''$systemPrompt

Story Concept: ${project.concept}
Status Quo: ${project.statusQuo}
Inciting Incident: ${project.incitingIncident}
Themes: ${project.themes}
Style: ${jsonEncode(project.style.toJson())}
Threads: ${jsonEncode(project.threads.map((t) => t.toJson()).toList())}''';

      final response = await _callLLM(
        prompt,
        maxLength: 8192,
        project: project,
        label: 'Act Structurer',
      );
      final json = StoryJson.parseJson(response);

      if (json == null || json['acts'] == null) {
        throw Exception('Failed to parse act structure from AI response');
      }

      project.acts = (json['acts'] as List)
          .map((a) => StoryAct.fromJson(a))
          .toList();

      await _repository.saveProject(project);
      _setStatus(
        'Act Structurer',
        '${project.actCount}-act structure created!',
      );
    } catch (e) {
      _setStatus('Act Structurer', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Stage 3: Scene Weaver — act → scenes.
  Future<void> _quickScenes(StoryProject project, int actIndex) async {
    _isRunning = true;
    final actNum = actIndex + 1;
    _setStatus('Scene Weaver', 'Weaving scenes for Act $actNum...');

    try {
      final act = project.acts[actIndex];
      final systemPrompt =
          StoryPrompts.sceneWeaver(actNum, project.promptTier) +
          (project.faithfulMode ? faithfulSceneDirective : '');
      final previousContext = StoryContext.previousActs(project, actIndex);
      final chatContext = await _getChatHistoryContext(project);
      final prompt =
          '''$systemPrompt

Story Concept: ${project.concept}
Themes: ${project.themes}
Style: ${jsonEncode(project.style.toJson())}
Threads: ${jsonEncode(project.threads.map((t) => t.toJson()).toList())}
$previousContext
$chatContext
ACT $actNum: ${act.title}
${act.description}

Existing Cast: ${project.cast.map((c) => '${c.name} (${c.role})').join(', ')}
${actIndex > 0 ? '\nIMPORTANT: This is Act $actNum. Maintain continuity with the events described in the STORY SO FAR section above. Build upon established plot threads and character developments.' : ''}
${chatContext.isNotEmpty ? '\nCRITICAL: The chat history above is CANON. Scenes MUST dramatize the events from these conversations. Map chat events to specific scenes in this act.' : ''}''';

      final response = await _callLLM(
        prompt,
        maxLength: 8192,
        project: project,
        label: 'Scene Weaver',
      );
      final json = StoryJson.parseJson(response);

      if (json == null || json['scenes'] == null) {
        throw Exception('Failed to parse scenes from AI response');
      }

      project.scenes[actIndex] = (json['scenes'] as List)
          .map((s) => StoryScene.fromJson(s))
          .toList();

      // Add any new characters
      if (json['new_characters'] != null) {
        for (final nc in json['new_characters'] as List) {
          final newChar = StoryCastMember.fromJson(nc);
          if (!project.cast.any((c) => c.name == newChar.name)) {
            project.cast.add(newChar);
          }
        }
      }

      await _repository.saveProject(project);
      _setStatus(
        'Scene Weaver',
        'Act $actNum scenes created! (${project.scenes[actIndex]?.length ?? 0} scenes)',
      );
    } catch (e) {
      _setStatus('Scene Weaver', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Stage 4: Beat Director — scene → beats.
  Future<void> _quickBeats(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    _isRunning = true;
    final scene = project.scenes[actIndex]![sceneIndex];
    _setStatus('Beat Director', 'Breaking down "${scene.title}" into beats...');

    try {
      final systemPrompt = StoryPrompts.beatDirector(project.promptTier);
      final prompt =
          '''$systemPrompt

Scene: ${scene.title}
Description: ${scene.description}
Location: ${scene.location}
Characters: ${scene.castNames.join(', ')}
Active Threads: ${scene.activeThreadIds.join(', ')}
Scene Valence: ${scene.valence}''';

      final response = await _callLLM(
        prompt,
        maxLength: 6144,
        project: project,
        label: 'Beat Director',
      );
      debugPrint(
        '[BeatDirector] Raw response (first 500): ${response.length > 500 ? response.substring(0, 500) : response}',
      );
      final json = StoryJson.parseJson(response);

      if (json == null || json['beats'] == null) {
        debugPrint(
          '[BeatDirector] Parse failed. Keys found: ${json?.keys.toList()}',
        );
        throw Exception('Failed to parse beats from AI response');
      }

      final beatsList = json['beats'] as List;
      debugPrint('[BeatDirector] Found ${beatsList.length} beats');
      if (beatsList.isNotEmpty) {
        debugPrint(
          '[BeatDirector] First beat keys: ${(beatsList.first as Map).keys.toList()}',
        );
        debugPrint('[BeatDirector] First beat: ${beatsList.first}');
      }

      final sId = '$actIndex-$sceneIndex';
      project.beats[sId] = beatsList.map((b) => StoryBeat.fromJson(b)).toList();

      await _repository.saveProject(project);
      _setStatus(
        'Beat Director',
        '"${scene.title}" broken into ${project.beats[sId]?.length ?? 0} beats!',
      );
    } catch (e) {
      _setStatus('Beat Director', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }
}
