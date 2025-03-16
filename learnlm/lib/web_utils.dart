import 'dart:html' as html;

// Utility functions specific to web platform
class PlatformUtils {
  // Get base URL from current document origin when running in web
  static String getBaseUrl() {
    final location = html.window.location;
    return '${location.protocol}//${location.hostname}:${location.port}';
  }
  
  // Get WebSocket URL from current document origin when running in web
  static String getWebSocketUrl() {
    final location = html.window.location;
    final protocol = location.protocol == 'https:' ? 'wss:' : 'ws:';
    return '$protocol//${location.hostname}:${location.port}/api/chat/completion/stream';
  }
}
