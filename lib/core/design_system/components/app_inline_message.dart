import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_tokens.dart';

enum AppInlineMessageTone { error, warning, info }

final class AppInlineMessage extends StatelessWidget {
  const AppInlineMessage({
    required this.message,
    this.tone = AppInlineMessageTone.error,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final AppInlineMessageTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (tone) {
      AppInlineMessageTone.error => (
        AppColors.danger,
        AppColors.danger.withValues(alpha: 0.10),
      ),
      AppInlineMessageTone.warning => (
        AppColors.warning,
        AppColors.warning.withValues(alpha: 0.10),
      ),
      AppInlineMessageTone.info => (AppColors.sage, AppColors.sageSoft),
    };
    final icon = switch (tone) {
      AppInlineMessageTone.error => Icons.error_outline_rounded,
      AppInlineMessageTone.warning => Icons.warning_amber_rounded,
      AppInlineMessageTone.info => Icons.info_outline_rounded,
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: foreground.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final messageRow = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
            final hasAction = actionLabel != null && onAction != null;
            if (!hasAction) return messageRow;
            final action = TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: foreground),
              child: Text(actionLabel!),
            );
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  messageRow,
                  const SizedBox(height: AppSpacing.xxs),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: messageRow),
                const SizedBox(width: AppSpacing.sm),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}
