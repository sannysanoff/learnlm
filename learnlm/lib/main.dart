import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:gpt_markdown/gpt_markdown.dart';

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

void main() {
  // Add error handling for Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log the error but don't crash the app
    print('Flutter error caught: ${details.exception}');
    // Still report to Flutter's console in debug mode
    FlutterError.dumpErrorToConsole(details);
  };
  
  // Handle async errors that aren't caught elsewhere
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    print('Uncaught platform error: $error');
    print(stack);
    return true; // Return true to indicate the error was handled
  };
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LearnLM Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const ConversationsPage(),
        '/chat': (context) => const ChatPage(title: 'LearnLM Chat'),
      },
    );
  }
}

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  List<ChatSummary> _chats = [];
  bool _isLoading = true;
  String? _userSecret;
  String _searchQuery = '';
  TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadUserSecret().then((_) {
      if (_userSecret != null) {
        _loadChats();
      }
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadUserSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final userSecret = prefs.getString('user_secret');
    if (userSecret != null && userSecret.isNotEmpty) {
      setState(() {
        _userSecret = userSecret;
      });
    }
  }
  
  Future<void> _saveUserSecret(String secret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_secret', secret);
    setState(() {
      _userSecret = secret;
    });
  }
  
  Future<void> _loadChats() async {
    if (_userSecret == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final chats = await ChatApiService.getChats(_userSecret!);
      setState(() {
        _chats = chats;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading chats: $e');
      setState(() {
        _isLoading = false;
      });
      
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load conversations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _promptForUserSecret() async {
    final userSecretController = TextEditingController();
    userSecretController.text = const Uuid().v4();
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Set User Secret'),
          content: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                const Text(
                  'A user secret is required to save and manage conversations. We\'ve generated one for you, but you can change it if you want.',
                ),
                TextField(
                  controller: userSecretController,
                  decoration: const InputDecoration(
                    hintText: 'Enter user secret',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (userSecretController.text.isNotEmpty) {
                  _saveUserSecret(userSecretController.text).then((_) {
                    _loadChats();
                  });
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _deleteChat(ChatSummary chat) async {
    if (_userSecret == null) return;
    
    try {
      final success = await ChatApiService.deleteChat(chat.id, _userSecret!);
      if (success) {
        setState(() {
          _chats.removeWhere((c) => c.id == chat.id);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conversation deleted'),
            ),
          );
        }
      }
    } catch (e) {
      print('Error deleting chat: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete conversation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  List<ChatSummary> get filteredChats {
    if (_searchQuery.isEmpty) {
      return _chats;
    }
    
    return _chats.where((chat) => 
      chat.title.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }
  
  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChats,
            tooltip: 'Refresh conversations',
          ),
        ],
      ),
      body: _userSecret == null 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Set up a user secret to view your conversations.'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _promptForUserSecret,
                  child: const Text('Set User Secret'),
                ),
              ],
            ),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search conversations',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                    suffixIcon: _searchQuery.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : filteredChats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('No conversations found'),
                            const SizedBox(height: 16),
                            if (_searchQuery.isNotEmpty)
                              OutlinedButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                                child: const Text('Clear search'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredChats.length,
                        itemBuilder: (context, index) {
                          final chat = filteredChats[index];
                          final createdAt = chat.createdAtDateTime;
                          final updatedAt = chat.updatedAtDateTime;
                          
                          return Dismissible(
                            key: Key('chat-${chat.id}'),
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16.0),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (direction) async {
                              return await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text("Confirm"),
                                    content: Text(
                                      "Are you sure you want to delete '${chat.title}'?",
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text("Cancel"),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: const Text(
                                          "Delete",
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            onDismissed: (direction) {
                              _deleteChat(chat);
                            },
                            child: ListTile(
                              title: Text(
                                chat.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Created: ${dateFormat.format(createdAt)} at ${timeFormat.format(createdAt)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    'Updated: ${dateFormat.format(updatedAt)} at ${timeFormat.format(updatedAt)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: const Text("Confirm"),
                                            content: Text(
                                              "Are you sure you want to delete '${chat.title}'?",
                                            ),
                                            actions: <Widget>[
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(false),
                                                child: const Text("Cancel"),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop(true);
                                                  _deleteChat(chat);
                                                },
                                                child: const Text(
                                                  "Delete",
                                                  style: TextStyle(color: Colors.red),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/chat',
                                  arguments: {'chatId': chat.id, 'title': chat.title},
                                ).then((_) {
                                  // Refresh the list when returning from chat
                                  _loadChats();
                                });
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
      floatingActionButton: _userSecret != null ? FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/chat',
          ).then((_) {
            // Refresh the list when returning from chat
            _loadChats();
          });
        },
        label: const Text('New Chat'),
        icon: const Icon(Icons.add),
      ) : null,
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.title});

  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isProcessing = false;
  String _currentResponse = "";
  DateTime? _startResponseTime;
  
  // Bottom scroll control
  bool _isAtBottom = true;
  bool _shouldAutoScroll = true;
  bool _stickyScroll = false;
  
  // Chat management properties
  String? _userSecret;
  String _conversationTitle = "";
  int? _chatId;
  bool _isFirstMessage = true;
  final _userSecretController = TextEditingController();
  bool _isLoadingExistingChat = false;

  @override
  void initState() {
    super.initState();
    _loadUserSecret();
    _connectToServer();
    
    // Initialize scroll controller and listener
    _scrollController.addListener(_onScroll);
    
    // Focus the text field when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForExistingChat();
      _focusNode.requestFocus();
    });
  }
  
  void _onScroll() {
    // Check if we're at the bottom of the scroll view
    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;
    final atBottom = currentScroll >= maxScroll - 50; // Within 50 pixels of bottom
    
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        // If user manually scrolled to the bottom, turn auto-scroll back on
        if (atBottom && !_stickyScroll) {
          _shouldAutoScroll = true;
        }
      });
    }
  }
  
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  void _checkForExistingChat() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map<String, dynamic>) {
      final chatId = args['chatId'];
      final title = args['title'];
      
      if (chatId != null && title != null) {
        setState(() {
          _chatId = chatId;
          _conversationTitle = title;
          _isFirstMessage = false;
        });
        
        // Load existing chat
        _loadExistingChat(chatId);
      }
    }
  }
  
  Future<void> _loadExistingChat(int chatId) async {
    if (_userSecret == null) {
      await _loadUserSecret();
      if (_userSecret == null) {
        await _promptForUserSecret();
      }
    }
    
    if (_userSecret == null) return;
    
    setState(() {
      _isLoadingExistingChat = true;
    });
    
    try {
      final chatData = await ChatApiService.getChat(chatId, _userSecret!);
      
      // Debug: Print raw response from server
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
      
      final List<dynamic> messagesData = chatData['messages'];
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
      print("\n=== SORTING MESSAGES ===");
      final hasTimestamps = messagesData.isNotEmpty && messagesData[0].containsKey('timestamp');
      print("Has timestamps: $hasTimestamps");
      
      if (hasTimestamps) {
        print("Sorting ${userMessages.length + assistantMessages.length} messages by timestamp");
        
        // Sort all messages by timestamp
        final allMessages = [...userMessages, ...assistantMessages];
        allMessages.sort((a, b) {
          if (a.timestamp == null && b.timestamp == null) {
            print("Both messages have null timestamps - keeping original order");
            return 0;
          }
          if (a.timestamp == null) {
            print("First message has null timestamp - placing it first");
            return -1;
          }
          if (b.timestamp == null) {
            print("Second message has null timestamp - placing it first");
            return 1;
          }
          print("Comparing timestamps: ${a.timestamp} vs ${b.timestamp}");
          return a.timestamp!.compareTo(b.timestamp!);
        });
        
        print("Messages after sorting: ${allMessages.length}");
        loadedMessages.addAll(allMessages);
      } else {
        print("No timestamps available - using alternating order fallback");
        // Fallback to alternating order if timestamps aren't available
        int userIndex = 0;
        int assistantIndex = 0;
        
        while (userIndex < userMessages.length || assistantIndex < assistantMessages.length) {
          // Add user message if available
          if (userIndex < userMessages.length) {
            loadedMessages.add(userMessages[userIndex]);
            userIndex++;
          }
          
          // Add assistant message if available
          if (assistantIndex < assistantMessages.length) {
            loadedMessages.add(assistantMessages[assistantIndex]);
            assistantIndex++;
          }
        }
      }
      
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
      
      setState(() {
        _messages.clear();
        _messages.addAll(loadedMessages);
        _isLoadingExistingChat = false;
        _shouldAutoScroll = true;
        _stickyScroll = false;
      });
      
      // Scroll to bottom after loading messages
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      print('Error loading chat: $e');
      setState(() {
        _isLoadingExistingChat = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load conversation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadUserSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final userSecret = prefs.getString('user_secret');
    if (userSecret != null && userSecret.isNotEmpty) {
      setState(() {
        _userSecret = userSecret;
      });
    }
  }

  Future<void> _saveUserSecret(String secret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_secret', secret);
    setState(() {
      _userSecret = secret;
    });
  }

  String _generateDefaultTitle() {
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return 'Chat ${formatter.format(now)}';
  }

  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  void _connectToServer() {
    if (_isReconnecting) {
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
            
            if (responseData["status"] == "streaming") {
              // If this is the first chunk, record the start time
              if (_currentResponse.isEmpty && _startResponseTime == null) {
                _startResponseTime = DateTime.now();
              }
                
              setState(() {
                // Get the incoming chunk and log its size
                final String chunk = responseData["chunk"];
                print("Received chunk size: ${chunk.length} characters");
                
                // Debug the chunk's content if it's small
                if (chunk.length < 50) {
                  print("Chunk content: $chunk");
                } else {
                  print("Chunk preview: ${chunk.substring(0, 50)}...");
                }
                
                // Append the chunk to the full response
                _currentResponse += chunk;
                // Update the last message if it's from the assistant
                final now = DateTime.now().toUtc().toIso8601String();
                
                if (_messages.isNotEmpty && !_messages.last.isUser) {
                  // Preserve the original timestamp and other properties
                  final originalMsg = _messages.last;
                  _messages.last = ChatMessage(
                    text: _currentResponse,
                    isUser: false,
                    timestamp: originalMsg.timestamp ?? now,
                    generationDuration: originalMsg.generationDuration,
                  );
                } else {
                  _messages.add(ChatMessage(
                    text: _currentResponse,
                    isUser: false,
                    timestamp: now,
                  ));
                }
                
                // Keep focus on the text field during streaming
                _focusNode.requestFocus();
              });
              
              // Auto-scroll to bottom if enabled
              if (_shouldAutoScroll && !_stickyScroll) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });
              }
            } else if (responseData["status"] == "complete") {
              // Calculate the generation duration if we have a start time
              String? generationDuration;
              if (_startResponseTime != null) {
                final endTime = DateTime.now();
                final duration = endTime.difference(_startResponseTime!);
                generationDuration = '${duration.inSeconds}.${(duration.inMilliseconds % 1000) ~/ 100}s';
                
                // Update the last assistant message with the duration
                if (_messages.isNotEmpty && !_messages.last.isUser) {
                  final msg = _messages.last;
                  _messages.last = ChatMessage(
                    text: msg.text,
                    isUser: false,
                    timestamp: msg.timestamp,
                    generationDuration: generationDuration,
                  );
                }
              }
              
              setState(() {
                _isProcessing = false;
                _currentResponse = "";
                _startResponseTime = null; // Reset the start time
              });
              
              // Save or update the conversation on the server
              _saveConversation(_currentResponse);
              
              // Focus the text field after receiving a response
              _focusNode.requestFocus();
              
              // Reset reconnect attempts on successful communication
              _reconnectAttempts = 0;
            } else if (responseData["status"] == "error") {
              final now = DateTime.now().toUtc().toIso8601String();
              setState(() {
                _isProcessing = false;
                _currentResponse = "";
                _startResponseTime = null; // Reset the start time
                _messages.add(ChatMessage(
                  text: "Error: ${responseData["message"]}",
                  isUser: false,
                  isError: true,
                  timestamp: now,
                ));
              });
              // Also focus text field on error
              _focusNode.requestFocus();
            } else if (responseData["status"] == "saved") {
              // Handle saved conversation response
              if (responseData.containsKey("id")) {
                setState(() {
                  _chatId = responseData["id"];
                });
                print("Chat saved with ID: $_chatId");
              }
            } else if (responseData["status"] == "title_recommendation") {
              // Handle title recommendation
              if (responseData.containsKey("recommended_title") && 
                  responseData.containsKey("chat_id")) {
                final String recommendedTitle = responseData["recommended_title"];
                final int chatId = responseData["chat_id"];
                
                // Only apply if it's for our current chat and title is valid
                if (chatId == _chatId && recommendedTitle.isNotEmpty) {
                  setState(() {
                    _conversationTitle = recommendedTitle;
                  });
                  
                  // Update chat with the new title
                  _saveConversationWithTitle(recommendedTitle);
                  
                  print("Applied recommended title: $recommendedTitle");
                }
              }
            }
            
            setState(() {
              _isConnected = true;
            });
          } catch (e) {
            print("Error processing server message: $e");
          }
        },
        onError: (error) {
          print("WebSocket error: $error");
          setState(() {
            _isConnected = false;
            _isProcessing = false;
          });
          _showConnectionError();
          _scheduleReconnect();
        },
        onDone: () {
          print("WebSocket connection closed");
          setState(() {
            _isConnected = false;
            _isProcessing = false;
          });
          _scheduleReconnect();
        },
      );
      
      setState(() {
        _isConnected = true;
      });
    } catch (e) {
      print("Error connecting to WebSocket: $e");
      setState(() {
        _isConnected = false;
        _isProcessing = false;
      });
      _showConnectionError();
      _scheduleReconnect();
    }
  }
  
  void _scheduleReconnect() {
    if (_isReconnecting || !mounted) {
      return;
    }
    
    setState(() {
      _isReconnecting = true;
    });
    
    // Implement exponential backoff for reconnection attempts
    final backoffSeconds = _reconnectAttempts < 5 
        ? (1 << _reconnectAttempts) // 1, 2, 4, 8, 16 seconds
        : 30; // Max 30 seconds
    
    print("Scheduling reconnect in $backoffSeconds seconds (attempt ${_reconnectAttempts + 1})");
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
          _reconnectAttempts++;
        });
        _connectToServer();
      }
    });
  }
  
  @override
  void dispose() {
    _channel?.sink.close();
    _controller.dispose();
    _focusNode.dispose();
    _userSecretController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  void _showConnectionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to connect to the server'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _promptForUserSecret() async {
    if (_userSecret != null && _userSecret!.isNotEmpty) {
      return;
    }

    _userSecretController.text = const Uuid().v4();
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Set User Secret'),
          content: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                const Text(
                  'A user secret is required to save and manage conversations. We\'ve generated one for you, but you can change it if you want.',
                ),
                TextField(
                  controller: _userSecretController,
                  decoration: const InputDecoration(
                    hintText: 'Enter user secret',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (_userSecretController.text.isNotEmpty) {
                  _saveUserSecret(_userSecretController.text);
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }


  void _saveConversation(String assistantResponse) {
    if (_userSecret == null || _userSecret!.isEmpty) {
      print("No user secret available, cannot save conversation");
      return;
    }

    // Prepare history for the request
    final List<Map<String, dynamic>> messageHistory = [];
    
    for (var message in _messages) {
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
    
    if (_chatId != null) {
      // Update existing chat
      request = {
        "user_secret": _userSecret,
        "chat_id": _chatId,
        "title": _conversationTitle,
        "history": {
          "system_message": "You are a helpful AI assistant.",
          "messages": messageHistory,
        }
      };
    } else {
      // Create new chat
      request = {
        "user_secret": _userSecret,
        "title": _conversationTitle,
        "history": {
          "system_message": "You are a helpful AI assistant.",
          "messages": messageHistory,
        }
      };
    }
    
    // Send the save request
    _channel?.sink.add(jsonEncode({
      "command": "save_chat",
      "data": request
    }));
  }
  
  void _saveConversationWithTitle(String newTitle) {
    if (_userSecret == null || _userSecret!.isEmpty || _chatId == null) {
      print("Cannot update title: missing user secret or chat ID");
      return;
    }
    
    // Create request object for updating just the title
    final request = {
      "user_secret": _userSecret,
      "chat_id": _chatId,
      "title": newTitle,
      "history": {
        "system_message": "You are a helpful AI assistant.",
        "messages": [] // Empty messages since we're only updating the title
      }
    };
    
    // Send the save request
    _channel?.sink.add(jsonEncode({
      "command": "save_chat",
      "data": request
    }));
  }

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty || _isProcessing) return;
    
    final userMessage = _controller.text;
    
    // Check if user secret is set, if not prompt for it
    if (_userSecret == null || _userSecret!.isEmpty) {
      await _promptForUserSecret();
    }
    
    // For the first message, set default title without prompting
    if (_isFirstMessage) {
      setState(() {
        _conversationTitle = _generateDefaultTitle();
        _isFirstMessage = false;
      });
    }
    
    if (_channel != null && _isConnected) {
      // Get current timestamp
      final now = DateTime.now().toUtc().toIso8601String();
      
      // Add user message to chat
      setState(() {
        _messages.add(ChatMessage(
          text: userMessage,
          isUser: true,
          timestamp: now,
        ));
        _isProcessing = true;
        _currentResponse = "";
        
        // Always enable auto-scroll when user sends a message
        _shouldAutoScroll = true;
        _stickyScroll = false;
      });
      
      // Scroll to bottom after adding the message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      
      // Prepare history for the request
      final List<Map<String, dynamic>> messageHistory = [];
      
      for (var message in _messages) {
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
        "user_secret": _userSecret,
        "chat_id": _chatId,
        "title": _conversationTitle,
      };
      
      // Convert request to JSON with explicit UTF-8 encoding
      final jsonRequest = jsonEncode(request);
      
      // Debug outgoing request
      print("\n=== OUTGOING WEBSOCKET REQUEST ===");
      print("JSON length: ${jsonRequest.length}");
      print("Has Unicode: ${jsonRequest.codeUnits.any((unit) => unit > 127)}");
      print("============================\n");
      
      // Send the request with explicit UTF-8 encoding
      _channel!.sink.add(jsonRequest);
      
      // Record start time for generation duration calculation
      _startResponseTime = DateTime.now();
      
      // Add placeholder for assistant response with timestamp
      setState(() {
        _messages.add(ChatMessage(
          text: "",
          isUser: false,
          timestamp: DateTime.now().toUtc().toIso8601String(),
        ));
      });
      
      _controller.clear();
      
      // Keep focus on text field even during processing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    } else {
      _showConnectionError();
      // Try to reconnect
      _connectToServer();
    }
  }

  // This method is removed as it's now combined with the other dispose method below

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Row(
          children: [
            Expanded(
              child: Text(_conversationTitle.isNotEmpty 
                ? _conversationTitle 
                : widget.title
              ),
            ),
            if (_chatId != null) 
              Tooltip(
                message: "Chat ID: $_chatId",
                child: const Icon(Icons.check_circle, color: Colors.green),
              ),
          ],
        ),
        actions: [
          Tooltip(
            message: _isConnected 
              ? "Connected" 
              : _isReconnecting 
                ? "Reconnecting..." 
                : "Disconnected",
            child: _isReconnecting
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                )
              : Icon(
                  _isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.pop(context);
            },
            tooltip: 'Back to conversations',
          ),
        ],
      ),
      body: _isLoadingExistingChat
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading conversation...'),
              ],
            ),
          )
        : Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      itemCount: _messages.length,
                      padding: const EdgeInsets.all(8.0),
                      itemBuilder: (context, index) {
                        return _messages[index];
                      },
                    ),
                    // Bottom-bound checkbox
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(24),
                        color: Theme.of(context).colorScheme.surface,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            setState(() {
                              if (_isAtBottom) {
                                // Toggle sticky mode when already at bottom
                                _stickyScroll = !_stickyScroll;
                              } else {
                                // Scroll to bottom and enable auto-scroll
                                _shouldAutoScroll = true;
                                _scrollToBottom();
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: _shouldAutoScroll,
                                  onChanged: (value) {
                                    setState(() {
                                      _shouldAutoScroll = value ?? false;
                                      if (_shouldAutoScroll) {
                                        _scrollToBottom();
                                      } else {
                                        _stickyScroll = true; // Enable sticky mode when unchecking
                                      }
                                    });
                                  },
                                ),
                                const Text('Auto-scroll'),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1.0),
              Container(
                decoration: BoxDecoration(color: Theme.of(context).cardColor),
                child: _buildTextComposer(),
              ),
            ],
          ),
    );
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.primary),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Row(
          children: [
            Flexible(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: (_) => _sendMessage(),
                // Use key handling to add another way to send messages
                onEditingComplete: () {
                  // This provides another way to submit the form
                  if (!_isProcessing) {
                    _sendMessage();
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Send a message',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                // Keep the text field always enabled but handle input in the onChanged callback
                enabled: true,
                readOnly: _isProcessing, // Only make it read-only when processing
                // Add keyboard type to avoid some issues
                keyboardType: TextInputType.multiline,
              ),
            ),
            const SizedBox(width: 8.0),
            IconButton(
              icon: _isProcessing 
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
              onPressed: _isProcessing ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isError;
  final String? timestamp;
  final String? generationDuration;

  const ChatMessage({
    super.key,
    required this.text,
    required this.isUser,
    this.isError = false,
    this.timestamp,
    this.generationDuration,
  });
  
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'ChatMessage(isUser: $isUser, isError: $isError, text: ${text.substring(0, min(20, text.length))}...)';
  }
  
  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      // Format differently based on how old the message is
      if (difference.inDays > 0) {
        // More than a day old - show date and time
        return DateFormat('MMM d, h:mm a').format(date);
      } else if (difference.inHours > 0) {
        // Hours old
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        // Minutes old
        return '${difference.inMinutes}m ago';
      } else {
        // Just now
        return 'Just now';
      }
    } catch (e) {
      // If there's any parsing error, just return the raw timestamp
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUser) 
            const Spacer()
          else
            CircleAvatar(
              backgroundColor: isError 
                ? Colors.red.shade100 
                : Colors.blue.shade100,
              child: Icon(
                isError ? Icons.error : Icons.smart_toy,
                color: isError ? Colors.red : Colors.blue,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: isUser 
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                  : isError
                    ? Colors.red.shade50
                    : Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      text.isEmpty 
                        ? const Text("...")
                        : isUser
                          ? SelectionArea(
                              child: Text(
                                text,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            )
                          : isError
                            ? SelectionArea(
                                child: Text(
                                  text,
                                  style: const TextStyle(
                                    color: Colors.red,
                                  ),
                                ),
                              )
                            : SelectionArea(
                                child: GptMarkdown(
                                  text,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.secondary,
                                  ),
                                ),
                              ),
                  if (timestamp != null || generationDuration != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (timestamp != null)
                          Text(
                            _formatTimestamp(timestamp!),
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        if (timestamp != null && generationDuration != null)
                          Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        if (generationDuration != null)
                          Text(
                            '$generationDuration',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ],
                  ],
                  ),
                  // Copy button
                  if (text.isNotEmpty)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        icon: Icon(
                          Icons.copy,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: text)).then((_) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Message copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          });
                        },
                        tooltip: 'Copy message',
                        constraints: BoxConstraints.tightFor(width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        splashRadius: 16,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isUser) 
            const Spacer()
          else
            CircleAvatar(
              backgroundColor: Colors.green.shade100,
              child: const Icon(
                Icons.person,
                color: Colors.green,
              ),
            ),
        ],
      ),
    );
  }
}
