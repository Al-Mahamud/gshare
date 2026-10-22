import 'package:flutter/material.dart';

import '../services/app_services.dart';
import 'widgets.dart';

class TransfersTab extends StatelessWidget {
  const TransfersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final log = AppServices.I.log;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final sessions = log.sessions;
        if (sessions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Transfers you send or receive appear here.', textAlign: TextAlign.center),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: log.clearFinished, child: const Text('Clear finished')),
            ),
            for (final s in sessions) TransferTile(key: ValueKey(s.id), session: s),
          ],
        );
      },
    );
  }
}
