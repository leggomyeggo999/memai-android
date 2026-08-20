# MemDroid Design Spec — "Midnight Instrument"

**Status:** Definitive. This document is the single source of truth for the UI redesign.
**Audience:** parallel implementation agents. You will not see the candidate directions or the
judge verdicts — everything you need is here.
**Companion documents (read them, they are binding):**
`docs/redesign/CONSTRAINTS.md` (hard contracts — violating one is a bug even if this spec seems
to allow it) and `docs/redesign/UX_FINDINGS.md` (the numbered problems `#1`–`#15` referenced
throughout).

**Rule of precedence:** `CONSTRAINTS.md` > this spec > your judgement. Where this spec appears
to contradict a constraint, the constraint wins and you must flag it in your PR description.

---

## 0. HOW TO USE THIS DOCUMENT

1. Find your work package in §6. It names the **exact files you own**. Do not edit files owned
   by another package — coordination cost is the main risk in a parallel rebuild.
2. Read §1 (identity), §2 (tokens), and the §3 entries for the components you consume.
3. Read your screen's §4 entry **including its "Constraint callouts" block**, which reproduces
   the contracts from `CONSTRAINTS.md` that apply to your file.
4. Run the verification checklist in §6.4 before you call your package done.

### 0.1 Ten rules that apply everywhere

1. **Elevation is zero, app-wide.** `elevation: 0` and `surfaceTintColor: Colors.transparent` on
   every surface. Depth = a surface step + a 1dp hairline. **No `BoxShadow` anywhere, in either
   theme.** The only darkness that reads as a shadow is the modal scrim.
2. **No raw exception text ever reaches a user.** Everything goes through `memErrorText()` (§3.6).
3. **No hardcoded `Color(0x…)` outside `lib/theme/`.** Read colours from `Theme.of(context).colorScheme`
   or `Theme.of(context).extension<MemSemanticColors>()!`.
4. **Every interactive element has a ≥48dp touch target.** Visual size may be smaller; pad it out.
5. **`tertiary` is reserved for AI provenance.** No stock component (SegmentedButton, Switch,
   FilterChip, ProgressIndicator, Slider) may resolve to `tertiary`. See §2.10.
6. **Per-frame cost budget** (§2.11): no shimmer-sweep gradients, no `ShaderMask`, no `Opacity`
   wrapping a long list, no shadows, no default 300 ms ripple.
7. **Async hygiene is load-bearing.** Capture `ScaffoldMessenger` *before* every `await`; check
   `mounted` after every `await`; defer `AppScope` reads to post-frame in `initState` paths.
   Use `AsyncPageMixin` (§3.15).
8. **Numerals are tabular everywhere** (§2.4). Timers and relative times must never shift layout.
9. **Loading never blanks content that already exists.** Skeletons are for first load only.
10. **No new pub packages.** No `google_fonts`, no new binary assets. See §2.4.

---

## 1. IDENTITY

### 1.1 Thesis

**MemDroid is a precision instrument for thought.** A true-black OLED canvas (and a cool-paper
light twin) where hierarchy is built from tonal surface steps and 1dp hairlines instead of
shadows; one electric blue does all the talking; one violet marks everything a model produced;
one warm ink ramp gives every collection a stable identity colour; and every number is tabular
so nothing jitters.

The feel is *fast and honest*. Touch is answered in 80 ms, not with a 300 ms ripple bloom.
Refreshes never blank the screen. Errors say what happened and offer a way out. Destructive acts
are reversible or clearly confirmed. Background work is visible.

### 1.2 What beats Mem iOS, and why

| Axis | Mem iOS | MemDroid |
|---|---|---|
| **Speed-feel** | Soft cards, shadow animations, spinners that blank the list | 80 ms press flash, `NoSplash`, stale-content retention on refresh, skeletons only on first load, infinite scroll |
| **Information density** | ~2 fields per row, low density, mushy hierarchy | 76 dp note rows: title + 2-line snippet + collection tags + relative time; filter chips carry note counts; NoteDetail shows created/updated/word count |
| **Wayfinding** | Collection colour is decoration on one screen | The collection ink follows a collection *everywhere* — filter chip, note-row tag, detail chip, Capture picker, Collections list. Users navigate by colour before they read a word |
| **AI provenance** | AI and user content blur together | One violet marks everything the model touched: the assistant header sparkle, the streaming caret, the "Processing in Mem" chip. User ink is never violet |
| **Honesty** | State implied by which button is greyed out | Explicit `StatusTile`s with dots and copy; real drag handles; a live amplitude ring instead of a progress bar that looks like loading |
| **Recovery** | Destructive actions promoted, no undo | Cancel is the promoted button, the destructive action is a demoted error-coloured text button, and trash + capture-clear both offer real Undo |

### 1.3 Explicitly out of scope (named follow-ups, do not build)

- **NEXT-1 — Note previews inside chat answers.** Parsing assistant output for note references
  and rendering nested cards is *pipeline* work, not presentation. Same for surfacing
  `MemToolRunner` tool-call events as inline "Added to # X" confirmations.
- **NEXT-2 — Stop / cancel generation.** Verified: there is no `CancelToken` or stream
  cancellation anywhere in `lib/core/llm/`. The three provider paths cannot be cancelled today.
  The UI must **not** promise a Stop button (§4.5). Ship cancellation plumbing first.
- **NEXT-3 — Hold-to-talk gesture-arena rework beyond pointer-down.** Pointer-down start *is* in
  scope (§4.4). Full slide-to-cancel with scroll-conflict arbitration is not.
- **NEXT-4 — `ChatPromptQueue` consecutive-duplicate dedupe.** `#13` notes double-tapping the
  widget burns two LLM runs. The redesign only *displays* queue depth; it must not change queue
  semantics. File the dedupe separately.
- **NEXT-5 — Vendoring Inter/JetBrains Mono as binary font assets.** See §2.4.

---

## 2. TOKENS

All token files live under `lib/theme/` and are owned by **WP-0**. Every other package reads
them; nobody else writes them.

### 2.1 Default theme mode

- The app ships **`ThemeMode.dark` by default**. Dark is the existing product identity
  (`scaffoldBackgroundColor #050505`) and the launch splash is dark.
- **Light is fully first-class**, uses the *identical depth grammar* (zero elevation, hairlines,
  no shadows), and is selectable.
- `MaterialApp` gets `theme:` (light), `darkTheme:` (dark), and `themeMode: app.themeMode`.
- Settings → Appearance offers **System / Light / Dark**, persisted via `AppearanceStore`
  (`shared_preferences`, key `appearance_theme_mode_v1`, values `system|light|dark`, default
  `dark`).
- **Splash discontinuity is fixed by WP-0B:** `values/colors.xml` gets a light `launch_bg`,
  a new `values-night/colors.xml` gets the dark one, and both `styles.xml` files already select
  the right parent. Anyone choosing System or Light must not see a dark→light flash.

### 2.2 ColorScheme — DARK (default)

Construct explicitly with `ColorScheme(brightness: Brightness.dark, …)` — **not** `fromSeed`.
Every field below must be set; an unset role falls back to a seed-derived colour and drifts.

```dart
const memDarkScheme = ColorScheme(
  brightness: Brightness.dark,

  primary:              Color(0xFF5EA2FF),
  onPrimary:            Color(0xFF002F63),
  primaryContainer:     Color(0xFF123A78),
  onPrimaryContainer:   Color(0xFFCFE2FF),
  primaryFixed:         Color(0xFFCFE2FF),
  onPrimaryFixed:       Color(0xFF002F63),
  primaryFixedDim:      Color(0xFF9EC6FF),
  onPrimaryFixedVariant:Color(0xFF06407F),

  secondary:            Color(0xFFA9B4C6),
  onSecondary:          Color(0xFF16202E),
  secondaryContainer:   Color(0xFF232C3A),
  onSecondaryContainer: Color(0xFFD8E1F0),

  tertiary:             Color(0xFFB79DFF), // AI ONLY — see §2.10
  onTertiary:           Color(0xFF26105E),
  tertiaryContainer:    Color(0xFF3A2A6E),
  onTertiaryContainer:  Color(0xFFE5DBFF),

  error:                Color(0xFFFF6369),
  onError:              Color(0xFF3A0507),
  errorContainer:       Color(0xFF5C1519),
  onErrorContainer:     Color(0xFFFFD9D9),

  surface:                   Color(0xFF050505), // scaffold + canvas
  onSurface:                 Color(0xFFEDEDF0),
  onSurfaceVariant:          Color(0xFF9A9AA5),
  surfaceDim:                Color(0xFF050505),
  surfaceBright:             Color(0xFF2A2A30),
  surfaceContainerLowest:    Color(0xFF0A0A0A), // sticky bars, input bar
  surfaceContainerLow:       Color(0xFF0E0E10), // list sections, cards
  surfaceContainer:          Color(0xFF121214), // inputs, chips, search pill
  surfaceContainerHigh:      Color(0xFF17171A), // pressed rows, user bubbles
  surfaceContainerHighest:   Color(0xFF1C1C20), // sheets, dialogs

  outline:        Color(0xFF63636F), // BOUNDARY hairline — ≥3:1, see §2.7
  outlineVariant: Color(0xFF2E2E36), // DIVIDER hairline — decorative

  inverseSurface:   Color(0xFFEDEDF0),
  onInverseSurface: Color(0xFF17171A),
  inversePrimary:   Color(0xFF1E5AC8),

  surfaceTint: Color(0x00000000), // transparent — kills M3 elevation tint
  shadow:      Color(0xFF000000),
  scrim:       Color(0xFF000000),
);
```

Modal scrim opacity: **60 %** (`scrim.withValues(alpha: 0.60)`), dark and light alike.

### 2.3 ColorScheme — LIGHT ("Daylight Instrument")

Deliberately a **cool paper**, not a warm cream — it must not read as a re-skin of the official
Mem client.

```dart
const memLightScheme = ColorScheme(
  brightness: Brightness.light,

  primary:              Color(0xFF1E5AC8), // evolution of the historic #1E5AA8 seed
  onPrimary:            Color(0xFFFFFFFF),
  primaryContainer:     Color(0xFFDCE8FF),
  onPrimaryContainer:   Color(0xFF062E6B),
  primaryFixed:         Color(0xFFDCE8FF),
  onPrimaryFixed:       Color(0xFF062E6B),
  primaryFixedDim:      Color(0xFFAFC9F5),
  onPrimaryFixedVariant:Color(0xFF124397),

  secondary:            Color(0xFF4D5A6E),
  onSecondary:          Color(0xFFFFFFFF),
  secondaryContainer:   Color(0xFFE1E7F0),
  onSecondaryContainer: Color(0xFF1D2836),

  tertiary:             Color(0xFF6A48D0), // AI ONLY — see §2.10
  onTertiary:           Color(0xFFFFFFFF),
  tertiaryContainer:    Color(0xFFE9E1FF),
  onTertiaryContainer:  Color(0xFF2A1265),

  error:                Color(0xFFBA1A1A),
  onError:              Color(0xFFFFFFFF),
  errorContainer:       Color(0xFFFFDAD6),
  onErrorContainer:     Color(0xFF410002),

  surface:                   Color(0xFFFBFBFC),
  onSurface:                 Color(0xFF17181C),
  onSurfaceVariant:          Color(0xFF5C616B),
  surfaceDim:                Color(0xFFDCDDE2),
  surfaceBright:             Color(0xFFFFFFFF),
  surfaceContainerLowest:    Color(0xFFFFFFFF),
  surfaceContainerLow:       Color(0xFFF6F7F9),
  surfaceContainer:          Color(0xFFF1F2F5),
  surfaceContainerHigh:      Color(0xFFEBECF0),
  surfaceContainerHighest:   Color(0xFFE4E6EB),

  outline:        Color(0xFF7E828C), // BOUNDARY hairline — ≥3:1
  outlineVariant: Color(0xFFD7DAE1), // DIVIDER hairline — decorative

  inverseSurface:   Color(0xFF2C2E33),
  onInverseSurface: Color(0xFFF1F2F5),
  inversePrimary:   Color(0xFF5EA2FF),

  surfaceTint: Color(0x00000000),
  shadow:      Color(0xFF000000),
  scrim:       Color(0xFF000000),
);
```

**Verified contrast (must not regress — `test/theme_contrast_test.dart` enforces it):**

| Pair | Dark | Light |
|---|---|---|
| `onSurface` on `surface` | 17.4 : 1 | 17.2 : 1 |
| `onSurfaceVariant` on `surface` | 7.3 : 1 | 6.0 : 1 |
| `onSurfaceVariant` on `surfaceContainerLow` | 6.9 : 1 | 5.7 : 1 |
| `primary` on `surface` | 7.9 : 1 | 6.1 : 1 |
| `tertiary` on `surface` | 9.0 : 1 | 5.9 : 1 |
| `outline` on `surface` | 3.2 : 1 | 3.7 : 1 |
| `outline` on `surfaceContainer` | 3.2 : 1 | 3.4 : 1 |
| `onPrimary` on `primary` | 5.1 : 1 | 6.1 : 1 |

Secondary text is **always** `onSurfaceVariant`. Never `onSurface` with an opacity — opacity-faded
white is the most common M3 dark-mode contrast failure and is banned.

### 2.4 Typography

**Font decision — no `google_fonts`, no new packages, no network fetch.**

