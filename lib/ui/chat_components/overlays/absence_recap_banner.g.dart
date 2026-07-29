// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'absence_recap_banner.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Ephemeral per-session dismissed state for the "Previously on…" banner —
/// @riverpod Notifier (project codegen standard). One set of dismissed
/// session ids covers every session; keepAlive because a dismissal should
/// survive the banner unmounting (autoDispose would resurrect it).

@ProviderFor(DismissedAbsenceBanners)
final dismissedAbsenceBannersProvider = DismissedAbsenceBannersProvider._();

/// Ephemeral per-session dismissed state for the "Previously on…" banner —
/// @riverpod Notifier (project codegen standard). One set of dismissed
/// session ids covers every session; keepAlive because a dismissal should
/// survive the banner unmounting (autoDispose would resurrect it).
final class DismissedAbsenceBannersProvider
    extends $NotifierProvider<DismissedAbsenceBanners, Set<String>> {
  /// Ephemeral per-session dismissed state for the "Previously on…" banner —
  /// @riverpod Notifier (project codegen standard). One set of dismissed
  /// session ids covers every session; keepAlive because a dismissal should
  /// survive the banner unmounting (autoDispose would resurrect it).
  DismissedAbsenceBannersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dismissedAbsenceBannersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dismissedAbsenceBannersHash();

  @$internal
  @override
  DismissedAbsenceBanners create() => DismissedAbsenceBanners();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$dismissedAbsenceBannersHash() =>
    r'e224bd3471921369b0db72a0d40bb5115de30650';

/// Ephemeral per-session dismissed state for the "Previously on…" banner —
/// @riverpod Notifier (project codegen standard). One set of dismissed
/// session ids covers every session; keepAlive because a dismissal should
/// survive the banner unmounting (autoDispose would resurrect it).

abstract class _$DismissedAbsenceBanners extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
