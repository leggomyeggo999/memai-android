library;

/// Curated API model ids with human labels for the Settings picker.
///
/// Update when providers ship new flagship models; [CuratedChatModel.apiModelId]
/// must match each vendor’s REST `model` parameter.
///
/// One row in the add-model dropdown: [apiModelId] is sent to the provider API.
class CuratedChatModel {
  const CuratedChatModel({
    required this.apiModelId,
    required this.catalogLabel,
  });

  final String apiModelId;
  final String catalogLabel;
}

/// Short vendor name shown in composed titles and subtitles.
String chatProviderBrand(String provider) {
  switch (provider) {
    case 'openai':
      return 'OpenAI';
    case 'anthropic':
      return 'Anthropic';
    case 'gemini':
      return 'Google';
    default:
      return provider;
  }
}

/// Primary list title shown in Chat / Settings (`OpenAI · GPT-5.5`, etc.).
String composeChatDisplayName(String provider, CuratedChatModel model) =>
    '${chatProviderBrand(provider)} · ${model.catalogLabel}';

/// Latest major lines plus ~2 older generations each — adjust as APIs evolve.
const List<CuratedChatModel> kCuratedOpenAiModels = [
  CuratedChatModel(apiModelId: 'gpt-5.5', catalogLabel: 'GPT-5.5'),
  CuratedChatModel(apiModelId: 'gpt-5.4-mini', catalogLabel: 'GPT-5.4 Mini'),
  CuratedChatModel(apiModelId: 'gpt-5', catalogLabel: 'GPT-5'),
  CuratedChatModel(apiModelId: 'gpt-4.1', catalogLabel: 'GPT-4.1'),
  CuratedChatModel(apiModelId: 'gpt-4o', catalogLabel: 'GPT-4o'),
  CuratedChatModel(apiModelId: 'gpt-4o-mini', catalogLabel: 'GPT-4o mini'),
];

const List<CuratedChatModel> kCuratedAnthropicModels = [
  CuratedChatModel(
    apiModelId: 'claude-opus-4-7',
    catalogLabel: 'Claude Opus 4.7',
  ),
  CuratedChatModel(
    apiModelId: 'claude-sonnet-4-6',
    catalogLabel: 'Claude Sonnet 4.6',
  ),
  CuratedChatModel(
    apiModelId: 'claude-haiku-4-5-20251001',
    catalogLabel: 'Claude Haiku 4.5',
  ),
  CuratedChatModel(
    apiModelId: 'claude-3-7-sonnet-20250219',
    catalogLabel: 'Claude 3.7 Sonnet',
  ),
  CuratedChatModel(
    apiModelId: 'claude-3-5-sonnet-20241022',
    catalogLabel: 'Claude 3.5 Sonnet',
  ),
];

const List<CuratedChatModel> kCuratedGeminiModels = [
  CuratedChatModel(apiModelId: 'gemini-2.5-pro', catalogLabel: 'Gemini 2.5 Pro'),
  CuratedChatModel(
    apiModelId: 'gemini-2.5-flash',
    catalogLabel: 'Gemini 2.5 Flash',
  ),
  CuratedChatModel(
    apiModelId: 'gemini-2.5-flash-lite',
    catalogLabel: 'Gemini 2.5 Flash-Lite',
  ),
  CuratedChatModel(
    apiModelId: 'gemini-2.0-flash',
    catalogLabel: 'Gemini 2.0 Flash',
  ),
  CuratedChatModel(
    apiModelId: 'gemini-1.5-pro',
    catalogLabel: 'Gemini 1.5 Pro',
  ),
  CuratedChatModel(
    apiModelId: 'gemini-1.5-flash',
    catalogLabel: 'Gemini 1.5 Flash',
  ),
];

List<CuratedChatModel> curatedModelsForProvider(String provider) {
  switch (provider) {
    case 'openai':
      return kCuratedOpenAiModels;
    case 'anthropic':
      return kCuratedAnthropicModels;
    case 'gemini':
      return kCuratedGeminiModels;
    default:
      return const [];
  }
}

CuratedChatModel? curatedModelByApiId(String provider, String apiModelId) {
  for (final m in curatedModelsForProvider(provider)) {
    if (m.apiModelId == apiModelId) return m;
  }
  return null;
}
