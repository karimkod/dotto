import 'package:flutter/material.dart';

import '../feedback/feedback.dart';
import '../feedback/feedback_store.dart';
import '../theme/app_theme.dart';

/// A quick OK / KO feedback dialog. OK is a two-tap flow; KO reveals a comment
/// field. Includes an "Export" action to download all feedback as JSON.
class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key, required this.level});

  final int level;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  bool _ko = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(String status, String comment) {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    FeedbackStore.add(FeedbackEntry(
      level: widget.level,
      status: status,
      comment: comment,
      timestamp: DateTime.now().toUtc().toIso8601String(),
    ));
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Thanks for the feedback!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.ink, width: 3),
      ),
      title: Text(
        'Level ${widget.level} — Feedback',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          fontSize: 18,
        ),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_ko) ...[
              const Text('How was this level?',
                  style: TextStyle(color: AppColors.textSoft)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _choice('✅  OK', const Color(0xFF66BB6A),
                        () => _save('ok', '')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _choice('❌  KO', AppColors.coral,
                        () => setState(() => _ko = true)),
                  ),
                ],
              ),
            ] else ...[
              const Text("What didn't work?",
                  style: TextStyle(color: AppColors.textSoft)),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => _save('ko', v.trim()),
                decoration: InputDecoration(
                  hintText: 'e.g. ball movement too fast',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _choice('Submit', AppColors.coral,
                  () => _save('ko', _controller.text.trim())),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        TextButton(
          onPressed: FeedbackStore.exportJson,
          child: const Text('Export all (JSON)',
              style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
              style: TextStyle(color: AppColors.textSoft)),
        ),
      ],
    );
  }

  Widget _choice(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ink, width: 2.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
