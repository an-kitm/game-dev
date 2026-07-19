import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'nickname_provider.dart';

/// First-run screen: pick a display name. Anonymous auth has already happened
/// in `main()`, so this only captures a human-readable nickname.
class NicknameScreen extends ConsumerStatefulWidget {
  const NicknameScreen({super.key});

  @override
  ConsumerState<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends ConsumerState<NicknameScreen> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(nicknameProvider.notifier).set(name);
    // go_router redirect will move us to /home automatically.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CanvasBackground(
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Wordmark(eyebrow: 'Pick a name to play with'),
                const SizedBox(height: 32),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 16,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'e.g. Ankit',
                  ),
                  onSubmitted: (_) => _continue(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _continue,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