`pubspec.yaml` has no `google_fonts` dependency and the `fonts:` section is commented out. Adding
a runtime-fetched webfont to an app that is otherwise usable offline at launch would mean the
first cold/offline start renders a different face than the design, and CI goldens would race a
network fetch. **The identity here is carried by the scale — sizes, weights, tracking, and
tabular figures — not by a bespoke face.** We ship on the platform stack.

```dart
const kMemSans = null;                       // inherit platform default (Roboto on Android)
const kMemSansFallback = <String>['Roboto', 'Noto Sans', 'sans-serif'];
const kMemMono = 'RobotoMono';
const kMemMonoFallback = <String>['monospace'];
```

Set `fontFamilyFallback: kMemSansFallback` on every `TextStyle` in the theme so rendering is
pinned and identical in CI and on device. The first frame must never wait on a font.

**Global numeral rule (mandatory):** every style in the `TextTheme` carries
`fontFeatures: const [FontFeature.tabularFigures()]`. Timestamps, counts, elapsed timers,
and `n/4` figures then tick without a pixel of layout shift. This is the subliminal "instrument"
tell.

**Scale** — `size/line-height, weight, tracking`, all in logical pixels:

| Role | Spec | Used for |
|---|---|---|
| `displaySmall` | 32/38, w700, −0.5 | Empty-state and first-run headlines only |
| `headlineSmall` | 24/30, w600, −0.25 | NoteDetail title |
| `titleLarge` | 20/26, w600, −0.2 | AppBar titles |
| `titleMedium` | 16/22, w600, −0.1 | Row titles, card titles |
| `titleSmall` | 14/20, w600, 0 | Sheet headers, `StatusTile` labels |
| `bodyLarge` | 16/26, w400, 0 | Markdown body, chat text, multi-line inputs |
| `bodyMedium` | 14/20, w400, 0 | Row snippets, field descriptions |
| `bodySmall` | 12/16, w400, +0.1 | Metadata, timestamps, counts |
| `labelLarge` | 14/20, w600, +0.1 | Buttons |
| `labelMedium` | 12/16, w600, +0.4 | Chips, collection tags |
| `labelSmall` | 11/14, w700, +0.8 | Section eyebrows **(UPPERCASE)** |

**Date group headers are NOT `labelSmall` and NOT uppercase.** `#15` names ALL-CAPS as the
problem. They render in `labelMedium` **sentence case** (`Today`, `Yesterday`, `Monday`,
`Mar 4`) in `onSurfaceVariant`. `labelSmall` UPPERCASE is reserved for structural section
eyebrows in Settings and Prompt Jobs (`ACCOUNT`, `CHAT MODELS`, `PINNED · 2/4`).

**Markdown ramp** (NoteDetail read mode, `MarkdownStyleSheet`):
h1 22/28 w700 · h2 18/24 w600 · h3 16/22 w600 · p 16/26 w400 · blockquote 16/26 with a 3 dp
`outline` left rule · code (inline and block) `kMemMono` 13/20 on `surfaceContainer`, radius 6,
1 dp `outlineVariant` border · links `primary`, underline on press only.

### 2.5 Semantic tokens — `MemSemanticColors`

`lib/theme/mem_semantic_colors.dart`. A `ThemeExtension<MemSemanticColors>` registered on both
`ThemeData`s. Access: `Theme.of(context).extension<MemSemanticColors>()!`.

```dart
@immutable
class MemSemanticColors extends ThemeExtension<MemSemanticColors> {
  final Color success, successContainer, onSuccessContainer;
  final Color warning, warningContainer, onWarningContainer;
  final Color pending, pendingContainer, onPendingContainer;
  final Color recording, recordingContainer, onRecordingContainer;
  final Color aiAccent, aiContainer, onAiContainer;          // mirrors tertiary
  final List<CollectionInk> collectionInks;                   // exactly 8
  // + copyWith / lerp
}
```

| Token | Dark | Light | Use |
|---|---|---|---|
| `success` | `#3DD68C` | `#1B7F4B` | 8 dp status dot, status-pill text |
| `successContainer` / `onSuccessContainer` | `#0C2E24` / `#B6EFD4` | `#DDF5EC` / `#0A3D28` | status pill background |
| `warning` | `#FFB224` | `#B26A00` | advisory: model-catalog drift, session-retention hint |
| `warningContainer` / `onWarningContainer` | `#33270C` / `#FFE0A6` | `#FBF0D7` / `#5C3A00` | |
| `pending` | `#E8C26C` | `#8A5A00` | **in-flight work**: OAuth browser round-trip, memIt processing, widget sync |
| `pendingContainer` / `onPendingContainer` | `#3A2E12` / `#F3DFB4` | `#FAEFD6` / `#4A2F00` | |
| `recording` | `#FF8A7A` | `#C03A2E` | **mic active only** — deliberately distinct from `error` |
| `recordingContainer` / `onRecordingContainer` | `#3A1512` / `#FFD6CF` | `#FCE4E0` / `#4A150E` | |
| `aiAccent` | `#B79DFF` | `#6A48D0` | = `tertiary`; mirrored so AI sites read as intentional |
| `aiContainer` / `onAiContainer` | `#3A2A6E` / `#E5DBFF` | `#E9E1FF` / `#2A1265` | |

**Hard rule:** `success`, `warning`, and `pending` appear **only** as an 8 dp dot or as
status-pill text/containers. They are never a fill for a button, a row, or a chip. This is what
keeps the colour constitution from leaking.

### 2.6 Collection ink ramp (derived client-side)

The Mem data model has **no** colour or emoji field on collections (`MemCollectionItem` is
`id/title/description/noteCount/createdAt/updatedAt`). Colour is a **derived presentation token**,
never API data. Document it as such in code.

`lib/theme/mem_collection_ink.dart`:

```dart
@immutable
class CollectionInk {
  const CollectionInk({required this.fg, required this.bg, required this.name});
  final Color fg;   // dot + label
  final Color bg;   // tag / chip background
  final String name;
}

/// FNV-1a (32-bit) over the UTF-16 code units of the collection id.
/// Stable forever: the same id always lands on the same ink, across sessions,
/// devices, and screens. NEVER re-hash to avoid a collision.
int collectionInkIndex(String collectionId) {
  var hash = 0x811c9dc5;
  for (final unit in collectionId.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
    hash ^= (unit >> 8) & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash % 8;
}

CollectionInk collectionInkFor(BuildContext context, String collectionId) =>
    Theme.of(context).extension<MemSemanticColors>()!
        .collectionInks[collectionInkIndex(collectionId)];
```

Explicit `(fg, bg)` **pairs per brightness** — never an alpha-blended fill, so contrast is
deterministic on every surface the tag lands on.

| # | Name | Dark fg / bg | Light fg / bg | Label contrast (12 sp w600) |
|---|---|---|---|---|
| 0 | Blue | `#6DA6FF` / `#12233F` | `#1E55B8` / `#E3ECFC` | 6.4 / 5.8 |
| 1 | Cyan | `#4CC9E8` / `#0E2B33` | `#0E6E88` / `#DFF4F9` | 8.9 / 5.1 |
| 2 | Teal | `#43D9A3` / `#0C2E24` | `#0B7B57` / `#DDF5EC` | 9.7 / 4.6 |
| 3 | Green | `#7ACE7A` / `#14301A` | `#3B7A24` / `#E5F4DE` | 8.1 / 4.6 |
| 4 | Amber | `#FFC94D` / `#33270C` | `#8A6200` / `#FBF0D7` | 9.6 / 4.9 |
| 5 | Coral | `#FF8A70` / `#391B14` | `#B0402A` / `#FCE7E1` | 6.6 / 4.9 |
| 6 | Pink | `#FF7EB6` / `#38152A` | `#AD3273` / `#FBE4EF` | 6.5 / 5.0 |
| 7 | Slate | `#A9B8C9` / `#1E262F` | `#3F5259` / `#DFE3E4` | 7.4 / 6.3 |

**No violet in the ramp** — violet is reserved for AI provenance (§2.10). All 16 pairs clear
4.5 : 1 at label size; `test/collection_ink_test.dart` asserts it mechanically.

**Collision rule (past 8 collections, two collections share an ink — by design):**
- Colour is **never the sole signifier.** Every tag and chip renders the collection **title**
  alongside the dot. A dot-only variant may be used *only* where the title is adjacent in the
  same row (Collections Manage leading dot).
- Adjacent chips in a `ChipStrip` are separated by an 8 dp gap and each carries a 1 dp `outline`
  boundary, so two same-ink neighbours still read as two chips.
- The hash is **never** perturbed to avoid a collision. Stability beats uniqueness.

### 2.7 Border, hairline, and surface-layering rules

**Two hairline tokens, two jobs.** This distinction is load-bearing on a true-black canvas.

| Token | Value | Contrast vs its host | Where |
|---|---|---|---|
| `colorScheme.outline` — **boundary** | dark `#63636F`, light `#7E828C` | **≥3 : 1** | Any container that must be *identified as a distinct interactive surface*: input fields, chips, the search pill, segmented buttons, the idle mic ring, list-section borders, the NavigationBar top edge |
| `colorScheme.outlineVariant` — **divider** | dark `#2E2E36`, light `#D7DAE1` | ~1.5 : 1 (decorative) | Row dividers *inside* an already-bounded section, and nothing else |

**Hairline width — the mdpi fix.** Never specify a thickness below `1.0`. Snap 1 dp to whole
physical pixels so the line can neither vanish nor fatten:

```dart
// lib/ui/hairline.dart
double hairlineWidth(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  if (dpr <= 1.0) return 1.0;
  return (1.0 * dpr).roundToDouble() / dpr;
}
```

Use it for every `Border.all(width:)`, `BorderSide(width:)`, and `Divider(thickness:)`.
`DividerThemeData(thickness: 1, space: 1, color: outlineVariant)` globally.

**Surface layering ladder (dark → light equivalents are the same steps):**

```
surface                 #050505  canvas / scaffold / chat conversation ground / NavigationBar
surfaceContainerLowest  #0A0A0A  sticky action bars, chat input bar
surfaceContainerLow     #0E0E10  list sections, cards, assistant-block wells
surfaceContainer        #121214  input fills, chips, search pill
surfaceContainerHigh    #17171A  pressed rows, user chat bubbles
surfaceContainerHighest #1C1C20  bottom sheets, dialogs (under a 60 % scrim)
```

**Grouped sections replace floating per-row cards.** Today four files hand-roll
`Material(color: cardTheme.color, radius 14)`. That pattern is retired. A section is one
`surfaceContainerLow` container, radius 12, with a 1 dp `outline` border; rows are full-bleed
inside it, separated by 1 dp `outlineVariant` dividers inset 16 dp from the left.

**`cardTheme.color` is retired.** Its three consumers (`notes_page.dart:419`,
`collections_manage_page.dart:160`, `mem_chat_page.dart:511`) all move to `AppListSection` /
`AppRow`. `CardThemeData` in the theme keeps `color: colorScheme.surfaceContainerLow`,
`elevation: 0`, `surfaceTintColor: transparent`, radius 12, and a 1 dp `outline` side — for any
stray `Card` — but new code should not use `Card`.

**Focus ring:** 2 dp `primary` at 40 % alpha, drawn *outside* the shape.

### 2.8 Radius scale

| Radius | Applies to |
|---|---|
| 6 | Inline code, collection tags, small badges |
| 10 | Buttons, chips, status pills, segmented buttons |
| 12 | List sections, input fields, cards |
| 16 | Dialogs |
| 20 | Bottom-sheet top corners |
| `StadiumBorder` | Search pill, extended FAB, mic button, NavigationBar indicator, circular icon buttons |
| 28 | Standard FAB (M3) |

One scale. The historical 14-vs-16 clash is gone.

### 2.9 Spacing, sizing, and chrome insets

- **Base grid 4 dp.** Page horizontal inset **16**. Section internal padding **14 h / 12 v**.
- **Row heights:** 56 (settings/status), 64 (single-line list), **76 (note rows — fixed)**.
- Gap between sections **24**; gap header→section **8**; gap between chips **8**.
- **Touch targets ≥48 dp app-wide.** Chips use `MaterialTapTargetSize.padded` plus transparent
  padding — this fixes Chat's ~32 px chips (`#8`).
- **Chip strips are exactly 56 dp tall** (48 dp targets + 4 dp above/below).

`lib/theme/mem_metrics.dart`:

```dart
abstract final class MemInsets {
  static const double navBarHeight     = 64;
  static const double listBottomForNav = 104; // 64 nav + 40 breathing room
  static const double listBottomForFab = 96;  // clears a 56 dp FAB + 16 margin + 24
  static const double stickyBarHeight  = 72;
  static const double pageH            = 16;
  static const double editorScrollPad  = 140; // scrollPadding on tall text fields
}
```

These replace the magic `120` / `96` / `12` values. **Bottom-stack budget (verified, must not
regress):** Notes = 104 only (the nav bar is the sole chrome). Capture = sticky bar 72 + nav 64 =
136 of chrome, and the content field is the flexible child so it shrinks rather than pushing CTAs
off-screen. Collections / Prompt Jobs are pushed routes with no nav bar: FAB inset 96 only.
NoteDetail edit = sticky bar 72 + keyboard. **No screen composes more than 140 dp of bottom
chrome.**

### 2.10 The AI-provenance reservation

`tertiary` / `aiAccent` violet marks **only** content a model produced or is producing:

