import 'package:dio/dio.dart';

import '../config/mem_endpoints.dart';
import 'mem_api_exception.dart';
import 'mem_models.dart';

/// Thin, typed wrapper around the public Mem REST API (`https://api.mem.ai`).
///
/// Auth: `Authorization: Bearer <Mem API key>` as per
/// https://docs.mem.ai/api-reference/overview/authentication
class MemApiClient {
  MemApiClient({required String apiKey, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: MemEndpoints.apiBase,
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Accept': 'application/json',
              },
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  Future<List<MemNoteListItem>> listNotes({
    int limit = 50,
    String? page,
    String orderBy = 'updated_at',
    bool includeContent = false,
    String? collectionId,
  }) async {
    final q = <String, dynamic>{
      'limit': limit,
      'order_by': orderBy,
      'include_note_content': includeContent,
      if (page != null) 'page': page,
      if (collectionId != null) 'collection_id': collectionId,
    };
    final res = await _dio.get<Map<String, dynamic>>(
      '/v2/notes',
      queryParameters: q,
    );
    final data = res.data;
    if (data == null) throw MemApiException('Empty response');
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => _parseListItem(e as Map<String, dynamic>)).toList();
  }

  MemNoteListItem _parseListItem(Map<String, dynamic> e) {
    return MemNoteListItem(
      id: e['id'] as String,
      title: e['title'] as String? ?? '',
      snippet: e['snippet'] as String?,
      content: e['content'] as String?,
      createdAt: DateTime.parse(e['created_at'] as String),
      updatedAt: DateTime.parse(e['updated_at'] as String),
      collectionIds: (e['collection_ids'] as List<dynamic>? ?? [])
          .map((x) => x as String)
          .toList(),
    );
  }

  Future<MemNoteFull> readNote(String noteId) async {
    final res = await _dio.get<Map<String, dynamic>>('/v2/notes/$noteId');
    final e = res.data;
    if (e == null) throw MemApiException('Empty response');
    return MemNoteFull(
      id: e['id'] as String,
      title: e['title'] as String? ?? '',
      content: e['content'] as String? ?? '',
      version: e['version'] as int,
      createdAt: DateTime.parse(e['created_at'] as String),
      updatedAt: DateTime.parse(e['updated_at'] as String),
      collectionIds: (e['collection_ids'] as List<dynamic>? ?? [])
          .map((x) => x as String)
          .toList(),
      trashedAt: e['trashed_at'] != null
          ? DateTime.parse(e['trashed_at'] as String)
          : null,
    );
  }

  Future<List<MemNoteListItem>> searchNotes({
    required String query,
    int limit = 20,
    int offset = 0,
    String? snapshotId,
    bool includeContent = false,
  }) async {
    final q = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      if (snapshotId != null) 'snapshot_id': snapshotId,
    };
    final res = await _dio.post<Map<String, dynamic>>(
      '/v2/notes/search',
      queryParameters: q,
      data: {
        'query': query,
        'config': {'include_note_content': includeContent},
      },
    );
    final data = res.data;
    if (data == null) throw MemApiException('Empty response');
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => _parseListItem(e as Map<String, dynamic>)).toList();
  }

  Future<MemNoteFull> createNote({
    required String markdown,
    List<String>? collectionIds,
    List<String>? collectionTitles,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v2/notes',
      data: {
        'content': markdown,
        if (collectionIds != null) 'collection_ids': collectionIds,
        if (collectionTitles != null) 'collection_titles': collectionTitles,
      },
    );
    final e = res.data;
    if (e == null) throw MemApiException('Empty response');
    return MemNoteFull(
      id: e['id'] as String,
      title: e['title'] as String? ?? '',
      content: e['content'] as String? ?? '',
      version: e['version'] as int,
      createdAt: DateTime.parse(e['created_at'] as String),
      updatedAt: DateTime.parse(e['updated_at'] as String),
      collectionIds: (e['collection_ids'] as List<dynamic>? ?? [])
          .map((x) => x as String)
          .toList(),
      trashedAt: null,
    );
  }

  Future<MemNoteFull> updateNote({
    required String noteId,
    required String markdown,
    required int version,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v2/notes/$noteId',
      data: {'content': markdown, 'version': version},
    );
    final e = res.data;
    if (e == null) throw MemApiException('Empty response');
    return MemNoteFull(
      id: e['id'] as String,
      title: e['title'] as String? ?? '',
      content: e['content'] as String? ?? '',
      version: e['version'] as int,
      createdAt: DateTime.parse(e['created_at'] as String),
      updatedAt: DateTime.parse(e['updated_at'] as String),
      collectionIds: (e['collection_ids'] as List<dynamic>? ?? [])
          .map((x) => x as String)
          .toList(),
      trashedAt: e['trashed_at'] != null
          ? DateTime.parse(e['trashed_at'] as String)
          : null,
    );
  }

  Future<String> memIt({
    required String input,
    String? instructions,
    String? context,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v2/mem-it',
      data: {
        'input': input,
        if (instructions != null) 'instructions': instructions,
        if (context != null) 'context': context,
      },
    );
    final id = res.data?['request_id'] as String?;
    if (id == null) throw MemApiException('mem-it missing request_id');
    return id;
  }

  Future<List<MemCollectionItem>> listCollections({
    int limit = 50,
    String? page,
    String orderBy = 'updated_at',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v2/collections',
      queryParameters: {
        'limit': limit,
        'order_by': orderBy,
        if (page != null) 'page': page,
      },
    );
    final data = res.data;
    if (data == null) throw MemApiException('Empty response');
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) {
      final m = e as Map<String, dynamic>;
      return MemCollectionItem(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        description: m['description'] as String?,
        noteCount: m['note_count'] as int? ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> rawListNotes({
    int limit = 50,
    String? page,
    String orderBy = 'updated_at',
    bool includeContent = false,
    String? collectionId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v2/notes',
      queryParameters: {
        'limit': limit,
        'order_by': orderBy,
        'include_note_content': includeContent,
        if (page != null) 'page': page,
        if (collectionId != null) 'collection_id': collectionId,
      },
    );
    final data = res.data;
    if (data == null) throw MemApiException('Empty response');
    return data;
  }

  static String formatError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final meta = data['error_metadata'];
      if (meta is Map<String, dynamic>) {
        final msg = meta['message'] as String?;
        if (msg != null) return msg;
      }
      final desc = data['error_description'] as String?;
      if (desc != null) return desc;
    }
    return e.message ?? 'Network error';
  }
}
