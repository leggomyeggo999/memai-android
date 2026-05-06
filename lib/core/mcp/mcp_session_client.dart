import 'package:dio/dio.dart';

import '../config/mem_endpoints.dart';

/// Minimal [Streamable HTTP](https://modelcontextprotocol.io/) client for
/// `https://mcp.mem.ai/mcp` using JSON-RPC 2.0 and optional `mcp-session-id`.
///
/// **Requires** a valid OAuth access token scoped for MCP (obtained via the
/// same Mem OAuth endpoints used by desktop connectors).
class McpSessionClient {
  McpSessionClient({required String accessToken, Dio? dio})
    : _token = accessToken,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 45),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Accept': 'application/json, text/event-stream',
                'Content-Type': 'application/json',
              },
            ),
          );

  final String _token;
  final Dio _dio;
  String? _sessionId;
  bool _handshakeDone = false;

  Map<String, String> _headers() {
    return {
      'Authorization': 'Bearer $_token',
      'MCP-Protocol-Version': MemEndpoints.mcpProtocolVersion,
      if (_sessionId != null) MemEndpoints.mcpSessionHeader: _sessionId!,
    };
  }

  void _captureSession(Response<dynamic> response) {
    final sid = response.headers.value(MemEndpoints.mcpSessionHeader) ??
        response.headers.value('Mcp-Session-Id');
    if (sid != null && sid.isNotEmpty) {
      _sessionId = sid;
    }
  }

  /// Runs the MCP handshake once per client instance.
  Future<void> connect() async {
    if (_handshakeDone) return;
    final res = await _dio.post<dynamic>(
      MemEndpoints.mcpEndpoint,
      data: <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, dynamic>{
          'protocolVersion': MemEndpoints.mcpProtocolVersion,
          'capabilities': <String, dynamic>{
            'tools': <String, dynamic>{},
          },
          'clientInfo': <String, dynamic>{
            'name': 'memai_android',
            'version': '1.0.0',
          },
        },
      },
      options: Options(headers: _headers()),
    );
    _captureSession(res);

    // Notification — no response id (server may return 202 empty).
    final n = await _dio.post<dynamic>(
      MemEndpoints.mcpEndpoint,
      data: <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
      options: Options(headers: _headers(), validateStatus: (s) => s != null && s < 500),
    );
    _captureSession(n);
    _handshakeDone = true;
  }

  /// Invokes a Mem MCP tool (see docs: search_notes, create_note, …).
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final res = await _dio.post<dynamic>(
      MemEndpoints.mcpEndpoint,
      data: <String, dynamic>{
        'jsonrpc': '2.0',
        'id': DateTime.now().microsecondsSinceEpoch,
        'method': 'tools/call',
        'params': <String, dynamic>{'name': name, 'arguments': arguments},
      },
      options: Options(headers: _headers()),
    );
    _captureSession(res);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err != null) {
        throw McpRpcException(err.toString());
      }
      final result = data['result'];
      if (result is Map<String, dynamic>) return result;
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    }
    // SSE / stream responses would need a different parser — surface clearly.
    throw McpRpcException('Unexpected MCP response payload (${data.runtimeType})');
  }
}

class McpRpcException implements Exception {
  McpRpcException(this.message);
  final String message;
  @override
  String toString() => 'McpRpcException: $message';
}
