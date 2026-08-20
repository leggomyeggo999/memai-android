// Headless rendering harness for the "Midnight Instrument" golden showcase.
//
// `flutter test` runs on the Dart VM with the engine's *test* font, which draws
// every glyph as a filled rectangle. A golden rendered that way is worthless for
// a human review — the whole point of these images is to read the type ramp and
// the copy. So this harness loads the **real** Roboto (and the real
// MaterialIcons glyph font) out of the Flutter SDK's `material_fonts` artifact
// cache before any golden is pumped.
//
// Why the family name is `Roboto`: `lib/theme/mem_typography.dart` sets
// `fontFamily: kMemSans` (which is `null`) and
// `fontFamilyFallback: ['Roboto', 'Noto Sans', 'sans-serif']` on every style the
// theme produces. `ui.TextStyle` builds its family list as
// `[?fontFamily, ...fontFamilyFallback]`, so with a null `fontFamily` the first
// family the engine ever looks up is literally `Roboto`. Registering the SDK's
// roboto-*.ttf under that exact family is therefore what the theme resolves to —
// no theme override, no `copyWith`, no fork of the production text theme.
//
// `MaterialIcons` gets the same treatment: without it every `Icon` in the app
// renders as the missing-glyph box, which would make the goldens lie about the
// icon language just as badly as box-text would.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical size of the golden "device": a common 411 x 915 dp Android phone.
const Size kMemGoldenLogicalSize = Size(411, 915);

/// Device pixel ratio the goldens are captured at. 2.0 keeps text crisp enough
/// to read in a reviewer's image viewer without producing enormous PNGs.
const double kMemGoldenDpr = 2.0;

/// A frozen "now" so every relative timestamp and day label in the goldens is
/// byte-stable across runs. Nothing in the harness reads the wall clock.
final DateTime kMemGoldenNow = DateTime(2026, 3, 4, 15, 30);

bool _fontsLoaded = false;

/// Loads the real Roboto + MaterialIcons faces into the test engine.
///
/// Idempotent, and safe to call from `setUpAll`. Throws with an actionable
/// message if the SDK artifact cache cannot be found — a silent fallback would
/// hand back box-glyph goldens, which is the exact failure this exists to stop.
Future<void> loadMemGoldenFonts() async {
  if (_fontsLoaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  final Directory dir = _materialFontsDir();

  await _loadFamily(dir, 'Roboto', const <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-light.ttf',
  ]);
  // Bold/medium italics are not used by the theme; regular italic is, by
  // Markdown emphasis, so it is cheap insurance.
  await _loadFamily(dir, 'Roboto', const <String>[
    'roboto-italic.ttf',
  ], optional: true);

  await _loadFamily(dir, 'MaterialIcons', const <String>[
    'materialicons-regular.otf',
  ]);

  _fontsLoaded = true;
}

Future<void> _loadFamily(
  Directory dir,
  String family,
  List<String> fileNames, {
  bool optional = false,
}) async {
  final FontLoader loader = FontLoader(family);
  int added = 0;
  for (final String name in fileNames) {
    final File f = File('${dir.path}${Platform.pathSeparator}$name');
    if (!f.existsSync()) {
      if (optional) continue;
      throw StateError(
        'Golden harness: missing font "$name" in ${dir.path}. '
        'Run `flutter precache` or point MEM_MATERIAL_FONTS_DIR at a directory '
        'that contains the Flutter SDK material_fonts artifacts.',
      );
    }
    final Uint8List bytes = await f.readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    added++;
  }
  if (added == 0) return;
  await loader.load();
}

/// Finds the SDK's `bin/cache/artifacts/material_fonts` directory.
///
/// Resolution order: an explicit env override, `FLUTTER_ROOT`, then a walk up
/// from the running Dart executable (`<flutter>/bin/cache/dart-sdk/bin/dart`).
Directory _materialFontsDir() {
  final List<String> candidates = <String>[];

  final String? override =
      Platform.environment['MEM_MATERIAL_FONTS_DIR'];
  if (override != null && override.isNotEmpty) candidates.add(override);

  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    candidates.add(_join(flutterRoot, 'bin/cache/artifacts/material_fonts'));
  }

  Directory walk = File(Platform.resolvedExecutable).parent;
  for (int i = 0; i < 8; i++) {
    candidates.add(_join(walk.path, 'artifacts/material_fonts'));
    candidates.add(_join(walk.path, 'bin/cache/artifacts/material_fonts'));
    final Directory parent = walk.parent;
    if (parent.path == walk.path) break;
    walk = parent;
  }

  for (final String c in candidates) {
    final Directory d = Directory(c);
    if (d.existsSync() &&
        File('${d.path}${Platform.pathSeparator}roboto-regular.ttf')
            .existsSync()) {
      return d;
    }
  }
  throw StateError(
    'Golden harness: could not locate the Flutter SDK material_fonts cache. '
    'Tried:\n  ${candidates.join('\n  ')}\n'
    'Set MEM_MATERIAL_FONTS_DIR to the directory holding roboto-regular.ttf.',
  );
}

