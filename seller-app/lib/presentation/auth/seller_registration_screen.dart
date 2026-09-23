import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/admin_config.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../core/theme/brand_emblem.dart';

class SellerRegistrationScreen extends StatefulWidget {
  final VoidCallback onRegistrationSuccess;

  const SellerRegistrationScreen({
    super.key,
    required this.onRegistrationSuccess,
  });

  @override
  State<SellerRegistrationScreen> createState() => _SellerRegistrationScreenState();
}

class _SellerRegistrationScreenState extends State<SellerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 1;
  bool _isLoading = false;
  String? _errorMessage;

  // Step 1 Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Step 2 Controllers
  final _storeNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _upiIdController = TextEditingController();
  final _addressController = TextEditingController();

  // Step 3
  final _utrController = TextEditingController();
  bool _paymentConfirmed = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _storeNameController.dispose();
    _phoneController.dispose();
    _upiIdController.dispose();
    _addressController.dispose();
    _utrController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _errorMessage = null;
        _currentStep++;
      });
    }
  }

  void _previousStep() {
    setState(() {
      _errorMessage = null;
      _currentStep--;
    });
  }

  Future<void> _launchUpi() async {
    final Uri url = Uri.parse(AdminConfig.upiPaymentUrl);
    if (!await launchUrl(url)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open UPI app. Please pay manually.')),
      );
    }
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_paymentConfirmed || _utrController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please provide transaction details and confirm payment.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // 1. Generate store_slug from store name
      String storeSlug = _storeNameController.text.trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');

      if (storeSlug.isEmpty) {
        storeSlug = 'store-${DateTime.now().millisecondsSinceEpoch}';
      }

      // 2. Create auth user with metadata for DB trigger
      final authResponse = await SupabaseService.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'store_name': _storeNameController.text.trim(),
          'store_slug': storeSlug,
          'phone_number': _phoneController.text.trim(),
          'upi_id': _upiIdController.text.trim(),
          'return_address': _addressController.text.trim(),
          'utr_number': _utrController.text.trim(),
        },
      );

      if (authResponse.user == null) {
        throw const AuthException('Registration failed, please try again.');
      }

      // 3. If session is available immediately, ensure profile is upserted
      if (authResponse.session != null) {
        try {
          await SupabaseService.instance.client.from('profiles').upsert({
            'id': authResponse.user!.id,
            'store_name': _storeNameController.text.trim(),
            'store_slug': storeSlug,
            'phone_number': _phoneController.text.trim(),
            'upi_id': _upiIdController.text.trim(),
            'upi_vpa': _upiIdController.text.trim(),
            'upi_display_name': _storeNameController.text.trim(),
            'return_address': _addressController.text.trim(),
            'default_shipping_fee_paisa': 8000,
          });
        } catch (_) {}

        if (mounted) {
          setState(() => _isLoading = false);
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.obsidianSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.goldPrimary.withValues(alpha: 0.4)),
              ),
              title: const Text(
                'Application Under Review',
                style: TextStyle(
                  color: AppColors.goldPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                'Your boutique account ($email) and onboarding payment reference (${_utrController.text.trim()}) have been recorded for administrative verification.\n\nAll boutique accounts require administrator approval before publishing live drops.',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Go to Sign In',
                    style: TextStyle(
                      color: AppColors.goldPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      } else {
        // Confirmation email required
        if (mounted) {
          setState(() => _isLoading = false);
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.obsidianSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.goldPrimary.withValues(alpha: 0.4)),
              ),
              title: const Text(
                'Registration Submitted',
                style: TextStyle(
                  color: AppColors.goldPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                'Your boutique account ($email) and onboarding payment reference (${_utrController.text.trim()}) have been recorded.\n\nPlease check your email inbox to verify your email, then sign in to access your boutique.',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Go to Sign In',
                    style: TextStyle(
                      color: AppColors.goldPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          if (e.message.toLowerCase().contains('already registered')) {
            _errorMessage = 'An account with this email already exists.';
          } else {
            _errorMessage = e.message;
          }
          _isLoading = false;
        });
      }
    } on PostgrestException {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not create profile. Please try again.';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool obscureText = false,
    Widget? suffixIcon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.goldPrimary, size: 20),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: AppColors.obsidian,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.textMuted, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.textMuted, width: 0.3),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.goldPrimary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.crimson, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.crimson, width: 1.5),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.5)),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(1, 'Account'),
        _buildLine(1),
        _buildDot(2, 'Profile'),
        _buildLine(2),
        _buildDot(3, 'Payment'),
      ],
    );
  }

  Widget _buildDot(int stepNumber, String label) {
    final isActive = _currentStep >= stepNumber;
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppColors.goldPrimary : AppColors.obsidianSurface,
            border: Border.all(
              color: isActive ? AppColors.goldPrimary : AppColors.textMuted,
            ),
          ),
          child: Center(
            child: Text(
              stepNumber.toString(),
              style: TextStyle(
                color: isActive ? AppColors.obsidian : AppColors.textMuted,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildLine(int stepNumber) {
    final isActive = _currentStep > stepNumber;
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      color: isActive ? AppColors.goldPrimary : AppColors.textMuted.withValues(alpha: 0.3),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _emailController,
          label: 'Email Address',
          hint: 'seller@myboutique.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Email is required';
            final emailRegex = RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w{2,}$');
            if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email';
            return null;
          },
        ),
        _buildTextField(
          controller: _passwordController,
          label: 'Password',
          icon: Icons.lock_outline,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Password is required';
            if (value.length < 8) return 'Password must be at least 8 characters';
            return null;
          },
        ),
        _buildTextField(
          controller: _confirmPasswordController,
          label: 'Confirm Password',
          icon: Icons.lock_outline,
          obscureText: _obscureConfirmPassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
            ),
            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          ),
          validator: (value) {
            if (value != _passwordController.text) return 'Passwords do not match';
            return null;
          },
        ),
        const SizedBox(height: 24),
        BounceableButton(
          text: 'Next: Boutique Profile',
          variant: ButtonVariant.goldGradient,
          onPressed: _nextStep,
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _storeNameController,
          label: 'Boutique Store Name',
          icon: Icons.storefront_outlined,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Store name is required';
            if (value.trim().length < 2 || value.trim().length > 100) return 'Must be between 2-100 characters';
            return null;
          },
        ),
        _buildTextField(
          controller: _phoneController,
          label: 'Phone Number (WhatsApp)',
          hint: '9876543210',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Phone number is required';
            final phone = value.trim();
            if (!RegExp(r'^(?:91)?[6-9]\d{9}$').hasMatch(phone)) return 'Enter a valid 10-digit Indian mobile number';
            return null;
          },
        ),
        _buildTextField(
          controller: _upiIdController,
          label: 'UPI ID (For Customer Payments)',
          hint: 'yourname@okaxis',
          icon: Icons.account_balance_outlined,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'UPI ID is required';
            if (!RegExp(r'^[a-zA-Z0-9.\-_]{2,255}@[a-zA-Z]{2,64}$').hasMatch(value.trim())) return 'Enter a valid UPI ID (e.g. name@upi)';
            return null;
          },
        ),
        _buildTextField(
          controller: _addressController,
          label: 'Return / Pickup Address',
          icon: Icons.location_on_outlined,
          maxLines: 3,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Return address is required';
            if (value.trim().length < 10 || value.trim().length > 500) return 'Must be between 10-500 characters';
            return null;
          },
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: BounceableButton(
                text: 'Back',
                variant: ButtonVariant.darkCard,
                onPressed: _previousStep,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: BounceableButton(
                text: 'Next: Payment',
                variant: ButtonVariant.goldGradient,
                onPressed: _nextStep,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Onboarding Fee Payment',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.goldPrimary.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Text(
                'One-time Onboarding Fee',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                AdminConfig.onboardingFeeDisplay,
                style: const TextStyle(color: AppColors.goldPrimary, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Payee: ${AdminConfig.onboardingUpiDisplayName}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              // QR Code Container
              Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.goldPrimary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    AdminConfig.qrCodeAssetPath,
                    height: 190,
                    width: 190,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Icon(Icons.qr_code_2_rounded, size: 100, color: Colors.black87),
                    ),
                  ),
                ),
              ),
              // Copyable UPI ID Chip
              InkWell(
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: AdminConfig.onboardingUpiId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Admin UPI ID copied to clipboard!'),
                      backgroundColor: AppColors.emerald,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.goldPrimary.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.goldPrimary),
                      SizedBox(width: 8),
                      Text(
                        AdminConfig.onboardingUpiId,
                        style: TextStyle(
                          color: AppColors.goldPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.copy_rounded, size: 14, color: AppColors.goldPrimary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              BounceableButton(
                text: 'Pay via UPI App',
                variant: ButtonVariant.goldGradient,
                onPressed: _launchUpi,
              ),
              const SizedBox(height: 10),
              const Text(
                'Scan the QR code above or tap to copy UPI ID & pay ₹50',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildTextField(
          controller: _utrController,
          label: 'Transaction Reference (UTR Number)',
          hint: '12-digit UPI UTR number',
          icon: Icons.receipt_long_outlined,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'UTR is required for admin verification';
            return null;
          },
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _paymentConfirmed,
                activeColor: AppColors.goldPrimary,
                checkColor: AppColors.obsidian,
                side: const BorderSide(color: AppColors.textMuted),
                onChanged: (value) {
                  setState(() {
                    _paymentConfirmed = value ?? false;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _paymentConfirmed = !_paymentConfirmed;
                  });
                },
                child: Text(
                  'I have completed the payment of ${AdminConfig.onboardingFeeDisplay}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: BounceableButton(
                text: 'Back',
                variant: ButtonVariant.darkCard,
                onPressed: _isLoading ? null : _previousStep,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.goldPrimary))
                : BounceableButton(
                    text: 'Complete Registration',
                    variant: ButtonVariant.goldGradient,
                    onPressed: _submitRegistration,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandEmblem(
                    size: 56,
                    showText: true,
                    subtitle: 'Create your boutique account',
                  ),
                  const SizedBox(height: 32),
                  _buildStepIndicator(),
                  const SizedBox(height: 32),
                  Container(
                    decoration: AppTheme.cardDecoration(
                      backgroundColor: AppColors.obsidianSurface,
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.crimsonTint,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.crimson.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: AppColors.crimson, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: AppColors.crimson),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (_currentStep == 1) _buildStep1(),
                          if (_currentStep == 2) _buildStep2(),
                          if (_currentStep == 3) _buildStep3(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Already have an account? Sign In',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
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
