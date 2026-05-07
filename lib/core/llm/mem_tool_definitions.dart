/// OpenAPI-style tool specs for OpenAI `tools` and Anthropic `tools`.
///
/// Names mirror Mem MCP tools:
/// https://docs.mem.ai/mcp/supported-tools
List<Map<String, dynamic>> memToolSpecifications() {
  return [
    _fn(
      'search_notes',
      'Semantic / keyword search across your Mem notes. Use for discovery.',
      {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query text.'},
          'limit': {
            'type': 'integer',
            'description': 'Max results (1–50).',
            'default': 10,
          },
        },
        'required': ['query'],
      },
    ),
    _fn(
      'list_notes',
      'List notes with cursor pagination, ordered by updated or created time.',
      {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Page size (1–100).',
            'default': 25,
          },
          'order_by': {
            'type': 'string',
            'enum': ['updated_at', 'created_at'],
            'default': 'updated_at',
          },
          'collection_id': {
            'type': 'string',
            'description': 'Optional collection UUID filter.',
          },
        },
      },
    ),
    _fn(
      'get_note',
      'Read the full markdown for one note by UUID.',
      {
        'type': 'object',
        'properties': {
          'note_id': {
            'type': 'string',
            'description': 'Note UUID from list/search.',
          },
        },
        'required': ['note_id'],
      },
    ),
    _fn(
      'create_note',
      'Create a new markdown note. First line becomes the title.',
      {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'description': 'Full markdown body.'},
          'collection_titles': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional collection names (Mem matches existing).',
          },
        },
        'required': ['content'],
      },
    ),
    _fn(
      'update_note',
      'Replace note content. You MUST supply the current version from get_note.',
      {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'string'},
          'content': {'type': 'string'},
          'version': {'type': 'integer'},
        },
        'required': ['note_id', 'content', 'version'],
      },
    ),
    _fn(
      'list_collections',
      'List collections (folders) in Mem.',
      {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'default': 50},
        },
      },
    ),
    _fn(
      'mem_it',
      'Send raw content to Mem for background structuring (async on Mem side).',
      {
        'type': 'object',
        'properties': {
          'input': {'type': 'string'},
          'instructions': {'type': 'string'},
        },
        'required': ['input'],
      },
    ),
    _fn(
      'trash_note',
      'Soft-delete a note (moves to trash; restorable).',
      {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'string', 'description': 'Note UUID'},
        },
        'required': ['note_id'],
      },
    ),
    _fn(
      'restore_note',
      'Restore a trashed note to the active set.',
      {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'string', 'description': 'Trashed note UUID'},
        },
        'required': ['note_id'],
      },
    ),
  ];
}

/// Function declarations for Gemini `tools[].functionDeclarations`.
List<Map<String, dynamic>> memToolGeminiDeclarations() {
  return [
    for (final t in memToolSpecifications())
      {
        'name': t['function']['name'] as String,
        'description': t['function']['description'] as String,
        'parameters': Map<String, dynamic>.from(
          t['function']['parameters'] as Map,
        ),
      },
  ];
}

Map<String, dynamic> _fn(
  String name,
  String description,
  Map<String, dynamic> parametersSchema,
) {
  return {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parametersSchema,
    },
  };
}
