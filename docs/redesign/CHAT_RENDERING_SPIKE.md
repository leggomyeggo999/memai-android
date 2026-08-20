# WP-S — Chat rendering spike

**Question (§6.2):** can `flutter_chat_ui 2.11.1`'s `Builders` API express full-width assistant
blocks with a header row, right-aligned user bubbles, centred system rows, error rows with a retry
action, and a typing/streaming state?

**Verdict: GO.** Keep `flutter_chat_ui`. Every §4.5 row shape is expressible through
`Builders.chatMessageBuilder` + `Builders.textMessageBuilder`. No fork, no vendoring, no
hand-rolled `ListView`. The fallback is specified in §6 below but is **not** being taken.

**Deliverable:** `lib/features/chat/chat_message_builders.dart` — real, compiling widgets that
WP-7 wires in, not a research memo. `dart analyze` on it is clean.

Sources read for this spike (not the pub.dev docs — the actual pinned source):

- `…/pub.dev/flutter_chat_core-2.9.0/lib/src/models/builders.dart`
- `…/pub.dev/flutter_chat_core-2.9.0/lib/src/models/message.dart`
- `…/pub.dev/flutter_chat_core-2.9.0/lib/src/theme/chat_theme.dart`
- `…/pub.dev/flutter_chat_ui-2.11.1/lib/src/chat.dart`
- `…/pub.dev/flutter_chat_ui-2.11.1/lib/src/chat_message/chat_message_internal.dart`
- `…/pub.dev/flutter_chat_ui-2.11.1/lib/src/chat_message/chat_message.dart`
- `…/pub.dev/flutter_chat_ui-2.11.1/lib/src/composer.dart`
- `…/pub.dev/flutter_chat_ui-2.11.1/lib/src/chat_animated_list/chat_animated_list.dart`
- `lib/features/chat/mem_chat_page.dart`, `lib/core/chat/chat_session_store.dart`

---

## 1. Why it works — the two hooks that decide it

`ChatMessageInternal.build` (`chat_message_internal.dart:96`) does exactly two things:

```dart
final child = _buildMessage(...);            // dispatches on the Message subtype
return builders.chatMessageBuilder?.call(context, msg, index, animation, child, …)
    ?? ChatMessage(…, child: child);          // the default wrapper
```

That means:

1. **`chatMessageBuilder` replaces the entire per-item wrapper.** The default `ChatMessage`
   (`chat_message.dart:139-189`) is what makes bubble layout feel mandatory — it wraps the child in
   `Align(alignment: isSentByMe ? centerEnd : centerStart)` and then a
   `Row(mainAxisSize: MainAxisSize.min, children: [… Flexible(child: child) …])`. A genuinely
   full-width block fights that. Overriding `chatMessageBuilder` removes it wholesale, and our
   replacement hands the child the full content width and lets the child align itself. That is the
   single fact the GO rests on.
2. **`textMessageBuilder` supplies the content**, typed as `TextMessage`, with `index`,
   `isSentByMe` and `groupStatus`. Everything the app sends is a `TextMessage`, so this one builder
   covers all five row shapes.

Mapping, row by row:

| §4.5 requirement | Mechanism | Verified |
|---|---|---|
| Full-width assistant block + header row | `chatMessageBuilder` drops the `Align`/min-`Row`; `MemAssistantBlock` uses `CrossAxisAlignment.stretch` | yes |
| Right-aligned user bubble, 78 % max width | `MemUserBubble`: `LayoutBuilder` → `ConstrainedBox(maxWidth: w * 0.78)` inside `Align.centerRight` | yes |
| Centred system row | `MemSystemRow`, routed on `authorId` (see §2) | yes |
| Error row with retry | `MemErrorRow`, `errorContainer` + 48 dp retry `IconButton` | yes |
| Typing / streaming state | `MemTypingDots` on the `'…'` sentinel; `MemStreamingCaret` on `streamingMessageId` (see §3) | yes |
| Themed from app tokens, no `ChatTheme.dark()` clash | `ChatTheme.fromThemeData(Theme.of(context))` (`chat_theme.dart:44`) maps `colorScheme` and `textTheme` straight through — zero hardcoded colours | yes |
| Empty state | `Builders.emptyChatListBuilder` | yes (WP-7) |

