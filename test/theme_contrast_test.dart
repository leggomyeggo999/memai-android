import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memai_android/theme/mem_app_theme.dart';
import 'package:memai_android/theme/mem_collection_ink.dart';
import 'package:memai_android/theme/mem_color_schemes.dart';
import 'package:memai_android/theme/mem_semantic_colors.dart';
import 'package:memai_android/theme/mem_typography.dart';

/// WCAG 2.1 contrast ratio between two opaque colours.
///
/// `Color.computeLuminance()` already implements the WCAG relative-luminance
/// formula (sRGB gamma expansion + the 0.2126/0.7152/0.0722 weights), so this
/// is only the ratio step.
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The published table rounds to one decimal; allow that rounding but nothing
/// more. A real regression moves the ratio far further than 0.05.
const double _roundingSlack = 0.05;

void expectRatio(
  Color fg,
  Color bg,
  double atLeast, {
  required String label,
}) {
  final double actual = contrastRatio(fg, bg);
  expect(
    actual,
    greaterThanOrEqualTo(atLeast - _roundingSlack),
    reason:
        '$label is ${actual.toStringAsFixed(2)}:1, '
        'below the required ${atLeast.toStringAsFixed(2)}:1',
  );
}

void main() {
  group('§2.3 verified contrast table — must not regress', () {
    test('dark scheme', () {
      const ColorScheme cs = memDarkScheme;
      expectRatio(
        cs.onSurface,
        cs.surface,
        17.4,
        label: 'dark onSurface on surface',
      );
      expectRatio(
        cs.onSurfaceVariant,
        cs.surface,
        7.3,
        label: 'dark onSurfaceVariant on surface',
      );
      expectRatio(
        cs.onSurfaceVariant,
        cs.surfaceContainerLow,
        6.9,
        label: 'dark onSurfaceVariant on surfaceContainerLow',
      );
      expectRatio(cs.primary, cs.surface, 7.9, label: 'dark primary on surface');
      expectRatio(
        cs.tertiary,
        cs.surface,
        9.0,
        label: 'dark tertiary on surface',
      );
      expectRatio(cs.outline, cs.surface, 3.2, label: 'dark outline on surface');
      expectRatio(
        cs.outline,
        cs.surfaceContainer,
        3.2,
        label: 'dark outline on surfaceContainer',
      );
      expectRatio(
        cs.onPrimary,
        cs.primary,
        5.1,
        label: 'dark onPrimary on primary',
      );
    });

    test('light scheme', () {
      const ColorScheme cs = memLightScheme;
      expectRatio(
        cs.onSurface,
        cs.surface,
        17.2,
        label: 'light onSurface on surface',
      );
      expectRatio(
        cs.onSurfaceVariant,
        cs.surface,
        6.0,
        label: 'light onSurfaceVariant on surface',
      );
      expectRatio(
        cs.onSurfaceVariant,
        cs.surfaceContainerLow,
        5.7,
        label: 'light onSurfaceVariant on surfaceContainerLow',
      );
      expectRatio(
        cs.primary,
        cs.surface,
        6.1,
        label: 'light primary on surface',
      );
      expectRatio(
        cs.tertiary,
        cs.surface,
        5.9,
        label: 'light tertiary on surface',
      );
      expectRatio(
        cs.outline,
        cs.surface,
        3.7,
        label: 'light outline on surface',
      );
      expectRatio(
        cs.outline,
        cs.surfaceContainer,
        3.4,
        label: 'light outline on surfaceContainer',
      );
      expectRatio(
        cs.onPrimary,
        cs.primary,
        6.1,
        label: 'light onPrimary on primary',
      );
    });
  });

  group('§2.7 outline is a real boundary', () {
    test('outline clears 3:1 on every surface a bounded container sits on', () {
      for (final Brightness b in Brightness.values) {
        final ColorScheme cs = memSchemeFor(b);
        final Map<String, Color> hosts = <String, Color>{
          'surface': cs.surface,
          'surfaceContainerLow': cs.surfaceContainerLow,
          'surfaceContainer': cs.surfaceContainer,
        };
        hosts.forEach((String name, Color host) {
          expectRatio(
            cs.outline,
            host,
            3.0,
            label: '${b.name} outline on $name',
          );
        });
      }
    });

    test('outlineVariant is decorative only — it is NOT a boundary', () {
      for (final Brightness b in Brightness.values) {
        final ColorScheme cs = memSchemeFor(b);
        expect(
          contrastRatio(cs.outlineVariant, cs.surfaceContainerLow),
          lessThan(3.0),
          reason:
              '${b.name} outlineVariant must stay a quiet divider; if it ever '
              'clears 3:1 the two hairline tokens have collapsed into one',
        );
      }
    });
  });

  group('§2.6 collection ink ramp', () {
    test('all 16 pairs clear 4.5:1 at label size', () {
      for (final Brightness b in Brightness.values) {
        final List<CollectionInk> ramp = memCollectionInksFor(b);
        expect(ramp, hasLength(kMemCollectionInkCount));
        for (int i = 0; i < ramp.length; i++) {
          final CollectionInk ink = ramp[i];
          expectRatio(
            ink.fg,
            ink.bg,
            4.5,
            label: '${b.name} ink $i (${ink.name}) fg on bg',
          );
        }
      }
    });
  });

  group('§2.5 semantic status colours', () {
    test('every status dot clears 3:1 on every surface it lands on', () {
      for (final Brightness b in Brightness.values) {
        final ColorScheme cs = memSchemeFor(b);
        final MemSemanticColors sem = MemSemanticColors.of(b);
        final Map<String, Color> dots = <String, Color>{
          'success': sem.success,
          'warning': sem.warning,
          'pending': sem.pending,
          'recording': sem.recording,
          'aiAccent': sem.aiAccent,
        };
        final Map<String, Color> hosts = <String, Color>{
          'surface': cs.surface,
          'surfaceContainerLow': cs.surfaceContainerLow,
          'surfaceContainer': cs.surfaceContainer,
        };
        dots.forEach((String dot, Color fg) {
          hosts.forEach((String host, Color bg) {
            expectRatio(fg, bg, 3.0, label: '${b.name} $dot dot on $host');
          });
        });
      }
    });

    test('status-pill text clears 4.5:1 on its own container', () {
      for (final Brightness b in Brightness.values) {
        final MemSemanticColors sem = MemSemanticColors.of(b);
        final Map<String, List<Color>> pills = <String, List<Color>>{
          'success': <Color>[sem.onSuccessContainer, sem.successContainer],
          'warning': <Color>[sem.onWarningContainer, sem.warningContainer],
          'pending': <Color>[sem.onPendingContainer, sem.pendingContainer],
          'recording': <Color>[
            sem.onRecordingContainer,
            sem.recordingContainer,
          ],
          'ai': <Color>[sem.onAiContainer, sem.aiContainer],
        };
        pills.forEach((String name, List<Color> pair) {
          expectRatio(
            pair[0],
            pair[1],
            4.5,
            label: '${b.name} on${name}Container on ${name}Container',
          );
        });
      }
    });

    test('recording is a distinct red from error, and aiAccent = tertiary', () {
      for (final Brightness b in Brightness.values) {
        final ColorScheme cs = memSchemeFor(b);
        final MemSemanticColors sem = MemSemanticColors.of(b);
        expect(
          sem.recording,
          isNot(cs.error),
          reason:
              '${b.name}: a live microphone is not a failure — recording must '
              'never be colorScheme.error',
        );
        expect(sem.aiAccent, cs.tertiary, reason: '${b.name} aiAccent mirror');
        expect(sem.aiContainer, cs.tertiaryContainer);
        expect(sem.onAiContainer, cs.onTertiaryContainer);
      }
    });
  });

  group('token completeness — no role may fall back to a seed', () {
    test('dark scheme pins every role the app reads', () {
      const ColorScheme cs = memDarkScheme;
      expect(cs.brightness, Brightness.dark);
      expect(cs.primary, const Color(0xFF5EA2FF));
      expect(cs.onPrimary, const Color(0xFF002F63));
      expect(cs.primaryContainer, const Color(0xFF123A78));
      expect(cs.onPrimaryContainer, const Color(0xFFCFE2FF));
      expect(cs.primaryFixed, const Color(0xFFCFE2FF));
      expect(cs.onPrimaryFixed, const Color(0xFF002F63));
      expect(cs.primaryFixedDim, const Color(0xFF9EC6FF));
      expect(cs.onPrimaryFixedVariant, const Color(0xFF06407F));
      expect(cs.secondary, const Color(0xFFA9B4C6));
      expect(cs.onSecondary, const Color(0xFF16202E));
      expect(cs.secondaryContainer, const Color(0xFF232C3A));
      expect(cs.onSecondaryContainer, const Color(0xFFD8E1F0));
      expect(cs.tertiary, const Color(0xFFB79DFF));
      expect(cs.onTertiary, const Color(0xFF26105E));
      expect(cs.tertiaryContainer, const Color(0xFF3A2A6E));
      expect(cs.onTertiaryContainer, const Color(0xFFE5DBFF));
      expect(cs.error, const Color(0xFFFF6369));
      expect(cs.onError, const Color(0xFF3A0507));
      expect(cs.errorContainer, const Color(0xFF5C1519));
      expect(cs.onErrorContainer, const Color(0xFFFFD9D9));
      expect(cs.surface, const Color(0xFF050505));
      expect(cs.onSurface, const Color(0xFFEDEDF0));
      expect(cs.onSurfaceVariant, const Color(0xFF9A9AA5));
      expect(cs.surfaceDim, const Color(0xFF050505));
      expect(cs.surfaceBright, const Color(0xFF2A2A30));
      expect(cs.surfaceContainerLowest, const Color(0xFF0A0A0A));
      expect(cs.surfaceContainerLow, const Color(0xFF0E0E10));
      expect(cs.surfaceContainer, const Color(0xFF121214));
      expect(cs.surfaceContainerHigh, const Color(0xFF17171A));
      expect(cs.surfaceContainerHighest, const Color(0xFF1C1C20));
      expect(cs.outline, const Color(0xFF63636F));
      expect(cs.outlineVariant, const Color(0xFF2E2E36));
      expect(cs.inverseSurface, const Color(0xFFEDEDF0));
      expect(cs.onInverseSurface, const Color(0xFF17171A));
      expect(cs.inversePrimary, const Color(0xFF1E5AC8));
      expect(cs.shadow, const Color(0xFF000000));
      expect(cs.scrim, const Color(0xFF000000));
    });

    test('light scheme pins every role the app reads', () {
      const ColorScheme cs = memLightScheme;
      expect(cs.brightness, Brightness.light);
      expect(cs.primary, const Color(0xFF1E5AC8));
      expect(cs.onPrimary, const Color(0xFFFFFFFF));
      expect(cs.primaryContainer, const Color(0xFFDCE8FF));
      expect(cs.onPrimaryContainer, const Color(0xFF062E6B));
      expect(cs.primaryFixed, const Color(0xFFDCE8FF));
      expect(cs.onPrimaryFixed, const Color(0xFF062E6B));
      expect(cs.primaryFixedDim, const Color(0xFFAFC9F5));
      expect(cs.onPrimaryFixedVariant, const Color(0xFF124397));
      expect(cs.secondary, const Color(0xFF4D5A6E));
      expect(cs.onSecondary, const Color(0xFFFFFFFF));
      expect(cs.secondaryContainer, const Color(0xFFE1E7F0));
      expect(cs.onSecondaryContainer, const Color(0xFF1D2836));
      expect(cs.tertiary, const Color(0xFF6A48D0));
      expect(cs.onTertiary, const Color(0xFFFFFFFF));
      expect(cs.tertiaryContainer, const Color(0xFFE9E1FF));
      expect(cs.onTertiaryContainer, const Color(0xFF2A1265));
      expect(cs.error, const Color(0xFFBA1A1A));
      expect(cs.onError, const Color(0xFFFFFFFF));
      expect(cs.errorContainer, const Color(0xFFFFDAD6));
      expect(cs.onErrorContainer, const Color(0xFF410002));
      expect(cs.surface, const Color(0xFFFBFBFC));
      expect(cs.onSurface, const Color(0xFF17181C));
      expect(cs.onSurfaceVariant, const Color(0xFF5C616B));
      expect(cs.surfaceDim, const Color(0xFFDCDDE2));
      expect(cs.surfaceBright, const Color(0xFFFFFFFF));
      expect(cs.surfaceContainerLowest, const Color(0xFFFFFFFF));
      expect(cs.surfaceContainerLow, const Color(0xFFF6F7F9));
      expect(cs.surfaceContainer, const Color(0xFFF1F2F5));
      expect(cs.surfaceContainerHigh, const Color(0xFFEBECF0));
      expect(cs.surfaceContainerHighest, const Color(0xFFE4E6EB));
      expect(cs.outline, const Color(0xFF7E828C));
      expect(cs.outlineVariant, const Color(0xFFD7DAE1));
      expect(cs.inverseSurface, const Color(0xFF2C2E33));
      expect(cs.onInverseSurface, const Color(0xFFF1F2F5));
      expect(cs.inversePrimary, const Color(0xFF5EA2FF));
      expect(cs.shadow, const Color(0xFF000000));
      expect(cs.scrim, const Color(0xFF000000));
    });

    test('surfaceTint is transparent — the M3 elevation tint is dead', () {
      for (final Brightness b in Brightness.values) {
        expect(memSchemeFor(b).surfaceTint.a, 0.0, reason: b.name);
      }
    });

    test('the container ladder steps away from the canvas monotonically', () {
      // Low -> Highest must move steadily *away* from the canvas so a section
      // on a card on a sheet keeps reading as three distinct layers. (The
      // `lowest` step is deliberately outside this run: in light mode it is
      // pure white, which is brighter than the off-white canvas.)
      for (final Brightness b in Brightness.values) {
        final ColorScheme cs = memSchemeFor(b);
        final List<double> ladder = <double>[
          cs.surfaceContainerLow.computeLuminance(),
          cs.surfaceContainer.computeLuminance(),
          cs.surfaceContainerHigh.computeLuminance(),
          cs.surfaceContainerHighest.computeLuminance(),
        ];
        for (int i = 1; i < ladder.length; i++) {
          if (b == Brightness.dark) {
            expect(
              ladder[i],
              greaterThan(ladder[i - 1]),
              reason: 'dark ladder step $i must get lighter',
            );
          } else {
            expect(
              ladder[i],
              lessThan(ladder[i - 1]),
              reason: 'light ladder step $i must get darker',
            );
          }
        }
      }
    });
  });

  group('§2.12 ThemeData assembly', () {
    test('MemSemanticColors is registered on BOTH ThemeDatas', () {
      for (final Brightness b in Brightness.values) {
        final ThemeData theme = buildMemTheme(b);
        final MemSemanticColors? sem = theme.extension<MemSemanticColors>();
        expect(sem, isNotNull, reason: '${b.name} theme extension missing');
        expect(sem, same(MemSemanticColors.of(b)));
        expect(sem!.collectionInks, hasLength(kMemCollectionInkCount));
      }
    });

    test('scheme, scaffold, and elevation grammar', () {
      for (final Brightness b in Brightness.values) {
        final ThemeData theme = buildMemTheme(b);
        final ColorScheme cs = memSchemeFor(b);
        expect(theme.colorScheme, cs);
        expect(theme.brightness, b);
        expect(theme.scaffoldBackgroundColor, cs.surface);
        expect(theme.useMaterial3, isTrue);
        expect(theme.splashFactory, NoSplash.splashFactory);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.appBarTheme.backgroundColor, cs.surface);
        expect(theme.navigationBarTheme.elevation, 0);
        expect(theme.navigationBarTheme.backgroundColor, cs.surface);
        expect(theme.navigationBarTheme.indicatorColor, cs.primary);
        expect(theme.cardTheme.elevation, 0);
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(theme.bottomSheetTheme.modalElevation, 0);
        expect(theme.snackBarTheme.elevation, 0);
        expect(theme.floatingActionButtonTheme.elevation, 0);
        expect(theme.dividerTheme.color, cs.outlineVariant);
        expect(theme.dividerTheme.thickness, greaterThanOrEqualTo(1.0));
      }
    });

    test('the global InputDecorationTheme owns OutlineInputBorder', () {
      for (final Brightness b in Brightness.values) {
        final ThemeData theme = buildMemTheme(b);
        final InputDecorationThemeData deco = theme.inputDecorationTheme;
        expect(deco.filled, isTrue);
        expect(deco.fillColor, memSchemeFor(b).surfaceContainer);
        expect(deco.isDense, isFalse);
        expect(deco.enabledBorder, isA<OutlineInputBorder>());
        expect(deco.focusedBorder, isA<OutlineInputBorder>());
        expect(deco.errorBorder, isA<OutlineInputBorder>());
        expect(
          (deco.enabledBorder! as OutlineInputBorder).borderSide.color,
          memSchemeFor(b).outline,
        );
        expect(
          (deco.focusedBorder! as OutlineInputBorder).borderSide.width,
          2.0,
        );
      }
    });

    test('no stock component resolves to tertiary (§2.10 reservation)', () {
      for (final Brightness b in Brightness.values) {
        final ThemeData theme = buildMemTheme(b);
        final ColorScheme cs = memSchemeFor(b);
        const Set<WidgetState> selected = <WidgetState>{WidgetState.selected};

        expect(theme.progressIndicatorTheme.color, cs.primary);
        expect(theme.switchTheme.trackColor!.resolve(selected), cs.primary);
        expect(theme.radioTheme.fillColor!.resolve(selected), cs.primary);
        expect(theme.checkboxTheme.fillColor!.resolve(selected), cs.primary);
        expect(theme.sliderTheme.activeTrackColor, cs.primary);
        expect(theme.chipTheme.selectedColor, cs.primary);
        expect(
          theme.segmentedButtonTheme.style!.backgroundColor!.resolve(selected),
          cs.primary,
        );
        expect(
          theme.segmentedButtonTheme.style!.foregroundColor!.resolve(selected),
          cs.onPrimary,
        );
        expect(
          theme.navigationBarTheme.iconTheme!.resolve(selected)!.color,
          cs.onPrimary,
        );
      }
    });
  });

  group('§2.4 typography', () {
    test('every TextTheme role is pinned, tabular, and non-null', () {
      for (final Brightness b in Brightness.values) {
        final TextTheme t = buildMemTheme(b).textTheme;
        final Map<String, TextStyle?> roles = <String, TextStyle?>{
          'displayLarge': t.displayLarge,
          'displayMedium': t.displayMedium,
          'displaySmall': t.displaySmall,
          'headlineLarge': t.headlineLarge,
          'headlineMedium': t.headlineMedium,
          'headlineSmall': t.headlineSmall,
          'titleLarge': t.titleLarge,
          'titleMedium': t.titleMedium,
          'titleSmall': t.titleSmall,
          'bodyLarge': t.bodyLarge,
          'bodyMedium': t.bodyMedium,
          'bodySmall': t.bodySmall,
          'labelLarge': t.labelLarge,
          'labelMedium': t.labelMedium,
          'labelSmall': t.labelSmall,
        };
        roles.forEach((String name, TextStyle? style) {
          expect(style, isNotNull, reason: '${b.name} $name is null');
          expect(
            style!.fontFamilyFallback,
            kMemSansFallback,
            reason: '${b.name} $name has no pinned fallback',
          );
          expect(
            style.fontFeatures,
            kMemTabularFigures,
            reason: '${b.name} $name is not tabular',
          );
          expect(style.fontSize, isNotNull);
          expect(style.height, isNotNull);
        });
      }
    });

    test('the named scale matches the spec', () {
      final TextTheme t = memTextTheme(memDarkScheme);
      void check(
        String name,
        TextStyle? s,
        double size,
        double lineHeight,
        FontWeight weight,
        double tracking,
      ) {
        expect(s!.fontSize, size, reason: '$name size');
        expect(s.height, closeTo(lineHeight / size, 1e-9), reason: '$name lh');
        expect(s.fontWeight, weight, reason: '$name weight');
        expect(s.letterSpacing, tracking, reason: '$name tracking');
      }

      check('displaySmall', t.displaySmall, 32, 38, FontWeight.w700, -0.5);
      check('headlineSmall', t.headlineSmall, 24, 30, FontWeight.w600, -0.25);
      check('titleLarge', t.titleLarge, 20, 26, FontWeight.w600, -0.2);
      check('titleMedium', t.titleMedium, 16, 22, FontWeight.w600, -0.1);
      check('titleSmall', t.titleSmall, 14, 20, FontWeight.w600, 0);
      check('bodyLarge', t.bodyLarge, 16, 26, FontWeight.w400, 0);
      check('bodyMedium', t.bodyMedium, 14, 20, FontWeight.w400, 0);
      check('bodySmall', t.bodySmall, 12, 16, FontWeight.w400, 0.1);
      check('labelLarge', t.labelLarge, 14, 20, FontWeight.w600, 0.1);
      check('labelMedium', t.labelMedium, 12, 16, FontWeight.w600, 0.4);
      check('labelSmall', t.labelSmall, 11, 14, FontWeight.w700, 0.8);
    });

    test('the mono style is pinned and tabular too', () {
      final TextStyle mono = memMonoStyle();
      expect(mono.fontFamily, kMemMono);
      expect(mono.fontFamilyFallback, kMemMonoFallback);
      expect(mono.fontFeatures, kMemTabularFigures);
      expect(mono.fontSize, 13);
    });
  });
}
