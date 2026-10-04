import 'package:flutter/material.dart';

import '../../core/errors/exceptions.dart';
import '../../core/theme/app_colors.dart';

/// Asks the seller to type their password before a sensitive change, such as
/// the UPI ID buyers pay to or the phone number buyers contact (SA-AUTH-004).
///
/// [reauthenticate] signs in again with the password; the fresh session lets
/// the database accept the change. Returns `true` once the password was
/// confirmed, `false` when the seller cancels.
Future<bool> showConfirmPasswordDialog(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function(String password) reauthenticate,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConfirmPasswordDialog(
      title: title,
      message: message,
      reauthenticate: reauthenticate,
    ),
  );
  return result == true;
}

class _ConfirmPasswordDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<void> Function(String password) reauthenticate;

  const _ConfirmPasswordDialog({
    required this.title,
    required this.message,
    required this.reauthenticate,
  });

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.reauthenticate(password);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is LiveDropException ? e.message : 'Could not check your password. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.obsidianElevated,
      title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('confirm-password-field'),
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            enabled: !_busy,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: 'Your LiveDrop password',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('confirm-password-submit'),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Confirm'),
        ),
      ],
    );
  }
}
