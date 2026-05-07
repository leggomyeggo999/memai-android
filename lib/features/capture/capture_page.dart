import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app_scope.dart';
import '../../widgets/settings_launcher.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/voice/openai_whisper_client.dart';

/// **Fast capture** lane: Mem-it for unstructured drops, or explicit markdown
/// when the user wants a verbatim note.
class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final _bodyCtrl = TextEditingController();
  final _instrCtrl = TextEditingController();
  final _whisperPromptCtrl = TextEditingController();
  final _languageCtrl = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  bool _busy = false;
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

  MemApiClient? _client(BuildContext context) {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  Future<void> _memIt() async {
    final messenger = ScaffoldMessenger.of(context);
    final app = AppScope.of(context);
    final c = _client(context);
    if (c == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add your Mem API key in Settings first.')),
      );
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await c.memIt(
        input: _bodyCtrl.text,
        instructions: _instrCtrl.text.trim().isEmpty
            ? null
            : _instrCtrl.text.trim(),
      );
      if (!mounted) return;
      _bodyCtrl.clear();
      _instrCtrl.clear();
      app.bumpNotesListRevision();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRaw() async {
    final messenger = ScaffoldMessenger.of(context);
    final app = AppScope.of(context);
    final c = _client(context);
    if (c == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add your Mem API key in Settings first.')),
      );
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await c.createNote(markdown: _bodyCtrl.text);
      if (!mounted) return;
      _bodyCtrl.clear();
      app.bumpNotesListRevision();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Add an OpenAI chat model + API key in Settings first.'),
          ),
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
            : (_languageCtrl.text.trim().isEmpty ? null : _languageCtrl.text.trim()),
        model: voiceModel,
      );
      if (!mounted) return;
      final normalized = _autoPunctuate ? _autoPunctuateText(text) : text;
      if (normalized.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No speech detected.')),
        );
        return;
      }
      if (_replaceMode || _bodyCtrl.text.trim().isEmpty) {
        _bodyCtrl.text = normalized;
      } else {
        final existing = _bodyCtrl.text.trimRight();
        _bodyCtrl.text = '$existing\n\n$normalized';
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Transcription failed: $e')));
      }
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
        messenger.showSnackBar(
          const SnackBar(content: Text('Microphone permission denied.')),
        );
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

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _bodyCtrl.dispose();
    _instrCtrl.dispose();
    _whisperPromptCtrl.dispose();
    _languageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture'),
        actions: settingsIconActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Drop text, transcripts, or HTML — Mem-it processes it on the server (see Mem API docs).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_CaptureMicMode>(
            segments: const [
              ButtonSegment(
                value: _CaptureMicMode.longform,
                icon: Icon(Icons.mic_none),
                label: Text('Longform'),
              ),
              ButtonSegment(
                value: _CaptureMicMode.pushToTalk,
                icon: Icon(Icons.touch_app_outlined),
                label: Text('Hold to talk'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (set) {
              final next = set.first;
              if (_recording) {
                _cancelRecording();
              }
              setState(() => _mode = next);
            },
          ),
          const SizedBox(height: 12),
          _VoiceCapturePanel(
            mode: _mode,
            recording: _recording,
            transcribing: _transcribing,
            elapsed: _recordingElapsed,
            level: _level,
            disabled: _busy,
            onLongformToggle: () async {
              if (_recording) {
                await _stopRecordingAndTranscribe();
              } else {
                await _startRecording();
              }
            },
            onHoldStart: () async {
              await HapticFeedback.mediumImpact();
              await _startRecording();
            },
            onHoldEnd: () async {
              await HapticFeedback.lightImpact();
              await _stopRecordingAndTranscribe();
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: _replaceMode,
            contentPadding: EdgeInsets.zero,
            title: const Text('Transcription insertion mode'),
            subtitle: Text(
              _replaceMode
                  ? 'Replace current content with latest transcription'
                  : 'Append each transcription to existing content',
            ),
            onChanged: (v) => setState(() => _replaceMode = v),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: _autoPunctuate,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto punctuation'),
            subtitle: const Text(
              'Add sentence capitalization and final punctuation to transcripts',
            ),
            onChanged: (v) => setState(() => _autoPunctuate = v),
          ),
          const SizedBox(height: 8),
          SegmentedButton<_WhisperLanguageMode>(
            segments: const [
              ButtonSegment(
                value: _WhisperLanguageMode.autoDetect,
                icon: Icon(Icons.auto_awesome),
                label: Text('Language: Auto'),
              ),
              ButtonSegment(
                value: _WhisperLanguageMode.forced,
                icon: Icon(Icons.language),
                label: Text('Language: Forced'),
              ),
            ],
            selected: {_languageMode},
            onSelectionChanged: (set) {
              setState(() => _languageMode = set.first);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _languageCtrl,
            enabled: _languageMode == _WhisperLanguageMode.forced,
            maxLines: 1,
            decoration: const InputDecoration(
              labelText: 'Whisper language hint (optional)',
              hintText: 'e.g. en, es, fr',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _whisperPromptCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Whisper prompt hint (optional)',
              hintText: 'Custom vocabulary/context for better transcription',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _bodyCtrl,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Content',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instrCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Instructions for Mem-it (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _memIt,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Mem-it (smart capture)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _saveRaw,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Save as raw markdown note'),
          ),
        ],
      ),
    );
  }
}

enum _CaptureMicMode { longform, pushToTalk }

class _VoiceCapturePanel extends StatelessWidget {
  const _VoiceCapturePanel({
    required this.mode,
    required this.recording,
    required this.transcribing,
    required this.elapsed,
    required this.level,
    required this.disabled,
    required this.onLongformToggle,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final _CaptureMicMode mode;
  final bool recording;
  final bool transcribing;
  final Duration elapsed;
  final double level;
  final bool disabled;
  final Future<void> Function() onLongformToggle;
  final Future<void> Function() onHoldStart;
  final Future<void> Function() onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = recording ? cs.errorContainer : cs.primaryContainer;
    final fg = recording ? cs.onErrorContainer : cs.onPrimaryContainer;
    final timeLabel = _formatElapsed(elapsed);
    if (mode == _CaptureMicMode.longform) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                transcribing
                    ? 'Transcribing…'
                    : (recording
                        ? 'Recording… tap to stop'
                        : 'Tap to start longform recording'),
              ),
              const SizedBox(height: 6),
              if (recording) Text(timeLabel, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              _LevelMeter(level: level),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: bg,
                  foregroundColor: fg,
                  minimumSize: const Size(180, 180),
                  shape: const CircleBorder(),
                ),
                onPressed: disabled || transcribing ? null : onLongformToggle,
                child: Icon(
                  recording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 72,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(transcribing
                ? 'Transcribing…'
                : 'Hold the button to talk, release to transcribe'),
            const SizedBox(height: 6),
            if (recording) Text(timeLabel, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            _LevelMeter(level: level),
            const SizedBox(height: 12),
            GestureDetector(
              onLongPressStart: disabled || transcribing
                  ? null
                  : (_) {
                      onHoldStart();
                    },
              onLongPressEnd: disabled || transcribing
                  ? null
                  : (_) {
                      onHoldEnd();
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.2),
                      blurRadius: 16,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  recording ? Icons.graphic_eq_rounded : Icons.keyboard_voice,
                  size: 72,
                  color: fg,
                ),
              ),
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

enum _WhisperLanguageMode { autoDetect, forced }

String _formatElapsed(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        minHeight: 8,
        value: level,
      ),
    );
  }
}
