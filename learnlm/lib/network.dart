import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional import for web platform
import 'web_utils.dart' if (dart.library.io) 'non_web_utils.dart';

// Import ChatMessage for use within this file
import 'components/chat_message.dart';
// Also re-export it for backward compatibility
export 'components/chat_message.dart';

// JSON processing utilities
class JsonUtils {
  // Debug raw response data from server
  static void debugRawServerResponse(Map<String, dynamic> chatData) {
    print("\n=== RAW SERVER RESPONSE ===");
    print("Chat ID: ${chatData['id']}");
    print("Title: ${chatData['title']}");
    print("Created at: ${chatData['created_at']}");
    print("Updated at: ${chatData['updated_at']}");
    print("Messages count: ${chatData['messages'].length}");
    
    print("\n=== RAW MESSAGES ===");
    final messages = chatData['messages'];
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final role = msg['role'];
      final timestamp = msg.containsKey('timestamp') ? msg['timestamp'] : "NO_TIMESTAMP";
      // Handle content encoding properly
      String content = msg['content'].toString();
      
      // Debug raw content data
      print("[$i] Raw content type: ${msg['content'].runtimeType}");
      
      // Check for Unicode characters
      final hasUnicode = content.codeUnits.any((unit) => unit > 127);
      print("[$i] Has Unicode: $hasUnicode");
      
      // If it contains Unicode, ensure proper UTF-8 display
      if (hasUnicode) {
        try {
          final bytes = utf8.encode(content);
          final bytes16 = bytes.take(16).toList();
          print("[$i] First 16 bytes: $bytes16");
          
          // For debugging: re-encode and decode to ensure consistency
          final reDecoded = utf8.decode(bytes);
          print("[$i] Re-decoded first 10 chars: ${reDecoded.length > 10 ? reDecoded.substring(0, 10) : reDecoded}");
          content = reDecoded;
        } catch (e) {
          print("[$i] Encoding error: $e");
        }
      }
      
      final contentPreview = content.length > 100 
          ? content.substring(0, 100) + "..." 
          : content;
          
      // Print using special formatting to help identify encoding issues
      print("[$i] ($role) [$timestamp]:");
      print("   CONTENT[UTF-8]: $contentPreview");
    }
    print("=== END OF RAW RESPONSE ===\n");
  }
  
  // Process chat messages data from server response
  static List<ChatMessage> processChatMessages(List<dynamic> messagesData) {
    final List<ChatMessage> loadedMessages = [];
    
    // We need to properly sort user and assistant messages to maintain conversation flow
    final userMessages = <ChatMessage>[];
    final assistantMessages = <ChatMessage>[];
    
    print("\n=== PROCESSING MESSAGES ===");
    for (int i = 0; i < messagesData.length; i++) {
      final msg = messagesData[i];
      if (msg['role'] == 'system') {
        print("[$i] Skipping system message");
        continue;
      }
      
      final isUserMsg = msg['role'] == 'user';
      final timestamp = msg.containsKey('timestamp') ? msg['timestamp'] : null;
      
      print("[$i] Processing ${isUserMsg ? 'USER' : 'ASSISTANT'} message with timestamp: $timestamp");
      
      final chatMsg = ChatMessage(
        text: msg['content'],
        isUser: isUserMsg,
        timestamp: timestamp,
      );
      
      if (isUserMsg) {
        userMessages.add(chatMsg);
        print("  → Added to userMessages (${userMessages.length})");
      } else {
        assistantMessages.add(chatMsg);
        print("  → Added to assistantMessages (${assistantMessages.length})");
      }
    }
    print("=== END PROCESSING ===\n");
    
    // Sort messages by timestamp if available
    print("\n=== ADDING MESSAGES TO CHAT ===");
    // Simply add all messages to loadedMessages in the order they came from the server
    // No sorting needed as they're already sorted in the database
    print("Adding ${userMessages.length} user messages and ${assistantMessages.length} assistant messages");
    
    // Add all messages in the original order from the combined lists
    final allMessages = [...userMessages, ...assistantMessages];
    
    // Sort by the original index to maintain server order
    allMessages.sort((a, b) => 
      messagesData.indexWhere((msg) => 
        msg['content'] == a.text && msg['role'] == (a.isUser ? 'user' : 'assistant'))
      .compareTo(
        messagesData.indexWhere((msg) => 
          msg['content'] == b.text && msg['role'] == (b.isUser ? 'user' : 'assistant'))
      )
    );
    
    loadedMessages.addAll(allMessages);
    
    // Debug: Log reconstructed chat messages
    print("\n=== RECONSTRUCTED CHAT (SORTED BY TIMESTAMP) ===");
    for (int i = 0; i < loadedMessages.length; i++) {
      final msg = loadedMessages[i];
      final role = msg.isUser ? "USER" : "ASSISTANT";
      final timestamp = msg.timestamp ?? "NO_TIMESTAMP";
      final contentPreview = msg.text.length > 100 
          ? msg.text.substring(0, 100) + "..." 
          : msg.text;
      print("[$i] ($role) [$timestamp]: $contentPreview");
    }
    print("=== END OF RECONSTRUCTED CHAT ===\n");
    
    return loadedMessages;
  }
  
  // Debug raw WebSocket data
  static void debugRawWebSocketData(dynamic data) {
    // Debug raw WebSocket data to check encoding
    print("\n=== RAW WEBSOCKET DATA ===");
    print("Data type: ${data.runtimeType}");
    if (data is String) {
      print("First 50 chars: ${data.length > 50 ? data.substring(0, 50) : data}");
      print("String length: ${data.length}");
      
      // Check if the string has Unicode characters
      final hasUnicode = data.codeUnits.any((unit) => unit > 127);
      print("Has Unicode characters: $hasUnicode");
      
      // If Unicode detected, show the string explicitly decoded as UTF-8
      if (hasUnicode) {
        final bytes = utf8.encode(data);
        final decoded = utf8.decode(bytes);
        print("Re-decoded string (first 50 chars): ${decoded.length > 50 ? decoded.substring(0, 50) : decoded}");
      }
    } else if (data is List<int>) {
      // If it's binary data, decode as UTF-8
      final decoded = utf8.decode(data);
      print("Decoded binary data (first 50 chars): ${decoded.length > 50 ? decoded.substring(0, 50) : decoded}");
    }
    print("=========================\n");
  }
  
  // Debug outgoing WebSocket request
  static void debugOutgoingWebSocketRequest(String jsonRequest) {
    print("\n=== OUTGOING WEBSOCKET REQUEST ===");
    print("JSON length: ${jsonRequest.length}");
    print("Has Unicode: ${jsonRequest.codeUnits.any((unit) => unit > 127)}");
    print("============================\n");
  }
}

