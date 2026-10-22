import 'package:flutter/foundation.dart';

import '../core/models.dart';

/// All transfers of this app run, newest first. In memory only for now.
class TransferLog extends ChangeNotifier {
  final List<TransferSession> _sessions = [];

  List<TransferSession> get sessions => List.unmodifiable(_sessions);
  int get activeCount => _sessions.where((s) => s.isActive).length;

  void add(TransferSession session) {
    _sessions.insert(0, session);
    session.addListener(notifyListeners);
    notifyListeners();
  }

  void clearFinished() {
    _sessions.removeWhere((s) {
      final finished = !s.isActive;
      if (finished) s.removeListener(notifyListeners);
      return finished;
    });
    notifyListeners();
  }
}