Permitted sites — the assistant message header sparkle, the streaming caret, the "Processing in
Mem…" chip glyph, prompt-job chips in the Chat strip, and the `AiGlyph` on the Capture primary
CTA. Nothing else. User-authored content is never violet.

**Mechanical audit (part of the verification checklist):** grep for `tertiary` and `aiAccent`
across `lib/`. Every hit outside `lib/theme/` must be in `lib/ui/ai_glyph.dart` or one of the
permitted sites above. In particular **no stock component may resolve to `tertiary`** — M3 will
happily hand it to `SegmentedButton`, `FilterChip` selection, `Switch`, `Slider`, and
`ProgressIndicator` if you let it. The theme explicitly pins those to `primary` /
`secondaryContainer` (§2.12).

### 2.11 Motion, and the per-frame cost budget

```dart
abstract final class MemMotion {
  static const Duration press     = Duration(milliseconds: 80);
  static const Duration micro     = Duration(milliseconds: 120);
  static const Duration standard  = Duration(milliseconds: 220);
  static const Duration route     = Duration(milliseconds: 220);
  static const Duration skeleton  = Duration(milliseconds: 1100);
  static const Duration snack     = Duration(milliseconds: 2500);
  static const Duration snackAction = Duration(seconds: 4);
  static const Duration undo      = Duration(seconds: 6);
  static const Duration revealTimeout = Duration(seconds: 10);
  static const Duration streamStall   = Duration(seconds: 90);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve pulse      = Curves.easeInOut;
}
```

- **The 80 ms press is the signature.** Global: `splashFactory: NoSplash.splashFactory`, and
  every tappable surface sets `overlayColor` to `surfaceContainerHigh` (pressed) resolved in
  `MemMotion.press`. No 300 ms ripple spread anywhere.
- **Route transitions:** `PageTransitionsTheme(builders: {TargetPlatform.android:
  FadeForwardsPageTransitionsBuilder()})`. If that class is unavailable in the pinned Flutter
  version, fall back to `ZoomPageTransitionsBuilder()` — do not hand-roll.
- **Hero:** the note title Heroes from a Notes row into NoteDetail, `tag: 'note-title-${note.id}'`,
  with a `flightShuttleBuilder` that renders the destination style so the text does not restyle
  mid-flight.
- **Tab switching is instant.** No cross-fade between `IndexedStack` children — the whole point
  of the stack is a zero-cost, state-preserving switch, and an added 150 ms fade reads as latency
  on the app's fastest interaction.

**Per-frame cost budget — these are hard bans, not preferences:**

| Banned | Use instead |
|---|---|
| Shimmer sweep gradients | Opacity pulse 0.55→1.0, `MemMotion.skeleton`, `MemMotion.pulse` |
| `ShaderMask` edge fades on a scrolling strip (forces a `saveLayer` every frame) | A static `LinearGradient` overlay `Container` in an `IgnorePointer`, painted over the strip's known solid background |
| `Opacity` wrapping a long list (for the dimmed-refresh state) | Colour tokens on the rows themselves |
| `BoxShadow` in any theme | Surface step + hairline |
| Default `InkSplash` | `NoSplash` + `overlayColor` |

### 2.12 ThemeData assembly (WP-0 checklist)

`buildMemTheme(Brightness b)` returns one `ThemeData` per brightness. Set at minimum:

`useMaterial3: true` · `colorScheme` · `scaffoldBackgroundColor: cs.surface` ·
`extensions: [MemSemanticColors.of(b)]` · `splashFactory: NoSplash.splashFactory` ·
`textTheme` (§2.4) · `dividerTheme` (§2.7) · `pageTransitionsTheme` (§2.11) ·
`appBarTheme` (`centerTitle: false`, `scrolledUnderElevation: 0`, `elevation: 0`,
`surfaceTintColor: transparent`, `backgroundColor: cs.surface`, `titleTextStyle: titleLarge`) ·
`navigationBarTheme` (§4.1) · `inputDecorationTheme` (filled `surfaceContainer`, radius 12,
`enabledBorder` 1 dp `outline`, `focusedBorder` 2 dp `primary`, `errorBorder` 1 dp `error`,
`isDense: false`, `contentPadding: 14h/14v`) · `chipTheme` (§3.3) · `filledButtonTheme`,
`outlinedButtonTheme`, `textButtonTheme` (radius 10, min height 48, `labelLarge`) ·
`iconButtonTheme` (min 48) · `dialogTheme` (radius 16, `surfaceContainerHighest`, elevation 0) ·
`bottomSheetTheme` (radius 20 top, `surfaceContainerHighest`, elevation 0, `showDragHandle: true`) ·
`snackBarTheme` (floating, `inverseSurface` bg, `onInverseSurface` text, radius 10, elevation 0) ·
`cardTheme` (§2.7) · `segmentedButtonTheme` (selected = `primary`/`onPrimary`, **never**
`tertiary`) · `switchTheme` (`primary`) · `progressIndicatorTheme` (`primary`) ·
`floatingActionButtonTheme` (`primaryContainer`/`onPrimaryContainer`, elevation 0).

**Selection salience — one rule for the whole app.** Every "selected" affordance (NavigationBar
indicator, Notes filter chip, model radio row, segmented button) uses:
**`primary` fill + `onPrimary` content + a 16 dp check glyph + w600 label.** Verified ≥3 : 1 fill
contrast against `surface` in both themes (dark 7.9 : 1, light 6.1 : 1). Do not use
`primaryContainer` for selection — it fails 3 : 1 in light mode. `primaryContainer` remains a
*tonal* colour for non-selection surfaces (the "N results" strip, empty-state icon circles).

---

## 3. SHARED COMPONENTS

All live under `lib/ui/`. Owned by **WP-1** and **WP-2** (§6). Every screen consumes them; no
screen re-implements them.

### 3.1 `AppListSection` + `AppRow` — `lib/ui/app_list_section.dart`

Replaces all four hand-rolled `Material(#121212, radius 14)` card patterns.

```dart
class AppListSection extends StatelessWidget {
  const AppListSection({
    super.key,
    required this.children,     // usually AppRow, but any widget is allowed
    this.header,                // optional SectionHeader rendered ABOVE the section
    this.margin = const EdgeInsets.symmetric(horizontal: MemInsets.pageH),
    this.dividerIndent = 16,
    this.showDividers = true,
  });
}

class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    this.leading,               // ≤24dp glyph or a collection dot
    required this.title,        // titleMedium, maxLines 1, ellipsis
    this.subtitle,              // bodyMedium onSurfaceVariant, maxLines set by `subtitleMaxLines`
    this.subtitleMaxLines = 2,
    this.meta,                  // widget row under the subtitle (tags + right-aligned time)
    this.trailingText,          // bodySmall onSurfaceVariant, tabular, right-aligned
    this.trailing,              // ONE control max — never the row's primary action
    this.onTap,
    this.onLongPress,
    this.minHeight = 56,
    this.enabled = true,        // false ⇒ non-tappable AND rendered at reduced emphasis
    this.selected = false,
  });
}
```

**Visual.** Section: `surfaceContainerLow`, radius 12, 1 dp `outline` border, `clipBehavior:
Clip.antiAlias`. Rows are full-bleed inside; padding 16 h / 12 v; dividers 1 dp `outlineVariant`
inset 16 from the left, none after the last row.

**Behaviour.** The whole row is the tap target (`InkWell` with `overlayColor` →
`surfaceContainerHigh`, `splashFactory: NoSplash`, 80 ms). `trailing` must never hold the row's
primary action — primary actions are the row tap or a visible icon button; kebabs hold *secondary*
verbs only. `selected: true` adds a 2 dp `primary` left bar and a `primary` check glyph.

**Text-scale degradation (mandatory, in this order):** at `textScaler > 1.3`, drop the second
snippet line; then collapse collection tags to `+n`; then let the meta row wrap. Never clip.
Implement by reading `MediaQuery.textScalerOf(context).scale(14)` and branching — do not rely on
overflow.

### 3.2 `CollectionTag` — `lib/ui/collection_tag.dart`

```dart
enum CollectionTagVariant { tag, chip, dot }

class CollectionTag extends StatelessWidget {
  const CollectionTag({
    super.key,
    required this.collectionId,
    required this.title,
    this.variant = CollectionTagVariant.tag,
    this.count,                 // shown in `chip` variant only, tabular
    this.selected = false,      // `chip` variant only
    this.onTap,
  });
}
```

- **`tag`** (display / navigation): 24 dp tall, `bg` from the ink pair, 6 dp `fg` dot + title in
  `labelMedium` `fg`, radius 6, 8 h padding. If `onTap != null` the visual stays 24 dp but the
  widget is wrapped to a 48 dp target.
- **`chip`** (filter bars): 40 dp visual inside a 48 dp target, radius 10, 1 dp `outline`
  boundary. Unselected: ink `bg` fill, ink `fg` label, `· 32` count in the same colour.
  **Selected: `primary` fill, `onPrimary` label, leading 16 dp check** (§2.12) — the ink dot
  stays visible so identity survives selection.
- **`dot`**: 10 dp circle in ink `fg`, for a row's `leading` where the title is adjacent.

**Overflow in note rows:** at most **2** tags then a `+n` tag in `surfaceContainer` /
`onSurfaceVariant`.

Titles come from a client-side join of `MemNoteListItem.collectionIds` against the already-fetched
collections list. If a title is missing, render the raw id (matching NoteDetail's existing
`_collectionTitle` fallback) rather than hiding the tag.

### 3.3 `ChipStrip` — `lib/ui/chip_strip.dart`

```dart
class ChipStrip extends StatelessWidget {
  const ChipStrip({
    super.key,
    required this.children,     // chips; each already ≥48dp target
    this.leadingPinned,         // e.g. the 'All' chip — never scrolls away
    this.trailingAction,        // e.g. the manage-collections icon button
    this.height = 56,
    this.backgroundColor,       // defaults to colorScheme.surface (no tinted band)
    this.controller,
  });
}
```

**Visual.** 56 dp tall on `surface` — the old `surfaceContainerHighest @ 35 %` band is retired.
Chips 8 dp apart, 16 dp leading/trailing padding. **Scroll hint = a 16 dp static
`LinearGradient` overlay** (background colour → transparent) on each edge, in an `IgnorePointer`,
shown only when the strip actually overflows. **No `ShaderMask`.**

**Behaviour.** `leadingPinned` renders outside the scroll view on the left; `trailingAction`
outside on the right. `MaterialTapTargetSize.padded` on every chip. Horizontal drags must not be
stolen by a parent vertical scroller — the strip owns its own `ScrollController`.

### 3.4 `EditorSheet` — `lib/ui/editor_sheet.dart`

The one modal editor scaffold: Collections editor, Prompt-job editor, chat-model editor, secret-key
editors, jobs picker.

```dart
Future<T?> showEditorSheet<T>({
  required BuildContext context,
  required String title,
  required List<Widget> Function(BuildContext sheetContext, EditorSheetState state) fieldsBuilder,
  required bool Function() isValid,             // gates the Save button
  required Future<void> Function(BuildContext sheetContext) onSave,
  String saveLabel = 'Save',
  Widget? footerNote,
});
```

**Visual.** `showModalBottomSheet(isScrollControlled: true, showDragHandle: true)`,
`surfaceContainerHighest`, radius 20 top. Header row: `titleSmall` title + a 48 dp close **X** on
the right. Fields use the global `InputDecorationTheme` — **never** re-declare
`OutlineInputBorder()` inline. Inline validation errors under the field. Sticky footer:
full-width `FilledButton` with an `InlineSpinner` while saving.

**Contracts baked in (do not deviate):**
- `isScrollControlled: true` and bottom padding `MediaQuery.viewInsetsOf(context).bottom + 20`.
- **Save is disabled until `isValid()`** — this replaces every silent no-op on empty input.
- **Save ordering:** capture the *page's* `ScaffoldMessenger` **before** anything async → pop the
  sheet via `sheetContext` → `await onSave(...)`. On error the sheet **stays open** and the
  message shows.
- Controllers are seeded from `existing` and disposed in the sheet's `State` (with the one
  documented exception in Settings' model editor, §4.7).
- Values are trimmed on save.

### 3.5 `EmptyState` — `lib/ui/empty_state.dart`

```dart
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.headline,     // titleMedium (displaySmall for first-run screens)
    required this.body,         // bodyMedium onSurfaceVariant, ONE line of copy
    this.ctaLabel,
    this.onCta,
    this.secondaryChips,        // e.g. Chat starter prompts
  });
}
```

64 dp `primaryContainer` circle holding a 28 dp `onPrimaryContainer` icon; headline; one body
line; one `FilledButton` CTA. Centred, max width 320. CTAs wire to `AppState.goToShellTab(…)` or
`Navigator.push(const SettingsPage(focusSection: …))`.

### 3.6 `ErrorState` + `errSnack()` + `memErrorText()` — `lib/ui/error_state.dart`

```dart
/// The ONLY way an error becomes user-visible.
String memErrorText(Object error);

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry, this.title});
}

/// Snackbar variant. `onSettings` adds an 'Open Settings' action for auth failures.
void errSnack(ScaffoldMessengerState messenger, Object error, {VoidCallback? onRetry, SettingsSection? openSettings});
```

`memErrorText` routes: `DioException` → **`MemApiClient.formatError(e)`** (purpose-built, currently
unused — this finally uses it); `MemApiException` → its message; anything else → the generic
`'Something went wrong. Please try again.'`. **A raw `e.toString()` must never reach a widget.**
Where a `MemErrorReporter` context string exists, the *raw* string still goes to telemetry.

