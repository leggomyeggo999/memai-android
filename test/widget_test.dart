import 'package:flutter_test/flutter_test.dart';

import 'package:memai_android/core/config/mem_endpoints.dart';

void main() {
  test('Mem API and MCP endpoints are stable', () {
    expect(MemEndpoints.apiBase, 'https://api.mem.ai');
    expect(MemEndpoints.mcpEndpoint, 'https://mcp.mem.ai/mcp');
    expect(
      MemEndpoints.tokenEndpoint,
      'https://api.mem.ai/api/v2/oauth2/token',
    );
  });
}
