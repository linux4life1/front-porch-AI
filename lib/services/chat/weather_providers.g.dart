// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod surface for weather (Living Time §3) — @riverpod codegen style
/// (project standard, maintainer directive 2026-07-21): family parameters
/// are plain named args, autoDispose is the default, and the provider is
/// memoized per-argument so the deterministic recompute runs only when the
/// story day/session actually changes. The engine stays pure; inputs cross
/// the Provider→Riverpod boundary as plain values handed down by the
/// existing widget tree (TimeStrip).

@ProviderFor(dailyWeather)
final dailyWeatherProvider = DailyWeatherFamily._();

/// Riverpod surface for weather (Living Time §3) — @riverpod codegen style
/// (project standard, maintainer directive 2026-07-21): family parameters
/// are plain named args, autoDispose is the default, and the provider is
/// memoized per-argument so the deterministic recompute runs only when the
/// story day/session actually changes. The engine stays pure; inputs cross
/// the Provider→Riverpod boundary as plain values handed down by the
/// existing widget tree (TimeStrip).

final class DailyWeatherProvider
    extends $FunctionalProvider<DailyWeather, DailyWeather, DailyWeather>
    with $Provider<DailyWeather> {
  /// Riverpod surface for weather (Living Time §3) — @riverpod codegen style
  /// (project standard, maintainer directive 2026-07-21): family parameters
  /// are plain named args, autoDispose is the default, and the provider is
  /// memoized per-argument so the deterministic recompute runs only when the
  /// story day/session actually changes. The engine stays pure; inputs cross
  /// the Provider→Riverpod boundary as plain values handed down by the
  /// existing widget tree (TimeStrip).
  DailyWeatherProvider._({
    required DailyWeatherFamily super.from,
    required ({String sessionSeed, int dayCount, DateTime date}) super.argument,
  }) : super(
         retry: null,
         name: r'dailyWeatherProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dailyWeatherHash();

  @override
  String toString() {
    return r'dailyWeatherProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<DailyWeather> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DailyWeather create(Ref ref) {
    final argument =
        this.argument as ({String sessionSeed, int dayCount, DateTime date});
    return dailyWeather(
      ref,
      sessionSeed: argument.sessionSeed,
      dayCount: argument.dayCount,
      date: argument.date,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DailyWeather value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DailyWeather>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DailyWeatherProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyWeatherHash() => r'531d2f11f34563f52413f0c25b2ccb644d6f905b';

/// Riverpod surface for weather (Living Time §3) — @riverpod codegen style
/// (project standard, maintainer directive 2026-07-21): family parameters
/// are plain named args, autoDispose is the default, and the provider is
/// memoized per-argument so the deterministic recompute runs only when the
/// story day/session actually changes. The engine stays pure; inputs cross
/// the Provider→Riverpod boundary as plain values handed down by the
/// existing widget tree (TimeStrip).

final class DailyWeatherFamily extends $Family
    with
        $FunctionalFamilyOverride<
          DailyWeather,
          ({String sessionSeed, int dayCount, DateTime date})
        > {
  DailyWeatherFamily._()
    : super(
        retry: null,
        name: r'dailyWeatherProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Riverpod surface for weather (Living Time §3) — @riverpod codegen style
  /// (project standard, maintainer directive 2026-07-21): family parameters
  /// are plain named args, autoDispose is the default, and the provider is
  /// memoized per-argument so the deterministic recompute runs only when the
  /// story day/session actually changes. The engine stays pure; inputs cross
  /// the Provider→Riverpod boundary as plain values handed down by the
  /// existing widget tree (TimeStrip).

  DailyWeatherProvider call({
    required String sessionSeed,
    required int dayCount,
    required DateTime date,
  }) => DailyWeatherProvider._(
    argument: (sessionSeed: sessionSeed, dayCount: dayCount, date: date),
    from: this,
  );

  @override
  String toString() => r'dailyWeatherProvider';
}
