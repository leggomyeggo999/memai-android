import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/llm/chat_model_profile.dart';
import '../../core/llm/curated_chat_models.dart';
import '../../theme/mem_metrics.dart';
import '../../theme/mem_semantic_colors.dart';
import '../../ui/app_list_section.dart';
import '../../ui/async_page_mixin.dart';
import '../../ui/confirm_destructive_dialog.dart';
import '../../ui/editor_sheet.dart';
import '../../ui/empty_state.dart';
import '../../ui/feedback.dart';
import '../../ui/provider_badge.dart';
import '../../ui/section_header.dart';
import '../../ui/status_tile.dart';
import 'prompt_jobs_page.dart';

/// The anchors every "Open Settings" CTA in the app deep-links to.
///
/// A CTA that dumps the user at the top of a long scroll is not a recovery, so
/// `errSnack` and the chat model switcher name the section that matches the
/// failure and [SettingsPage.focusSection] scrolls there on the first frame.
enum SettingsSection { account, models, voice, automation, appearance, security }

/// Settings, rebuilt from a README into an instrument panel (§4.7).
///
/// State is **stated, not implied**: every credential and connection reports
/// through a [StatusTile] with a dot and words, instead of being inferred from
/// which button happens to be greyed out.
///
/// The constructor stays `const`-compatible with no required arguments, because
/// `settingsIconActions` / `SettingsGearButton` push `const SettingsPage()` and
/// that contract must hold.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.focusSection});

  /// Scrolled into view on the first frame. Null lands at the top.
  final SettingsSection? focusSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with AsyncPageMixin<SettingsPage> {
  /// Friendly labels over the **exact** transcription model values the voice
  /// pipeline sends. Only the labels are presentation; the ids are contract.
  static const List<(String id, String label)> _voiceModels = <(String, String)>[
    ('whisper-1', 'Whisper'),
    ('gpt-4o-mini-transcribe', 'GPT-4o mini transcribe'),
  ];

  static const List<String> _providers = <String>['openai', 'anthropic', 'gemini'];

  /// One anchor per section, so [SettingsPage.focusSection] and the setup
  /// card's tiles can both scroll to the same places.
  final Map<SettingsSection, GlobalKey> _anchors = <SettingsSection, GlobalKey>{
    for (final SettingsSection s in SettingsSection.values) s: GlobalKey(),
  };

  /// Sheet-owned secret fields. They live on the page's `State` — not inside
  /// the sheet closure — so they are disposed exactly once, at page teardown,
  /// and never while a route is still finishing its teardown rebuild.
  final TextEditingController _memKeySheetCtrl = TextEditingController();
  final TextEditingController _voiceKeySheetCtrl = TextEditingController();

  /// True while the OAuth browser round-trip is in flight — the pending tile
  /// that closes the dead-air gap.
  bool _mcpBusy = false;

  /// Reveal state for whichever secret sheet is open (only one ever is).
  bool _reveal = false;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    // `AppScope.of` registers an inherited dependency and must not run during
    // initState, so anything that needs it is deferred to post-frame. Key
    // presence and masks are read in `build` from the same live [AppState]
    // instead — see [_maskOf].
    postFrame(() => _scrollTo(widget.focusSection));
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _memKeySheetCtrl.dispose();
    _voiceKeySheetCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

  /// The masked tail of a stored secret, or null when nothing is stored.
  ///
  /// Presence **and** mask are derived from live [AppState] on every build,
  /// never snapshotted into widget state: Settings is reachable from the
  /// hydration gate, so a page built before `AppState.load()` resolves would
  /// otherwise keep reporting "Not set" for a key that is in fact in the vault
  /// — and the sheet's only delete affordance would never render. `AppScope`
  /// is an `InheritedNotifier`, so hydration and every key write rebuild this
  /// page and the tiles correct themselves on the next frame.
  ///
  /// Only the last three characters ever reach the tree ([memMaskedSecret]);
  /// the full value is never held in widget state and never rendered.
  static String? _maskOf(String? secret) =>
      (secret == null || secret.isEmpty) ? null : memMaskedSecret(secret);

  void _scrollTo(SettingsSection? section) {
    if (section == null) return;
    final BuildContext? anchor = _anchors[section]?.currentContext;
    if (anchor == null) return;
    unawaited(
      Scrollable.ensureVisible(
        anchor,
        alignment: 0,
        duration: MemMotion.standard,
        curve: MemMotion.emphasized,
      ),
    );
  }

  void _resetReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _reveal = false;
  }

  /// A revealed secret re-obscures itself after 10 s. Shoulder-surf safety is
  /// not something the user should have to remember to switch back on.
  void _toggleReveal(EditorSheetState state) {
    _revealTimer?.cancel();
    _reveal = !_reveal;
    if (_reveal) {
      _revealTimer = Timer(MemMotion.revealTimeout, () {
        _reveal = false;
        state.refresh();
      });
    }
    state.refresh();
  }

  /// The profile the app would use right now: the active one, or the first as
  /// the same fallback Chat applies on an id miss.
  ChatModelProfile? _activeProfile(AppState app) {
    if (app.chatModels.isEmpty) return null;
    for (final ChatModelProfile m in app.chatModels) {
      if (m.id == app.activeModelId) return m;
    }
    return app.chatModels.first;
  }

  // ------------------------------------------------------------- MCP OAuth

  Future<void> _connectMcp(AppState app) async {
    final ScaffoldMessengerState messenger = messengerOf();
    setStateIfMounted(() => _mcpBusy = true);
    try {
      await app.connectMcp();
      if (!mounted) return;
      memSnack(messenger, 'Mem MCP connected.');
    } on FlutterAppAuthUserCancelledException {
      if (!mounted) return;
      memSnack(messenger, 'Sign-in cancelled.');
    } on PlatformException catch (e) {
      if (!mounted) return;
      memSnack(messenger, 'OAuth error: ${e.message}');
    } catch (e) {
      // The OAuth error taxonomy is a hard contract (CONSTRAINTS.md): the
      // generic branch reports `toString`. It is the one place in the app a
      // raw exception string is deliberately surfaced.
      if (!mounted) return;
      memSnack(messenger, e.toString());
    } finally {
      setStateIfMounted(() => _mcpBusy = false);
    }
  }

  Future<void> _disconnectMcp(AppState app) async {
    final bool ok = await confirmDestructive(
      context,
      title: 'Disconnect Mem MCP?',
      consequence:
          'The stored access token is deleted. Chat tools fall back to your '
          'Mem API key.',
      actionLabel: 'Disconnect',
    );
    if (!ok || !mounted) return;
    final ScaffoldMessengerState messenger = messengerOf();
    await app.disconnectMcp();
    if (!mounted) return;
    memSnack(messenger, 'Mem MCP disconnected.');
  }

  // --------------------------------------------------------- secret editors

  /// The app's worst footgun, defused.
  ///
  /// The field starts **blank** — a stored secret is never prefilled as
  /// revealable plaintext — and Save is gated on the field being dirty, so an
  /// untouched sheet can never wipe a key. The underlying trim + empty→null
  /// delete semantics are unchanged; they are simply no longer reachable by
  /// accident, only through the explicit error-styled Remove action.
  Future<void> _showSecretSheet({
    required String title,
    required TextEditingController controller,
    required String fieldLabel,
    required String helperText,
    required bool hasStoredKey,
    required Future<void> Function(String? trimmedOrNull) write,
    required String savedMessage,
    required String removedMessage,
    required String removeTitle,
    required String removeConsequence,
  }) async {
    // Captured from the page, before anything async.
    final ScaffoldMessengerState messenger = messengerOf();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    controller.clear();
    _resetReveal();
    EditorSheetState? sheet;

    await showEditorSheet<void>(
      context: context,
      title: title,
      saveLabel: 'Save key',
      footerNote: const Text('Stored in your device keystore.'),
      isValid: () => controller.text.trim().isNotEmpty,
      fieldsBuilder: (BuildContext sheetContext, EditorSheetState state) {
        sheet = state;
        return <Widget>[
          TextField(
            controller: controller,
            obscureText: !_reveal,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (String _) => state.refresh(),
            decoration: InputDecoration(
              labelText: fieldLabel,
              hintText: 'Enter a new key to replace',
              helperText: helperText,
              suffixIcon: IconButton(
                tooltip: _reveal ? 'Hide key' : 'Show key',
                icon: Icon(
                  _reveal
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => _toggleReveal(state),
              ),
            ),
          ),
          if (hasStoredKey) ...<Widget>[
            const SizedBox(height: MemSpace.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: state.saving
                    ? null
                    : () async {
                        final bool ok = await confirmDestructive(
                          sheetContext,
                          title: removeTitle,
                          consequence: removeConsequence,
                          actionLabel: 'Remove key',
                        );
                        if (!ok || !sheetContext.mounted) return;
                        // The trim + empty -> null delete path, reached the
                        // only way it can now be reached: on purpose.
                        await write(null);
                        if (!sheetContext.mounted) return;
                        state.close();
                        // No local mask to refresh: `write` notifies AppState
                        // and the page rebuilds off the live value.
                        memSnack(messenger, removedMessage);
                      },
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  minimumSize: const Size(64, MemSize.touchTarget),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove key'),
              ),
            ),
          ],
        ];
      },
      onSave: (BuildContext sheetContext) async {
        final String value = controller.text.trim();
        // Unreachable — isValid gates it — but the empty->null contract is
        // spelled out here rather than assumed.
        if (value.isEmpty) return;
        await write(value);
        if (!sheetContext.mounted) return;
        sheet?.close();
        memSnack(messenger, savedMessage);
      },
    );

    _resetReveal();
  }

  Future<void> _showMemKeySheet(AppState app) {
    return _showSecretSheet(
      title: 'Mem API key',
      controller: _memKeySheetCtrl,
      fieldLabel: 'Mem API key',
      helperText: 'From Mem Settings → API.',
      hasStoredKey: app.hasMemRest,
      write: app.setMemApiKey,
      savedMessage: 'Mem API key saved.',
      removedMessage: 'Mem API key removed.',
      removeTitle: 'Remove key?',
      removeConsequence:
          'Notes, capture, and Mem chat tools stop working until you add a '
          'key again.',
    );
  }

  Future<void> _showVoiceKeySheet(AppState app) {
    return _showSecretSheet(
      title: 'OpenAI key for voice',
      controller: _voiceKeySheetCtrl,
      fieldLabel: 'OpenAI API key',
      helperText: 'Uses your chat model key when empty.',
      // Live, exactly as the Mem sheet reads `app.hasMemRest`: a snapshot
      // would hide the Remove action for a key stored before hydration.
      hasStoredKey: app.voiceOpenAiApiKey?.isNotEmpty ?? false,
      write: app.setVoiceOpenAiApiKey,
      savedMessage: 'Voice key saved.',
      removedMessage: 'Voice key removed.',
      removeTitle: 'Remove key?',
      removeConsequence:
          'Voice transcription falls back to your OpenAI chat model key.',
    );
  }

  // ----------------------------------------------------------- model editor

  Future<void> _showChatModelEditor({ChatModelProfile? existing}) async {
    final bool isEdit = existing != null;

    // The save-order contract: messenger + AppScope come from the **page**
    // context, before anything async, and are what the sheet writes through
    // after it has popped itself.
    final ScaffoldMessengerState messenger = messengerOf();
    final AppState pageApp = AppScope.of(context);

    // Intentionally NOT disposed. The route can still be finishing teardown
    // animations after this future completes and briefly rebuild the
    // TextField; disposing here crashes on that rebuild.
    final TextEditingController keyCtrl = TextEditingController();

    String provider = existing?.provider ?? 'openai';
    List<CuratedChatModel> catalog = curatedModelsForProvider(provider);
    CuratedChatModel? selected = existing == null
        ? (catalog.isEmpty ? null : catalog.first)
        : (curatedModelByApiId(provider, existing.model) ??
              (catalog.isEmpty ? null : catalog.first));

    // Catalog drift: the stored api model id is no longer in the curated list,
    // so a replacement is pre-selected and the user is told why.
    final bool drifted =
        existing != null &&
        curatedModelByApiId(existing.provider, existing.model) == null;

    _resetReveal();
    EditorSheetState? sheet;

    await showEditorSheet<void>(
      context: context,
      title: isEdit ? 'Edit chat model' : 'Add chat model',
      saveLabel: isEdit ? 'Save model' : 'Add model',
      footerNote: const Text('Stored in your device keystore.'),
      // New profiles REQUIRE a key; on edit a blank key keeps the vault entry.
      isValid: () =>
          selected != null && (isEdit || keyCtrl.text.trim().isNotEmpty),
      fieldsBuilder: (BuildContext sheetContext, EditorSheetState state) {
        sheet = state;
        final ThemeData theme = Theme.of(sheetContext);
        final ColorScheme scheme = theme.colorScheme;
        final TextTheme text = theme.textTheme;

        return <Widget>[
          SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              for (final String p in _providers)
                ButtonSegment<String>(
                  value: p,
                  label: Text(chatProviderBrand(p)),
                ),
            ],
            selected: <String>{provider},
            selectedIcon: const Icon(Icons.check, size: MemSize.selectionCheck),
            onSelectionChanged: (Set<String> next) {
              // Provider change resets the catalog and the selection.
              provider = next.first;
              catalog = curatedModelsForProvider(provider);
              selected = catalog.isEmpty ? null : catalog.first;
              state.refresh();
            },
          ),
          if (drifted) ...<Widget>[
            const SizedBox(height: MemSpace.x3),
            _DriftWarning(storedModel: existing.model),
          ],
          const SizedBox(height: MemSpace.x4),
          if (catalog.isEmpty)
            Text(
              'No models defined for this provider.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            DropdownButtonFormField<CuratedChatModel>(
              // The key is load-bearing: `initialValue` seeds the FormField
              // once, so a provider change has to build a fresh field for the
              // reset to land.
              key: ValueKey<String>(provider),
              initialValue: selected,
              isExpanded: true,
              // `DropdownButton` defaults to elevation 8 and 2 dp corners, and
              // no theme suppresses it (`dropdownMenuTheme` only reaches the M3
              // `DropdownMenu`). Left unset the menu would paint the app's only
              // BoxShadow — on top of an explicitly elevation-0 sheet (§0.1).
              elevation: 0,
              borderRadius: MemRadius.sectionAll,
              decoration: const InputDecoration(labelText: 'Model'),
              items: <DropdownMenuItem<CuratedChatModel>>[
                for (final CuratedChatModel m in catalog)
                  DropdownMenuItem<CuratedChatModel>(
                    value: m,
                    child: Text(m.catalogLabel, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (CuratedChatModel? m) {
                selected = m;
                state.refresh();
              },
            ),
          if (selected != null) ...<Widget>[
            const SizedBox(height: MemSpace.x2),
            Text(
              'API model id · ${selected!.apiModelId}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: MemSpace.x4),
          TextField(
            controller: keyCtrl,
            obscureText: !_reveal,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (String _) => state.refresh(),
            decoration: InputDecoration(
              labelText: 'Provider API key',
              helperText: isEdit
                  ? 'Leave blank to keep the stored key.'
                  : 'Required for a new model.',
              suffixIcon: IconButton(
                tooltip: _reveal ? 'Hide key' : 'Show key',
                icon: Icon(
                  _reveal
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => _toggleReveal(state),
              ),
            ),
          ),
        ];
      },
      onSave: (BuildContext sheetContext) async {
        final CuratedChatModel? sel = selected;
        if (sel == null) return;
        final String keyText = keyCtrl.text.trim();
        if (!isEdit && keyText.isEmpty) return;

        // The profile id keys BOTH the ChatModelProfile and its vault entry:
        // an existing id is preserved, a new one is a Uuid v4.
        final String profileId = existing?.id ?? const Uuid().v4();
        final ChatModelProfile p = ChatModelProfile(
          id: profileId,
          // Always recomputed, never user-editable.
          displayName: composeChatDisplayName(provider, sel),
          provider: provider,
          model: sel.apiModelId,
        );
        final List<ChatModelProfile> next = isEdit
            ? pageApp.chatModels
                  .map((ChatModelProfile m) => m.id == profileId ? p : m)
                  .toList()
            : <ChatModelProfile>[...pageApp.chatModels, p];
        // add -> the new profile becomes active; edit -> keep the current one.
        final String activeAfter = isEdit
            ? (pageApp.activeModelId ?? profileId)
            : profileId;

        if (!sheetContext.mounted) return;
        sheet?.close();
        if (keyText.isNotEmpty) {
          await pageApp.vault.setLlmApiKey(profileId, keyText);
        }
        await pageApp.saveChatModels(next, activeId: activeAfter);
        memSnack(messenger, isEdit ? 'Chat model saved.' : 'Chat model added.');
      },
    );

    _resetReveal();
  }

  Future<void> _confirmRemoveModel(ChatModelProfile m) async {
    final bool ok = await confirmDestructive(
      context,
      title: 'Remove chat model?',
      consequence:
          '“${m.displayName}” and its stored key are removed from this device.',
      actionLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    final ScaffoldMessengerState messenger = messengerOf();
    final AppState app = AppScope.of(context);
    final List<ChatModelProfile> next = app.chatModels
        .where((ChatModelProfile x) => x.id != m.id)
        .toList(growable: false);
    // The vault key is deleted BEFORE saveChatModels.
    await app.vault.setLlmApiKey(m.id, null);
    // remove-active -> promote the first; remove-last -> null.
    final String? newActive = next.isEmpty
        ? null
        : (app.activeModelId == m.id ? next.first.id : app.activeModelId);
    await app.saveChatModels(next, activeId: newActive);
    if (!mounted) return;
    memSnack(messenger, 'Chat model removed.');
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          // A settings page is a short, fixed list whose section anchors must
          // all be laid out for `Scrollable.ensureVisible` to reach them, so
          // it is deliberately not virtualised.
          padding: const EdgeInsets.only(bottom: MemSpace.sectionGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: MemSpace.x4),
              _buildSetupCard(app),
              _buildAccountSection(app),
              ..._buildModelsSection(app),
              ..._buildVoiceSection(app),
              _buildAutomationSection(app),
              ..._buildAppearanceSection(app),
              _buildSecuritySection(),
            ],
          ),
        ),
      ),
    );
  }

  /// The first-run orientation surface. All three tiles read from the same
  /// inputs as `AppState.setupComplete`, which is also what drives the gear
  /// badge — so the badge and this card can never disagree.
  Widget _buildSetupCard(AppState app) {
    final bool hasKey = app.hasMemRest;
    final bool hasModels = app.chatModels.isNotEmpty;
    final ChatModelProfile? active = _activeProfile(app);
    final String? voiceMask = _maskOf(app.voiceOpenAiApiKey);
    final bool hasVoiceKey = voiceMask != null;
    final int count = app.chatModels.length;

    return AppListSection(
      children: <Widget>[
        StatusTile(
          icon: Icons.cloud_outlined,
          label: 'Mem account',
          level: hasKey ? StatusLevel.ok : StatusLevel.error,
          status: hasKey ? 'Connected' : 'Add your API key',
          onTap: () => _scrollTo(SettingsSection.account),
        ),
        StatusTile(
          icon: active == null
              ? Icons.smart_toy_outlined
              : ProviderBadge.glyphFor(active.provider),
          label: 'Chat models',
          level: hasModels ? StatusLevel.ok : StatusLevel.error,
          status: hasModels
              ? '$count ${count == 1 ? 'model' : 'models'}'
              : 'Add a chat model',
          detail: active == null ? null : '${active.displayName} active',
          onTap: () => _scrollTo(SettingsSection.models),
        ),
        StatusTile(
          icon: Icons.mic_none_outlined,
          label: 'Voice',
          level: hasVoiceKey ? StatusLevel.ok : StatusLevel.neutral,
          status: hasVoiceKey ? 'Key saved · $voiceMask' : 'Using chat key',
          detail: hasVoiceKey
              ? null
              : 'Falls back to your OpenAI chat model key.',
          onTap: () => _scrollTo(SettingsSection.voice),
        ),
      ],
    );
  }

  Widget _buildAccountSection(AppState app) {
    final bool hasKey = app.hasMemRest;
    final String? memMask = _maskOf(app.memApiKey);
    final String keyStatus = memMask == null
        ? 'Not set'
        : 'Key saved · $memMask';

    return AppListSection(
      header: SectionHeader(
        key: _anchors[SettingsSection.account],
        label: 'Account',
        // AppListSection owns the horizontal margin and the 8 dp header gap;
        // this only has to supply the 24 dp gap from the previous section.
        padding: const EdgeInsets.only(top: MemSpace.sectionGap),
      ),
      children: <Widget>[
        StatusTile(
          icon: Icons.key_outlined,
          label: 'Mem API key',
          level: hasKey ? StatusLevel.ok : StatusLevel.error,
          status: keyStatus,
          detail: 'Powers Notes, capture, and Mem chat tools.',
          actionLabel: 'Edit',
          onAction: () => unawaited(_showMemKeySheet(app)),
        ),
        StatusTile(
          icon: Icons.hub_outlined,
          label: 'Mem MCP',
          level: _mcpBusy
              ? StatusLevel.pending
              : (app.mcpConnected ? StatusLevel.ok : StatusLevel.neutral),
          status: _mcpBusy
              ? 'Waiting for browser…'
              : (app.mcpConnected ? 'Connected' : 'Not connected'),
          detail: 'Optional — chat tools prefer your Mem API key.',
          busy: _mcpBusy,
          actionLabel: app.mcpConnected ? 'Disconnect' : 'Connect',
          onAction: app.mcpConnected
              ? () => unawaited(_disconnectMcp(app))
              : () => unawaited(_connectMcp(app)),
        ),
      ],
    );
  }

  List<Widget> _buildModelsSection(AppState app) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;

    final List<Widget> rows = <Widget>[
      for (final ChatModelProfile m in app.chatModels)
        AppRow(
          leading: ProviderBadge(provider: m.provider, showName: false),
          title: Text(m.displayName),
          meta: Text(
            m.model,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          selected: m.id == app.activeModelId,
          // Row tap sets the active model — the RadioListTile is retired.
          onTap: m.id == app.activeModelId
              ? null
              : () => app.setActiveModel(m.id),
          trailing: SizedBox(
            width: MemSize.touchTarget,
            height: MemSize.touchTarget,
            child: PopupMenuButton<String>(
              tooltip: 'Model actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (String v) {
                if (v == 'edit') {
                  unawaited(_showChatModelEditor(existing: m));
                } else if (v == 'remove') {
                  unawaited(_confirmRemoveModel(m));
                }
              },
              itemBuilder: (BuildContext _) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
              ],
            ),
          ),
        ),
    ];

    return <Widget>[
      AppListSection(
        header: SectionHeader(
          key: _anchors[SettingsSection.models],
          label: 'Chat models',
          padding: const EdgeInsets.only(top: MemSpace.sectionGap),
        ),
        children: rows.isEmpty
            ? const <Widget>[
                EmptyState(
                  icon: Icons.smart_toy_outlined,
                  headline: 'No chat models',
                  body: 'Add a provider key to start chatting with your notes.',
                ),
              ]
            : rows,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          MemInsets.pageH,
          MemSpace.x3,
          MemInsets.pageH,
          0,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => unawaited(_showChatModelEditor()),
            child: const Text('Add model'),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildVoiceSection(AppState app) {
    final String? voiceMask = _maskOf(app.voiceOpenAiApiKey);
    final bool hasVoiceKey = voiceMask != null;

    return <Widget>[
      SectionHeader(key: _anchors[SettingsSection.voice], label: 'Voice'),
      Padding(
        padding: MemSpace.pageHorizontal,
        child: DropdownButtonFormField<String>(
          initialValue: app.voiceWhisperModel,
          isExpanded: true,
          // Same shadow ban as the chat-model picker: elevation 0 and the
          // section radius the popup menu theme already uses (§0.1 rule 1).
          elevation: 0,
          borderRadius: MemRadius.sectionAll,
          decoration: const InputDecoration(labelText: 'Transcription model'),
          items: <DropdownMenuItem<String>>[
            for (final (String id, String label) in _voiceModels)
              DropdownMenuItem<String>(value: id, child: Text(label)),
          ],
          onChanged: (String? v) {
            if (v != null) unawaited(app.setVoiceWhisperModel(v));
          },
        ),
      ),
      const SizedBox(height: MemSpace.x3),
      AppListSection(
        children: <Widget>[
          StatusTile(
            icon: Icons.vpn_key_outlined,
            label: 'OpenAI key',
            level: hasVoiceKey ? StatusLevel.ok : StatusLevel.neutral,
            status: hasVoiceKey ? 'Key saved · $voiceMask' : 'Not set',
            detail: 'Uses your chat model key when empty.',
            actionLabel: 'Edit',
            onAction: () => unawaited(_showVoiceKeySheet(app)),
          ),
        ],
      ),
    ];
  }

  Widget _buildAutomationSection(AppState app) {
    final int jobs = app.promptTemplates.length;
    final int pinned = app.pinnedTemplateIds.length;
    final String subtitle = jobs == 0
        ? 'No jobs yet'
        : '$jobs ${jobs == 1 ? 'job' : 'jobs'} · $pinned pinned';

    return AppListSection(
      header: SectionHeader(
        key: _anchors[SettingsSection.automation],
        label: 'Automation',
        padding: const EdgeInsets.only(top: MemSpace.sectionGap),
      ),
      children: <Widget>[
        AppRow(
          leading: const Icon(Icons.bolt_outlined),
          title: const Text('Prompt jobs'),
          subtitle: Text(subtitle),
          subtitleMaxLines: 1,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const PromptJobsPage(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppearanceSection(AppState app) {
    return <Widget>[
      SectionHeader(
        key: _anchors[SettingsSection.appearance],
        label: 'Appearance',
      ),
      Padding(
        padding: MemSpace.pageHorizontal,
        child: SegmentedButton<ThemeMode>(
          segments: const <ButtonSegment<ThemeMode>>[
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              label: Text('System'),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              label: Text('Light'),
            ),
            ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: <ThemeMode>{app.themeMode},
          selectedIcon: const Icon(Icons.check, size: MemSize.selectionCheck),
          onSelectionChanged: (Set<ThemeMode> next) =>
              unawaited(app.setThemeMode(next.first)),
        ),
      ),
    ];
  }

  Widget _buildSecuritySection() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;

    return AppListSection(
      header: SectionHeader(
        key: _anchors[SettingsSection.security],
        label: 'Security',
        padding: const EdgeInsets.only(top: MemSpace.sectionGap),
      ),
      children: <Widget>[
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: MemSpace.x4),
          childrenPadding: const EdgeInsets.fromLTRB(
            MemSpace.x4,
            0,
            MemSpace.x4,
            MemSpace.x4,
          ),
          title: Text(
            'Secrets stay on this device',
            style: text.bodySmall?.copyWith(color: scheme.onSurface),
          ),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Keys are held in the Android Keystore. Nothing leaves the '
                'device except the calls you configure — Mem, OpenAI, '
                'Anthropic, and Google.',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The catalog-drift advisory, in the `warning` register.
///
/// It is rendered in the status-pill grammar — an 8 dp `warning` dot on a
/// `warningContainer` with `onWarningContainer` text — because `warning` may
/// appear only as a dot or as pill text/containers (§2.5), never as loose
/// coloured prose.
class _DriftWarning extends StatelessWidget {
  const _DriftWarning({required this.storedModel});

  final String storedModel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MemSemanticColors sem = memSemanticColorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MemSpace.x3,
        vertical: MemSpace.x2,
      ),
      decoration: BoxDecoration(
        color: sem.warningContainer,
        borderRadius: MemRadius.controlAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: MemSpace.x1),
            child: Container(
              width: MemSize.statusDot,
              height: MemSize.statusDot,
              decoration: BoxDecoration(
                color: sem.warning,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: MemSpace.x2),
          Expanded(
            child: Text(
              '“$storedModel” is no longer in the catalog. A replacement is '
              'selected below.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: sem.onWarningContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
