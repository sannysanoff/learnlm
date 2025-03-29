import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../network.dart';
import '../storage.dart';
import '../components/chat_message.dart';

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
  WebSocketService _webSocketService = WebSocketService();
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
    _setupWebSocketService();
    
    // Initialize scroll controller and listener
    _scrollController.addListener(_onScroll);
    
    // Focus the text field when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForExistingChat();
      _focusNode.requestFocus();
    });
  }
  
  void _setupWebSocketService() {
    _webSocketService.onMessageReceived = _handleWebSocketMessage;
    _webSocketService.onError = (error) {
      print("WebSocket error in UI: $error");
      setState(() {
        _isProcessing = false;
      });
      _showConnectionError();
    };
    _webSocketService.onDisconnected = () {
      setState(() {
        _isProcessing = false;
      });
    };
    _webSocketService.connect();
  }
  
  void _handleWebSocketMessage(Map<String, dynamic> responseData) {
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
      
      // Server handles saving automatically after completion.
      // _saveConversation(); // Removed redundant call
      
      // Focus the text field after receiving a response
      _focusNode.requestFocus();
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
          _updateConversationTitle(recommendedTitle);
          
          print("Applied recommended title: $recommendedTitle");
        }
      }
    }
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
      
      // Debug raw response from server
      JsonUtils.debugRawServerResponse(chatData);
      
      // Process chat messages data
      final List<dynamic> messagesData = chatData['messages'];
      final List<ChatMessage> loadedMessages = JsonUtils.processChatMessages(messagesData);
      
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
    final userSecret = await StorageService.loadUserSecret();
    if (userSecret != null && userSecret.isNotEmpty) {
      setState(() {
        _userSecret = userSecret;
      });
    }
  }

  Future<void> _saveUserSecret(String secret) async {
    await StorageService.saveUserSecret(secret);
    setState(() {
      _userSecret = secret;
    });
  }

  String _generateDefaultTitle() {
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return 'Chat ${formatter.format(now)}';
  }

  
  @override
  void dispose() {
    _webSocketService.close();
    _controller.dispose();
    _focusNode.dispose();
    _userSecretController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  // _saveConversation method removed as it's redundant. Server handles saving automatically.
  
  void _updateConversationTitle(String newTitle) {
    if (_userSecret == null || _userSecret!.isEmpty || _chatId == null) {
      print("Cannot update title: missing user secret or chat ID");
      return;
    }
    
    try {
      _webSocketService.updateChatTitle(_userSecret!, _chatId!, newTitle);
    } catch (e) {
      print("Error updating conversation title: $e");
    }
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
    
    if (_webSocketService.isConnected) {
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
      
      try {
        // Send chat request via WebSocket service
        _webSocketService.sendChatRequest(
          _userSecret!, 
          _messages, 
          _conversationTitle, 
          _chatId
        );
        
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
      } catch (e) {
        print("Error sending message: $e");
        setState(() {
          _isProcessing = false;
        });
        _showConnectionError();
      }
    } else {
      _showConnectionError();
      // Try to reconnect
      _webSocketService.connect();
    }
  }

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
            message: _webSocketService.isConnected 
              ? "Connected" 
              : _webSocketService.isReconnecting 
                ? "Reconnecting..." 
                : "Disconnected",
            child: _webSocketService.isReconnecting
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                )
              : Icon(
                  _webSocketService.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _webSocketService.isConnected ? Colors.green : Colors.red,
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
