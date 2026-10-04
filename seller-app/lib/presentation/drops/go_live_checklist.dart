import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/env_config.dart';
import '../../core/services/offline_intake_queue.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/models.dart';

/// One line of the go-live checklist.
class GoLiveCheck {
  final String label;
  final String detail;

  /// A blocking check stops the drop from going live until it passes.
  final bool blocking;
  final bool passed;

  const GoLiveCheck({
    required this.label,
    required this.detail,
    required this.passed,
    this.blocking = true,
  });
}

/// Readiness of a draft drop before it goes live (SA-DROP-004, ADR-006).
class GoLiveReadiness {
  final List<GoLiveCheck> checks;

  const GoLiveReadiness(this.checks);

  bool get canGoLive => checks.every((c) => c.passed || !c.blocking);

  /// Builds the checklist from what the app already knows.
  ///
  /// Blocking: at least one piece on sale, no piece of this drop still in the
  /// intake queue (ADR-006), UPI turned on with a payee UPI ID (checkout
  /// refuses otherwise, migration 039), no other live drop.
  /// Warning only: no stream link.
  static GoLiveReadiness evaluate({
    required SellerDrop drop,
    required List<SellerProduct> products,
    required List<IntakeQueueItem> queuedItems,
    required SellerProfile? profile,
    required List<SellerDrop> allDrops,
  }) {
    final onSale = products.where((p) => p.status == ProductStatus.available).length;
    final queued = queuedItems
        .where((i) => i.dropId == drop.id && i.status != IntakeQueueStatus.completed)
        .toList();
    final needsAttention = queued.where((i) => i.status == IntakeQueueStatus.needsAttention).length;
    final upiOn = profile != null && profile.upiEnabled;
    final vpa = (profile?.upiVpa ?? profile?.upiId ?? '').trim();
    final otherLive = allDrops.where((d) => d.id != drop.id && d.status == DropStatus.live).firstOrNull;
    final hasStream = (drop.streamUrl ?? '').trim().isNotEmpty;

    return GoLiveReadiness([
      GoLiveCheck(
        label: onSale == 1 ? '1 piece on sale' : '$onSale pieces on sale',
        detail: onSale == 0 ? 'Add at least one piece before going live.' : 'Buyers will see these pieces.',
        passed: onSale > 0,
      ),
      GoLiveCheck(
        label: queued.isEmpty ? 'All photos uploaded' : '${queued.length} still uploading',
        detail: queued.isEmpty
            ? 'Every piece from the camera is saved.'
            : needsAttention > 0
                ? '$needsAttention need your attention in Products. Fix or discard them first.'
                : 'Wait until every piece is uploaded, so buyers see the whole collection.',
        passed: queued.isEmpty,
      ),
      GoLiveCheck(
        label: upiOn && vpa.isNotEmpty ? 'UPI payments on ($vpa)' : 'UPI payments are off',
        detail: upiOn && vpa.isNotEmpty
            ? 'Buyers pay to this UPI ID.'
            : 'Turn on UPI and add your UPI ID in Payment settings. Buyers cannot order without it.',
        passed: upiOn && vpa.isNotEmpty,
      ),
      GoLiveCheck(
        label: otherLive == null ? 'No other live drop' : '"${otherLive.title}" is still live',
        detail: otherLive == null ? 'Only one drop can be live at a time.' : 'Close it before going live.',
        passed: otherLive == null,
      ),
      GoLiveCheck(
        label: hasStream ? 'Stream link added' : 'No stream link',
        detail: hasStream
            ? 'Buyers can open your live stream from the drop page.'
            : 'Optional: add your Instagram or YouTube live link so buyers can watch.',
        passed: hasStream,
        blocking: false,
      ),
    ]);
  }
}

/// Bottom sheet shown when the seller taps "Go Live". Returns `true` when the
/// seller confirms and every blocking check passed.
Future<bool> showGoLiveChecklist(BuildContext context, SellerDrop drop, GoLiveReadiness readiness) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.obsidianSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final link = EnvConfig.getDropUrl(drop.slug);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ready to go live with "${drop.title}"?',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final check in readiness.checks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    check.passed
                        ? Icons.check_circle_rounded
                        : check.blocking
                            ? Icons.cancel_rounded
                            : Icons.info_outline_rounded,
                    color: check.passed
                        ? AppColors.emerald
                        : check.blocking
                            ? AppColors.crimson
                            : AppColors.goldPrimary,
                  ),
                  title: Text(check.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(check.detail, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      link,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: link)),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Once live, the drop link cannot be changed, and a closed drop cannot be reopened.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Not yet'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('go-live-confirm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: readiness.canGoLive ? () => Navigator.of(ctx).pop(true) : null,
                      child: Text(readiness.canGoLive ? 'Go Live' : 'Fix the items above'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