`ErrorState`: 64 dp `errorContainer` circle + `error_outline` in `onErrorContainer`, `titleMedium`
headline, `bodyMedium` detail from `memErrorText`, `FilledButton.tonal` **"Try again"** wired to
the screen's reload.

`errSnack` auto-attaches **"Open Settings"** (deep-linked to the right section) when the error is
a 401/403 or a missing-key condition, and **"Retry"** when `onRetry` is supplied.

### 3.7 `ConfirmDestructiveDialog` — `lib/ui/confirm_destructive_dialog.dart`

```dart
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,        // states the verb: 'Move to trash?', 'Delete forever?'
  required String consequence,  // one plain-language line
  required String actionLabel,
  String cancelLabel = 'Cancel',
});
```

**The grammar is inverted from today's code and must be identical at all six call sites**
(trash note, delete forever, delete collection, remove model, disconnect MCP, discard recording /
discard changes):

- **Cancel is the promoted button**: `FilledButton.tonal`, placed right (the reflex position).
- **The destructive action is demoted**: `TextButton` with `foregroundColor: colorScheme.error`,
  placed left, still a full 48 dp target, `labelLarge` w600 so it is findable.
- Outside tap resolves `false`. `showDialog<bool>` and the result is treated as
  `ok == true && mounted` at every call site.
- Radius 16, `surfaceContainerHighest`, 60 % scrim.

### 3.8 `SectionHeader` — `lib/ui/section_header.dart`

```dart
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label, this.trailing, this.uppercase = true});
}
```

`labelSmall` UPPERCASE `onSurfaceVariant`, 24 dp top / 8 dp bottom, optional trailing text button.
Replaces ~10 hand-rolled `titleMedium` + prose-paragraph pairs. **The prose paragraphs are
deleted** — anything worth keeping becomes field helper text.

### 3.9 `StatusTile` — `lib/ui/status_tile.dart`

Replaces every disabled-buttons-as-status pattern (`#30` in the shared-patterns list): MCP
connect/disconnect, "Add widget to home", key presence.

```dart
enum StatusLevel { ok, pending, attention, error, neutral }

class StatusTile extends StatelessWidget {
  const StatusTile({
    super.key,
    required this.icon,
    required this.label,        // titleSmall
    required this.level,
    required this.status,       // e.g. 'Connected', 'Key saved · ····4F2', 'Not set'
    this.detail,                // optional bodySmall second line
    this.actionLabel,
    this.onAction,
    this.busy = false,          // shows InlineSpinner in the pill AND disables the action
    this.onTap,                 // optional whole-tile tap (used by the setup card)
  });
}
```

56 dp min height. Leading 20 dp icon. Status pill on the right: 8 dp dot in the level colour +
`labelMedium` text on the matching `*Container`. Exactly **one** trailing action button. While
`busy`, the pill shows an `InlineSpinner` plus the pending copy (e.g. *"Waiting for browser…"*)
— this closes the OAuth dead-air gap.

Masked-secret copy format: `Key saved · ····4F2` (last 3 characters). Never render a full key.

### 3.10 `InlineSpinner` — `lib/ui/inline_spinner.dart`

```dart
class InlineSpinner extends StatelessWidget {
  const InlineSpinner({super.key, this.size = 16, this.color}); // strokeWidth 2, inherits fg
}
```

The only inline spinner token. Sizes: **16** (inside buttons/pills), **24** (list footers).
Replaces all five hardcoded 18/20 dp variants.

### 3.11 `SkeletonList` / `SkeletonRow` — `lib/ui/skeleton.dart`

```dart
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rowCount = 8, this.rowHeight = 76, this.inSection = true});
}
```

Bars in `surfaceContainerHigh` shaped to the real row geometry (title bar 60 % width, two snippet
bars, a tag stub, a time stub), pulsing opacity 0.55→1.0 over `MemMotion.skeleton` with
`MemMotion.pulse`. **No shimmer gradient. One `AnimationController` for the whole list**, shared
down via an `AnimatedBuilder` — not one per row.

**Rule: a skeleton is shown only when there is nothing else to show.** Never during a refresh
that has stale content, never during infinite-scroll append (that gets 3 tail skeleton rows,
which preserve scroll continuity better than a spinner).

### 3.12 `memSnack()` / `undoSnack()` — `lib/ui/feedback.dart`

```dart
void memSnack(ScaffoldMessengerState m, String message, {String? actionLabel, VoidCallback? onAction});
void undoSnack(ScaffoldMessengerState m, String message, {required Future<void> Function() onUndo, String? secondaryLabel, VoidCallback? onSecondary});
```

Copy system: **"Noun verb-past."** — `Note saved.` · `Collection deleted.` · `Moved to trash.` ·
`Captured — Mem is processing it.` Floating, `inverseSurface`, radius 10.
`MemMotion.snack` / `MemMotion.snackAction` / `MemMotion.undo` durations.

`undoSnack` is used in exactly two places (§5.2): trash-a-note and clear-the-capture-draft.

### 3.13 `StickyActionBar` — `lib/ui/sticky_action_bar.dart`

```dart
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    super.key,
    required this.primary,
    this.secondary,
    this.caption,               // one bodySmall line rendered ABOVE the buttons
  });
}
```

Bottom-docked, `SafeArea`, `surfaceContainerLowest`, 1 dp `outline` top hairline, 12 dp vertical
padding. Animates above the keyboard by padding with `MediaQuery.viewInsetsOf(context).bottom`
(`AnimatedPadding`, `MemMotion.micro`). Primary is `flex: 2`, secondary `flex: 1`. Both 48 dp.

### 3.14 `SearchPill` — `lib/ui/search_pill.dart`

```dart
class SearchPill extends StatelessWidget {
  const SearchPill({super.key, required this.hint, required this.onTap, this.focusNode, this.controller, this.onChanged, this.onClear, this.active = false});
}
```

44 dp tall, `StadiumBorder`, `surfaceContainer` fill, 1 dp `outline`, leading 20 dp search glyph,
`bodyMedium` hint. Collapsed it is a tap target that expands into an active text field with a
trailing clear **X** and a `Cancel` text button.

### 3.15 Supporting primitives

| File | Exports | Notes |
|---|---|---|
| `lib/ui/hairline.dart` | `hairlineWidth(context)`, `Hairline` widget | §2.7 |
| `lib/ui/ai_glyph.dart` | `AiGlyph({size = 14})` | `Icons.auto_awesome` in `aiAccent`. **The only place `tertiary` is read outside the theme.** |
| `lib/ui/provider_badge.dart` | `ProviderBadge({provider, showName})` | 20 dp glyph + name from the existing-but-unused `chatProviderBrand()`. Kills raw `(openai)` strings. |
| `lib/ui/date_labels.dart` | `memDayLabel(DateTime)`, `memRelativeTime(DateTime)` | `Today` / `Yesterday` / weekday name (this week) / `Mar 4` (older). **Presentation only** — see the Notes constraint callout. `memRelativeTime` → `2h`, `Mon`, `Mar 4`. |
| `lib/ui/settings_gear_button.dart` | `SettingsGearButton({badge})` | 48 dp, tooltip `Settings`, `Semantics(label: 'Settings')`, 8 dp `error` dot when setup is incomplete. |
| `lib/ui/async_page_mixin.dart` | `AsyncPageMixin<T extends StatefulWidget>` | Codifies: `messengerOf()` captures before awaits; `ifMounted(fn)`; `postFrame(fn)` for `AppScope` reads. Every redesigned screen mixes it in so the async contract cannot regress. |

**`lib/widgets/settings_launcher.dart` keeps its exact contract:** `settingsIconActions(BuildContext)`
still returns `List<Widget>` for `AppBar.actions`, still pushes `const SettingsPage()` on the
nearest `Navigator` so the route covers the NavigationBar, at all three call sites. Its body now
returns `[SettingsGearButton(badge: …)]` and derives the badge from `AppScope`:
`!hasMemRest || chatModels.isEmpty`.

---

## 4. PER-SCREEN SPECS

Each screen lists its layout top-to-bottom, the shared components it uses, the numbered UX
problems it fixes, and a **Constraint callouts** block reproducing the contracts that bind that
file.

### 4.1 SHELL — `lib/features/shell/mem_shell.dart`

**Structure is untouched.** One `MemShell`, one `IndexedStack` (Notes 0 / Capture 1 / Chat 2, all
kept alive), one Material 3 `NavigationBar` with the exact three icons.

**Restyle, via `NavigationBarTheme` only:**
- `height: 64`, `backgroundColor: colorScheme.surface` (continuous with the canvas — no seam),
  `elevation: 0`, `surfaceTintColor: transparent`, `labelBehavior: alwaysShow`,
  `labelTextStyle: labelSmall` (sentence case, not uppercase — the labels are `Notes`, `Capture`,
  `Chat`).
- **Indicator: `primary` stadium, 64 × 32**, selected icon `onPrimary`, unselected
  `onSurfaceVariant` (§2.12 selection rule).
- **Top hairline:** wrap the `NavigationBar` in a **decoration-only** `Container` with
  `BoxDecoration(border: Border(top: BorderSide(color: outline, width: hairlineWidth(context))))`.
  **The wrapper must not introduce a second `NavigationBar`, must not absorb pointer events, and
  must not wrap the destinations.** Re-run the smoke test after this change.

**Pre-hydration and terminal-failure state (fixes the blank-shell hole).** `AppState.load()` can
fail, leaving `isHydrated == false` **forever**. The shell must still render sensibly:
- While `!isHydrated`: each tab renders its **normal chrome** (AppBar + gear + nav bar) with a
  `SkeletonList` in the body. **Never a naked centred spinner.**
- If `!isHydrated` is still true **8 seconds** after first frame, each tab swaps the skeleton for
  an actionable `ErrorState`: *"Couldn't load your settings"* + **"Open Settings"** CTA. The app
  is never a dead void.

**Preserved verbatim:** deep-link handling (`memai://open` → tab 0; `memai://prompt?templateId=…`
→ tab 2 + enqueue), `shellTabRequest` consume-once-and-clear, the single `ChatPromptQueue`
instance injected into `MemChatPage`, `syncHomePromptWidget` at startup,
`MemJobNotifications.onOpenHomeTab`.

**Fixes:** `#3` (gear badge), `#4` (pre-hydration blankness), `#9` (nav no longer floats on a
mismatched tonal band).

> **Constraint callouts (from CONSTRAINTS.md):**
> - Exactly **one** `MemShell` and exactly **one** Material 3 `NavigationBar` must exist. No
>   `BottomNavigationBar`, no custom nav.
> - `Icons.add_circle_outline`, `Icons.chat_bubble_outline`, `Icons.article_outlined` must stay
>   **findable and tappable** as the tab-switch affordances.
> - Root wiring stays `AppScope(state: AppState(), child: MemDroidApp())` with those class names.
> - `IndexedStack` keeps all three tabs alive — Capture drafts, toggles, and in-progress
>   recordings, and all Chat state, must survive tab switches.
> - `shellTabRequest` is consumed once and cleared (via `scheduleMicrotask`).
> - `MemShell` creates **one** `ChatPromptQueue` and injects it — **instance identity must be
>   preserved** or widget-tap jobs are lost.
> - `syncHomePromptWidget` re-runs at shell startup.

### 4.2 NOTES — `lib/features/home/notes_page.dart`

Uses: `AppListSection`/`AppRow`, `CollectionTag`, `ChipStrip`, `SearchPill`, `SkeletonList`,
`EmptyState`, `ErrorState`, `SettingsGearButton`, `memDayLabel`, `AsyncPageMixin`.

**Top to bottom**

1. **AppBar** — pinned. `Notes` in `titleLarge`. Actions: a search icon (scrolls the pill into
   view and focuses it) + `SettingsGearButton(badge)`.
2. **`SearchPill`** — 16 dp gutters, in the scroll body (a `SliverToBoxAdapter`, **not pinned**),
   so it teaches that search exists but costs nothing once you scroll. Full interaction spec in
   §5.1. Verify at least **three full 76 dp rows remain above the fold** on a 5.5-inch device
   with the pill and chip strip present.
3. **`ChipStrip`** — `leadingPinned:` the `All` chip (null filter); one `CollectionTag(chip)` per
   collection showing its ink dot, title, and **tabular note count** (`Interviews · 32` — the
   unused `noteCount` field, finally surfaced); `trailingAction:` a tune icon →
   `CollectionsManagePage`. **The whole strip is hidden when `!hasMemRest`.**
4. **Collections-failure strip** — `listCollections` failures are non-fatal by contract, but they
   must not be silent. On failure render a single 40 dp row above the timeline:
   *"Collections unavailable"* + a `Retry` text button, in `surfaceContainer`. This fixes the
   silently-swallowed half of `#1`.
5. **Timeline** — day groups. Header: `memDayLabel(...)` in `labelMedium`, **sentence case**,
   `onSurfaceVariant`, 24 top / 8 bottom. Each group is one `AppListSection`.
