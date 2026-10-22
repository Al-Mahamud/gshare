import 'package:flutter/foundation.dart';

import '../core/models.dart';

/// Items the user has picked to send.
class SendSelection extends ChangeNotifier {
  final List<TransferItem> _items = [];

  List<TransferItem> get items => List.unmodifiable(_items);
  int get totalBytes => _items.fold<int>(0, (s, i) => s + i.size);

  Future<void> addPaths(Iterable<String> paths) async {
    for (final path in paths) {
      if (_items.any((i) => i.path == path)) continue;
      try {
        _items.add(await TransferItem.fromFile(path));
      } catch (_) {}
    }
    notifyListeners();
  }

  void addText(String text) {
    if (text.trim().isEmpty) return;
    _items.add(TransferItem.text(text));
    notifyListeners();
  }

  void remove(TransferItem item) {
    _items.remove(item);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
