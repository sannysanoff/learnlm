import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:intl/intl.dart';

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
      
      if (difference.inDays > 0) {
        return DateFormat('MMM d, h:mm a').format(date);
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
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