6. **Note row** — `AppRow`, **fixed 76 dp min height**:
   - `titleMedium` title, **1 line**, ellipsis. Wrapped in a `Hero`
     (`tag: 'note-title-${note.id}'`).
   - `bodyMedium` `onSurfaceVariant` snippet, **2 lines**. When `snippet` is null, fall back to
     the note's content — the load call may pass `includeContent: false` per contract, so the
     fallback is: use `content` if present, else render **no** snippet line and let the row
     shrink. Do **not** print a `No preview` placeholder.
   - **No leading article icon** — every note had the identical glyph; the ink dots carry
     identity and this buys ~24 dp of width.
   - Meta row: up to 2 `CollectionTag(tag)` + `+n`, and a right-aligned tabular `bodySmall`
     relative time (`memRelativeTime`).
   - Tap → `NoteDetailPage(noteId)` (noteId only).
7. **Infinite scroll** — the manual `Load more` button and its 120 px dead zone are **deleted**.
   A scroll listener fires the next page **400 dp from the end** while `_nextPage != null`.
   Tail renders **3 skeleton rows** while appending.
8. **Bottom inset** — `MemInsets.listBottomForNav` (104).

**States**

| State | Render |
|---|---|
| `!isHydrated` | Chrome + `SkeletonList` (see §4.1) |
| `!hasMemRest` | `EmptyState` — *"Connect your Mem account"* → `SettingsPage(focusSection: account)` |
| First load, no data | `SkeletonList(rowCount: 8, rowHeight: 76)` |
| **Refresh / filter change with existing rows** | **Stale rows stay visible** (§5.3). Never a skeleton, never a blank. `RefreshIndicator` is the only signal. |
| Zero notes | `EmptyState` — *"Capture your first note"* → `goToShellTab(1)` |
| Error | `ErrorState` + Retry |

**Fixes:** `#1`, `#3`, `#4`, `#6` (load-more), `#7` (search), `#11` (row starvation), `#15`
(date headers, hero).

> **Constraint callouts:**
> - **Idempotent lazy initial load** with guards `isHydrated && hasMemRest && !loading &&
>   !alreadyLoaded`, reachable from `initState` post-frame, `didChangeDependencies`, and app-state
>   changes.
> - `MemApiClient` is constructed **fresh per operation** from the *current* `memApiKey`; a
>   null/empty key yields a null client.
> - **Exact call shape:** `rawListNotes(limit: 40, includeContent: false, page: <cursor or null on
>   refresh>, collectionId: <filter>)`. Keep `next_page` **only when it is a `String`**. Use
>   `rawListNotes` — not the typed `listNotes`, which drops the cursor.
> - **Day grouping key stays `DateFormat.yMMMEd().format(n.updatedAt.toLocal())`.** `memDayLabel`
>   is a *pure presentation map over that key* — it must not change grouping, ordering, or the key
>   itself. Where server ordering is mixed, groups render in the order the keys first appear.
> - `'All'` chip = **null** filter. `_loadCollections` **auto-clears** a filter whose collection
>   has vanished.
> - **Refresh clears `items` + cursor pre-fetch.** (See §5.3 for how stale-content retention lives
>   entirely in the view layer without touching this.)
> - Load-more only when the cursor `!= null`, and calls **without** `refresh`.
> - `RefreshIndicator` + `AlwaysScrollableScrollPhysics` on **every** list state, including the
>   error and empty branches.
> - The manage-collections push is **awaited**, then collections **and** notes reload.
> - Card tap passes **noteId only**.
> - `MemErrorReporter.report(context: 'notes_load')` must survive.
> - Listener pattern: attach on instance change, detach old, detach in `dispose`, for both
>   `AppState` and `notesListRevision`.
> - The filter bar **must not render** when `!hasMemRest`.

### 4.3 COLLECTIONS MANAGE — `lib/features/home/collections_manage_page.dart`

Uses: `AppListSection`/`AppRow`, `CollectionTag(dot)`, `EditorSheet`, `ConfirmDestructiveDialog`,
`SkeletonList`, `EmptyState`, `ErrorState`, `SearchPill`, `AsyncPageMixin`.

**Top to bottom**

1. **AppBar** `Collections`. A search icon appears **only when > 10 collections** and reveals a
   client-side filter `SearchPill` (no API call).
2. **One `AppListSection`** of 64 dp `AppRow`s:
   - `leading:` `CollectionTag(dot)` — **the same ink** the user sees on Notes tags.
   - `title:` `titleMedium` name.
   - `subtitle:` **both** description **and** pluralised count — `Interview notes · 32 notes` /
     `1 note` / `No description · 4 notes`. Today it is one or the other, unpluralised (`#11`).
   - `trailingText:` `updated 2d` (tabular `bodySmall`) from the never-surfaced
     `MemCollectionItem.updatedAt`.
   - **Row tap opens the Edit sheet** (kills the inert-row false affordance and halves edit taps).
   - `trailing:` kebab holding **Delete only**.
3. **Extended FAB** `New collection`. **The FAB stays** — a create action belongs in the thumb
   zone. The last-row-occlusion bug is fixed by `MemInsets.listBottomForFab` (96), not by removing
   the affordance.

**States:** `SkeletonList` (replaces the odd 120 px floating spinner) · `EmptyState` *"Group
related notes into collections"* + CTA · `ErrorState` + Retry.

**Delete** → `confirmDestructive(title: 'Delete collection?', consequence: 'Notes inside are kept
— only the collection is removed. 32 notes will be untagged.')`.

**Fixes:** `#1`, `#3`, `#5`, `#6`, `#8` (FAB occlusion), `#10`, `#11`.

> **Constraint callouts:**
> - `AppScope` access is deferred to **post-frame**.
> - **Delete sequence exactly:** `deleteCollection` → `await` reload → `mounted` check →
>   `bumpNotesListRevision()` → snackbar. **No bump on failure.** `AppState` is captured *before*
>   the awaits.
> - **Create/update payload asymmetry is intentional and must be preserved:** `createCollection`
>   sends `description: null` when empty; `updateCollection` sends the **trimmed (possibly empty)**
>   string so an empty value clears it. Surface this in the editor as helper text
>   *"Leave empty to clear"* on edit only.
> - **Editor save ordering:** capture the page's `ScaffoldMessenger` **before** pop → pop the sheet
>   via `sheetContext` → `await onSaved()` (reload + bump). The sheet **stays open on error**.
> - `resolveClient` is injected **as a function** — never snapshot a client into the sheet.
> - **Plain `Navigator.pop()` with no result must remain sufficient** (NotesPage awaits the push).
> - `showModalBottomSheet` stays `isScrollControlled` with bottom padding
>   `MediaQuery.viewInsetsOf(context).bottom + 20`.
> - `RefreshIndicator` + `AlwaysScrollableScrollPhysics` retained on all states.
> - Every mutation bumps `notesListRevision`.

### 4.4 CAPTURE — `lib/features/capture/capture_page.dart`

Reordered around **"type first, configure never."** Today the two CTAs sit below six config
controls and get covered by the keyboard.

Uses: `AppListSection`, `StickyActionBar`, `ChipStrip`, `CollectionTag`, `ConfirmDestructiveDialog`,
`undoSnack`, `AiGlyph`, `InlineSpinner`, `AsyncPageMixin`, plus a new
`lib/features/capture/mic_ring_painter.dart`.

**Top to bottom**

1. **AppBar** `Capture` + `SettingsGearButton`.
2. **Content field — the hero, first on screen.** Borderless multi-line `TextField` inside an
   `AppListSection`, `bodyLarge` 16/26, **min 6 lines, grows**, hint
   *"What's on your mind? The first line becomes the title."*
   `scrollPadding: EdgeInsets.only(bottom: MemInsets.editorScrollPad)`.
3. **Voice module** — one `AppListSection`:
   - Left: **96 dp circular mic button.** Idle: `surfaceContainer` fill + 1 dp `outline` ring,
     `primary` mic glyph. Recording: `recordingContainer` fill, `recording`-coloured **12-bar
     radial amplitude ring** driven by the existing 120 ms normalised amplitude stream
     (`CustomPainter`, no assets, one `AnimationController` lerping between samples). Elapsed
     time beneath in tabular `bodySmall`.
     **96 dp, not smaller** — this is the app's signature eyes-free, one-handed, often-in-motion
     control; density is the wrong optimisation here.
   - Right: 48 dp `SegmentedButton` **Longform / Hold to talk** + a one-line hint.
   - **Hold-to-talk starts recording on `onPointerDown`**, with a small drag-slop grace so the
     surrounding scroller does not steal the gesture. This is mandatory: the current ~500 ms
     long-press timeout clips the first half-second of speech (`#8`). **Do not ship a pressed-state
     acknowledgement without moving the trigger** — cueing the user to speak before the recorder
     is live makes `#8` worse, and would be a new false affordance in the direction that otherwise
     polices them.
   - Switching mic mode **mid-recording** now asks `confirmDestructive('Discard recording?')`
     before the contract cancel runs.
   - While transcribing: bars settle into an `aiAccent` pulse with a *"Transcribing…"* label.
4. **"Add to collection"** — a `ChipStrip` of multi-select `CollectionTag(chip)`s. Feeds
   `createNote(collectionIds: …)` on the raw path (an unused API capability). `memIt` has no
   collection parameter, so on the AI path the selected **titles are appended to `context`**;
   a `bodySmall` footnote says *"Mem files AI captures automatically."*
5. **"Guidance for Mem (optional)"** — single-line field that grows. (Renamed from
   *"Instructions for Mem-it"* — `#14`.)
6. **"Transcription options"** — an `ExpansionTile`, **collapsed by default**. Contains: the
   replace/append switch, relabelled **"Replace note text with transcript"**; **"Auto
   punctuation"**; language mode + hint; and the Whisper prompt field, relabelled
   **"Vocabulary hints"** (the single best de-jargoning available — `#14`). This declutters
   every visit (`#6`).
7. **`StickyActionBar`** above the nav bar and the keyboard:
   - `primary:` `FilledButton` with `AiGlyph` + **"Mem it"**, `InlineSpinner` while busy.
   - `secondary:` `OutlinedButton` **"Save as note"**.
   - `caption:` **"Mem it lets AI title and file this note. Save as note keeps it verbatim."**
     The caption is mandatory — the button labels alone do not tell a new user what the
     difference is, and the violet glyph plus this one line teach the provenance system.
   - **Disable matrix preserved exactly:** mic blocked by `busy || transcribing`; both saves
     blocked by `busy` only.

**Success behaviour**
- Fields clear per contract, but the clear is **announced and reversible**: a 150 ms fade-clear
  plus `undoSnack('Captured.')` whose **Undo restores the complete draft** — body text,
  guidance text, selected collection ids, and the replace/append and language states — not just
  the body. Secondary action **"View notes"** → `goToShellTab(0)`.
- The `memIt` path additionally shows a dismissible processing chip keyed to the returned
  `request_id`: `AiGlyph` + *"Processing in Mem…"* + a `pending` dot.
  **Expiry rule (mandatory — there is no completion callback):** the chip auto-dismisses after
  **90 seconds**, or on the next `notesListRevision` bump, whichever comes first, and is always
  manually dismissible. It must never become a permanent artefact.

**Fixes:** `#2` (silent clear, discarded audio), `#4`, `#6`, `#8`, `#10` (level meter),
`#13` (`request_id`), `#14`.

> **Constraint callouts:**
> - `memIt` sends the **RAW untrimmed body** (trim only for the emptiness guard). `saveRaw` sends
>   raw markdown.
> - Fields clear **only on success**. Instructions are trimmed→null and cleared **only on memIt
>   success**.
> - **Transcript insertion:** replace when `_replaceMode` **or** the body is blank; otherwise
>   `existing.trimRight() + '\n\n' + normalized`. Auto-punctuate gate and the
>   `'No speech detected.'` empty-result path are preserved.
> - **OpenAI key resolution order, exactly:** `voiceOpenAiApiKey` → active chat model if
>   `provider == 'openai'` → first openai model → `vault.getLlmApiKey(profileId)`.
> - **Recording:** `hasPermission()` check; AAC-LC 128 kbps / 44.1 kHz to
>   `'<tmp>/capture_<epochMs>.m4a'`; stop uses `(returned path ?? _activeRecordPath)`; the temp
>   file is deleted in `finally` **regardless of outcome**; mic-mode switch cancels the recording.
> - Amplitude normalisation `((db + 60) / 60).clamp(0, 1)` at **120 ms**.
> - Haptics: **medium** on hold start, **light** on hold end.
> - Disable matrix: mic blocked by `busy || transcribing`; saves blocked by `busy` only.
> - `bumpNotesListRevision()` after **every** successful `memIt` and `createNote`.
> - `dispose` cancels the timer and amplitude subscription, disposes the recorder and **all**
>   text controllers.
> - Page state survives tab switches (`IndexedStack`) — do not introduce anything that resets on
>   rebuild.

### 4.5 CHAT — `lib/features/chat/mem_chat_page.dart`

The library `ChatTheme.dark()` clash is replaced by a theme built from the app's own tokens.
**Current code is a bare `Chat(chatController:, currentUserId:, resolveUser:, onMessageSend:,
onMessageLongPress:, theme: ChatTheme.dark())` at `mem_chat_page.dart:571` with zero
customisation.** Everything below the theme swap requires custom message builders — see
**WP-S**, the mandatory spike (§6.2), which must land before this package starts.

Uses: `ChipStrip`, `ProviderBadge`, `AiGlyph`, `EmptyState`, `ErrorState`, `InlineSpinner`,
`AppListSection`, `AsyncPageMixin`, plus new
`lib/features/chat/model_switcher_sheet.dart` and `lib/features/chat/chat_message_builders.dart`.

