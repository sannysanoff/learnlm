import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';

// Re-export ChatMessage for backward compatibility
export 'components/chat_message.dart';

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
  static const String baseUrl = 'http://achtung:8035';
  
  // Get all chats for a user
  static Future<List<ChatSummary>> getChats(String userSecret) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/chats?user_secret=$userSecret'),
    );
    
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
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
      // Hardcoded hostname and port for desktop
      final uri = Uri.parse('ws://achtung:8035/api/chat/completion/stream');
      _channel = WebSocketChannel.connect(uri);
      
      _channel!.stream.listen(
        (data) {
          try {
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
              data = decoded;
            }
            print("=========================\n");
            
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
      print("\n=== OUTGOING WEBSOCKET REQUEST ===");
      print("JSON length: ${jsonRequest.length}");
      print("Has Unicode: ${jsonRequest.codeUnits.any((unit) => unit > 127)}");
      print("============================\n");
      
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
        "messages": messageHistory.map((msg) => {
          "role": msg["role"],
          "parts": [{"text": msg["content"]}]
        }).toList(),
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
