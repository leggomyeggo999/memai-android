import 'package:flutter_test/flutter_test.dart';
import 'package:memai_android/core/mcp/mem_oauth.dart';

void main() {
  test('MCP redirect URI parses (RFC scheme — no underscore)', () {
    expect(() => Uri.parse(MemMcpOAuth.redirectUrl), returnsNormally);
    expect(Uri.parse(MemMcpOAuth.redirectUrl).scheme, 'com.memai.memaiandroid');
    expect(Uri.parse(MemMcpOAuth.redirectUrl).host, 'oauth');
  });
}
