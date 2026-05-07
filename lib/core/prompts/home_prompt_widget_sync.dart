import 'dart:io';

import 'package:home_widget/home_widget.dart';

import 'prompt_template.dart';

const _kWidgetAndroidName = 'PromptJobsWidgetProvider';

/// Writes up to four pinned jobs for the Android home screen widget.
Future<void> syncHomePromptWidget({
  required List<PromptTemplate> all,
  required List<String> pinnedIds,
}) async {
  if (!Platform.isAndroid) return;

  for (var i = 0; i < 4; i++) {
    if (i < pinnedIds.length) {
      final id = pinnedIds[i];
      final t = _byId(all, id);
      await HomeWidget.saveWidgetData<String>('pinned_${i}_id', id);
      await HomeWidget.saveWidgetData<String>(
        'pinned_${i}_title',
        t?.title.trim().isEmpty == true ? 'Job' : (t?.title ?? 'Job'),
      );
    } else {
      await HomeWidget.saveWidgetData<String>('pinned_${i}_id', '');
      await HomeWidget.saveWidgetData<String>('pinned_${i}_title', '');
    }
  }

  await HomeWidget.updateWidget(
    androidName: _kWidgetAndroidName,
    qualifiedAndroidName: 'com.memai.memai_android.$_kWidgetAndroidName',
  );
}

PromptTemplate? _byId(List<PromptTemplate> all, String id) {
  for (final t in all) {
    if (t.id == id) return t;
  }
  return null;
}

Future<void> requestPinPromptWidget() async {
  if (!Platform.isAndroid) return;
  await HomeWidget.requestPinWidget(
    qualifiedAndroidName: 'com.memai.memai_android.$_kWidgetAndroidName',
  );
}

Future<bool> isPinWidgetSupported() async {
  if (!Platform.isAndroid) return false;
  final v = await HomeWidget.isRequestPinWidgetSupported();
  return v ?? false;
}
