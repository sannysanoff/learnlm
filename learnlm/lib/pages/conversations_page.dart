import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network.dart';
import '../storage.dart';

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
              // Informational card about LearnLM
              Card(
                margin: const EdgeInsets.all(8.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About LearnLM',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'LearnLM is an educational model, NOT a general-purpose LLM. It\'s designed to help you learn.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('📚 TIP: Ask it to teach you about specific topics.'),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          const url = 'https://github.com/sannysanoff/learnlm';
                          if (await canLaunch(url)) {
                            await launch(url);
                          }
                        },
                        child: const Text(
                          'GitHub Repository: https://github.com/sannysanoff/learnlm',
                          style: TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
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
