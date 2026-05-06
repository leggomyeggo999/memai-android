import 'dart:convert';

import 'package:dio/dio.dart';

import '../mem/mem_api_client.dart';
import '../mcp/mcp_session_client.dart';

/// Executes Mem tool calls either via **REST** (preferred when a Mem API key
/// exists — same backend Mem documents for rate limits) or via the **hosted MCP
/// HTTP endpoint** when only an OAuth access token is available.
///
/// See: https://docs.mem.ai/mcp/supported-tools
class MemToolRunner {
  MemToolRunner({this.api, McpSessionClient? mcp})
    : _mcp = mcp;

  final MemApiClient? api;
  final McpSessionClient? _mcp;

  bool get hasBackend => (api != null) || (_mcp != null);

  Future<void> ensureMcpConnected() async {
    final m = _mcp;
    if (m == null) return;
    await m.connect();
  }

  /// Returns a concise JSON string suitable for feeding back into the LLM.
  Future<String> run(String name, Map<String, dynamic> args) async {
    if (api != null) {
      return _runRest(name, args);
    }
    final mcp = _mcp;
    if (mcp != null) {
      await ensureMcpConnected();
      final raw = await mcp.callTool(name, args);
      return jsonEncode(raw);
    }
    throw StateError('No Mem backend (add API key or connect MCP OAuth).');
  }

  Future<String> _runRest(String name, Map<String, dynamic> args) async {
    final c = api!;
    try {
      switch (name) {
        case 'search_notes':
          final list = await c.searchNotes(
            query: args['query'] as String,
            limit: (args['limit'] as num?)?.toInt() ?? 10,
            includeContent: false,
          );
          return jsonEncode({
            'results': [
              for (final n in list)
                {
                  'id': n.id,
                  'title': n.title,
                  'snippet': n.snippet,
                  'updated_at': n.updatedAt.toIso8601String(),
                },
            ],
          });
        case 'list_notes':
          final raw = await c.rawListNotes(
            limit: (args['limit'] as num?)?.toInt() ?? 25,
            orderBy: args['order_by'] as String? ?? 'updated_at',
            includeContent: false,
            collectionId: args['collection_id'] as String?,
          );
          return jsonEncode({
            'total': raw['total'],
            'next_page': raw['next_page'],
            'results': raw['results'],
          });
        case 'get_note':
          final note = await c.readNote(args['note_id'] as String);
          return jsonEncode({
            'id': note.id,
            'title': note.title,
            'content': note.content,
            'version': note.version,
            'updated_at': note.updatedAt.toIso8601String(),
          });
        case 'create_note':
          final note = await c.createNote(
            markdown: args['content'] as String,
            collectionTitles: (args['collection_titles'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList(),
          );
          return jsonEncode({
            'id': note.id,
            'title': note.title,
            'version': note.version,
          });
        case 'update_note':
          final note = await c.updateNote(
            noteId: args['note_id'] as String,
            markdown: args['content'] as String,
            version: (args['version'] as num).toInt(),
          );
          return jsonEncode({'id': note.id, 'version': note.version});
        case 'list_collections':
          final list = await c.listCollections(
            limit: (args['limit'] as num?)?.toInt() ?? 50,
          );
          return jsonEncode({
            'results': [
              for (final x in list)
                {
                  'id': x.id,
                  'title': x.title,
                  'note_count': x.noteCount,
                },
            ],
          });
        case 'mem_it':
          final req = await c.memIt(
            input: args['input'] as String,
            instructions: args['instructions'] as String?,
          );
          return jsonEncode({
            'request_id': req,
            'status':
                'Mem is processing this asynchronously; it will appear in search shortly.',
          });
        case 'trash_note':
          final req = await c.trashNote(args['note_id'] as String);
          return jsonEncode({'request_id': req, 'status': 'moved to trash'});
        case 'restore_note':
          final req = await c.restoreNote(args['note_id'] as String);
          return jsonEncode({'request_id': req, 'status': 'restored'});
        default:
          return jsonEncode({'error': 'unknown_tool', 'name': name});
      }
    } on DioException catch (e) {
      return jsonEncode({
        'error': MemApiClient.formatError(e),
        'status_code': e.response?.statusCode,
      });
    }
  }
}
