import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/exceptions.dart';
import '../../core/services/offline_intake_queue.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validation/product_rules.dart';
import '../../data/repositories/seller_repository.dart';

/// UI for pieces that could not go live (SA-INT-001): a sheet listing every
/// piece that needs attention and an editor to fix code / title / size /
/// price or discard the piece. Fixed pieces are re-queued and synced again;
/// nothing here is retried automatically.

enum QueuedPieceAction { save, discard }

class QueuedPieceEdit {
  final QueuedPieceAction action;
  final String code;
  final String title;
  final String size;
  final int pricePaisa;

  const QueuedPieceEdit({
    required this.action,
    this.code = '',
    this.title = '',
    this.size = '',
    this.pricePaisa = 0,
  });
}

String queuedStatusLabel(IntakeQueueItem item) {
  switch (item.status) {
    case IntakeQueueStatus.needsAttention:
      return 'Needs attention';
    case IntakeQueueStatus.failed:
      return 'Retrying';
    case IntakeQueueStatus.completed:
      return 'Live';
    case IntakeQueueStatus.pending:
    case IntakeQueueStatus.uploading:
    case IntakeQueueStatus.uploaded:
      return 'Syncing';
  }
}

/// Opens the editor for [item] and applies the result to [queue].
Future<void> fixQueuedPiece(
  BuildContext context, {
  required OfflineIntakeQueue queue,
  required SellerRepository repository,
  required IntakeQueueItem item,
  Iterable<String> otherCodesInDrop = const [],
}) async {
  final result = await showDialog<QueuedPieceEdit>(
    context: context,
    builder: (_) => QueuedPieceEditorDialog(item: item, otherCodesInDrop: otherCodesInDrop),
  );
  if (result == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  if (result.action == QueuedPieceAction.discard) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: Text('Discard ${item.code}?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'The photos saved on this phone are deleted and this piece will not be listed.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.crimson,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard piece'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await queue.discardItem(item.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(removed
            ? 'Discarded ${item.code}.'
            : '${item.code} is uploading right now — try again in a moment.'),
        backgroundColor: removed ? AppColors.obsidianElevated : AppColors.crimson,
      ),
    );
    return;
  }

  try {
    final updated = await queue.updateItem(
      item.id,
      code: result.code,
      title: result.title,
      pricePaisa: result.pricePaisa,
      size: result.size,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved — ${updated.code} is syncing again.'),
        backgroundColor: AppColors.emerald,
      ),
    );
    unawaited(queue.processQueue(repository));
  } on LiveDropException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(e.message), backgroundColor: AppColors.crimson),
    );
  }
}

/// Bottom sheet listing every piece that needs attention, reachable from the
/// inventory banner.
Future<void> showPiecesNeedingAttention(
  BuildContext context, {
  required OfflineIntakeQueue queue,
  required SellerRepository repository,
  Iterable<String> Function(IntakeQueueItem item)? otherCodesFor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.obsidianSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return ValueListenableBuilder<int>(
        valueListenable: queue.changes,
        builder: (context, _, _) {
          final items = queue.items
              .where((i) => i.status == IntakeQueueStatus.needsAttention)
              .toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      items.isEmpty
                          ? 'Nothing needs attention'
                          : 'Fix ${items.length} ${items.length == 1 ? 'piece' : 'pieces'} before they go live',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'These pieces are saved on this phone but buyers cannot see them yet.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final item in items)
                            _AttentionTile(
                              item: item,
                              onEdit: () => fixQueuedPiece(
                                context,
                                queue: queue,
                                repository: repository,
                                item: item,
                                otherCodesInDrop: otherCodesFor?.call(item) ?? const [],
                              ),
                              onRetry: () => queue.retryItem(item.id, repository),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _AttentionTile extends StatelessWidget {
  final IntakeQueueItem item;
  final VoidCallback onEdit;
  final VoidCallback onRetry;

  const _AttentionTile({required this.item, required this.onEdit, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(
        backgroundColor: AppColors.obsidianElevated,
        borderColor: AppColors.crimson.withValues(alpha: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                item.code.isEmpty ? '(no code)' : item.code,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.attentionReason ?? 'The server rejected this piece.',
            style: const TextStyle(fontSize: 12, color: AppColors.crimson, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onRetry,
                child: const Text('Try again', style: TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldPrimary,
                  foregroundColor: Colors.black,
                ),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Fix piece'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Editor for a piece that has not gone live. Validates inline with
/// [ProductRules] and blocks saving invalid input.
class QueuedPieceEditorDialog extends StatefulWidget {
  final IntakeQueueItem item;
  final Iterable<String> otherCodesInDrop;

  const QueuedPieceEditorDialog({
    super.key,
    required this.item,
    this.otherCodesInDrop = const [],
  });

  @override
  State<QueuedPieceEditorDialog> createState() => _QueuedPieceEditorDialogState();
}

class _QueuedPieceEditorDialogState extends State<QueuedPieceEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _titleController;
  late final TextEditingController _sizeController;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.item.code);
    _titleController = TextEditingController(text: widget.item.title);
    _sizeController = TextEditingController(text: widget.item.size);
    _priceController = TextEditingController(
      text: widget.item.pricePaisa > 0 ? (widget.item.pricePaisa ~/ 100).toString() : '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _sizeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String? _validateCode(String? value) {
    return ProductRules.validateCode(value ?? '') ??
        ProductRules.validateCodeUnique(value ?? '', widget.otherCodesInDrop);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      QueuedPieceEdit(
        action: QueuedPieceAction.save,
        code: ProductRules.normalizeCode(_codeController.text),
        title: _titleController.text.trim(),
        size: _sizeController.text.trim(),
        pricePaisa: ProductRules.parseRupeesToPaisa(_priceController.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reason = widget.item.attentionReason;
    return AlertDialog(
      backgroundColor: AppColors.obsidianSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      title: Text(
        'Fix ${widget.item.code.isEmpty ? 'piece' : widget.item.code}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.always,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null) ...[
                Text(
                  reason,
                  style: const TextStyle(fontSize: 12, color: AppColors.crimson, height: 1.35),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                key: const ValueKey('queued-piece-code'),
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Code',
                  helperText: '# and 1–6 letters or digits, e.g. #A01',
                ),
                validator: _validateCode,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('queued-piece-title'),
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => ProductRules.validateTitle(value ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('queued-piece-size'),
                controller: _sizeController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Size'),
                validator: (value) => ProductRules.validateSize(value ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('queued-piece-price'),
                controller: _priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Price (₹ INR)'),
                validator: (value) => ProductRules.validatePriceRupees(value ?? ''),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const QueuedPieceEdit(action: QueuedPieceAction.discard),
          ),
          child: const Text('Discard', style: TextStyle(color: AppColors.crimson)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.goldPrimary,
            foregroundColor: Colors.black,
          ),
          onPressed: _save,
          child: const Text('Save & sync'),
        ),
      ],
    );
  }
}