String _join(String a, String b) {
  final String sep = Platform.pathSeparator;
  final String tail = b.replaceAll('/', sep);
  return a.endsWith(sep) ? '$a$tail' : '$a$sep$tail';
}

/// The concrete family `fontFamily: null` resolves to on the real product
/// target. `kMemSans` is deliberately null so Android hands the app its platform
/// face, and `kMemSansFallback` pins that to Roboto first.
const String _kGoldenFamily = 'Roboto';

// ---------------------------------------------------------------------------
// Spinner phase
// ---------------------------------------------------------------------------

/// Number of "path" cycles `CircularProgressIndicator` packs into one turn of
/// its controller.
///
/// From `material/progress_indicator.dart`: the indeterminate controller runs
/// for `_kIndeterminateCircularDuration = 1333 * 2222` ms and
/// `_pathCount = _kIndeterminateCircularDuration ~/ 1333`, i.e. 2222 sweeps of
/// 1333 ms each.
const int kMemGoldenSpinnerPathCount = 2222;

/// The controller phase at which the indeterminate arc is at its **longest**.
///
/// Everything `_CircularProgressIndicatorPainter` draws is a pure function of
/// `controller.value`. Let `s = SawTooth(_pathCount).transform(value)` be the
/// position inside one 1333 ms sweep; then
///
/// ```text
/// head  = Interval(0.0, 0.5, curve: fastOutSlowIn).transform(s)
/// tail  = Interval(0.5, 1.0, curve: fastOutSlowIn).transform(s)
/// sweep = (head - tail) * 3 / 2 * pi
/// ```
///
/// `head` finishes climbing to 1.0 exactly at `s == 0.5`, which is also the
/// last instant before `tail` leaves 0.0 — so `s == 0.5` is the single frame
/// where the arc is a full 3/2 pi (270 degree) "C". Either side of it the arc
/// is shorter, and near `s == 0` or `s == 1` it collapses to the ~2 px dash
/// that made these goldens look like a broken component.
///
/// `s == 0.5` therefore means `value == 0.5 / _pathCount`.
const double kMemGoldenSpinnerPhase = 0.5 / kMemGoldenSpinnerPathCount;

AnimationController? _spinnerController;

/// A **stopped** controller parked at [kMemGoldenSpinnerPhase].
///
/// Injected into `ProgressIndicatorThemeData.controller` by [memGoldenTheme],
/// which is what every `CircularProgressIndicator` under the golden
/// `MaterialApp` resolves to when it has no `controller` of its own (see
/// `_CircularProgressIndicatorState._controller`). Because it never ticks, the
/// painted phase no longer depends on *when* the spinner's element happened to
/// be built — which is the whole bug: [resolveMaxScrollExtent] and the per-page
/// `jumpTo` calls build and dispose lazy `ListView` children repeatedly, so a
/// self-driven controller started at a different moment on every page landed on
/// a different, sometimes invisible, point of the sweep.
///
/// One instance for the whole process: it owns no started `Ticker`, so there is
/// nothing to leak, and sharing it keeps every spinner in every golden at the
/// identical pose.
AnimationController get memGoldenSpinnerController =>
    _spinnerController ??= AnimationController(
      vsync: const TestVSync(),
      duration: CircularProgressIndicator.defaultAnimationDuration,
      value: kMemGoldenSpinnerPhase,
    );

