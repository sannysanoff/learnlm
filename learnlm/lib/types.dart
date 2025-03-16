import 'package:flutter/material.dart';

// Re-export ChatMessage from components for backward compatibility
export 'components/chat_message.dart';

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