**Top to bottom**

1. **AppBar** — title `Chat`. Beneath the title, a 36 dp **`ModelSwitcher` pill**:
   `ProviderBadge` + display name + `expand_more`, `surfaceContainer` + 1 dp `outline`, 48 dp
   target. Tapping opens a bottom sheet of model profiles (radio rows with `ProviderBadge`, active
   check, and a *"Manage models"* row → Settings). This kills the debug-ish
   `'<displayName> (<provider>)'` AppBar string while keeping the active model and provider
   visible, as the contract requires. Actions: `SettingsGearButton`.
2. **Model switch is announced, not silent.** On switch, after the persist-old-then-restore
   sequence, insert a **system row**:
   *"Switched to Claude Sonnet — conversation restored from Aug 15"* (using the never-used
   `ChatSessionSnapshot.savedAt`). See the system-row mechanism below.
3. **Jobs `ChipStrip`** (56 dp, real 48 dp targets — fixes the 32 px / `top: 10` hack):
   up to 12 prompt-template chips prefixed with `AiGlyph`, plus an `All` chip opening the
   searchable picker sheet. A **running** job's chip shows an `InlineSpinner` + its title.
4. **Persistent job-status row, directly above the composer** — not a chip inside a horizontally
   scrolling strip that can scroll out of view exactly when it matters. 40 dp,
   `surfaceContainer`: `InlineSpinner` + *"Running: Daily digest"* + a `+1 queued` count read
   passively from the never-used `ChatPromptQueue.hasPending`. Hidden when idle. Fixes `#13`.
5. **Conversation** — background is `surface` (`#050505`), killing today's `#0A0A0A` seam.
   - **Assistant messages are not bubbles.** Full-width text blocks on the canvas with a 12 dp
     header row (`AiGlyph` in `aiAccent` + model display name + tabular time) and a 20 dp left
     inset. This is the sharpest exploit of Mem's weak AI/user separation.
   - **User messages** are right-aligned bubbles: `surfaceContainerHigh`, radius 16 with a 4 dp
     bottom-right corner, max width 78 %, `bodyLarge`.
   - **Pending / streaming:** while the pending message text equals the `'…'` sentinel, render an
     animated three-dot pulse. Once tokens arrive, text streams with a 2 dp `aiAccent` caret block
     that fades on completion.
   - **Streaming death path (mandatory):** if no token arrives for `MemMotion.streamStall`
     (90 s), the pending bubble converts to an error row with **Retry**. A dropped stream must
     never leave a permanently animating shimmer with no way out.
   - **Errors render as error rows**, not as fake assistant prose: an `errorContainer` block with
     `memErrorText` copy and a retry icon that re-sends the preceding user message. The persisted
     `'Error: '` prefix contract is unchanged — only the *rendering* changes.
   - **Long-press opens a context menu** (Copy / Retry / Select text) instead of silently copying
     to the clipboard (`#15`). Because a full-width assistant block is an awkward long-press
     target, the assistant header row also carries a visible 32 dp overflow glyph opening the same
     menu.
6. **Composer** — `surfaceContainerLowest` bar with a 1 dp `outline` top hairline, 52 dp pill
   `TextField`, 44 dp `FilledIconButton` send.
   **While busy the send button shows an `InlineSpinner` and is disabled. There is NO stop
   button.** Verified: no `CancelToken` or stream cancellation exists in any of the three
   provider paths, so a stop affordance would be a lie. See NEXT-2.
7. **Empty states** — no messages: `EmptyState` *"Ask about your notes"* + 3 starter-prompt chips
   that send real prompts. No model: `EmptyState` CTA *"Add a chat model"* →
   `SettingsPage(focusSection: models)`. No backend: CTA to connect.

**System rows — the persistence mechanism (mandatory, get this exactly right).**
Today the persist filter keeps messages where `m is TextMessage && text.trim().isNotEmpty &&
text != '…'`. System rows (model-switch divider, "Running <job>…", "Restored from <date>") are a
**new class of message** and would otherwise be written into `ChatSessionStore` and reappear on
restore.

- Introduce `const _kSystemId = 'system';` alongside `_kUserId` / `_kAssistantId`.
- System rows are inserted into the controller with `authorId: _kSystemId` and rendered centred,
  `bodySmall`, `onSurfaceVariant`.
- **The persist filter gains exactly one clause:**
  `… && m.authorId != _kSystemId`. **The `'…'` sentinel string stays byte-identical.**
- System rows are **never** added to `_openAiHist` / `_anthropicHist` / `_geminiHist`. Provider
  histories continue to be replaced wholesale from agent results.
- The pending-bubble **id-rewrite-in-place** behaviour is unchanged.

**Fixes:** `#2` (silent model swap), `#3`, `#4`, `#8`, `#9`, `#13`, `#14`, `#15`.

> **Constraint callouts:**
> - **Send order, unchanged:** trim → busy gate → profile gate → backend gate
>   (`!hasMemRest && !mcpConnected` aborts) → vault key gate → insert user msg → insert pending
>   `'…'` bubble → `refreshMcpIfNeeded` → `MemToolRunner` (REST preferred; MCP client only when
>   `!hasMemRest && mcpConnected`) → `hasBackend` check → dispatch on the literal strings
>   `'openai' | 'anthropic' | 'gemini'`.
> - Streaming **rewrites the pending bubble in place (same id)**. `'…'` is the sentinel filtered
>   out on persist.
> - Provider histories are replaced **wholesale** from results, with `_openAiHist[0]` **always**
>   the system message; anthropic/gemini receive the system prompt separately.
> - HTTP 400 → `_resetProviderHistory`. `_failMessage` rewrites the pending bubble with the
>   `'Error: '` prefix. `finally`: `busy = false` + unawaited persist when mounted.
> - **Per-profile persistence:** `ChatSessionStore` key `'chat_session_v1_<profileId>'`, 5-day
>   retention, text-only round-trip.
> - **Profile switch persists the OLD session first, then restores** (null → empty; reseed the
>   `openAiHist` system message if the stored history is empty).
> - **Prompt jobs poll at 150 ms while busy, then run.** A user send while busy is aborted with a
>   snackbar. **Both behaviours must survive.** FIFO serial processing with the
>   `_drainingPromptRuns` re-entrancy guard.
> - `MemJobNotifications.showPromptJobFinished` fires on **both** success and failure, but only
>   when `notifyTitle != null`.
> - `MemErrorReporter` contexts `'prompt_job'` vs `'chat'` must survive; chat reports include
>   provider and httpStatus.
> - The jobs picker's `onPick` **pops the sheet BEFORE** `_runFromTemplate`.
> - `_activeProfile` falls back to the first model on an id miss.
> - **Active model + provider must stay visible somewhere.**
> - The app listener is removed against the **cached `_app` reference**; the promptQueue listener
>   is removed; `_chat` is disposed.
> - **`ChatPromptQueue` semantics are read-only for this redesign:** `enqueue()` adds then
>   notifies; `drainAll()` is an atomic copy-then-clear (a second listener must see empty).
>   Display queue depth; do **not** add writes, dedupe, or cancel.

### 4.6 NOTE DETAIL — `lib/features/note/note_detail_page.dart`

Uses: `AppListSection`, `CollectionTag`, `StickyActionBar`, `ConfirmDestructiveDialog`,
`undoSnack`, `ErrorState`, `errSnack`, `AsyncPageMixin`.

**Top to bottom**

1. **AppBar** — the state machine stays keyed on `inTrash × _editing`:
   - read: back · **Edit** pencil · overflow.
   - **`Delete permanently…` appears in the overflow ONLY when the note is in trash.** In the
     read state the overflow holds `Move to trash`. This is the literal fix for `#5`'s
     always-visible-single-item-overflow complaint and matches Mail/Photos convention.
   - trash: adds **Restore**.
   - edit: `Cancel` text button + `Save`.
2. **Trashed banner** (new) — a full-width `errorContainer` strip under the AppBar:
   *"In Trash"* + *"Notes in Trash can be deleted permanently."* + a `FilledButton.tonal`
   **Restore**. An explicit state instead of state-implied-by-which-button-appeared (`#11`).
3. **Title** — `headlineSmall`, wrapped in the matching `Hero`
   (`tag: 'note-title-${widget.noteId}'`).
4. **Metadata line** (new, read mode) — tabular `bodySmall` `onSurfaceVariant`:
   *"Created Mar 4, 2026 · Updated 2h ago · 342 words"* from `MemNoteFull.createdAt` /
   `updatedAt` plus a derived word count. All three were previously unshown (`#11`).
5. **Collection tags are now real** — `CollectionTag(tag, onTap:)`. Tapping pops to the Notes tab
   with that collection filter applied, via the new `AppState.notesFilterRequest` channel (§5.4).
   This kills the false affordance (`#10`).
6. **Read body** — **selectable `MarkdownBody`** (never `Markdown`), 20 dp gutters, the §2.4
   markdown ramp.
7. **Edit mode** — raw markdown `TextField`,
   `scrollPadding: EdgeInsets.only(bottom: MemInsets.editorScrollPad)` (140) so the cursor clears
   the keyboard and the sticky bar (`#8`); helper *"The first line becomes the title."*;
   collection `FilterChip`s restyled as selectable `CollectionTag(chip)`s.
   **`StickyActionBar`** duplicates **Save** above the keyboard (the AppBar Save stays, because
   the action gating is part of the state machine).
8. **Unsaved-changes guard** — see §5.2. This is the app's top data-loss trap.

**Fixes:** `#1`, `#2`, `#5`, `#8`, `#10`, `#11`, `#15`.

> **Constraint callouts:**
> - Post-frame `_load`. A missing key short-circuits with `'Missing Mem API key.'`
> - **`listCollections` failure is swallowed** and chips fall back to the raw id via
>   `_collectionTitle`. Keep the fallback; you may additionally show the quiet
>   *"Collections unavailable — Retry"* strip, but the failure must stay **non-fatal**.
> - **Optimistic concurrency:** `_version` is captured from **every** `readNote`/`updateNote`
>   response and passed back. Save silently no-ops without a version or key.
> - **`updateNote` is ONE combined write** of markdown + the **full** `collectionIds` list +
>   version. Success repopulates **all** state from the server response, then bumps
>   `notesListRevision`. Failure **keeps edit mode and the controller text**.
> - `_beginEdit` snapshots the collection set; `_cancelEdit` restores it.
> - Read mode **MUST** use `MarkdownBody` with `selectable: true` — a nested scrollable
>   (`Markdown`) steals drags on mobile.
> - Both confirms are `showDialog<bool>` and proceed only on `true && mounted`.
> - **Trash/restore reload in place (no pop). Hard delete is the only pop**, with the `Navigator`
>   captured before the await.
> - AppBar action gating stays keyed on `inTrash × _editing`.
> - *"First line becomes the title"* is **Mem API semantics**, not just hint copy.

### 4.7 SETTINGS — `lib/features/settings/settings_page.dart`

From README to instrument panel. A `ListView` of `AppListSection`s with `SectionHeader` eyebrows.
**Every prose paragraph is deleted** — what survives becomes field helper text.

Signature change (const-compatible, so the launcher contract holds):
```dart
enum SettingsSection { account, models, voice, automation, appearance, security }
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.focusSection});
  final SettingsSection? focusSection;
}
```
`focusSection` scrolls to that section's anchor on first frame. **`settingsIconActions` still
pushes `const SettingsPage()` with no arguments.** Every *"Open Settings"* CTA in the app must
deep-link to the relevant section rather than dumping the user at the top of a long scroll.

**Top to bottom**

1. **Setup status card** (top, above the sections) — three `StatusTile`s sharing **one derived
   `setupComplete` signal with the gear badge**, so the badge and the card can never disagree:
   - *Mem account* — `ok` + `Connected` / `error` + `Add your API key`
   - *Chat models* — `ok` + `3 models · Claude Sonnet active` (with `ProviderBadge`) /
     `error` + `Add a chat model`
   - *Voice* — `ok` + `Key saved` / `neutral` + `Uses your OpenAI chat model key`
   Each tile taps to scroll to its section. This is the only real first-run orientation surface
   in the app (`#3`).
2. **ACCOUNT** —
   - `StatusTile` **Mem API key**: `success` dot + `Key saved · ····4F2`, or `error` dot +
     `Not set`. Trailing **Edit** opens an `EditorSheet`.
     **The key sheet is the app's worst footgun and is fixed as follows:** the field starts
     **blank** with the hint *"Enter a new key to replace"* — a stored secret is never prefilled
     as revealable plaintext (`#12`). If the field reveals, it **auto-re-obscures after 10 s**.
     **Save is disabled unless the field is dirty**, so an untouched sheet can never wipe a key.
     Deletion is an explicit error-styled **"Remove key"** button behind
     `confirmDestructive('Remove key?')`. The underlying trim/empty→null delete semantics are
     unchanged — they are just no longer reachable by accident.
   - `StatusTile` **Mem MCP**: `Connected` / `Not connected` / `pending` +
     *"Waiting for browser…"* with an `InlineSpinner` during the OAuth round-trip (closes the
     dead-air gap, `#4`). One contextual action: Connect or Disconnect. **Disconnect now
     confirms** (`#5`).