// Ensure UTF-8 encoding is used for all HTTP and WebSocket communications
const Encoding utf8Encoding = utf8;

// Chat models
class ChatSummary {
  final int id;
  final String title;
  final String createdAt;
  final String updatedAt;
  
  ChatSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
  
  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: json['id'],
      title: json['title'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }
  
  DateTime get createdAtDateTime => DateTime.parse(createdAt);
  DateTime get updatedAtDateTime => DateTime.parse(updatedAt);
}

// Chat API service
class ChatApiService {
  static String get baseUrl => PlatformUtils.getBaseUrl();
  
  // Get all chats for a user
  static Future<List<ChatSummary>> getChats(String userSecret) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/chats?user_secret=$userSecret'),
      headers: {
        'Accept': 'application/json; charset=utf-8',
        'Content-Type': 'application/json; charset=utf-8'
      }
    );
    
    if (response.statusCode == 200) {
      // Add debug info for encoding
      print("\n=== CHAT LIST RESPONSE ENCODING INFO ===");
      print("Response content-type: ${response.headers['content-type']}");
      print("Response content length: ${response.contentLength}");
      
      // Explicitly decode the response body as UTF-8
      final decodedBody = utf8.decode(response.bodyBytes);
      
      List<dynamic> data = jsonDecode(decodedBody);
      return data.map((item) => ChatSummary.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load chats: ${response.statusCode}');
    }
  }
  
  // Delete a chat
  static Future<bool> deleteChat(int chatId, String userSecret) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/chats/$chatId?user_secret=$userSecret'),
    );
    
    return response.statusCode == 204;
  }
  
  // Get detailed chat
  static Future<Map<String, dynamic>> getChat(int chatId, String userSecret) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/chats/$chatId?user_secret=$userSecret'),
      headers: {
        'Accept': 'application/json; charset=utf-8',
        'Content-Type': 'application/json; charset=utf-8'
      }
    );
    
    if (response.statusCode == 200) {
      // Add debug info for encoding
      print("\n=== HTTP RESPONSE ENCODING INFO ===");
      print("Response content-type: ${response.headers['content-type']}");
      print("Response content length: ${response.contentLength}");
      print("First few bytes of response: ${response.bodyBytes.take(20).toList()}");
      
      // Explicitly decode the response body as UTF-8
      final decodedBody = utf8.decode(response.bodyBytes);
      
      // Debug info for decoded text
      if (decodedBody.length > 100) {
        print("First 100 chars of decoded body: ${decodedBody.substring(0, 100)}");
      }
      
      return jsonDecode(decodedBody);
    } else {
      throw Exception('Failed to load chat: ${response.statusCode}');
    }
  }
}

class WebSocketService {
  WebSocketChannel? _channel;
  bool isConnected = false;
  bool isReconnecting = false;
  int reconnectAttempts = 0;
  Timer? reconnectTimer;
  
  // Callbacks
  Function(Map<String, dynamic>)? onMessageReceived;
  Function(dynamic)? onError;
  Function()? onDisconnected;
  
