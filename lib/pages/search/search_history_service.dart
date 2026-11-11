import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SearchHistoryStore {
  Future<List<String>> load();
  Future<void> save(List<String> history);
}

class SecureSearchHistoryStore implements SearchHistoryStore {
  static const String _storageKey = 'plexus_search_history';

  const SecureSearchHistoryStore();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<List<String>> load() async {
    final storedHistory = await _storage.read(key: _storageKey);
    if (storedHistory == null || storedHistory.isEmpty) return const [];

    final decoded = jsonDecode(storedHistory);
    if (decoded is! List) {
      throw const FormatException('搜索历史存储格式无效');
    }
    return decoded
        .whereType<String>()
        .where((query) => query.trim().isNotEmpty)
        .toList();
  }

  @override
  Future<void> save(List<String> history) =>
      _storage.write(key: _storageKey, value: jsonEncode(history));
}
