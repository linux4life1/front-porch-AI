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

part of 'main.dart';

/// The full provider graph. ORDER IS LOAD-BEARING: a Provider.of inside a
/// create/update only resolves providers ABOVE it in this list. [db] and
/// [needsMigration] arrive from _openDatabaseGuarded in main().
Widget _buildRootWidget(AppDatabase db, bool needsMigration) {
  // ── Re-entry guards for the two proxies whose `update` is NOT idempotent ──
  //
  // A ProxyProvider's `update` runs on EVERY notification from any dependency,
  // not just when that dependency changes identity. KoboldService alone
  // notifies per stdout line while the managed backend generates (and again
  // every 150ms of live progress), and LLMProvider re-broadcasts all of it, so
  // "once in a while" is really "up to once per frame, forever".
  //
  // These are function-local, so hot restart (a fresh _buildRootWidget call)
  // starts clean.

  // ChatService.setLLMProvider APPENDS a listener with no removeListener, so
  // re-wiring the same pair leaks one callback per frame — and LLMProvider then
  // dispatches all of them on every Kobold log line.
  ChatService? wiredChat;
  LLMProvider? wiredChatLlm;
  void wireChatToLlmProvider(ChatService chat, LLMProvider llm) {
    if (identical(wiredChat, chat) && identical(wiredChatLlm, llm)) return;
    wiredChat = chat;
    wiredChatLlm = llm;
    chat.setLLMProvider(llm);
    // Lets the live-status sources (oMLX poller) gate their polling on an
    // actual generation being in flight.
    llm.isGenerationActive = () => chat.isGenerating;
  }

  // StoryPipelineService binds its LLMService and AppDatabase at construction,
  // so it has to be rebuilt when either changes — but ONLY then. Rebuilding on
  // an unrelated notification disposes the instance a story run is streaming
  // into: the pages' Consumer2 rebinds to a fresh instance whose isRunning is
  // false, so the progress overlay vanishes and Generate re-enables while the
  // orphan keeps writing.
  LLMService? storyLlmService;
  AppDatabase? storyDb;
  StoryPipelineService buildStoryPipeline(
    BuildContext context,
    LLMProvider llmProvider,
    StorageService storage,
  ) {
    // The live handle, never the startup snapshot this closure captured:
    // reopenAndRebindDatabase closes that one (backup restore, storage move,
    // stable-DB import) and every query against it then throws.
    final liveDb = AppDatabase.current ?? db;
    storyLlmService = llmProvider.activeService;
    storyDb = liveDb;
    return StoryPipelineService(
      Provider.of<StoryRepository>(context, listen: false),
      llmProvider.activeService,
      MemoryService(
        Provider.of<EmbeddingService>(context, listen: false),
        storage,
        liveDb,
      ),
      liveDb,
    );
  }

  // The web relay with every collaborator wired. A named function rather than
  // an inline `create:` so the proxy's `update` can fall back to it instead of
  // ever handing out a half-wired host.
  WebServerHost createWebServerHost(BuildContext context) {
    final host = WebServerHost(
      Provider.of<StorageService>(context, listen: false),
    );
    host.setDatabase(db);
    host.setChatService(Provider.of<ChatService>(context, listen: false));
    host.setKoboldService(Provider.of<KoboldService>(context, listen: false));
    host.setCharacterRepository(
      Provider.of<CharacterRepository>(context, listen: false),
    );
    host.setGroupChatRepository(
      Provider.of<GroupChatRepository>(context, listen: false),
    );
    host.setLlmProvider(Provider.of<LLMProvider>(context, listen: false));
    host.setFolderService(Provider.of<FolderService>(context, listen: false));
    host.setUserPersonaService(
      Provider.of<UserPersonaService>(context, listen: false),
    );
    host.setWorldRepository(
      Provider.of<WorldRepository>(context, listen: false),
    );
    host.setModelManager(Provider.of<ModelManager>(context, listen: false));
    host.setHardwareService(
      Provider.of<HardwareService>(context, listen: false),
    );
    host.setImageGenService(
      Provider.of<ImageGenService>(context, listen: false),
    );
    host.setTtsService(Provider.of<TtsService>(context, listen: false));
    host.setSttService(Provider.of<SttService>(context, listen: false));
    host.setStoryRepository(
      Provider.of<StoryRepository>(context, listen: false),
    );
    host.setStoryPipelineService(
      Provider.of<StoryPipelineService>(context, listen: false),
    );
    return host;
  }

  // ProviderScope: Riverpod root for new-code state (CLAUDE.md Riverpod
  // migration; first consumer: Living Time weather). Wraps the existing
  // Provider tree without touching service init order — legacy providers
  // below are unchanged.
  return riverpod.ProviderScope(
    child: MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<bool>.value(value: needsMigration), // migration flag
        ChangeNotifierProvider(create: (_) => StorageService()),
        // AppState owns only transient UI state (selected tab index).
        // Theme / dark mode is now driven exclusively by StorageService (single source of truth,
        // persisted, notifies after async prefs load). This eliminates the prior race + glue bugs.
        ChangeNotifierProvider(create: (_) => AppState()),
        // Repository (Backporch) account session. Lazy — constructed + restored
        // only when the Repository page is first opened, so users who never
        // touch the online hub pay nothing and make no network calls.
        ChangeNotifierProvider(create: (_) => AuthState()..init()),
        ChangeNotifierProxyProvider<StorageService, DownloadManager>(
          create: (context) => DownloadManager(
            targetDir: Provider.of<StorageService>(
              context,
              listen: false,
            ).modelsDir.path,
          ),
          // Re-point the target dir on every storage notify (notably the one
          // after async init sets rootPath) so downloads always land in the
          // configured models folder, not a relative path captured at create.
          update: (context, storage, previous) =>
              (previous ?? DownloadManager(targetDir: storage.modelsDir.path))
                ..targetDir = storage.modelsDir.path,
        ),
        ChangeNotifierProxyProvider<StorageService, KoboldService>(
          create: (context) => KoboldService(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? KoboldService(storage),
        ),
        ChangeNotifierProvider(create: (_) => HardwareService()),
        // Anonymous, opt-out app analytics. Lazy like AuthState — only built
        // when the Stoop is first opened (RepositoryPage reads it), so users who
        // never touch the hub make no network calls. It listens to AuthState and
        // pings once per launch when signed in and analytics is enabled.
        Provider<StoopAnalytics>(
          create: (ctx) => StoopAnalytics(
            ctx.read<AuthState>(),
            ctx.read<HardwareService>(),
          ),
          dispose: (_, s) => s.dispose(),
        ),
        ChangeNotifierProxyProvider<StorageService, CharacterRepository>(
          create: (context) => CharacterRepository(
            db,
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? CharacterRepository(db, storage),
        ),
        ChangeNotifierProvider(create: (context) => UserPersonaService(db)),
        // GroupChatRepository early (before ChatService) so the DI wiring in ChatService
        // create/update can successfully Provider.of it. Critical for the decoupled
        // member loading fallback in setActiveGroup.
        ChangeNotifierProxyProvider<StorageService, GroupChatRepository>(
          create: (context) => GroupChatRepository(
            Provider.of<StorageService>(context, listen: false),
            db,
          ),
          update: (context, storage, previous) =>
              previous ?? GroupChatRepository(storage, db),
        ),
        ChangeNotifierProvider(create: (context) => FolderService(db)),
        ChangeNotifierProxyProvider3<
          CharacterRepository,
          StorageService,
          GroupChatRepository,
          WorldRepository
        >(
          create: (context) {
            final repo = WorldRepository(
              Provider.of<StorageService>(context, listen: false),
              db,
            );
            // Wire CharacterRepository for avatar path resolution
            repo.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            repo.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            return repo;
          },
          update: (context, charRepo, storage, groups, previous) {
            final newRepo = previous ?? WorldRepository(storage, db);
            // Re-wire CharacterRepository if changed
            newRepo.setCharacterRepository(charRepo);
            newRepo.setGroupChatRepository(groups);
            return newRepo;
          },
        ),
        ChangeNotifierProvider<EmbeddingService>(
          create: (context) => EmbeddingService(
            Provider.of<StorageService>(context, listen: false),
          ),
        ),
        ChangeNotifierProxyProvider<StorageService, BackendManager>(
          create: (context) => BackendManager(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? BackendManager(storage),
        ),
        ChangeNotifierProxyProvider<StorageService, OpenCodeManager>(
          create: (context) => OpenCodeManager(
            rootPath:
                Provider.of<StorageService>(context, listen: false).rootPath ??
                '',
          ),
          update: (context, storage, previous) {
            final root = storage.rootPath ?? '';
            if (previous != null && previous.closet.rootPath == root) {
              return previous;
            }
            previous?.dispose();
            return OpenCodeManager(rootPath: root);
          },
        ),
        ChangeNotifierProxyProvider2<
          StorageService,
          DownloadManager,
          ModelManager
        >(
          create: (context) => ModelManager(
            Provider.of<StorageService>(context, listen: false),
            Provider.of<DownloadManager>(context, listen: false),
          ),
          update: (context, storage, downloadManager, previous) =>
              previous ?? ModelManager(storage, downloadManager),
        ),
        ChangeNotifierProvider(create: (_) => OpenRouterService()),
        ChangeNotifierProxyProvider4<
          KoboldService,
          OpenRouterService,
          StorageService,
          BackendManager,
          LLMProvider
        >(
          create: (context) => LLMProvider(
            Provider.of<KoboldService>(context, listen: false),
            Provider.of<OpenRouterService>(context, listen: false),
            Provider.of<StorageService>(context, listen: false),
            Provider.of<BackendManager>(context, listen: false),
          ),
          update: (context, kobold, openRouter, storage, backend, previous) =>
              previous ?? LLMProvider(kobold, openRouter, storage, backend),
        ),
        ChangeNotifierProxyProvider4<
          KoboldService,
          UserPersonaService,
          StorageService,
          WorldRepository,
          ChatService
        >(
          create: (context) {
            final chatService = ChatService(
              Provider.of<KoboldService>(context, listen: false),
              Provider.of<UserPersonaService>(context, listen: false),
              Provider.of<StorageService>(context, listen: false),
              Provider.of<WorldRepository>(context, listen: false),
            );
            // Wire LLMProvider and CharacterRepository immediately at creation time
            chatService.setDatabase(db);
            wireChatToLlmProvider(
              chatService,
              Provider.of<LLMProvider>(context, listen: false),
            );
            chatService.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            // Wire GroupChatRepository for decoupled group member loading
            chatService.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            // Wire MemoryService for RAG
            try {
              final storage = Provider.of<StorageService>(
                context,
                listen: false,
              );
              final memoryService = MemoryService(
                Provider.of<EmbeddingService>(context, listen: false),
                storage,
                db,
              );
              chatService.setMemoryService(memoryService);
            } catch (_) {}
            return chatService;
          },
          update: (context, kobold, persona, storage, worldRepo, previous) {
            if (previous != null) {
              wireChatToLlmProvider(
                previous,
                Provider.of<LLMProvider>(context, listen: false),
              );
              previous.setCharacterRepository(
                Provider.of<CharacterRepository>(context, listen: false),
              );
              previous.setGroupChatRepository(
                Provider.of<GroupChatRepository>(context, listen: false),
              );
              try {
                previous.setTtsService(
                  Provider.of<TtsService>(context, listen: false),
                );
              } catch (_) {}
              return previous;
            }
            final chatService = ChatService(
              kobold,
              persona,
              storage,
              worldRepo,
            );
            chatService.setDatabase(db);
            wireChatToLlmProvider(
              chatService,
              Provider.of<LLMProvider>(context, listen: false),
            );
            chatService.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            chatService.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            return chatService;
          },
        ),
        ChangeNotifierProxyProvider<
          StorageService,
          ExpressionClassifierService
        >(
          create: (context) => ExpressionClassifierService(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? ExpressionClassifierService(storage),
        ),
        ChangeNotifierProxyProvider3<
          StorageService,
          BackendManager,
          KoboldService,
          SetupService
        >(
          create: (context) => SetupService(
            Provider.of<StorageService>(context, listen: false),
            Provider.of<BackendManager>(context, listen: false),
            Provider.of<KoboldService>(context, listen: false),
          ),
          update: (context, storage, backend, kobold, previous) =>
              previous ?? SetupService(storage, backend, kobold),
        ),
        ChangeNotifierProvider(create: (_) => UpdateService()),
        ChangeNotifierProxyProvider<StorageService, VoiceManager>(
          create: (context) =>
              VoiceManager(Provider.of<StorageService>(context, listen: false)),
          update: (context, storage, previous) =>
              previous ?? VoiceManager(storage),
        ),
        ChangeNotifierProxyProvider2<StorageService, VoiceManager, TtsService>(
          create: (context) => TtsService(
            Provider.of<StorageService>(context, listen: false),
            Provider.of<VoiceManager>(context, listen: false),
          ),
          update: (context, storage, voiceManager, previous) =>
              previous ?? TtsService(storage, voiceManager),
        ),
        ChangeNotifierProxyProvider2<
          TtsService,
          StorageService,
          AudiobookGeneratorService
        >(
          create: (context) => AudiobookGeneratorService(
            Provider.of<TtsService>(context, listen: false),
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, tts, storage, previous) =>
              previous ?? AudiobookGeneratorService(tts, storage),
        ),
        ChangeNotifierProxyProvider<StorageService, SttService>(
          create: (context) =>
              SttService(Provider.of<StorageService>(context, listen: false)),
          update: (context, storage, previous) {
            // Call-mode TTS awareness is wired by the call overlay itself
            // (CallSession.attachTtsBusyProbe) — no TTS ref needed here.
            return previous ?? SttService(storage);
          },
        ),
        ChangeNotifierProxyProvider<StorageService, ImageGenService>(
          create: (context) {
            return ImageGenService(
              Provider.of<StorageService>(context, listen: false),
            );
          },
          update: (context, storage, previous) {
            return previous ?? ImageGenService(storage);
          },
        ),
        // Porch Stories: repository + pipeline must be above WebServerHost
        ChangeNotifierProvider(
          create: (context) {
            final repo = StoryRepository(db);
            repo.loadProjects();
            return repo;
          },
        ),
        ChangeNotifierProxyProvider2<
          LLMProvider,
          StorageService,
          StoryPipelineService
        >(
          create: (context) => buildStoryPipeline(
            context,
            Provider.of<LLMProvider>(context, listen: false),
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, llmProvider, storage, previous) {
            // Rebuild ONLY when something the service froze at construction
            // actually changed: the backend the user switched to, or the
            // database a restore/storage-move swapped in. Any other
            // notification must keep the running instance — replacing it
            // mid-run leaves the story pages bound to a fresh service whose
            // isRunning is false (overlay gone, Generate re-enabled) while the
            // orphaned one keeps streaming into the project.
            if (previous != null &&
                identical(storyLlmService, llmProvider.activeService) &&
                identical(storyDb, AppDatabase.current ?? db)) {
              return previous;
            }
            return buildStoryPipeline(context, llmProvider, storage);
          },
        ),
        // Web server: the React PWA + Dart shelf rewrite (lib/services/web).
        // Started on launch (_autoStartWebServer) or via the Settings toggle.
        // Collaborators are wired via setX. ChatService's own ImageGenService
        // (Scene Guest portraits) is wired in the post-frame block below.
        ChangeNotifierProxyProvider<StoryPipelineService, WebServerHost>(
          create: createWebServerHost,
          // The Story proxy above mints a NEW pipeline when the user switches
          // backends, so the relay must be re-pointed or the PWA keeps
          // generating stories on the backend the app happened to launch with
          // (and on a disposed service). Every other collaborator here is a
          // single instance for the app's lifetime; this one is not.
          update: (context, storyPipeline, previous) =>
              (previous ?? createWebServerHost(context))
                ..setStoryPipelineService(storyPipeline),
        ),
      ],
      child: const MyApp(),
    ),
  );
}