  void connect() {
    if (isReconnecting) {
      return;
    }
    
    try {
      // Use platform-appropriate WebSocket URL
      final uri = Uri.parse(PlatformUtils.getWebSocketUrl());
      _channel = WebSocketChannel.connect(uri);
      
      _channel!.stream.listen(
        (data) {
          try {
            // Debug raw WebSocket data
            JsonUtils.debugRawWebSocketData(data);
            
            // Convert binary data to string if needed
            if (data is List<int>) {
              data = utf8.decode(data);
            }
            
            // Explicitly use UTF-8 decoding for WebSocket data
            final decodedData = data is String ? data : utf8.decode(data as List<int>);
            final responseData = jsonDecode(decodedData);
            
            isConnected = true;
            
            // Call the callback with the parsed data
            if (onMessageReceived != null) {
              onMessageReceived!(responseData);
            }
            
          } catch (e) {
            print("Error processing server message: $e");
            if (onError != null) {
              onError!(e);
            }
          }
        },
        onError: (error) {
          print("WebSocket error: $error");
          isConnected = false;
          if (onError != null) {
            onError!(error);
          }
          scheduleReconnect();
        },
        onDone: () {
          print("WebSocket connection closed");
          isConnected = false;
          if (onDisconnected != null) {
            onDisconnected!();
          }
          scheduleReconnect();
        },
      );
      
      isConnected = true;
    } catch (e) {
      print("Error connecting to WebSocket: $e");
      isConnected = false;
      if (onError != null) {
        onError!(e);
      }
      scheduleReconnect();
    }
  }
  
  void scheduleReconnect() {
    if (isReconnecting) {
      return;
    }
    
    isReconnecting = true;
    
    // Implement exponential backoff for reconnection attempts
    final backoffSeconds = reconnectAttempts < 5 
        ? (1 << reconnectAttempts) // 1, 2, 4, 8, 16 seconds
        : 30; // Max 30 seconds
    
    print("Scheduling reconnect in $backoffSeconds seconds (attempt ${reconnectAttempts + 1})");
    
    reconnectTimer?.cancel();
    reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      isReconnecting = false;
      reconnectAttempts++;
      connect();
    });
  }
  
  void sendMessage(Map<String, dynamic> data) {
    if (_channel != null && isConnected) {
      final jsonRequest = jsonEncode(data);
      
      // Debug outgoing request
      JsonUtils.debugOutgoingWebSocketRequest(jsonRequest);
      
      _channel!.sink.add(jsonRequest);
    } else {
      throw Exception('WebSocket is not connected');
    }
  }
  
  void saveChat(String userSecret, String title, List<ChatMessage> messages, [int? chatId]) {
    if (_channel == null || !isConnected) {
      throw Exception('WebSocket is not connected');
    }
    
    // Prepare history for the request
    final List<Map<String, dynamic>> messageHistory = [];
    
    for (var message in messages) {
      if (message.isUser) {
        messageHistory.add({
          "role": "user",
          "content": message.text,
        });
      } else if (!message.isError) {
        messageHistory.add({
          "role": "assistant",
          "content": message.text,
        });
      }
    }
    
    // Create request object
    final Map<String, dynamic> request;
    
    if (chatId != null) {
      // Update existing chat
      request = {
        "user_secret": userSecret,
        "chat_id": chatId,
        "title": title,
        "history": {
          "system_message": "You are a helpful AI assistant.",
          "messages": messageHistory,
        }
      };
    } else {
      // Create new chat
      request = {
        "user_secret": userSecret,
        "title": title,
        "history": {
          "system_message": "You are a helpful AI assistant.",
          "messages": messageHistory,
        }
      };
    }
    
    // Send the save request
    _channel!.sink.add(jsonEncode({
      "command": "save_chat",
      "data": request
    }));
  }
  
  void updateChatTitle(String userSecret, int chatId, String newTitle) {
    if (_channel == null || !isConnected) {
      throw Exception('WebSocket is not connected');
    }
    
    // Create request object for updating just the title
    final request = {
      "user_secret": userSecret,
      "chat_id": chatId,
      "title": newTitle,
      "history": {
        "system_message": "You are a helpful AI assistant.",
        "messages": [] // Empty messages since we're only updating the title
      }
    };
    
    // Send the save request
    _channel!.sink.add(jsonEncode({
      "command": "save_chat",
      "data": request
    }));
  }
  
  void sendChatRequest(String userSecret, List<ChatMessage> messages, String conversationTitle, [int? chatId]) {
    if (_channel == null || !isConnected) {
      throw Exception('WebSocket is not connected');
    }
    
    // Prepare history for the request
    final List<Map<String, dynamic>> messageHistory = [];
    
    for (var message in messages) {
      if (message.isUser) {
        messageHistory.add({
          "role": "user",
          "content": message.text,
        });
      } else if (!message.isError) {
        messageHistory.add({
          "role": "assistant",
          "content": message.text,
        });
      }
    }
    
    // Create request object
    final request = {
      "history": {
        "messages": messageHistory,  // Keep messages in the original format with "content" field
      },
      "temperature": 0.7,
      "top_p": 0.95,
      "top_k": 64,
      "max_tokens": 4096,
      "user_secret": userSecret,
      "chat_id": chatId,
      "title": conversationTitle,
    };
    
    // Send the request
    sendMessage(request);
  }
  
  void close() {
    reconnectTimer?.cancel();
    _channel?.sink.close();
  }
}
