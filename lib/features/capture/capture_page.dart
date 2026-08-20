import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';
import '../../core/voice/openai_whisper_client.dart';
import '../../theme/mem_metrics.dart';
import '../../theme/mem_semantic_colors.dart';
import '../../ui/ai_glyph.dart';
import '../../ui/app_list_section.dart';
import '../../ui/async_page_mixin.dart';
import '../../ui/chip_strip.dart';
import '../../ui/collection_tag.dart';
import '../../ui/confirm_destructive_dialog.dart';
import '../../ui/error_state.dart';
import '../../ui/feedback.dart';
import '../../ui/inline_spinner.dart';
import '../../ui/section_header.dart';
import '../../ui/sticky_action_bar.dart';
import '../../widgets/settings_launcher.dart';
import 'mic_ring_painter.dart';

/// **Fast capture** lane: Mem-it for unstructured drops, or explicit markdown
/// when the user wants a verbatim note.
///
/// Reordered around **"type first, configure never."** The content field is the
/// hero and comes first; the voice module sits under it; every Whisper knob is
/// behind one collapsed disclosure; and both CTAs live in a
/// [StickyActionBar] that stays above the keyboard *and* the shell's
/// NavigationBar, with a mandatory caption teaching the Mem-it vs
/// Save-as-note difference.
class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with AsyncPageMixin {
  /// How long the "Processing in Mem…" chip may live. There is no completion
  /// callback for `mem-it`, so the chip needs an expiry or it becomes a
  /// permanent artefact: it disappears after this, on the next
  /// `notesListRevision` bump, or on a manual dismiss — whichever is first.
  static const Duration _processingChipExpiry = Duration(seconds: 90);

  final _bodyCtrl = TextEditingController();
  final _instrCtrl = TextEditingController();
  final _whisperPromptCtrl = TextEditingController();
  final _languageCtrl = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  bool _busy = false;

  /// Presentation-only: which of the two CTAs owns the current [_busy] window,
  /// so the spinner appears on the button the user actually pressed.
  bool _busyIsMemIt = false;
  bool _transcribing = false;
  bool _recording = false;
  bool _replaceMode = false;
  bool _autoPunctuate = true;
  _CaptureMicMode _mode = _CaptureMicMode.longform;
  _WhisperLanguageMode _languageMode = _WhisperLanguageMode.autoDetect;
  String? _activeRecordPath;
  Duration _recordingElapsed = Duration.zero;
  double _level = 0;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _elapsedTimer;

  /// True between `onPointerDown` and `onPointerUp` on the hold-to-talk mic.
  /// It is what lets a release that lands *before* the recorder finished
  /// starting still stop the recording — pointer-down triggering makes very
  /// short holds common, and without this the recorder would run forever.
  bool _holdActive = false;

  /// Collections offered by the "Add to collection" strip. Presentation-only
  /// garnish: a failure to load them must never block a capture.
  List<MemCollectionItem> _collections = const <MemCollectionItem>[];
  final Set<String> _selectedCollectionIds = <String>{};
  bool _collectionsRequested = false;

  /// The transcription disclosure. [_optionsEpoch] is part of the
  /// `ExpansionTile`'s key: bumping it rebuilds the tile collapsed while the
  /// controllers — and therefore every value inside it — survive untouched.
  bool _optionsExpanded = false;
  int _optionsEpoch = 0;

  /// The `mem-it` request currently in flight on the server, or null.
  String? _processingRequestId;
  Timer? _processingTimer;

  /// Drives the fade half of the announced, reversible clear.
  bool _clearing = false;
  Timer? _clearTimer;

  AppState? _app;

  MemApiClient? _client(BuildContext context) {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppState app = AppScope.of(context);
    if (!identical(app, _app)) {
      // Attach-on-instance-change / detach-old / detach-in-dispose, the same
      // listener discipline NotesPage uses on this notifier.
      _app?.notesListRevision.removeListener(_onNotesListRevision);
      _app?.shellTabRequest.removeListener(_onShellTabRequest);
      _app = app;
      app.notesListRevision.addListener(_onNotesListRevision);
      app.shellTabRequest.addListener(_onShellTabRequest);
    }
    _maybeLoadCollections();
  }