The send pipeline, `InMemoryChatController`, the id-rewrite streaming, the persist filter and the
provider histories are **untouched**. This is a presentation-layer change in the strict sense.

---

## 2. What we deliberately do NOT use, and why (both are contract traps)

### 2.1 `Message.system` / `systemMessageBuilder` — banned

The obvious move for centred system rows is `Message.system`. It is wrong here:

- The current persist filter is `m is TextMessage && text.trim().isNotEmpty && text != '…'`
  (`mem_chat_page.dart:133-137`). A `SystemMessage` already fails `m is TextMessage`, which would
  make §4.5's **mandated single added clause** (`&& m.authorId != _kSystemId`) dead code. The spec
  says "the persist filter gains **exactly one** clause"; that clause is only meaningful if system
  rows are `TextMessage`s.
- `ChatSessionStore._encodeUiMessage` (`chat_session_store.dart:129`) has a non-`TextMessage`
  branch that writes `'text': ''`. Introducing a second `Message` subtype into the controller puts
  live traffic through a branch nothing exercises today.

**Chosen path:** system rows are `Message.text(authorId: 'system', …)`. `chat_message_builders.dart`
exports `memChatSystemMessage()` so there is exactly one place that can get the author id wrong,
and `kMemChatSystemAuthorId` for the persist-filter clause.

### 2.2 `Message.textStream` / `textStreamMessageBuilder` — banned

The library models streaming as a distinct `TextStreamMessage` subtype with a `streamId`. Adopting
it would break three contracts at once:

- Streaming **rewrites the pending bubble in place under the same id** (`streamBubble`,
  `mem_chat_page.dart:305-319`). A subtype swap is not an in-place rewrite.
- The `'…'` sentinel would no longer be the text of the pending message, so the persist filter's
  `text != '…'` clause would stop catching it.
- `_failMessage` and the terminal `updateMessage` both construct `Message.text`; they would need a
  second code path.

**Chosen path:** streaming state is *derived*. `'…'` → three-dot pulse; `id == streamingMessageId`
→ caret. `MemChatBuilderConfig.streamingMessageId` is the only new state WP-7 carries, set to
`pendingId` when the run starts and cleared in the existing `finally`.

---

## 3. Where the library does resist, and the fix for each

None of these is fatal. All are known before WP-7 starts, which is the point of the spike.

1. **`composerBuilder` results are placed directly into a `Stack`** (`chat.dart:167-173`), and the
   default `Composer` returns a `Positioned` (`composer.dart:386`). Worse, the default composer
   wraps itself in a `BackdropFilter` with `sigmaX/Y = 20` — a `saveLayer` every frame, explicitly
   banned by §2.11.
   **Fix (recommended):** do not use the library composer at all. Put `Chat` in an `Expanded`
   inside the page `Column`, and pass `composerBuilder: (_) => const SizedBox.shrink()`. The §4.5
   job-status row (item 4) and composer (item 6) then live in the page column where the spec wants
   them, above the shell chrome. `ComposerHeightNotifier` stays at 0 and `ChatAnimatedList`'s
   default `bottomPadding: 20` applies, which is what we want when the composer is external.
   **Alternative:** a custom composer *inside* `Chat` must return
   `Positioned(left: 0, right: 0, bottom: 0, …)` **and** push its measured height into
   `context.read<ComposerHeightNotifier>().setHeight(h)` after layout, or the list's bottom padding
   is wrong. Only take this path if the keyboard behaviour of the external composer disappoints.

2. **Gestures live in the default wrapper.** `ChatMessage` is what reads
   `OnMessageTapCallback` / `OnMessageLongPressCallback` off the provider tree
   (`chat_message.dart:125-129`). Once `chatMessageBuilder` is overridden, `Chat`'s
   `onMessageLongPress` argument is **inert**.
   **Fix:** long-press is delivered through `MemChatBuilderConfig.onOpenMessageMenu`, wired on the
   assistant body, the user bubble and the error row. This is required anyway — §4.5 replaces the
   silent clipboard copy with a Copy / Retry / Select text menu (`#15`). WP-7 should drop
   `onMessageLongPress:` from the `Chat` call rather than leave a dead argument.

