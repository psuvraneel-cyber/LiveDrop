import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/validation/product_rules.dart';

/// Code / title / price fields of the camera intake sheet (SA-INT-001).
///
/// Must sit inside a [Form]: every field validates inline with
/// [ProductRules], and the sheet only saves when `Form.validate()` passes, so
/// an invalid piece is never queued.
class IntakeDraftFields extends StatelessWidget {
  final TextEditingController codeController;
  final TextEditingController titleController;
  final TextEditingController priceController;

  /// Codes already used in the drop (server products + queued pieces).
  final Iterable<String> Function() existingCodes;
  final ValueChanged<String>? onCodeChanged;

  const IntakeDraftFields({
    super.key,
    required this.codeController,
    required this.titleController,
    required this.priceController,
    required this.existingCodes,
    this.onCodeChanged,
  });

  String? _validateCode(String? value) {
    return ProductRules.validateCode(value ?? '') ??
        ProductRules.validateCodeUnique(value ?? '', existingCodes());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('intake-code-field'),
          controller: codeController,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            labelText: 'Code',
            helperText: '# and 1–6 letters or digits, e.g. #A01',
            errorMaxLines: 2,
          ),
          validator: _validateCode,
          onChanged: onCodeChanged,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('intake-title-field'),
          controller: titleController,
          style: const TextStyle(color: AppColors.textPrimary),
          maxLength: ProductRules.maxTitleLength,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          decoration: const InputDecoration(
            labelText: 'Item Title',
            hintText: 'e.g. Banarasi Silk Saree',
            errorMaxLines: 2,
          ),
          validator: (value) => ProductRules.validateTitle(value ?? ''),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('intake-price-field'),
          controller: priceController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            prefixText: '₹ ',
            prefixStyle: TextStyle(
              color: AppColors.emerald,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            labelText: 'Price (₹ INR)',
          ),
          validator: (value) => ProductRules.validatePriceRupees(value ?? ''),
        ),
      ],
    );
  }
}