  @override
  void dispose() {
    _app?.notesListRevision.removeListener(_onNotesListRevision);
    _app?.shellTabRequest.removeListener(_onShellTabRequest);
    _processingTimer?.cancel();
    _clearTimer?.cancel();
    _elapsedTimer?.cancel();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _bodyCtrl.dispose();
    _instrCtrl.dispose();
    _whisperPromptCtrl.dispose();
    _languageCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Transcription disclosure (§5.7)
  // ---------------------------------------------------------------------------

  /// The disclosure must not remember that it was open: advanced config is
  /// supposed to stop taxing every visit. The *values* inside it persist —
  /// only the panel closes.
  void _collapseOptions() {
    if (!_optionsExpanded) return;
    setStateIfMounted(() {
      _optionsExpanded = false;
      _optionsEpoch++;
    });
  }

  void _onShellTabRequest() {
    // Tab index 1 is Capture. This covers every entry the shell announces
    // (deep links, `goToShellTab`); see the note in the PR about the shell
    // exposing its active tab so a plain NavigationBar tap does the same.
    if (_app?.shellTabRequest.value == 1) _collapseOptions();
  }

  // ---------------------------------------------------------------------------
  // Processing chip (#13) — visible background work, with a mandatory expiry.
  // ---------------------------------------------------------------------------

  void _onNotesListRevision() {
    // The list refreshed, so whatever Mem was chewing on has landed (or another
    // capture superseded it). Either way the chip has said all it can say.
    if (_processingRequestId == null) return;
    _dismissProcessing();
  }

  void _startProcessing(String requestId) {
    _processingTimer?.cancel();
    setState(() => _processingRequestId = requestId);
    _processingTimer = Timer(_processingChipExpiry, () {
      if (!mounted) return;
      setState(() {
        _processingRequestId = null;
        _processingTimer = null;
      });
    });
  }

  void _dismissProcessing() {
    _processingTimer?.cancel();
    _processingTimer = null;
    setStateIfMounted(() => _processingRequestId = null);
  }

  // ---------------------------------------------------------------------------
  // Collections
  // ---------------------------------------------------------------------------

  void _maybeLoadCollections() {
    if (_collectionsRequested) return;
    final AppState? app = _app;
    if (app == null || !app.isHydrated || !app.hasMemRest) return;
    _collectionsRequested = true;
    postFrame(() => unawaited(_loadCollections()));
  }

  Future<void> _loadCollections() async {
    final c = _client(context);
    if (c == null) {
      _collectionsRequested = false;
      return;
    }
    try {
      final items = await c.listCollections(limit: 50);
      if (!mounted) return;
      setState(() {
        _collections = items;
        // A selection whose collection vanished server-side is dropped, the
        // same auto-clear NotesPage applies to a stale filter.
        final ids = items.map((e) => e.id).toSet();
        _selectedCollectionIds.removeWhere((id) => !ids.contains(id));
      });
    } catch (_) {
      // Swallowed on purpose: the picker is optional on this screen and a
      // collections outage must not stop the user capturing. Allow a retry the
      // next time dependencies change.
      _collectionsRequested = false;
    }
  }

  /// `mem-it` has no collection parameter, so on the AI path the selected
  /// titles ride along in `context` instead. Null when nothing is selected, so
  /// the request body is byte-identical to the old one in the common case.
  String? _collectionContext() {
    if (_selectedCollectionIds.isEmpty) return null;
    final titles = <String>[];
    for (final c in _collections) {
      if (_selectedCollectionIds.contains(c.id)) titles.add(c.title);
    }
    if (titles.isEmpty) return null;
    return 'Suggested collections: ${titles.join(', ')}';
  }

  // ---------------------------------------------------------------------------
  // Draft snapshot / restore — Undo has to be real (§5.2).
  // ---------------------------------------------------------------------------

  _CaptureDraft _snapshotDraft() {
    return _CaptureDraft(
      body: _bodyCtrl.text,
      guidance: _instrCtrl.text,
      collectionIds: _selectedCollectionIds.toList(),
      replaceMode: _replaceMode,
      autoPunctuate: _autoPunctuate,
      languageMode: _languageMode,
      languageHint: _languageCtrl.text,
    );
  }

  void _restoreDraft(_CaptureDraft draft) {
    if (!mounted) return;
    _clearTimer?.cancel();
    _clearTimer = null;
    setState(() {
      _bodyCtrl.text = draft.body;
      _instrCtrl.text = draft.guidance;
      _selectedCollectionIds
        ..clear()
        ..addAll(draft.collectionIds);
      _replaceMode = draft.replaceMode;
      _autoPunctuate = draft.autoPunctuate;
      _languageMode = draft.languageMode;
      _languageCtrl.text = draft.languageHint;
      _clearing = false;
    });
  }

  /// The clear is announced and reversible: the content fades out and back in
  /// so it is visibly gone, and the snackbar's Undo restores the **complete**
  /// draft — body, guidance, collection ids, and the transcription state.
  void _announceClear(
    ScaffoldMessengerState messenger,
    _CaptureDraft draft,
    String message,
  ) {
    final AppState app = _app ?? AppScope.of(context);
    _collapseOptions();
    setState(() => _clearing = true);
    _clearTimer?.cancel();
    _clearTimer = Timer(MemMotion.micro, () {
      setStateIfMounted(() => _clearing = false);
    });
    undoSnack(
      messenger,
      message,
      onUndo: () async => _restoreDraft(draft),
      secondaryLabel: 'View notes',
      onSecondary: () => app.goToShellTab(0),
    );
  }

  // ---------------------------------------------------------------------------
  // Saves
  // ---------------------------------------------------------------------------

  Future<void> _memIt() async {
    final messenger = ScaffoldMessenger.of(context);
    final app = AppScope.of(context);
    final c = _client(context);
    if (c == null) {
      memSnack(messenger, 'Add your Mem API key in Settings first.');
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _busyIsMemIt = true;
    });
    try {
      // RAW, untrimmed body — the trim above is only the emptiness guard.
      final requestId = await c.memIt(
        input: _bodyCtrl.text,
        instructions: _instrCtrl.text.trim().isEmpty
            ? null
            : _instrCtrl.text.trim(),
        context: _collectionContext(),
      );
      if (!mounted) return;
      final draft = _snapshotDraft();
      _bodyCtrl.clear();
      _instrCtrl.clear();
      _selectedCollectionIds.clear();
      app.bumpNotesListRevision();
      // Started *after* the bump so this capture's own bump cannot dismiss the
      // chip it just created; the next bump is the one that clears it.
      _startProcessing(requestId);
      _announceClear(messenger, draft, 'Captured — Mem is processing it.');
    } catch (e) {
      if (mounted) errSnack(messenger, e, context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRaw() async {
    final messenger = ScaffoldMessenger.of(context);
    final app = AppScope.of(context);
    final c = _client(context);
    if (c == null) {
      memSnack(messenger, 'Add your Mem API key in Settings first.');
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _busyIsMemIt = false;
    });
    try {
      final ids = _selectedCollectionIds.toList();
      await c.createNote(
        markdown: _bodyCtrl.text,
        collectionIds: ids.isEmpty ? null : ids,
      );
      if (!mounted) return;
      final draft = _snapshotDraft();
      // Guidance is deliberately NOT cleared here — it is cleared only on a
      // successful mem-it.
      _bodyCtrl.clear();
      _selectedCollectionIds.clear();
      app.bumpNotesListRevision();
      _announceClear(messenger, draft, 'Note saved.');
    } catch (e) {
      if (mounted) errSnack(messenger, e, context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Voice
  // ---------------------------------------------------------------------------

  Future<String?> _resolveOpenAiKey() async {
    final app = AppScope.of(context);
    if (app.voiceOpenAiApiKey != null && app.voiceOpenAiApiKey!.isNotEmpty) {
      return app.voiceOpenAiApiKey;
    }
    String? profileId;
    if (app.activeModelId != null) {
      for (final m in app.chatModels) {
        if (m.id == app.activeModelId && m.provider == 'openai') {
          profileId = m.id;
          break;
        }
      }
    }
    if (profileId == null) {
      for (final m in app.chatModels) {
        if (m.provider == 'openai') {
          profileId = m.id;
          break;
        }
      }
    }
    if (profileId == null) return null;
    return app.vault.getLlmApiKey(profileId);
  }

  Future<void> _appendTranscriptionFromFile(String filePath) async {
    final messenger = ScaffoldMessenger.of(context);
    final app = AppScope.of(context);
    final voiceModel = app.voiceWhisperModel;
    final key = await _resolveOpenAiKey();
    if (key == null || key.isEmpty) {
      if (mounted) {
        memSnack(
          messenger,
          'Add an OpenAI chat model + API key in Settings first.',
        );
      }
      return;
    }
    setState(() => _transcribing = true);
    try {
      final text = await OpenAiWhisperClient(apiKey: key).transcribeFile(
        File(filePath),
        prompt: _whisperPromptCtrl.text.trim().isEmpty
            ? null
            : _whisperPromptCtrl.text.trim(),
        language: _languageMode == _WhisperLanguageMode.autoDetect
            ? null
            : (_languageCtrl.text.trim().isEmpty
                  ? null
                  : _languageCtrl.text.trim()),
        model: voiceModel,
      );
      if (!mounted) return;
      final normalized = _autoPunctuate ? _autoPunctuateText(text) : text;
      if (normalized.isEmpty) {
        memSnack(messenger, 'No speech detected.');
        return;
      }
      if (_replaceMode || _bodyCtrl.text.trim().isEmpty) {
        _bodyCtrl.text = normalized;
      } else {
        final existing = _bodyCtrl.text.trimRight();
        _bodyCtrl.text = '$existing\n\n$normalized';
      }
    } catch (e) {
      if (mounted) errSnack(messenger, e, context: context);
    } finally {
      if (mounted) setState(() => _transcribing = false);
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _startRecording() async {
    if (_recording || _transcribing || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        memSnack(messenger, 'Microphone permission denied.');
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    setState(() {
      _recording = true;
      _activeRecordPath = path;
      _recordingElapsed = Duration.zero;
      _level = 0;
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recording) return;
      setState(() => _recordingElapsed += const Duration(milliseconds: 200));
    });
    await _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
          if (!mounted || !_recording) return;
          final db = amp.current;
          final normalized = ((db + 60) / 60).clamp(0.0, 1.0);
          setState(() => _level = normalized);
        });
  }

  Future<void> _stopRecordingAndTranscribe() async {
    if (!_recording) return;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final path = await _recorder.stop();
    setState(() => _recording = false);
    final p = path ?? _activeRecordPath;
    _activeRecordPath = null;
    if (p == null) return;
    await _appendTranscriptionFromFile(p);
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _recorder.cancel();
    setState(() {
      _recording = false;
      _activeRecordPath = null;
      _recordingElapsed = Duration.zero;
      _level = 0;
    });
  }

  Future<void> _toggleLongform() async {
    if (_recording) {
      await _stopRecordingAndTranscribe();
    } else {
      await _startRecording();
    }
  }

  /// Hold-to-talk **starts on pointer-down**. The old ~500 ms long-press
  /// timeout swallowed the first half-second of every utterance (`#8`); the
  /// pressed-state cue below is only honest because the recorder is already
  /// coming up when the finger lands.
  Future<void> _onHoldStart() async {
    if (_holdActive) return;
    _holdActive = true;
    await HapticFeedback.mediumImpact();
    await _startRecording();
    if (!_holdActive) {
      // Released before the recorder came up. Stop it now, or a tap-length
      // press would leave the mic running with nothing to end it.
      await _stopRecordingAndTranscribe();
    }
  }

  Future<void> _onHoldEnd() async {
    if (!_holdActive) return;
    _holdActive = false;
    await HapticFeedback.lightImpact();
    await _stopRecordingAndTranscribe();
  }

  Future<void> _changeMode(_CaptureMicMode next) async {
    if (next == _mode) return;
    if (_recording) {
      // The contract still cancels the recording on a mode switch — it just
      // asks first now, because discarded audio is unrecoverable (`#2`).
      final ok = await confirmDestructive(
        context,
        title: 'Discard recording?',
        consequence: 'The audio recorded so far will be discarded, not saved.',
        actionLabel: 'Discard',
      );
      if (!ok || !mounted) return;
      _holdActive = false;
      await _cancelRecording();
      if (!mounted) return;
    }
    setState(() => _mode = next);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool micBlocked = _busy || _transcribing;
    final bool savesBlocked = _busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture'),
        actions: settingsIconActions(context),
      ),
      body: Column(
        children: <Widget>[
          // The scroll view is the flexible child, so opening the keyboard
          // shrinks the content instead of pushing the CTAs off-screen.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(
                top: MemSpace.x4,
                bottom: MemSpace.sectionGap,
              ),
              children: <Widget>[
                if (_processingRequestId != null) ...<Widget>[
                  Padding(
                    padding: MemSpace.pageHorizontal,
                    child: _ProcessingChip(onDismiss: _dismissProcessing),
                  ),
                  const SizedBox(height: MemSpace.x4),
                ],
                _fade(_buildContentField(context)),
                const SizedBox(height: MemSpace.sectionGap),
                _buildVoiceModule(context, micBlocked: micBlocked),
                ..._buildCollectionPicker(context),
                const SizedBox(height: MemSpace.sectionGap),
                _fade(_buildGuidanceField(context)),
                const SizedBox(height: MemSpace.sectionGap),
                _buildTranscriptionOptions(context),
              ],
            ),
          ),
          StickyActionBar(
            caption:
                'Mem it lets AI title and file this note. '
                'Save as note keeps it verbatim.',
            secondary: OutlinedButton(
              onPressed: savesBlocked ? null : () => unawaited(_saveRaw()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (_busy && !_busyIsMemIt) ...<Widget>[
                    const InlineSpinner(),
                    const SizedBox(width: MemSpace.x2),
                  ],
                  const Flexible(
                    child: Text(
                      'Save as note',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            primary: FilledButton(
              onPressed: savesBlocked ? null : () => unawaited(_memIt()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // The violet marks the one CTA that hands the note to a
                  // model — the §2.10 provenance system, taught right here.
                  if (_busy && _busyIsMemIt)
                    const InlineSpinner()
                  else
                    const AiGlyph(size: 16),
                  const SizedBox(width: MemSpace.x2),
                  const Flexible(
                    child: Text(
                      'Mem it',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The announced half of the announced-and-reversible clear.
  Widget _fade(Widget child) {
    return AnimatedOpacity(
      duration: MemMotion.micro,
      curve: MemMotion.emphasized,
      opacity: _clearing ? 0 : 1,
      child: child,
    );
  }

  Widget _buildContentField(BuildContext context) {
    return AppListSection(
      children: <Widget>[
        Padding(
          padding: MemSpace.sectionPadding,
          child: TextField(
            controller: _bodyCtrl,
            minLines: 6,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.bodyLarge,
            // The section already draws the boundary; the field inside it is
            // borderless. (The global InputDecorationTheme still owns every
            // OutlineInputBorder in the app — none is declared here.)
            decoration: const InputDecoration(
              filled: false,
              isDense: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintMaxLines: 2,
              hintText:
                  "What's on your mind? The first line becomes the title.",
            ),
            scrollPadding: const EdgeInsets.only(
              bottom: MemInsets.editorScrollPad,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceModule(BuildContext context, {required bool micBlocked}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MemSemanticColors semantics = memSemanticColorsOf(context);

    final String hint = _mode == _CaptureMicMode.longform
        ? 'Tap the mic to start, tap again to stop and transcribe.'
        : 'Hold the mic to talk. Recording starts the moment you touch it.';

    final String status = _transcribing
        ? 'Transcribing…'
        : _formatElapsed(_recordingElapsed);
    final Color statusColor = _recording
        ? semantics.recording
        : scheme.onSurfaceVariant;

    return AppListSection(
      children: <Widget>[
        Padding(
          padding: MemSpace.sectionPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _buildMicButton(context, micBlocked: micBlocked),
                  const SizedBox(height: MemSpace.x2),
                  SizedBox(
                    width: MemSize.micButton,
                    child: Text(
                      status,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Tabular figures come from the theme, so the timer never
                      // shifts the layout as it ticks.
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: MemSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Scrollable so the two labels can never clip, at any text
                    // scale, in the width left beside a 96 dp mic.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<_CaptureMicMode>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: MemSpace.x2,
                          ),
                        ),
                        segments: const <ButtonSegment<_CaptureMicMode>>[
                          ButtonSegment<_CaptureMicMode>(
                            value: _CaptureMicMode.longform,
                            label: Text('Longform'),
                          ),
                          ButtonSegment<_CaptureMicMode>(
                            value: _CaptureMicMode.pushToTalk,
                            label: Text('Hold to talk'),
                          ),
                        ],
                        selected: <_CaptureMicMode>{_mode},
                        onSelectionChanged: (Set<_CaptureMicMode> set) =>
                            unawaited(_changeMode(set.first)),
                      ),
                    ),
                    const SizedBox(height: MemSpace.x2),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMicButton(BuildContext context, {required bool micBlocked}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final MemSemanticColors semantics = memSemanticColorsOf(context);

    final MicRingState ringState = _transcribing
        ? MicRingState.transcribing
        : (_recording ? MicRingState.recording : MicRingState.idle);

    final Color fill = _recording
        ? semantics.recordingContainer
        : scheme.surfaceContainer;
    final Color glyphColor = _recording
        ? semantics.onRecordingContainer
        : (micBlocked ? scheme.onSurfaceVariant : scheme.primary);
    final IconData glyph = _recording
        ? (_mode == _CaptureMicMode.longform
              ? Icons.stop_rounded
              : Icons.graphic_eq_rounded)
        : Icons.mic_rounded;

    final Widget face = AnimatedContainer(
      duration: MemMotion.micro,
      curve: MemMotion.emphasized,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(glyph, size: 34, color: glyphColor),
    );

    final Widget ring = MicRing(
      state: ringState,
      level: _level,
      child: face,
    );

    if (_mode == _CaptureMicMode.longform) {
      return Semantics(
        button: true,
        label: _recording ? 'Stop recording' : 'Start longform recording',
        child: SizedBox.square(
          dimension: MemSize.micButton,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              overlayColor: memPressOverlay(scheme),
              onTap: micBlocked ? null : () => unawaited(_toggleLongform()),
              child: ring,
            ),
          ),
        ),
      );
    }

    // Hold to talk: a raw Listener, so the recorder starts on the DOWN event
    // rather than after a long-press timeout, and so a stray drag cannot hand
    // the gesture to the surrounding scroller mid-utterance.
    return Semantics(
      button: true,
      label: 'Hold to talk',
      // A screen reader cannot hold a button down, so the semantic action is
      // the same start/stop toggle the longform mode uses.
      onTap: micBlocked ? null : () => unawaited(_toggleLongform()),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: micBlocked
            ? null
            : (PointerDownEvent _) => unawaited(_onHoldStart()),
        onPointerUp: (PointerUpEvent _) => unawaited(_onHoldEnd()),
        onPointerCancel: (PointerCancelEvent _) => unawaited(_onHoldEnd()),
        child: SizedBox.square(dimension: MemSize.micButton, child: ring),
      ),
    );
  }

  List<Widget> _buildCollectionPicker(BuildContext context) {
    final AppState? app = _app;
    if (app == null || !app.hasMemRest || _collections.isEmpty) {
      return const <Widget>[];
    }
    final ThemeData theme = Theme.of(context);
    return <Widget>[
      const SizedBox(height: MemSpace.sectionGap),
      const SectionHeader(
        label: 'Add to collection',
        uppercase: false,
        padding: EdgeInsets.fromLTRB(
          MemInsets.pageH,
          0,
          MemInsets.pageH,
          MemSpace.headerGap,
        ),
      ),
      ChipStrip(
        children: <Widget>[
          for (final MemCollectionItem c in _collections)
            CollectionTag(
              collectionId: c.id,
              title: c.title,
              variant: CollectionTagVariant.chip,
              selected: _selectedCollectionIds.contains(c.id),
              onTap: () => setState(() {
                if (!_selectedCollectionIds.remove(c.id)) {
                  _selectedCollectionIds.add(c.id);
                }
              }),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          MemInsets.pageH,
          MemSpace.x1,
          MemInsets.pageH,
          0,
        ),
        child: Text(
          'Mem files AI captures automatically.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
  }

  Widget _buildGuidanceField(BuildContext context) {
    return AppListSection(
      header: const SectionHeader(
        label: 'Guidance for Mem (optional)',
        uppercase: false,
        padding: EdgeInsets.zero,
      ),
      children: <Widget>[
        Padding(
          padding: MemSpace.sectionPadding,
          child: TextField(
            controller: _instrCtrl,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              filled: false,
              isDense: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintMaxLines: 2,
              hintText: 'e.g. Keep the action items, drop the small talk.',
            ),
            scrollPadding: const EdgeInsets.only(
              bottom: MemInsets.editorScrollPad,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptionOptions(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool forced = _languageMode == _WhisperLanguageMode.forced;

    return AppListSection(
      showDividers: false,
      children: <Widget>[
        ExpansionTile(
          // Bumping the epoch rebuilds this tile collapsed. The controllers and
          // the mode flags live on the State, so every value inside survives.
          key: ValueKey<int>(_optionsEpoch),
          initiallyExpanded: _optionsExpanded,
          onExpansionChanged: (bool expanded) => _optionsExpanded = expanded,
          title: const Text('Transcription options'),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: MemSpace.sectionPadH,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            MemSpace.sectionPadH,
            0,
            MemSpace.sectionPadH,
            MemSpace.sectionPadV,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SwitchListTile.adaptive(
              value: _replaceMode,
              contentPadding: EdgeInsets.zero,
              title: const Text('Replace note text with transcript'),
              subtitle: const Text(
                'Off: each transcript is appended below what is already there.',
              ),
              onChanged: (bool v) => setState(() => _replaceMode = v),
            ),
            SwitchListTile.adaptive(
              value: _autoPunctuate,
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto punctuation'),
              subtitle: const Text(
                'Capitalises the first word and adds a final full stop.',
              ),
              onChanged: (bool v) => setState(() => _autoPunctuate = v),
            ),
            const SizedBox(height: MemSpace.x3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_WhisperLanguageMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: MemSpace.x2),
                ),
                segments: const <ButtonSegment<_WhisperLanguageMode>>[
                  ButtonSegment<_WhisperLanguageMode>(
                    value: _WhisperLanguageMode.autoDetect,
                    icon: Icon(Icons.translate),
                    label: Text('Detect language'),
                  ),
                  ButtonSegment<_WhisperLanguageMode>(
                    value: _WhisperLanguageMode.forced,
                    icon: Icon(Icons.language),
                    label: Text('Set language'),
                  ),
                ],
                selected: <_WhisperLanguageMode>{_languageMode},
                onSelectionChanged: (Set<_WhisperLanguageMode> set) =>
                    setState(() => _languageMode = set.first),
              ),
            ),
            const SizedBox(height: MemSpace.x3),
            TextField(
              controller: _languageCtrl,
              enabled: forced,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: 'Language code',
                hintText: 'e.g. en, es, fr',
              ),
            ),
            const SizedBox(height: MemSpace.x3),
            TextField(
              controller: _whisperPromptCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Vocabulary hints',
                hintText: 'Names, jargon, or acronyms to expect',
              ),
            ),
            const SizedBox(height: MemSpace.x2),
            Text(
              'Values here are remembered; the panel closes again on your next '
              'visit.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _CaptureMicMode { longform, pushToTalk }

enum _WhisperLanguageMode { autoDetect, forced }

/// Everything a capture clear throws away, so Undo can put **all** of it back.
/// A body-only restore is not acceptable (§5.2).
@immutable
class _CaptureDraft {
  const _CaptureDraft({
    required this.body,
    required this.guidance,
    required this.collectionIds,
    required this.replaceMode,
    required this.autoPunctuate,
    required this.languageMode,
    required this.languageHint,
  });

  final String body;
  final String guidance;
  final List<String> collectionIds;
  final bool replaceMode;
  final bool autoPunctuate;
  final _WhisperLanguageMode languageMode;
  final String languageHint;
}

/// "Processing in Mem…" — the one place this screen admits to invisible
/// background work (`#13`).
///
/// A status pill: `pendingContainer` behind `onPendingContainer` text with an
/// 8 dp `pending` dot, which is the only shape the `pending` token is allowed
/// to take (§2.5). The [AiGlyph] marks the work as model-produced.
class _ProcessingChip extends StatelessWidget {
  const _ProcessingChip({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MemSemanticColors semantics = memSemanticColorsOf(context);

    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: MemSize.touchTarget),
        padding: const EdgeInsets.only(left: MemSpace.x3),
        decoration: BoxDecoration(
          color: semantics.pendingContainer,
          borderRadius: MemRadius.controlAll,
          border: Border.all(
            color: scheme.outline,
            width: hairlineWidth(context),
          ),
        ),
        child: Row(
          children: <Widget>[
            const AiGlyph(size: 16),
            const SizedBox(width: MemSpace.x2),
            Container(
              width: MemSize.statusDot,
              height: MemSize.statusDot,
              decoration: BoxDecoration(
                color: semantics.pending,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: MemSpace.x2),
            Expanded(
              child: Text(
                'Processing in Mem…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: semantics.onPendingContainer,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              iconSize: 18,
              color: semantics.onPendingContainer,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

String _autoPunctuateText(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;
  if (s.isNotEmpty) {
    s = s[0].toUpperCase() + s.substring(1);
  }
  if (!s.endsWith('.') && !s.endsWith('!') && !s.endsWith('?')) {
    s = '$s.';
  }
  return s;
}

String _formatElapsed(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