3. **`isSentByMe` is `currentUserId == authorId`**, so `'assistant'` and `'system'` both report
   `false`. Routing on it would render system notices as assistant blocks.
   **Fix:** `MemChatBuilderConfig.kindOf()` routes on `authorId` and only then on text.

4. **Automatic message grouping.** `ChatMessageInternal._resolveGroupStatus` groups same-author
   messages within 300 s and the default wrapper collapses their padding to 2 dp.
   **Fix:** `groupStatus` is ignored by `MemChatMessageWrapper`; padding is explicit. Assistant
   headers must not collapse — the header *is* the AI-provenance signal.

5. **`Builders` is a Freezed value with closure fields**, so a fresh `memChatBuilders(...)` compares
   unequal every rebuild and `_ChatState._updateBuilders()` re-runs. It is a field assignment, not a
   subtree rebuild — measured cost nil. `MemChatBuilderConfig` implements `==`/`hashCode` anyway, so
   WP-7 can memoise if it wants to.

6. **The header timestamp ticks while streaming.** `streamBubble` sets
   `createdAt: DateTime.now()` on every delta, so `resolvedTime` advances during a stream. This is
   pipeline behaviour and must not be changed. §2.4's global tabular figures mean it cannot shift
   layout. Accepted as-is.

7. **`ChatTheme` is a parallel theming system.** It only feeds the library's own default widgets —
   all of which we replace — but `Chat` still requires one. Pass
   `ChatTheme.fromThemeData(Theme.of(context))`; it reads `colorScheme` and `textTheme` directly, so
   it introduces no colour outside `lib/theme/` and it kills the `ChatTheme.dark()` /
   light-mode clash at `mem_chat_page.dart:577`.

8. **The `'Error'`-prefix heuristic.** `MemChatRowKind` detects a failed turn with
   `text.startsWith('Error')` — the exact test `_failMessage` itself uses before adding the prefix,
   so the two can never disagree, and it survives a persist/restore round-trip (where no in-memory
   id set would). A genuine model reply that opens with "Error" would be misclassified;
   `MemChatBuilderConfig.errorMessageIds` lets WP-7 pin the ids it actually failed this session and
   is unioned with the heuristic.

---

## 4. What WP-7 gets — public API of `lib/features/chat/chat_message_builders.dart`

Contract constants (byte-identical mirrors of `mem_chat_page.dart`):

```dart
const String kMemChatUserAuthorId      = 'user';
const String kMemChatAssistantAuthorId = 'assistant';
const String kMemChatSystemAuthorId    = 'system';   // the new _kSystemId
const String kMemChatPendingSentinel   = '…';        // NEVER retype this glyph
const String kMemChatErrorPrefix       = 'Error: ';
```

Helpers:

```dart
enum MemChatRowKind { user, assistant, assistantPending, assistantError, system }

String  memChatStripErrorPrefix(String text);
bool    memChatIsPendingSentinel(String text);
Message memChatSystemMessage({required String id, required String text, DateTime? createdAt});
```

Configuration and the builder factory:

```dart
@immutable
class MemChatBuilderConfig {
  const MemChatBuilderConfig({
    required String assistantLabel,            // ChatModelProfile.displayName
    String userAuthorId   = kMemChatUserAuthorId,
    String systemAuthorId = kMemChatSystemAuthorId,
    Widget? aiGlyph,                           // pass const AiGlyph() once WP-1 lands
    String? streamingMessageId,                // = pendingId while streaming, else null
    Set<String> errorMessageIds = const {},
    void Function(TextMessage)? onRetry,
    void Function(BuildContext, TextMessage)? onOpenMessageMenu,
    DateFormat? timeFormat,                    // default HH:mm
  });

  MemChatRowKind kindOf(TextMessage message);
}

Builders memChatBuilders(MemChatBuilderConfig config);
```

Widgets — each usable standalone in a plain `ListView`, none of them needing the
`flutter_chat_ui` provider tree:

