// Utility functions for non-web platforms
class PlatformUtils {
  // Get base URL for HTTP requests
  static String getBaseUrl() {
    return 'http://achtung:8035';
  }
  
  // Get WebSocket URL for chat connection
  static String getWebSocketUrl() {
    return 'ws://achtung:8035/api/chat/completion/stream';
  }
}