3. **CHAT MODELS** — `AppRow`s: `ProviderBadge` + `composeChatDisplayName` title + raw model id
   demoted to `bodySmall` meta + an active indicator. **Row tap sets the active model**
   (`RadioListTile` retired). Kebab = Edit / Remove. `Add model` `FilledButton.tonal` at the
   section foot. The cramped `AlertDialog` becomes an `EditorSheet`: provider `SegmentedButton`,
   model dropdown with the catalog-drift warning row (in `warning`), key field with helper
   *"Required for a new model. Leave blank to keep the stored key."*, and
   *"Stored in your device keystore."* Empty section → inline `EmptyState`.
4. **VOICE** — transcription model dropdown with **friendly labels** *(Whisper /
   GPT-4o mini transcribe)* over the exact values, plus a `StatusTile` **OpenAI key** using the
   same blank-start sheet, with helper *"Uses your chat model key when empty."*
5. **AUTOMATION** — nav `AppRow` **Prompt jobs** with a live subtitle `8 jobs · 2 pinned` →
   `PromptJobsPage`.
6. **APPEARANCE** — a 3-way `SegmentedButton`: System / Light / Dark. Default **Dark** (§2.1).
7. **SECURITY** — one `bodySmall` line with an `ExpansionTile` for the detail.

All feedback goes through `memSnack` with the standard copy system. Save buttons briefly morph to
a success check for 800 ms.

**Fixes:** `#1`, `#3`, `#4`, `#5`, `#12`, `#14`.

> **Constraint callouts:**
> - Key prefills read **post-frame**. (With the blank-start sheet, what is read post-frame is the
>   *presence* and last-3 characters for masking — never the full value into a visible field.)
> - **Trim + empty→null semantics: an empty field DELETES the stored key** (both Mem and voice).
>   Preserved — but now only reachable through the explicit Remove action.
> - **OAuth error taxonomy, verbatim:** `UserCancelled` → `'Sign-in cancelled.'`;
>   `PlatformException` → `'OAuth error: <msg>'`; generic → `toString`.
> - **Model editor save order:** capture messenger + `AppScope` from the **page** context → pop
>   the dialog/sheet → `vault.setLlmApiKey` **if a key was given** → `saveChatModels(activeId)`.
> - New profiles **REQUIRE** a key; a blank key on edit **keeps** the vault entry.
> - Profile id keys **both** `ChatModelProfile` and the vault entry: an existing id is preserved;
>   a new one is `Uuid v4`.
> - **Active-model rules:** add → new becomes active; edit → keep; remove-active → promote the
>   first; remove-last → null.
> - **The vault key is deleted BEFORE `saveChatModels` on remove.**
> - `displayName` is **always** recomputed via `composeChatDisplayName` and is **never**
>   user-editable.
> - Catalog-drift warning + provider-change reset behaviour preserved.
> - **The editor's `keyCtrl` is intentionally NOT disposed** (disposing it crashes on route
>   teardown rebuild). Keep the quirk and keep the comment explaining it.
> - Voice dropdown **values** are exactly `'whisper-1'` and `'gpt-4o-mini-transcribe'`. Only the
>   labels change.
> - **`PromptJobsPage` must stay reachable from Settings.**

### 4.8 PROMPT JOBS — `lib/features/settings/prompt_jobs_page.dart`

One vocabulary everywhere: **prompt jobs** (the Chat strip keeps the short label `Jobs`).

**Top to bottom**

1. **AppBar** `Prompt jobs`.
2. **HOME WIDGET** `StatusTile` — when pinning is unsupported, an explanatory row (**not** a
   greyed ghost button); when supported, `Add widget to home`.
3. **PINNED** — `SectionHeader('PINNED · 2/4')` then a `ReorderableListView` of 64 dp rows:
   tabular position number · title · 1-line prompt preview · a **real** drag handle
   (`ReorderableDragStartListener` wrapping the icon — the decorative-handle lie ends, `#10`) ·
   a visible 48 dp **unpin** `IconButton`.
4. **ALL JOBS** — `SectionHeader` with the count, then `AppRow`s: title · 1-line prompt preview ·
   a 14 dp filled push-pin in `primary` when pinned (a visible pinned indicator, `#11`) ·
   a visible **pin/unpin** `IconButton` (the primary action moves **out** of the kebab, `#6`) ·
   kebab = Edit / Delete. **Row tap opens Edit** (inert rows fixed).
   A `SearchPill` (client-side filter) appears once the list exceeds **8** jobs (`#7`).
5. **Extended FAB** `New job`; list bottom inset `MemInsets.listBottomForFab`.
6. **Empty state** — `EmptyState` *"Create your first prompt job"* / *"Run it from a home-screen
   widget with one tap"* + CTA.

**Editor** = `EditorSheet`: title + multiline prompt, **Save disabled until both are non-empty**
(the silent no-op dies), helper *"Sent to the model verbatim."*

**Fixes:** `#3`, `#5`, `#6`, `#7`, `#10`, `#11`.

> **Constraint callouts:**
> - **`pinnedTemplateIds` is the ORDER source of truth** (max 4, deduped, stale ids tolerated
>   silently via `promptById` + filter).
> - **Pin flow: `syncHomePromptWidget` BEFORE `requestPinPromptWidget`.**
> - Reorder uses the standard `newI > oldI` decrement, then persists the **full list**, unawaited.
> - `ReorderableListView` keys are `ValueKey(t.id)`.
> - The 5th-pin rejection guard and its snackbar are preserved.
> - Delete uses `showDialog<bool>` with `context.mounted` checks between awaits.
> - **Editor id = `existing?.id ?? Uuid v4`. Template ids are a STABLE contract for home-widget
>   deep links (`memai://prompt?templateId=<id>`) and must never be renamed or regenerated on
>   edit.**
> - Editor: pop the sheet (messenger captured first) **then** await `upsertPromptJob`.
> - `_pinSupported` is resolved async post-frame and gates the pin button.
> - The FAB must not occlude the last row's controls — hence the 96 dp inset.

---

## 5. NEW UX CAPABILITIES

### 5.1 Search (`searchNotes`) — Notes

The `searchNotes({query, limit, offset, snapshotId})` endpoint is completely unused today. It is
a **second pagination lane with different semantics** from the timeline's opaque cursor, and the
two must never touch.

**Interaction**
1. Tapping the `SearchPill` (or the AppBar search icon) enters **search mode**: the field focuses,
   the chip strip hides, the timeline fades out over `MemMotion.micro`.
2. **Debounce 300 ms**, minimum **2 characters**.
3. Results replace the timeline. A header strip in `primaryContainer` shows `9 results` (tabular)
   with a clear affordance.
4. Result rows are **identical** to timeline rows (same `AppRow`, same tags, same relative time).
5. Its own **offset pagination**: `offset += limit` (limit 20) on the same 400 dp-from-end trigger,
   passing `snapshotId` from the first response so paging is consistent.
6. `Cancel` / clear exits search mode and restores the timeline **exactly as it was** — same rows,
   same scroll offset, same filter, no refetch.

**Isolation guarantees (mandatory)**
- Search state lives in its own object (`lib/features/home/notes_search_controller.dart`).
  **It must never write into the timeline's `items`, `_nextPage`, or filter state.**
- **Stale-response cancellation:** every request carries a monotonically increasing sequence
  number; a response whose sequence is not the latest is discarded.
- The `'notes_load'` telemetry context belongs to the timeline. Search failures report under
  `'notes_search'` — a **new** context, additive, which does not disturb the existing consumed
  strings.
- Search states: typing (skeleton rows) · zero results (`EmptyState` *"No notes match"* ) ·
  error (`ErrorState` + Retry, staying in search mode).

### 5.2 Unsaved-changes guard and Undo

**NoteDetail guard.** `PopScope(canPop: !dirty)` where
`dirty = _editCtrl.text != _markdown || _assignedCollectionIds != _assignedBackup`.
Both an intercepted system-back pop **and** the Cancel button raise
`confirmDestructive(title: 'Discard changes?', consequence: 'Your edits will be lost.',
actionLabel: 'Discard')` — with **Keep editing** as the promoted button and **Discard** as the
demoted error-coloured text button (§3.7). Only on `true` does `_cancelEdit()` run (which restores
the collection snapshot) or the pop proceed.

Editor sheets with typed content use the same guard on dismiss.

**Undo — it must be real, not cosmetic.** Exactly two sites:

| Site | Undo does |
|---|---|
| **Trash a note** | Calls `restoreNote(noteId)`, then reloads in place and bumps `notesListRevision`. Because trash/restore return `request_id`s and the list is eventually consistent, the snackbar copy is *"Moved to trash."* and the restore path must tolerate the row briefly not reflecting the change; do **not** optimistically mutate the list, let the reload settle it. |
| **Capture clear** | Restores the **complete** draft: body text, guidance text, selected collection ids, replace/append mode, and language state. A body-only restore is not acceptable. |

`MemMotion.undo` = 6 s.

### 5.3 Infinite scroll + stale-content retention

**Infinite scroll.** The `Load more` button is deleted. A scroll listener fires the next page when
`position.pixels > position.maxScrollExtent - 400`, guarded by `!_loading && _nextPage != null`.
The call shape is unchanged (`rawListNotes(limit: 40, includeContent: false, page: _nextPage,
collectionId: _filterCollectionId)`). Tail = 3 skeleton rows.

**Stale-content retention — how it coexists with the refresh contract.**
`CONSTRAINTS.md` requires that refresh **clears `items` + cursor pre-fetch**. That stays true. The
retention lives entirely in the **view layer**:

1. At the start of a refresh, copy the current rows into an immutable `_displaySnapshot`.
2. The data layer then clears `items` and the cursor exactly as today.
3. While `items.isEmpty && _displaySnapshot != null`, the sliver renders the **snapshot**.
4. **Snapshot rows are non-tappable** (`AppRow(enabled: false)`) — a stale row could otherwise
   open a note the server just deleted. This is not optional.
5. On success the snapshot is dropped and the new rows render. **On error the snapshot is
   dropped** and `ErrorState` renders — a dimmed snapshot must never persist indefinitely.
6. The `notesListRevision` listener path must not be able to render a half-state: take the
   snapshot and clear in the **same** `setState`.

Flag this to the contract owner in the PR: the clear semantics are unchanged, only the rendering
source differs.

### 5.4 Collection deep-link channel — `AppState.notesFilterRequest`

Additive to `AppState`, mirroring `shellTabRequest` **exactly**:

```dart
/// When set, the Notes tab applies this collection filter once, then clears it.
final ValueNotifier<String?> notesFilterRequest = ValueNotifier(null);

void requestNotesFilter(String collectionId) {
  notesFilterRequest.value = collectionId;
  goToShellTab(0);
}
```

`NotesPage` listens, and on a non-null value: applies the filter, reloads, then clears the channel
in a `scheduleMicrotask` — **the same consume-once-and-clear discipline as `shellTabRequest`**.
Getting this wrong causes re-filter loops. Listener attach/detach follows the existing
attach-on-instance-change / detach-old / detach-in-dispose pattern.

If the channel cannot be landed safely, **cut the tappable-tag affordance** rather than shipping
another false one.

### 5.5 Chat model switcher

A bottom sheet (`showModalBottomSheet`, radius 20, `surfaceContainerHighest`) listing every
profile as a radio row: `ProviderBadge` · `composeChatDisplayName` · raw model id in `bodySmall`
meta · active check. A footer row **"Manage models"** pushes
`SettingsPage(focusSection: SettingsSection.models)`.

Selecting a profile calls the existing `setActiveModel` path. The existing listener then runs
`_switchSessionProfile`, which **persists the old session first, then restores the new one**. When
the restore completes, insert the system row (§4.5) naming the new model and, if
`ChatSessionSnapshot.savedAt` is non-null, the restore date. The swap is never silent again (`#2`).

### 5.6 Settings status cards

One derived signal, three consumers:

```dart
bool get setupComplete => hasMemRest && chatModels.isNotEmpty;
```

- `SettingsGearButton` shows its 8 dp `error` badge when `!setupComplete`.
- The setup card's three `StatusTile`s render from the same inputs.
- Every *"Open Settings"* CTA passes the `SettingsSection` that matches the failure.

The badge and the card can therefore never disagree.

### 5.7 Capture sticky CTA + collapsible advanced config

Covered in §4.4 steps 6–7. The interaction rules that matter:

- The `StickyActionBar` is **always visible**, above both the NavigationBar and the keyboard.
- The `ExpansionTile` for transcription options is **collapsed on every entry to the tab** — it
  does not remember its expanded state across tab switches, because the whole point is that
  advanced config stops taxing every visit. (The *values* inside it persist; only the disclosure
  collapses.)
- The content field is the flexible child of the column, so opening the keyboard shrinks the
  field rather than pushing the CTAs off-screen.

---

## 6. IMPLEMENTATION PLAN

### 6.1 Ordering

```
t0 ──► WP-0  Theme foundation        (blocks everything)
   ──► WP-0B Android brand surfaces  (independent)
   ──► WP-S  Chat rendering spike    (independent, blocks WP-7)

t1 ──► WP-1  Primitives A  ┐ (need WP-0 tokens only)
   ──► WP-2  Primitives B  ┘

t2 ──► WP-3 Shell · WP-4 Notes · WP-5 Collections · WP-6 Capture ·
       WP-7 Chat · WP-8 NoteDetail · WP-9 Settings · WP-10 PromptJobs
       (all parallel; each owns exactly one feature file plus its own new helpers)
```

### 6.2 Work packages and exact file ownership

**No two packages share a file. If you need a change in a file you do not own, request it — do
not edit it.**