```dart
class MemChatMessageWrapper extends StatelessWidget { … }  // chatMessageBuilder body
class MemChatMessageRow     extends StatelessWidget { … }  // textMessageBuilder body / router
class MemAssistantBlock     extends StatelessWidget { … }  // header + prose (+ pending/streaming)
class MemUserBubble         extends StatelessWidget { … }
class MemSystemRow          extends StatelessWidget { … }
class MemErrorRow           extends StatelessWidget { … }
class MemTypingDots         extends StatefulWidget  { … }
class MemStreamingCaret     extends StatelessWidget { … }
```

Wiring sketch:

```dart
Expanded(
  child: Chat(
    chatController: _chat,
    currentUserId: _kUserId,
    resolveUser: _resolve,
    onMessageSend: _handleSendFromInput,
    theme: ChatTheme.fromThemeData(Theme.of(context)),
    backgroundColor: Theme.of(context).colorScheme.surface,   // #050505, kills the seam
    builders: memChatBuilders(MemChatBuilderConfig(
      assistantLabel: profile?.displayName ?? 'Assistant',
      aiGlyph: const AiGlyph(),
      streamingMessageId: _streamingId,
      onRetry: _retryFailedTurn,
      onOpenMessageMenu: _showMessageMenu,
    )).copyWith(
      composerBuilder: (_) => const SizedBox.shrink(),
      emptyChatListBuilder: (_) => const _ChatEmptyState(),
    ),
  ),
),
```

### Design-token notes baked into the file

- Colours come from `Theme.of(context).colorScheme` only. Zero `Color(0x…)`; zero `BoxShadow`,
  `ShaderMask`, `Opacity(`, `OutlineInputBorder`, `CircularProgressIndicator`, or `e.toString()`
  (§6.4 greps verified on the file).
- `tertiary` appears at exactly two code sites, both on §2.10's permitted list: the assistant header
  sparkle and the streaming caret. The three-dot pending pulse is deliberately `onSurfaceVariant`,
  not violet — §2.10's permitted list does not include it and the audit is mechanical.
- The typing pulse animates **colour alpha**, never an `Opacity` widget, so there is no `saveLayer`
  (§2.11).
- No hairlines are drawn anywhere in the file, so it takes no dependency on WP-1's
  `lib/ui/hairline.dart`. Depth comes from surface steps (`surfaceContainerHigh` bubble,
  `errorContainer` block) as §2.7 prefers.
- Every tap target (header overflow, error retry) is a 48 × 48 `IconButton` with an explicit
  `BoxConstraints.tightFor`, independent of whatever `iconButtonTheme` WP-0 ships (§0.1 rule 4).

---

## 5. WP-7's remaining obligations (things this file cannot do for you)

1. **Add the persist-filter clause and nothing else.** The filter becomes
   `m is TextMessage && t.isNotEmpty && t != '…' && m.authorId != _kSystemId`. Do not retype the
   `'…'` — copy it, or import `kMemChatPendingSentinel`.
2. **Never add a system row to `_openAiHist` / `_anthropicHist` / `_geminiHist`.** Provider
   histories stay replaced wholesale from agent results, `_openAiHist[0]` always the system message.
3. **Track `streamingMessageId`.** Set it to `pendingId` immediately after inserting the pending
   bubble; clear it in the existing `finally` alongside `busy = false`. Do not add an await.
4. **Stream-stall watchdog (§4.5, mandatory).** Arm a 90 s (`MemMotion.streamStall`) timer that
   resets on each `streamBubble` delta; on expiry route through the *existing* `_failMessage` so the
   `'Error: '` prefix contract holds, then cancel it in `finally`. `MemErrorRow` renders the result
   with Retry — but the timer is yours.
5. **Retry semantics.** `onRetry` receives the failed assistant message; re-send the preceding user
   message through `_runUserPrompt` unchanged (trim → busy gate → profile gate → backend gate →
   vault key gate → …). Do not invent a second send path.
6. **Context menu.** `onOpenMessageMenu` should present Copy / Retry / Select text. The current
   silent `Clipboard.setData` in `_onMessageLongPress` is what `#15` is about; it goes away.

