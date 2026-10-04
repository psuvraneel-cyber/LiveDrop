import 'package:flutter/material.dart';
import '../../core/errors/exceptions.dart';
import '../../core/validation/free_shipping_rules.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';

/// LiveDrop Seller Mobile App — Create / Edit Drop Screen
class CreateDropScreen extends StatefulWidget {
  final SellerRepository repository;
  final SellerProfile? profile;
  final SellerDrop? existingDrop;

  const CreateDropScreen({
    super.key,
    required this.repository,
    this.profile,
    this.existingDrop,
  });

  @override
  State<CreateDropScreen> createState() => _CreateDropScreenState();
}

class _CreateDropScreenState extends State<CreateDropScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _slugController;
  late TextEditingController _shippingFeeController;
  late TextEditingController _freeShippingThresholdController;
  late TextEditingController _streamUrlController;
  bool _isLoading = false;
  bool _autoSlug = true;
  SellerProfile? _profile;

  bool get _isEditing => widget.existingDrop != null;

  @override
  void initState() {
    super.initState();
    final drop = widget.existingDrop;
    final profile = widget.profile;

    _titleController = TextEditingController(text: drop?.title ?? '');
    _slugController = TextEditingController(text: drop?.slug ?? '');
    _streamUrlController = TextEditingController(text: drop?.streamUrl ?? '');

    final defaultShipping = (drop?.shippingFeePaisa ?? profile?.defaultShippingFeePaisa ?? 8000) ~/ 100;
    _shippingFeeController = TextEditingController(text: defaultShipping.toString());

    // Only the drop's OWN threshold goes in the field. Blank means "use the
    // shop setting" (SA-PAY-008) — the shop value is shown as help text, never
    // prefilled as if it belonged to the drop.
    _freeShippingThresholdController = TextEditingController(
      text: FreeShippingRules.toRupeesInput(drop?.freeShippingThresholdPaisa),
    );
    _freeShippingThresholdController.addListener(_onThresholdChanged);

    _profile = profile;
    if (_profile == null) {
      _loadProfile();
    }

    if (_isEditing) {
      _autoSlug = false;
    }
  }

  Future<void> _loadProfile() async {
    try {
      final loaded = await widget.repository.getProfile();
      if (mounted) setState(() => _profile = loaded);
    } catch (_) {
      // The help text falls back to a neutral wording without the shop value.
    }
  }

  void _onThresholdChanged() {
    if (mounted) setState(() {});
  }

  /// Help text under the threshold field: what applies right now.
  String get _thresholdHelperText {
    final typed = FreeShippingRules.validateRupeesInput(_freeShippingThresholdController.text) == null
        ? FreeShippingRules.parseRupeesInput(_freeShippingThresholdController.text)
        : null;
    if (typed != null) {
      return 'This drop: ${FreeShippingRules.describe(typed)}';
    }
    final profile = _profile;
    if (profile == null) {
      return 'Leave blank to use your shop setting';
    }
    final shop = FreeShippingRules.resolve(shopThresholdPaisa: profile.freeShippingThresholdPaisa);
    return 'Blank uses your shop setting: ${shop.label}';
  }

  @override
  void dispose() {
    _freeShippingThresholdController.removeListener(_onThresholdChanged);
    _titleController.dispose();
    _slugController.dispose();
    _streamUrlController.dispose();
    _shippingFeeController.dispose();
    _freeShippingThresholdController.dispose();
    super.dispose();
  }

  void _onTitleChanged(String val) {
    if (_autoSlug && !_isEditing) {
      final generated = val
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      _slugController.text = generated;
    }
  }

  Future<void> _saveDrop() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final title = _titleController.text.trim();
      final slug = _slugController.text.trim().toLowerCase();
      final shippingFeePaisa = (int.parse(_shippingFeeController.text.trim())) * 100;
      // Blank clears the drop's own threshold (the shop setting then applies).
      final freeShippingThresholdPaisa =
          FreeShippingRules.parseRupeesInput(_freeShippingThresholdController.text);

      final streamUrlText = _streamUrlController.text.trim();
      final streamUrl = streamUrlText.isNotEmpty ? streamUrlText : null;

      SellerDrop savedDrop;
      if (_isEditing) {
        savedDrop = await widget.repository.updateDrop(
          dropId: widget.existingDrop!.id,
          title: title,
          slug: slug,
          shippingFeePaisa: shippingFeePaisa,
          freeShippingThresholdPaisa: freeShippingThresholdPaisa,
          streamUrl: streamUrl,
        );
      } else {
        savedDrop = await widget.repository.createDrop(
          title: title,
          slug: slug,
          shippingFeePaisa: shippingFeePaisa,
          freeShippingThresholdPaisa: freeShippingThresholdPaisa,
          streamUrl: streamUrl,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(savedDrop);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is LiveDropException ? e.message : 'Error saving drop: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181B),
        title: Text(
          _isEditing ? 'Edit Drop' : 'Create New Drop',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title Field
              TextFormField(
                controller: _titleController,
                onChanged: _onTitleChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Drop Title *',
                  hintText: 'e.g. Summer Vintage Drop #04',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Slug Field
              TextFormField(
                controller: _slugController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Public URL Slug *',
                  hintText: 'e.g. summer-vintage-04',
                  prefixText: '/drop/',
                  prefixStyle: const TextStyle(color: Color(0xFFF59E0B)),
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onTap: () => _autoSlug = false,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Slug is required';
                  }
                  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(val.trim())) {
                    return 'Slug can only contain lowercase letters, numbers, and hyphens';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Facebook Live Stream URL Field
              TextFormField(
                controller: _streamUrlController,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Facebook Live Stream URL (Optional)',
                  hintText: 'https://www.facebook.com/.../videos/...',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  helperText: 'Paste the public Facebook Live broadcast or video URL',
                  helperStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  prefixIcon: const Icon(Icons.live_tv, color: Color(0xFF1877F2)),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) {
                  if (val != null && val.trim().isNotEmpty) {
                    final trimmed = val.trim();
                    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
                      return 'Please enter a valid URL starting with http:// or https://';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              const Text(
                'Shipping Parameters (ADR-009 Integer Paisa)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),

              // Shipping Fee Field
              TextFormField(
                controller: _shippingFeeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                  labelText: 'Flat Shipping Fee (₹ INR) *',
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Shipping fee is required';
                  }
                  final parsed = int.tryParse(val.trim());
                  if (parsed == null || parsed < 0) {
                    return 'Please enter a valid non-negative integer amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Free Shipping Threshold Field
              TextFormField(
                controller: _freeShippingThresholdController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                  labelText: 'Free Shipping Threshold (₹ INR, Optional)',
                  hintText: 'e.g. 2999 (blank = shop setting)',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  helperText: _thresholdHelperText,
                  helperMaxLines: 2,
                  helperStyle: TextStyle(color: Colors.grey.shade500),
                  suffixIcon: _freeShippingThresholdController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear (use shop setting)',
                          icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade500),
                          onPressed: () => _freeShippingThresholdController.clear(),
                        ),
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: FreeShippingRules.validateRupeesInput,
              ),
              const SizedBox(height: 32),

              // Save Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoading ? null : _saveDrop,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text(
                        _isEditing ? 'Update Drop Details' : 'Create Drop (Draft)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
