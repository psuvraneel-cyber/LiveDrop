import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/errors/exceptions.dart';
import '../../core/services/image_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/bounceable_button.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';

/// Screen 4: Luxury Boutique Camera Intake Screen
/// Features 1:1 viewfinder bracket guides, zoom pill, gold shutter ring, and rapid intake bottom sheet.
class CameraIntakeScreen extends StatefulWidget {
  final SellerDrop? drop;
  final String? dropId;
  final SellerRepository repository;
  final ImageService imageService;

  const CameraIntakeScreen({
    super.key,
    this.drop,
    this.dropId,
    required this.repository,
    this.imageService = const ImageService(),
  }) : assert(drop != null || dropId != null, 'Either drop or dropId must be provided');

  @override
  State<CameraIntakeScreen> createState() => _CameraIntakeScreenState();
}

class _CameraIntakeScreenState extends State<CameraIntakeScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String? _errorMessage;

  // Viewfinder UI Controls
  bool _isFlashOn = false;
  bool _showGrid = true;
  double _selectedZoom = 1.0;
  int _currentCameraIndex = 0;
  String _activeMode = 'Photo'; // Photo or Gallery

  // Drop & Cataloging State
  SellerDrop? _resolvedDrop;
  int _nextCodeNumber = 1;
  String _codePrefix = 'A';
  final List<SellerProduct> _recentProducts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolvedDrop = widget.drop;
    _initialize();
  }

  Future<void> _initialize() async {
    if (_resolvedDrop == null && widget.dropId != null) {
      try {
        final drops = await widget.repository.getDrops();
        _resolvedDrop = drops.firstWhere(
          (d) => d.id == widget.dropId,
          orElse: () => drops.first,
        );
      } catch (_) {}
    }

    await _loadExistingProducts();
    await _initCamera();
  }

  Future<void> _loadExistingProducts() async {
    final dropId = _resolvedDrop?.id ?? widget.dropId;
    if (dropId == null) return;

    try {
      final products = await widget.repository.getProducts(dropId);
      if (mounted) {
        setState(() {
          _recentProducts.clear();
          _recentProducts.addAll(products.reversed);
          _computeNextCode(products);
        });
      }
    } catch (_) {}
  }

  void _computeNextCode(List<SellerProduct> products) {
    if (products.isEmpty) {
      _nextCodeNumber = 1;
      return;
    }

    int maxNum = 0;
    String prefix = 'A';

    final codeRegex = RegExp(r'^#?([A-Za-z]+)(\d+)$');
    for (final p in products) {
      final match = codeRegex.firstMatch(p.code.trim());
      if (match != null) {
        prefix = match.group(1)!.toUpperCase();
        final numVal = int.tryParse(match.group(2)!) ?? 0;
        if (numVal > maxNum) {
          maxNum = numVal;
        }
      }
    }

    _codePrefix = prefix;
    _nextCodeNumber = maxNum + 1;
  }

  String get _currentFlashCode {
    final cleanPrefix = _codePrefix.replaceAll('#', '').toUpperCase();
    return '#$cleanPrefix${_nextCodeNumber.toString().padLeft(2, '0')}';
  }

  Future<void> _initCamera() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        setState(() => _isCameraInitialized = false);
        return;
      }

      final camera = _availableCameras[_currentCameraIndex % _availableCameras.length];

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (mounted) {
        setState(() {
          _cameraController = controller;
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _errorMessage = 'Hardware camera unavailable ($e). Fallback to gallery available.';
        });
      }
    }
  }

  void _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    setState(() => _isFlashOn = !_isFlashOn);
    await _cameraController!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  void _flipCamera() async {
    if (_availableCameras.length < 2) return;
    _currentCameraIndex++;
    await _cameraController?.dispose();
    await _initCamera();
  }

  void _setZoom(double zoom) async {
    setState(() => _selectedZoom = zoom);
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setZoomLevel(zoom);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      Uint8List? rawBytes;

      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final xFile = await _cameraController!.takePicture();
        rawBytes = await xFile.readAsBytes();
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
        );
        if (picked != null) {
          rawBytes = await picked.readAsBytes();
        }
      }

      if (rawBytes == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final processed = await widget.imageService.processIntakeImage(rawBytes);

      if (mounted) {
        setState(() => _isProcessing = false);
        await _showIntakeBottomSheet(processed);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _isProcessing = true);
      final rawBytes = await picked.readAsBytes();
      final processed = await widget.imageService.processIntakeImage(rawBytes);

      if (mounted) {
        setState(() => _isProcessing = false);
        await _showIntakeBottomSheet(processed);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gallery import failed: $e'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    }
  }

  Future<void> _showIntakeBottomSheet(ProcessedImage processed) async {
    final codeCtrl = TextEditingController(text: _currentFlashCode);
    final titleCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String selectedSize = 'Free Size';
    bool isSaving = false;

    final sizes = ['Free Size', 'XS', 'S', 'M', 'L', 'XL', 'XXL'];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header with Image Thumbnail & Code
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            processed.bytes,
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Intake Piece — ${_resolvedDrop?.title ?? "Active Drop"}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '#${codeCtrl.text}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.goldPrimary,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.cardBorder),
                    const SizedBox(height: 12),

                    // Flash Code & Title Fields
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: TextField(
                            controller: codeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Code',
                            ),
                            onChanged: (val) => setSheetState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: titleCtrl,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'Item Title',
                              hintText: 'e.g. Banarasi Silk Saree',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Price Field
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
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
                    ),
                    const SizedBox(height: 14),

                    // Size Selection Chips
                    const Text(
                      'Size',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sizes.map((s) {
                        final isSelected = selectedSize == s;
                        return ChoiceChip(
                          label: Text(s),
                          selected: isSelected,
                          selectedColor: AppColors.goldPrimary,
                          backgroundColor: AppColors.obsidianElevated,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setSheetState(() => selectedSize = s);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    BounceableButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final title = titleCtrl.text.trim().isEmpty
                                  ? 'Item ${codeCtrl.text.trim()}'
                                  : titleCtrl.text.trim();
                              final priceNum = int.tryParse(priceCtrl.text.trim()) ?? 0;
                              if (priceNum <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter a valid price in ₹'),
                                    backgroundColor: AppColors.crimson,
                                  ),
                                );
                                return;
                              }

                              final dropId = _resolvedDrop?.id ?? widget.dropId;
                              if (dropId == null) return;

                              setSheetState(() => isSaving = true);

                              try {
                                final timestamp = DateTime.now().millisecondsSinceEpoch;
                                final fileName = '${codeCtrl.text.trim()}_$timestamp.jpg';

                                final imageUrl = await widget.repository.uploadProductImage(
                                  dropId: dropId,
                                  fileName: fileName,
                                  imageBytes: processed.bytes,
                                  contentType: 'image/jpeg',
                                );

                                final product = await widget.repository.createProduct(
                                  dropId: dropId,
                                  code: codeCtrl.text.trim(),
                                  title: title,
                                  pricePaisa: priceNum * 100,
                                  size: selectedSize,
                                  imageUrl: imageUrl,
                                );

                                if (!mounted || !ctx.mounted) return;
                                setState(() {
                                  _recentProducts.insert(0, product);
                                  _nextCodeNumber++;
                                });
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Piece #${product.code} saved! (#$_currentFlashCode ready)',
                                    ),
                                    backgroundColor: AppColors.emerald,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              } catch (err) {
                                setSheetState(() => isSaving = false);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      err is LiveDropException
                                          ? err.message
                                          : 'Error saving piece: $err',
                                    ),
                                    backgroundColor: AppColors.crimson,
                                  ),
                                );
                              }
                            },
                      isLoading: isSaving,
                      variant: ButtonVariant.goldGradient,
                      height: 50,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.black, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Save & Next Piece (→)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Controls Bar (Header, Flash, Grid, Close)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Add Product',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: _isFlashOn ? AppColors.goldPrimary : Colors.white70,
                          size: 22,
                        ),
                        onPressed: _toggleFlash,
                      ),
                      InkWell(
                        onTap: () => setState(() => _showGrid = !_showGrid),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _showGrid ? AppColors.goldMuted : AppColors.obsidianElevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _showGrid ? AppColors.goldPrimary : AppColors.cardBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.grid_3x3, size: 16, color: _showGrid ? AppColors.goldPrimary : Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                'Grid',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _showGrid ? AppColors.goldPrimary : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Viewfinder with 1:1 Square Bracket Guides
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_isCameraInitialized && _cameraController != null)
                    Center(
                      child: AspectRatio(
                        aspectRatio: _cameraController!.value.aspectRatio,
                        child: CameraPreview(_cameraController!),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.white24),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage ?? 'Camera ready. Tap shutter or gallery to intake.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),

                  // 1:1 Square Bracket Frame
                  Center(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        child: CustomPaint(
                          painter: ViewfinderGuidesPainter(
                            showGrid: _showGrid,
                            bracketColor: AppColors.goldPrimary,
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.goldPrimary, width: 0.8),
                                  ),
                                  child: Text(
                                    'Next: #$_currentFlashCode',
                                    style: const TextStyle(
                                      color: AppColors.goldPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Zoom Selector Pill (0.5, 1x, 2)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildZoomButton(0.5, '0.5'),
                            _buildZoomButton(1.0, '1x'),
                            _buildZoomButton(2.0, '2'),
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (_isProcessing)
                    Container(
                      color: Colors.black87,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppColors.goldPrimary),
                            SizedBox(height: 16),
                            Text(
                              'Cropping 1:1 & Optimizing Image...',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom Controls Bar (Thumbnail, Shutter, Flip, Mode)
            Container(
              color: AppColors.obsidian,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Shutter Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Thumbnail preview of last shot
                      InkWell(
                        onTap: _pickFromGallery,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.cardBorder, width: 1.5),
                            color: AppColors.obsidianElevated,
                          ),
                          child: _recentProducts.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _recentProducts.first.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.photo, color: Colors.white54),
                                  ),
                                )
                              : const Icon(Icons.photo, color: Colors.white54),
                        ),
                      ),

                      // Large Shutter Button (White inner with Gold outer ring)
                      GestureDetector(
                        onTap: _captureAndProcess,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.goldPrimary, width: 3.5),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // Camera Flip Icon
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 30),
                        onPressed: _flipCamera,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Mode Toggle Pill: Photo | Gallery
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.obsidianElevated,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildModeButton('Photo', () => setState(() => _activeMode = 'Photo')),
                        _buildModeButton('Gallery', () {
                          setState(() => _activeMode = 'Gallery');
                          _pickFromGallery();
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomButton(double zoom, String label) {
    final isSelected = _selectedZoom == zoom;
    return GestureDetector(
      onTap: () => _setZoom(zoom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.goldPrimary : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(String mode, VoidCallback onTap) {
    final isSelected = _activeMode == mode;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.goldPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          mode,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// Custom Viewfinder Painter for Corner Brackets and optional 3x3 Grid
class ViewfinderGuidesPainter extends CustomPainter {
  final bool showGrid;
  final Color bracketColor;

  ViewfinderGuidesPainter({
    required this.showGrid,
    required this.bracketColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Optional 3x3 Rule-of-thirds grid
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), gridPaint);
      canvas.drawLine(Offset(2 * w / 3, 0), Offset(2 * w / 3, h), gridPaint);
      canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), gridPaint);
      canvas.drawLine(Offset(0, 2 * h / 3), Offset(w, 2 * h / 3), gridPaint);
    }

    // Corner Brackets
    final bracketPaint = Paint()
      ..color = bracketColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const cornerLength = 24.0;

    // Top-Left
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLength, 0), bracketPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLength), bracketPaint);

    // Top-Right
    canvas.drawLine(Offset(w, 0), Offset(w - cornerLength, 0), bracketPaint);
    canvas.drawLine(Offset(w, 0), Offset(w, cornerLength), bracketPaint);

    // Bottom-Left
    canvas.drawLine(Offset(0, h), Offset(cornerLength, h), bracketPaint);
    canvas.drawLine(Offset(0, h), Offset(0, h - cornerLength), bracketPaint);

    // Bottom-Right
    canvas.drawLine(Offset(w, h), Offset(w - cornerLength, h), bracketPaint);
    canvas.drawLine(Offset(w, h), Offset(w, h - cornerLength), bracketPaint);
  }

  @override
  bool shouldRepaint(covariant ViewfinderGuidesPainter oldDelegate) {
    return oldDelegate.showGrid != showGrid || oldDelegate.bracketColor != bracketColor;
  }
}
