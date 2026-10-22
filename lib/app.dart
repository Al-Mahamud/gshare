import 'package:flutter/material.dart';

import 'services/app_services.dart';
import 'ui/home_screen.dart';
import 'ui/name_setup_screen.dart';

class GshareApp extends StatefulWidget {
  const GshareApp({super.key});

  @override
  State<GshareApp> createState() => _GshareAppState();
}

class _GshareAppState extends State<GshareApp> {
  late Future<void> _init = AppServices.init();

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0E7C86);
    return MaterialApp(
      title: 'gshare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
      home: FutureBuilder<void>(
        future: _init,
        builder: (context, snap) {
          if (snap.hasError) {
            return _StartupError(
              error: snap.error!,
              onRetry: () => setState(() => _init = AppServices.init()),
            );
          }
          if (snap.connectionState != ConnectionState.done) return const _Splash();
          final settings = AppServices.I.settings;
          return ListenableBuilder(
            listenable: settings,
            builder: (context, _) => settings.hasChosenName ? const HomeScreen() : const NameSetupScreen(),
          );
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(image: AssetImage('assets/logo.png'), width: 120, height: 120),
            SizedBox(height: 32),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Preparing secure identity…'),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('gshare could not start'),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
