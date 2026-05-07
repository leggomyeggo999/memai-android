import 'package:shared_preferences/shared_preferences.dart';

import 'prompt_template.dart';

const _kTemplates = 'prompt_templates_json_v1';
const _kPinned = 'prompt_pinned_template_ids_v1';

class PromptTemplateStore {
  Future<(List<PromptTemplate>, List<String>)> load() async {
    final p = await SharedPreferences.getInstance();
    final templates = PromptTemplate.decodeList(p.getString(_kTemplates));
    final pinned = p.getStringList(_kPinned) ?? [];
    return (templates, pinned);
  }

  Future<void> save({
    required List<PromptTemplate> templates,
    required List<String> pinnedTemplateIds,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTemplates, PromptTemplate.encodeList(templates));
    await p.setStringList(_kPinned, pinnedTemplateIds);
  }
}