| WP | Scope | Files owned (create ⊕ / edit ✎ / rewrite ⟲) |
|---|---|---|
| **WP-0** | Theme foundation, app wiring, `AppState` additions | ⊕ `lib/theme/mem_color_schemes.dart` · ⊕ `lib/theme/mem_semantic_colors.dart` · ⊕ `lib/theme/mem_collection_ink.dart` · ⊕ `lib/theme/mem_typography.dart` · ⊕ `lib/theme/mem_metrics.dart` · ⟲ `lib/theme/mem_app_theme.dart` · ✎ `lib/main.dart` · ✎ `lib/app_state.dart` · ⊕ `lib/core/settings/appearance_store.dart` · ⊕ `test/theme_contrast_test.dart` · ⊕ `test/collection_ink_test.dart` |
| **WP-0B** | Off-app brand surfaces | ✎ `android/app/src/main/res/values/colors.xml` · ⊕ `android/app/src/main/res/values-night/colors.xml` · ✎ `android/.../values/styles.xml` · ✎ `android/.../values-night/styles.xml` · ✎ `android/.../drawable/launch_background.xml` · ✎ `android/.../drawable-v21/launch_background.xml` · ✎ `android/.../drawable/ic_launcher_brain.xml` · ✎ `android/.../drawable/widget_prompt_bg.xml` · ✎ `android/.../layout/prompt_jobs_widget.xml` |
| **WP-1** | Primitives A | ⊕ `lib/ui/`: `inline_spinner.dart` · `hairline.dart` · `ai_glyph.dart` · `section_header.dart` · `empty_state.dart` · `error_state.dart` · `feedback.dart` · `confirm_destructive_dialog.dart` · `skeleton.dart` · `date_labels.dart` · `async_page_mixin.dart` |
| **WP-2** | Primitives B | ⊕ `lib/ui/`: `app_list_section.dart` · `collection_tag.dart` · `chip_strip.dart` · `status_tile.dart` · `editor_sheet.dart` · `sticky_action_bar.dart` · `search_pill.dart` · `provider_badge.dart` · `settings_gear_button.dart` · ✎ `lib/widgets/settings_launcher.dart` |
| **WP-S** | Chat rendering spike | ⊕ `docs/redesign/CHAT_RENDERING_SPIKE.md` · ⊕ `lib/features/chat/chat_message_builders.dart` |
| **WP-3** | Shell | ✎ `lib/features/shell/mem_shell.dart` |
| **WP-4** | Notes | ⟲ `lib/features/home/notes_page.dart` · ⊕ `lib/features/home/notes_search_controller.dart` |
| **WP-5** | Collections Manage | ⟲ `lib/features/home/collections_manage_page.dart` |
| **WP-6** | Capture | ⟲ `lib/features/capture/capture_page.dart` · ⊕ `lib/features/capture/mic_ring_painter.dart` |
| **WP-7** | Chat | ⟲ `lib/features/chat/mem_chat_page.dart` · ⊕ `lib/features/chat/model_switcher_sheet.dart` |
| **WP-8** | Note Detail | ⟲ `lib/features/note/note_detail_page.dart` |
| **WP-9** | Settings | ⟲ `lib/features/settings/settings_page.dart` |
| **WP-10** | Prompt Jobs | ⟲ `lib/features/settings/prompt_jobs_page.dart` |

**Read-only for everyone:** `lib/core/**` (except the one new `appearance_store.dart` owned by
WP-0), `lib/app_scope.dart`, `integration_test/**`.

**WP-0 `lib/app_state.dart` additions (nobody else edits this file):**
- `final ValueNotifier<String?> notesFilterRequest` + `requestNotesFilter(String)` (§5.4)
- `ThemeMode themeMode` (default `ThemeMode.dark`) + `Future<void> setThemeMode(ThemeMode)`
  persisting through `AppearanceStore`; load it inside the existing `load()` **before**
  `isHydrated = true`.
- `bool get setupComplete => hasMemRest && chatModels.isNotEmpty;`
- Nothing else. `AppState` still holds **no server data**; screens still own fetch/loading/error/
  pagination state; `notesListRevision` remains the sole cross-screen invalidation channel.

**WP-0B brand targets** (bring off-app surfaces into the palette — they are the user's *first*
brand contact and currently match nothing):
- `launch_bg`: light `#FBFBFC`, night `#050505`.
- `ic_launcher_brain.xml`: background `#050505` (night-safe on both), glyph `#5EA2FF` — replacing
  the current green `#2ABF74` on `#111418`, which matches no proposed palette.
- `widget_prompt_bg.xml`: solid `#0E0E10`, radius 12, plus a 1 dp `#63636F` stroke.
- `prompt_jobs_widget.xml`: header text `#EDEDF0`, slot text `#9A9AA5`.

**WP-S deliverable.** A written go/no-go on whether `flutter_chat_ui 2.11.1`'s `Builders` API can
express: full-width assistant blocks with a header row, right-aligned user bubbles, centred system
rows, error rows with a retry action, and a typing/streaming state. The document must state the
chosen path and, if the library resists, specify the fallback — a hand-rolled `ListView` over the
same `InMemoryChatController` and the same send pipeline — together with the list of contracts to
re-verify through the change (send order, pending-bubble id rewrite, `'…'` sentinel byte-identity,
persist filter, provider histories, HTTP-400 reset, per-profile persistence).

### 6.3 Cross-cutting risks each agent must respect

1. **`google_fonts` is not a dependency and must not become one** (§2.4). No new pub packages, no
   new binary assets, no network fetch on first launch.
2. **Colour centralisation is better than it looks.** The only hardcoded `Color(0xFF…)` values in
   `lib/` are the four in `lib/theme/mem_app_theme.dart`. The real work is retiring
   `cardTheme.color` and its three `Material()` call sites (`notes_page.dart:419`,
   `collections_manage_page.dart:160`, `mem_chat_page.dart:511`) — not a repo-wide colour hunt.
3. **The NavigationBar wrapper is where the smoke test breaks.** Decoration only, no pointer
   interception, no second `NavigationBar` (§4.1).
4. **`flutter_chat_ui` is the load-bearing risk** for the best visual idea in the redesign
   (§4.5, WP-S). Prototype before the Chat package starts, or the signature moment gets
   value-engineered away mid-implementation.
5. **The hairline is the winner's structural single point of failure.** Boundary vs divider
   (§2.7), `hairlineWidth()`, and an actual mdpi check.
6. **Refresh retention grazes a contract's letter** (§5.3). Keep the clear in the data layer,
   disable taps on the snapshot, drop the snapshot on error, and say so in the PR.
7. **Search is a second pagination lane** with foreign semantics (§5.1). Isolate it completely.
8. **Undo must be real** (§5.2), and the memIt processing chip must have an expiry (§4.4).

### 6.4 Verification checklist

Run all of it before declaring a package done. Items marked **[all]** apply to every package.

**Build and contract**
- [ ] **[all]** `flutter analyze` clean — zero new warnings.
- [ ] `flutter test` — existing unit tests pass unchanged.
- [ ] **`flutter test integration_test/app_smoke_test.dart` passes.** Non-negotiable for WP-3, and
      re-run by WP-4/6/7 since they render inside the shell. It asserts one `MemShell`, one
      `NavigationBar`, and that `Icons.article_outlined`, `Icons.add_circle_outline`,
      `Icons.chat_bubble_outline` are findable and tappable.
- [ ] `test/theme_contrast_test.dart` passes: every pair in §2.3 meets its stated ratio, all 16
      collection ink pairs clear 4.5 : 1 at label size, every status dot clears 3 : 1 against its
      container, `outline` clears 3 : 1 against `surface`/`surfaceContainerLow`/`surfaceContainer`
      in both brightnesses.
- [ ] **Token completeness:** a test asserts both `ColorScheme`s define every role the app reads,
      and that `MemSemanticColors` is registered on both `ThemeData`s. No role may fall back to a
      seed-derived colour. (Also: no token named `surfaceContainerLowLow` — that was a typo in an
      earlier draft.)

**Design system compliance (grep-able)**
- [ ] **[all]** No `Color(0x` outside `lib/theme/`.
- [ ] **[all]** No `BoxShadow` anywhere in `lib/`.
- [ ] **[all]** No `ShaderMask` in `lib/`.
- [ ] **[all]** No `Opacity(` wrapping a list or sliver.
- [ ] **[all]** No `OutlineInputBorder()` declared inline on a `TextField` — the global
      `InputDecorationTheme` owns it.
- [ ] **[all]** No `CircularProgressIndicator` outside `lib/ui/inline_spinner.dart` and
      `RefreshIndicator`.
- [ ] **[all]** No `e.toString()` reaching a `Text` or `SnackBar`.
- [ ] **`tertiary` / `aiAccent` audit:** every hit outside `lib/theme/` is `lib/ui/ai_glyph.dart`
      or one of the permitted AI sites in §2.10. No stock component resolves to `tertiary`.
- [ ] Every `Divider`/`BorderSide` thickness is ≥ 1.0 and uses `hairlineWidth(context)`.

**Device checks**
- [ ] **mdpi (dpr 1.0) emulator:** hairlines are visible and exactly 1 px; section boundaries read
      as boundaries.
- [ ] **Outdoors / max brightness sanity** on the dark theme: list sections are distinguishable
      from the canvas.
- [ ] **Light and dark both audited**, with the **same depth grammar** in each (zero elevation,
      hairlines, no shadows). A design whose structural read changes between themes is a bug.
- [ ] **Cold start with the network disabled**: correct fonts, no missing-glyph boxes, no blocked
      first frame.
- [ ] **Splash → app** in System, Light, and Dark: no brightness flash.
- [ ] **Text scale 1.3 and 2.0:** note rows degrade in the specified order (§3.1) and never clip;
      the 64 dp NavigationBar with always-visible labels survives.
- [ ] **Small phone (5.5-inch):** Notes shows ≥3 full 76 dp rows above the fold with the search
      pill and chip strip present; no screen composes >140 dp of bottom chrome.
- [ ] **Touch targets:** every chip, icon button, drag handle, and kebab measures ≥48 dp.

**Behavioural**
- [ ] Refresh on Notes never blanks the list; stale rows are non-tappable; the snapshot is dropped
      on error.
- [ ] Infinite scroll fires once per page, never re-enters, and never fires with a null cursor.
- [ ] Search never contaminates timeline paging state; stale responses are discarded.
- [ ] Undo restores the *complete* capture draft and actually calls `restoreNote` for trash.
- [ ] The memIt processing chip always disappears (90 s, revision bump, or manual dismiss).
- [ ] A dropped chat stream converts to an error row with Retry within 90 s.
- [ ] Chat system rows do **not** survive a persist/restore round-trip, and the `'…'` sentinel
      string is byte-identical to the original.
- [ ] Every "Open Settings" CTA lands on the right section.
- [ ] Every destructive confirm uses the same grammar (Cancel promoted, destructive demoted) at
      all six sites, and outside-tap cancels.
- [ ] `notesFilterRequest` consumes once and clears — no re-filter loop.

---

## 7. QUICK REFERENCE — UX PROBLEM → OWNER

| # | Problem | Fixed by |
|---|---|---|
| 1 | Raw exceptions, no recovery, silent swallows | `memErrorText`/`ErrorState`/`errSnack` (WP-1) + the collections-unavailable strip (WP-4, WP-8) |
| 2 | Silent data-loss traps | Unsaved guard (WP-8) · capture undo (WP-6) · announced model swap (WP-7) · discard-recording confirm (WP-6) |
| 3 | No empty states / first-run guidance | `EmptyState` (WP-1) · gear badge (WP-2) · setup card (WP-9) · pre-hydration shell (WP-3) |
| 4 | Broken loading feedback | Skeletons + stale retention (WP-4) · button spinners (WP-6) · OAuth pending tile (WP-9) |
| 5 | Destructive grammar | `ConfirmDestructiveDialog` (WP-1) at all six sites · trash-only "Delete forever" (WP-8) · MCP disconnect confirm (WP-9) |
| 6 | Buried / hostile primary actions | Sticky CTAs + disclosure (WP-6) · infinite scroll (WP-4) · visible pin toggle (WP-10) · row-tap edit (WP-5, WP-10) |
| 7 | No search | `searchNotes` UI (WP-4) · client filters (WP-5, WP-10) |
| 8 | Touch targets and input timing | 48 dp everywhere (WP-2) · pointer-down hold-to-talk + 96 dp mic (WP-6) · FAB inset (WP-5) · `scrollPadding` (WP-8) |
| 9 | Chat breaks the design language | Themed rendering, no seam, error rows (WP-7) |
| 10 | False affordances | Real drag handle (WP-10) · tappable tags via `notesFilterRequest` (WP-8) · amplitude ring (WP-6) · row-tap edit (WP-5) |
| 11 | Information starvation | Note-row tags/time (WP-4) · NoteDetail metadata + trash banner (WP-8) · collection description **and** count (WP-5) · pinned indicator (WP-10) |
| 12 | Settings is a README | Status tiles, sheets, blank-start secret editor (WP-9) |
| 13 | Invisible background work | Job status row + queue badge (WP-7) · memIt processing chip (WP-6) |
| 14 | Jargon | Copy pass (WP-6, WP-7, WP-9) |
| 15 | Non-standard interactions | Sentence-case date labels (WP-1/WP-4) · Hero (WP-4/WP-8) · chat context menu (WP-7) · route transitions (WP-0) |
