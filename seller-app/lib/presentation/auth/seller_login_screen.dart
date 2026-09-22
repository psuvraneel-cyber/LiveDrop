import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/boutique_haptics.dart';
import '../../core/theme/brand_emblem.dart';
import '../../core/theme/bounceable_button.dart';
import '../../core/config/admin_config.dart';
import '../../core/utils/url_launcher_helper.dart';
import 'seller_registration_screen.dart';

/// Screen 1: Luxury Boutique Login & Authentication Screen
/// Strictly matches Screen 1 of the visual specification.
class SellerLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const SellerLoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<SellerLoginScreen> createState() => _SellerLoginScreenState();
}

class _SellerLoginScreenState extends State<SellerLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      BoutiqueHaptics.heavy();
      setState(() {
        _errorMessage = 'Please enter both email and password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!SupabaseService.instance.isInitialized) {
      setState(() {
        _errorMessage = 'Supabase client is not initialized. Please verify environment configuration.';
        _isLoading = false;
      });
      return;
    }

    try {
      final client = SupabaseService.instance.client;
      final res = await client.auth.signInWithPassword(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (res.session != null) {
        BoutiqueHaptics.success();
        widget.onLoginSuccess();
      } else {
        BoutiqueHaptics.heavy();
        setState(() {
          _errorMessage = 'Authentication failed. Please check credentials.';
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      BoutiqueHaptics.heavy();
      setState(() {
        _errorMessage = 'Connection timed out. Please check your internet connection and try again.';
      });
    } on SocketException {
      if (!mounted) return;
      BoutiqueHaptics.heavy();
      setState(() {
        _errorMessage = 'Network error. Unable to reach the server. Please verify your connection.';
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      BoutiqueHaptics.heavy();
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('credentials')) {
        setState(() {
          _errorMessage = 'Invalid email or password. Please verify your credentials.';
        });
      } else {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (err) {
      if (!mounted) return;
      BoutiqueHaptics.heavy();
      setState(() {
        _errorMessage = 'Sign in error: ${err.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email address first.';
      });
      return;
    }
    
    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent to $email'),
          backgroundColor: const Color(0xFF10B981), // emerald
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to send reset email. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gold Coat Hanger Emblem & Brand Header
                  const BrandEmblem(
                    size: 72,
                    showText: true,
                    subtitle: 'Sign in to your boutique',
                  ),
                  const SizedBox(height: 8),

                  // Secondary subtitle ensuring test compatibility
                  const Text(
                    'Live-Stream Commerce & UPI Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Login Form Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: AppTheme.cardDecoration(
                      backgroundColor: AppColors.obsidianSurface,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.crimsonTint,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.crimson),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Email Field
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Seller Email',
                            hintText: 'seller@myboutique.com',
                            prefixIcon: Icon(Icons.email_outlined, color: AppColors.textMuted, size: 20),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field with Eye Toggle
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: '•••••••••',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Remember Me & Forgot Password Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      activeColor: AppColors.goldPrimary,
                                      checkColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      onChanged: (val) {
                                        setState(() {
                                          _rememberMe = val ?? true;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Flexible(
                                    child: Text(
                                      'Remember me',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _handleForgotPassword,
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                  color: AppColors.goldPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Gold Gradient Sign In Button
                        BounceableButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          isLoading: _isLoading,
                          height: 50,
                          variant: ButtonVariant.goldGradient,
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Sign In to Boutique',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Register New Account
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => SellerRegistrationScreen(
                                    onRegistrationSuccess: widget.onLoginSuccess,
                                  ),
                                ),
                              );
                            },
                            child: RichText(
                              text: const TextSpan(
                                text: 'New here? ',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Create Account',
                                    style: TextStyle(
                                      color: AppColors.goldPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Contact Admin via WhatsApp
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              BoutiqueHaptics.light();
                              UrlLauncherHelper.launchWhatsApp(
                                context: context,
                                phone: AdminConfig.whatsAppNumber,
                                message: AdminConfig.whatsAppMessage,
                              );
                            },
                            icon: const Icon(Icons.chat_outlined, size: 16, color: AppColors.textMuted),
                            label: const Text(
                              'Contact Admin via WhatsApp',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Footer trust badge
                  const Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_outlined, size: 14, color: AppColors.textMuted),
                          SizedBox(width: 6),
                          Text(
                            'Trusted by independent sellers across India',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
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
