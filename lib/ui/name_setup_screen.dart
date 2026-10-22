import 'package:flutter/material.dart';

import '../services/app_services.dart';

/// First launch: the user picks the name other devices will see. The app stays here until one is set.
class NameSetupScreen extends StatefulWidget {
  const NameSetupScreen({super.key});

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  bool get _valid => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final s = AppServices.I;
    // Settings notifies listeners, which swaps this screen for the home screen.
    await s.settings.setDeviceName(_controller.text);
    await s.discovery.restartAdvertising();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Image(image: AssetImage('assets/logo.png'), width: 96, height: 96),
                  const SizedBox(height: 24),
                  Text('Welcome to gshare', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Choose your name. People nearby see it when they send you files or receive files from you.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      hintText: 'e.g. Rahim',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _valid && !_saving ? _save : null,
                      child: const Text('Continue'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('You can change it later in Settings.', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
