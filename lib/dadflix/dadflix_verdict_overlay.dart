import 'package:flutter/material.dart';

/// dadflix: film sonunda "Nasıldı?" overlay'i. Kök olarak [Positioned]
/// döndürür (skip_segment_overlay / next_up_overlay kalıbı). Sol-alt köşe
/// kullanılır ki dizi senaryosunda sağ-alttaki Next Up ile çakışmasın.
class DadflixVerdictOverlay extends StatelessWidget {
  final String title;
  final VoidCallback onThumbsUp;
  final VoidCallback onThumbsDown;
  final VoidCallback onDismiss;

  const DadflixVerdictOverlay({
    super.key,
    required this.title,
    required this.onThumbsUp,
    required this.onThumbsDown,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      bottom: 120,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nasıldı?',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _VerdictButton(
                    icon: Icons.thumb_up_rounded,
                    label: 'Beğendim',
                    autofocus: true,
                    onPressed: onThumbsUp,
                  ),
                  const SizedBox(width: 8),
                  _VerdictButton(
                    icon: Icons.thumb_down_rounded,
                    label: 'Olmadı',
                    onPressed: onThumbsDown,
                  ),
                  const Spacer(),
                  _VerdictButton(
                    icon: Icons.close_rounded,
                    label: '',
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerdictButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool autofocus;
  final VoidCallback onPressed;

  const _VerdictButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      autofocus: autofocus,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: label.isEmpty ? const SizedBox.shrink() : Text(label),
    );
  }
}
