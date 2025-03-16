import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pages/conversations_page.dart';
import 'pages/chat_page.dart';

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
