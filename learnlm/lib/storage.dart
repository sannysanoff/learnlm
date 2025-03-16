import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String userSecretKey = 'user_secret';

  // Load user secret from SharedPreferences
  static Future<String?> loadUserSecret() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(userSecretKey);
  }

  // Save user secret to SharedPreferences
  static Future<void> saveUserSecret(String secret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userSecretKey, secret);
  }
}
