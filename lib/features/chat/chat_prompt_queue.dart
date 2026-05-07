import 'package:flutter/foundation.dart';

/// One-shot dispatch from shell (e.g. home screen widget tap) → chat executes text.
class QueuedPromptJob {
  const QueuedPromptJob({
    required this.text,
    required this.notificationTitle,
    required this.notifyOnComplete,
  });

  final String text;
  /// Short label used in notifications (widget runs).
  final String notificationTitle;
  final bool notifyOnComplete;
}

class ChatPromptQueue extends ChangeNotifier {
  QueuedPromptJob? _pending;

  bool get hasPending => _pending != null;

  void enqueue(QueuedPromptJob job) {
    _pending = job;
    notifyListeners();
  }

  /// Consumer should call once when handling the queue (e.g. from [addListener]).
  QueuedPromptJob? consume() {
    final j = _pending;
    _pending = null;
    return j;
  }
}
