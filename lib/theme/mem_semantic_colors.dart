import 'package:flutter/material.dart';

import 'mem_collection_ink.dart';

/// Semantic colours that Material 3 has no role for.
///
/// Registered as a [ThemeExtension] on **both** `ThemeData`s. Read it with:
///
/// ```dart
/// final sem = Theme.of(context).extension<MemSemanticColors>()!;
/// ```
///
/// or via the [memSemanticColorsOf] shorthand.
///
/// **Hard rule:** `success`, `warning`, and `pending` appear only as an 8 dp
/// status dot or as status-pill text/containers. They are never a fill for a
/// button, a row, or a chip — that discipline is what keeps the colour
/// constitution from leaking.
///
/// [recording] is deliberately a *different* red from `colorScheme.error`: a
/// live microphone is not a failure, and the two must never be confused.
///
/// [aiAccent] mirrors `colorScheme.tertiary` so every AI-provenance site reads
/// as intentional rather than as a stray accent.
@immutable
class MemSemanticColors extends ThemeExtension<MemSemanticColors> {
  const MemSemanticColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.pending,
    required this.pendingContainer,
    required this.onPendingContainer,
    required this.recording,
    required this.recordingContainer,
    required this.onRecordingContainer,
    required this.aiAccent,
    required this.aiContainer,
    required this.onAiContainer,
    required this.collectionInks,
  });

  /// Completed / connected / healthy. 8 dp dot and status-pill text.
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Advisory: model-catalog drift, session-retention hint.
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// In-flight work: OAuth browser round-trip, memIt processing, widget sync.
  final Color pending;
  final Color pendingContainer;
  final Color onPendingContainer;

  /// Microphone active **only** — distinct from `colorScheme.error`.
  final Color recording;
  final Color recordingContainer;
  final Color onRecordingContainer;

  /// AI provenance — mirrors `colorScheme.tertiary`. See the reservation rule.
  final Color aiAccent;
  final Color aiContainer;
  final Color onAiContainer;

  /// Exactly [kMemCollectionInkCount] entries, indexed by
  /// [collectionInkIndex].
  final List<CollectionInk> collectionInks;

  /// Dark instance.
  static const MemSemanticColors darkColors = MemSemanticColors(
    success: Color(0xFF3DD68C),
    successContainer: Color(0xFF0C2E24),
    onSuccessContainer: Color(0xFFB6EFD4),
    warning: Color(0xFFFFB224),
    warningContainer: Color(0xFF33270C),
    onWarningContainer: Color(0xFFFFE0A6),
    pending: Color(0xFFE8C26C),
    pendingContainer: Color(0xFF3A2E12),
    onPendingContainer: Color(0xFFF3DFB4),
    recording: Color(0xFFFF8A7A),
    recordingContainer: Color(0xFF3A1512),
    onRecordingContainer: Color(0xFFFFD6CF),
    aiAccent: Color(0xFFB79DFF),
    aiContainer: Color(0xFF3A2A6E),
    onAiContainer: Color(0xFFE5DBFF),
    collectionInks: memCollectionInksDark,
  );

  /// Light instance.
  static const MemSemanticColors lightColors = MemSemanticColors(
    success: Color(0xFF1B7F4B),
    successContainer: Color(0xFFDDF5EC),
    onSuccessContainer: Color(0xFF0A3D28),
    warning: Color(0xFFB26A00),
    warningContainer: Color(0xFFFBF0D7),
    onWarningContainer: Color(0xFF5C3A00),
    pending: Color(0xFF8A5A00),
    pendingContainer: Color(0xFFFAEFD6),
    onPendingContainer: Color(0xFF4A2F00),
    recording: Color(0xFFC03A2E),
    recordingContainer: Color(0xFFFCE4E0),
    onRecordingContainer: Color(0xFF4A150E),
    aiAccent: Color(0xFF6A48D0),
    aiContainer: Color(0xFFE9E1FF),
    onAiContainer: Color(0xFF2A1265),
    collectionInks: memCollectionInksLight,
  );

  /// The instance for [brightness]. `buildMemTheme` registers this.
  static MemSemanticColors of(Brightness brightness) =>
      brightness == Brightness.dark ? darkColors : lightColors;

  @override
  MemSemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? pending,
    Color? pendingContainer,
    Color? onPendingContainer,
    Color? recording,
    Color? recordingContainer,
    Color? onRecordingContainer,
    Color? aiAccent,
    Color? aiContainer,
    Color? onAiContainer,
    List<CollectionInk>? collectionInks,
  }) {
    return MemSemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      pending: pending ?? this.pending,
      pendingContainer: pendingContainer ?? this.pendingContainer,
      onPendingContainer: onPendingContainer ?? this.onPendingContainer,
      recording: recording ?? this.recording,
      recordingContainer: recordingContainer ?? this.recordingContainer,
      onRecordingContainer: onRecordingContainer ?? this.onRecordingContainer,
      aiAccent: aiAccent ?? this.aiAccent,
      aiContainer: aiContainer ?? this.aiContainer,
      onAiContainer: onAiContainer ?? this.onAiContainer,
      collectionInks: collectionInks ?? this.collectionInks,
    );
  }

  @override
  MemSemanticColors lerp(covariant MemSemanticColors? other, double t) {
    if (other == null) return this;
    return MemSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      pending: Color.lerp(pending, other.pending, t)!,
      pendingContainer: Color.lerp(
        pendingContainer,
        other.pendingContainer,
        t,
      )!,
      onPendingContainer: Color.lerp(
        onPendingContainer,
        other.onPendingContainer,
        t,
      )!,
      recording: Color.lerp(recording, other.recording, t)!,
      recordingContainer: Color.lerp(
        recordingContainer,
        other.recordingContainer,
        t,
      )!,
      onRecordingContainer: Color.lerp(
        onRecordingContainer,
        other.onRecordingContainer,
        t,
      )!,
      aiAccent: Color.lerp(aiAccent, other.aiAccent, t)!,
      aiContainer: Color.lerp(aiContainer, other.aiContainer, t)!,
      onAiContainer: Color.lerp(onAiContainer, other.onAiContainer, t)!,
      collectionInks: CollectionInk.lerpRamp(
        collectionInks,
        other.collectionInks,
        t,
      ),
    );
  }
}

/// Shorthand for `Theme.of(context).extension<MemSemanticColors>()!`.
///
/// Safe to force-unwrap: `buildMemTheme` registers the extension on both
/// `ThemeData`s, and `test/theme_contrast_test.dart` asserts it.
MemSemanticColors memSemanticColorsOf(BuildContext context) =>
    Theme.of(context).extension<MemSemanticColors>()!;