/// Returns [theme] with an explicit `fontFamily` on every text style that had
/// none.
///
/// **Why this is needed, and why it is not a lie.** `ui.ParagraphBuilder` builds
/// its family list as `[fontFamily ?? '', ...fontFamilyFallback]`. The empty
/// first entry is matched by `flutter_test`'s font manager — which answers *any*
/// family it does not know with the box-glyph test font — so resolution stops
/// before it ever reaches the `'Roboto'` fallback entry. Styles that go through
/// `ThemeData`'s `Typography` merge escape this, because `Typography` supplies
/// `fontFamily: 'Roboto'`; the styles `buildMemTheme` assigns straight into a
/// sub-theme (`appBarTheme.titleTextStyle`, `chipTheme.labelStyle`, the button
/// `textStyle`s, …) do not, and those are the ones that render as white bars.
///
/// Pinning the null families to `Roboto` reproduces exactly what Android's font
/// manager does with `fontFamily: null` on a device, so the goldens still show
/// the shipped type ramp — same sizes, weights, tracking, and tabular figures.
///
/// It also parks every indeterminate `CircularProgressIndicator` on
/// [memGoldenSpinnerController]. That is a capture-time concern only: the pose
/// it freezes is a real frame of the real animation (the widest one), it does
/// not change a single colour, size or stroke, and nothing in `lib/` is aware
/// of it.
ThemeData memGoldenTheme(ThemeData theme) {
  ButtonStyle? btn(ButtonStyle? s) =>
      s?.copyWith(textStyle: _pinProp(s.textStyle));

  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: _kGoldenFamily),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: _kGoldenFamily),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: _pin(theme.appBarTheme.titleTextStyle),
      toolbarTextStyle: _pin(theme.appBarTheme.toolbarTextStyle),
    ),
    navigationBarTheme: theme.navigationBarTheme.copyWith(
      labelTextStyle: _pinProp(theme.navigationBarTheme.labelTextStyle),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      hintStyle: _pin(theme.inputDecorationTheme.hintStyle),
      labelStyle: _pin(theme.inputDecorationTheme.labelStyle),
      floatingLabelStyle: _pin(theme.inputDecorationTheme.floatingLabelStyle),
      helperStyle: _pin(theme.inputDecorationTheme.helperStyle),
      errorStyle: _pin(theme.inputDecorationTheme.errorStyle),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: _pin(theme.chipTheme.labelStyle),
      secondaryLabelStyle: _pin(theme.chipTheme.secondaryLabelStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: btn(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: btn(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: btn(theme.textButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: btn(theme.elevatedButtonTheme.style),
    ),
    segmentedButtonTheme: theme.segmentedButtonTheme.copyWith(
      style: btn(theme.segmentedButtonTheme.style),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: _pin(theme.dialogTheme.titleTextStyle),
      contentTextStyle: _pin(theme.dialogTheme.contentTextStyle),
    ),
    snackBarTheme: theme.snackBarTheme.copyWith(
      contentTextStyle: _pin(theme.snackBarTheme.contentTextStyle),
    ),
    floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
      extendedTextStyle: _pin(theme.floatingActionButtonTheme.extendedTextStyle),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      titleTextStyle: _pin(theme.listTileTheme.titleTextStyle),
      subtitleTextStyle: _pin(theme.listTileTheme.subtitleTextStyle),
      leadingAndTrailingTextStyle: _pin(
        theme.listTileTheme.leadingAndTrailingTextStyle,
      ),
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      textStyle: _pin(theme.popupMenuTheme.textStyle),
      labelTextStyle: _pinProp(theme.popupMenuTheme.labelTextStyle),
    ),
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: _pin(theme.tooltipTheme.textStyle),
    ),
    progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
      controller: memGoldenSpinnerController,
    ),
  );
}

TextStyle? _pin(TextStyle? s) {
  if (s == null || s.fontFamily != null) return s;
  return s.copyWith(fontFamily: _kGoldenFamily);
}

WidgetStateProperty<TextStyle?>? _pinProp(
  WidgetStateProperty<TextStyle?>? property,
) {
  if (property == null) return null;
  return WidgetStateProperty.resolveWith<TextStyle?>(
    (Set<WidgetState> states) => _pin(property.resolve(states)),
  );
}

/// Sizes the test view to the golden device and restores it afterwards.
void sizeGoldenView(
  WidgetTester tester, {
  Size logicalSize = kMemGoldenLogicalSize,
  double dpr = kMemGoldenDpr,
}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(
    logicalSize.width * dpr,
    logicalSize.height * dpr,
  );
  addTearDown(tester.view.reset);
}

/// Pumps [child] inside a real `MaterialApp` carrying [theme].
///
/// Uses the production `memDarkTheme` / `memLightTheme` verbatim — the harness
/// never patches the theme, so what a golden shows is what the app ships.
///
/// Deliberately **no `pumpAndSettle`**: `SkeletonList`, `InlineSpinner` and
/// `MemTypingDots` all own repeating `AnimationController`s, so a settle would
/// spin until the 10-minute timeout. (`InlineSpinner` still *starts* its
/// internal controller even though [memGoldenTheme] hands it a parked one to
/// paint from, so this stays true.) Frames are advanced by a fixed number of
/// fixed-length pumps instead, which is also what makes the pulse phase (and
/// therefore the image) reproducible.
Future<void> pumpMemGolden(
  WidgetTester tester, {
  required ThemeData theme,
  required Widget child,
  Size logicalSize = kMemGoldenLogicalSize,
  double dpr = kMemGoldenDpr,
}) async {
  sizeGoldenView(tester, logicalSize: logicalSize, dpr: dpr);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: memGoldenTheme(theme),
      home: child,
    ),
  );
  await settleMemGolden(tester);
}

/// Advances enough frames for layout, post-frame callbacks (e.g. `ChipStrip`'s
/// overflow probe) and any route transition to reach a stable pose.
Future<void> settleMemGolden(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Resolves the true scroll extent of a **lazy** [ListView].
///
/// A lazy sliver only reports the extent of the children it has already laid
/// out, so reading `maxScrollExtent` once and jumping there lands short of the
/// end. Jumping repeatedly forces the remaining children to build until the
/// number stops growing.
Future<double> resolveMaxScrollExtent(
  WidgetTester tester,
  ScrollController controller,
) async {
  double previous = -1;
  double current = controller.position.maxScrollExtent;
  for (int i = 0; i < 12 && current > previous; i++) {
    previous = current;
    controller.jumpTo(current);
    await tester.pump();
    current = controller.position.maxScrollExtent;
  }
  controller.jumpTo(0);
  await tester.pump();
  return current;
}

/// Captures the whole app surface to `test/goldens/<name>.png`.
Future<void> expectMemGolden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// The two production themes, paired with the filename prefix used for each.
const List<(String, bool)> kMemGoldenThemes = <(String, bool)>[
  ('dark', true),
  ('light', false),
];