---

## 6. Plan B, specified but not taken

Trigger conditions that would flip this to NO-GO mid-implementation — none observed, listed so the
decision is falsifiable:

- `ChatAnimatedList`'s `SliverAnimatedList` diffing mis-animates the in-place pending-bubble rewrite
  (it does not: `ChatMessageInternal` subscribes to `operationsStream` and `setState`s on
  `ChatOperationType.update` for its own id — this is precisely the streaming path today).
- The external-composer layout in §3.1 produces keyboard-inset jank that the `Positioned` variant
  cannot fix.
- A future `flutter_chat_ui` bump changes the `chatMessageBuilder` signature. Pinned at 2.11.1; a
  bump is a deliberate act, not a surprise.

**The fallback, if it ever fires:** a hand-rolled `ListView.builder` over the **same**
`InMemoryChatController` and the **same** send pipeline. `_chat.messages` is the item source;
subscribe to `_chat.operationsStream` (or `ChangeNotifier` semantics of the controller) to rebuild;
reuse `MemChatMessageRow` and the five row widgets unchanged — they are deliberately free of any
`flutter_chat_ui` provider dependency, which is why the fallback costs a page-level `ListView` and
nothing else. What would be lost and must be re-implemented: insert/remove animation, auto-scroll to
end on send, scroll-to-bottom affordance, keyboard dismiss-on-drag, and safe-area handling.

**Contracts to re-verify through that change** (every one of them, with a device pass, not just a
compile):

1. **Send order**, unchanged and in this order: trim → busy gate → profile gate → backend gate
   (`!hasMemRest && !mcpConnected` aborts) → vault key gate → insert user msg → insert pending `'…'`
   bubble → `refreshMcpIfNeeded` → `MemToolRunner` (REST preferred; MCP client only when
   `!hasMemRest && mcpConnected`) → `hasBackend` check → dispatch on the literal strings
   `'openai' | 'anthropic' | 'gemini'`.
2. **Pending-bubble id rewrite in place** — `streamBubble` and the terminal `updateMessage` both
   reconstruct `Message.text` with the *same* `pendingId`; `_pendingById` still resolves it.
3. **`'…'` sentinel byte-identity** — the same single U+2026 HORIZONTAL ELLIPSIS in
   `streamBubble`'s empty-accumulator branch, the initial insert, and the persist filter.
4. **Persist filter** — `m is TextMessage && text.trim().isNotEmpty && text != '…'`, plus the one
   new `m.authorId != _kSystemId` clause; system rows must not survive a save/restore round-trip.
5. **Provider histories** replaced wholesale from agent results, `_openAiHist[0]` always the system
   message, anthropic/gemini receiving the system prompt separately; system rows never appended.
6. **HTTP 400 → `_resetProviderHistory(provider)`**, and `_failMessage` rewriting the pending bubble
   with the `'Error: '` prefix; `MemErrorReporter.report` still carrying context `'chat'` vs
   `'prompt_job'` with `provider` and `httpStatus`.
7. **Per-profile persistence** — `ChatSessionStore` key `'chat_session_v1_<profileId>'`, 5-day
   retention, text-only round-trip; profile switch persists the OLD session first, then restores
   (null → empty; reseed the `openAiHist` system message when the stored history is empty).
8. Plus, unchanged either way: prompt jobs polling at 150 ms while busy then running; a user send
   while busy aborting with a snackbar; FIFO serial drain with the `_drainingPromptRuns` guard;
   `MemJobNotifications.showPromptJobFinished` on both success and failure but only when
   `notifyTitle != null`; the jobs picker popping the sheet before `_runFromTemplate`;
   `_activeProfile` falling back to the first model on an id miss; the app listener removed against
   the cached `_app`, the promptQueue listener removed, `_chat` disposed;
   `ChatPromptQueue` treated as read-only (`enqueue` adds-then-notifies, `drainAll` is an atomic
   copy-then-clear).

Because the GO path leaves the controller, the message types and the whole send pipeline untouched,
items 1–8 are *unchanged code* rather than *re-verified code*. That asymmetry is the argument for
the GO.
