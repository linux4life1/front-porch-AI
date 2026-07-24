// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'milestone_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// "Our Story" timeline state (Living Time §7) — an @riverpod AsyncNotifier
/// (project standard): the async build IS the fetch, consumers render
/// through AsyncValue, and the class is unit-testable in a bare
/// ProviderContainer with a fake feed. Family args are plain named build
/// params; `revision` (message count) is bumped by the host widget so the
/// feed refetches when the chat moves. When v1.5 milestone writes land,
/// mutation methods go on this notifier — the reason it's a class, not a
/// FutureProvider.

@ProviderFor(MilestoneTimeline)
final milestoneTimelineProvider = MilestoneTimelineFamily._();

/// "Our Story" timeline state (Living Time §7) — an @riverpod AsyncNotifier
/// (project standard): the async build IS the fetch, consumers render
/// through AsyncValue, and the class is unit-testable in a bare
/// ProviderContainer with a fake feed. Family args are plain named build
/// params; `revision` (message count) is bumped by the host widget so the
/// feed refetches when the chat moves. When v1.5 milestone writes land,
/// mutation methods go on this notifier — the reason it's a class, not a
/// FutureProvider.
final class MilestoneTimelineProvider
    extends $AsyncNotifierProvider<MilestoneTimeline, List<MilestoneEntry>> {
  /// "Our Story" timeline state (Living Time §7) — an @riverpod AsyncNotifier
  /// (project standard): the async build IS the fetch, consumers render
  /// through AsyncValue, and the class is unit-testable in a bare
  /// ProviderContainer with a fake feed. Family args are plain named build
  /// params; `revision` (message count) is bumped by the host widget so the
  /// feed refetches when the chat moves. When v1.5 milestone writes land,
  /// mutation methods go on this notifier — the reason it's a class, not a
  /// FutureProvider.
  MilestoneTimelineProvider._({
    required MilestoneTimelineFamily super.from,
    required ({
      MilestoneFeed feed,
      String sessionId,
      String characterId,
      int revision,
      List<ChatMessage> messages,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'milestoneTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$milestoneTimelineHash();

  @override
  String toString() {
    return r'milestoneTimelineProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MilestoneTimeline create() => MilestoneTimeline();

  @override
  bool operator ==(Object other) {
    return other is MilestoneTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$milestoneTimelineHash() => r'fd413a41c403631a87f487de76dae0a47c4d52bb';

/// "Our Story" timeline state (Living Time §7) — an @riverpod AsyncNotifier
/// (project standard): the async build IS the fetch, consumers render
/// through AsyncValue, and the class is unit-testable in a bare
/// ProviderContainer with a fake feed. Family args are plain named build
/// params; `revision` (message count) is bumped by the host widget so the
/// feed refetches when the chat moves. When v1.5 milestone writes land,
/// mutation methods go on this notifier — the reason it's a class, not a
/// FutureProvider.

final class MilestoneTimelineFamily extends $Family
    with
        $ClassFamilyOverride<
          MilestoneTimeline,
          AsyncValue<List<MilestoneEntry>>,
          List<MilestoneEntry>,
          FutureOr<List<MilestoneEntry>>,
          ({
            MilestoneFeed feed,
            String sessionId,
            String characterId,
            int revision,
            List<ChatMessage> messages,
          })
        > {
  MilestoneTimelineFamily._()
    : super(
        retry: null,
        name: r'milestoneTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// "Our Story" timeline state (Living Time §7) — an @riverpod AsyncNotifier
  /// (project standard): the async build IS the fetch, consumers render
  /// through AsyncValue, and the class is unit-testable in a bare
  /// ProviderContainer with a fake feed. Family args are plain named build
  /// params; `revision` (message count) is bumped by the host widget so the
  /// feed refetches when the chat moves. When v1.5 milestone writes land,
  /// mutation methods go on this notifier — the reason it's a class, not a
  /// FutureProvider.

  MilestoneTimelineProvider call({
    required MilestoneFeed feed,
    required String sessionId,
    required String characterId,
    required int revision,
    required List<ChatMessage> messages,
  }) => MilestoneTimelineProvider._(
    argument: (
      feed: feed,
      sessionId: sessionId,
      characterId: characterId,
      revision: revision,
      messages: messages,
    ),
    from: this,
  );

  @override
  String toString() => r'milestoneTimelineProvider';
}

/// "Our Story" timeline state (Living Time §7) — an @riverpod AsyncNotifier
/// (project standard): the async build IS the fetch, consumers render
/// through AsyncValue, and the class is unit-testable in a bare
/// ProviderContainer with a fake feed. Family args are plain named build
/// params; `revision` (message count) is bumped by the host widget so the
/// feed refetches when the chat moves. When v1.5 milestone writes land,
/// mutation methods go on this notifier — the reason it's a class, not a
/// FutureProvider.

abstract class _$MilestoneTimeline
    extends $AsyncNotifier<List<MilestoneEntry>> {
  late final _$args =
      ref.$arg
          as ({
            MilestoneFeed feed,
            String sessionId,
            String characterId,
            int revision,
            List<ChatMessage> messages,
          });
  MilestoneFeed get feed => _$args.feed;
  String get sessionId => _$args.sessionId;
  String get characterId => _$args.characterId;
  int get revision => _$args.revision;
  List<ChatMessage> get messages => _$args.messages;

  FutureOr<List<MilestoneEntry>> build({
    required MilestoneFeed feed,
    required String sessionId,
    required String characterId,
    required int revision,
    required List<ChatMessage> messages,
  });
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<MilestoneEntry>>, List<MilestoneEntry>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<MilestoneEntry>>,
                List<MilestoneEntry>
              >,
              AsyncValue<List<MilestoneEntry>>,
              Object?,
              Object?
            >;
    element.handleCreate(
      ref,
      () => build(
        feed: _$args.feed,
        sessionId: _$args.sessionId,
        characterId: _$args.characterId,
        revision: _$args.revision,
        messages: _$args.messages,
      ),
    );
  }
}
