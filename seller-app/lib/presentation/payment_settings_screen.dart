import 'package:flutter/material.dart';
import '../data/repositories/seller_repository.dart';

/// LiveDrop Seller Mobile App — Direct UPI Payment Settings Screen (TASK-2.4B)
///
/// Enables sellers to configure their authoritative UPI ID, display name,
/// and optional payment instructions for direct buyer payments.
class PaymentSettingsScreen extends StatefulWidget {
  final SellerRepository repository;

  const PaymentSettingsScreen({super.key, required this.repository});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _upiVpaController;
  late TextEditingController _upiDisplayNameController;
  late TextEditingController _instructionsController;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _upiEnabled = true;
  String? _errorMessage;

  static final _vpaRegex = RegExp(r'^[a-zA-Z0-9.\-_]{2,255}@[a-zA-Z]{2,64}$');

  @override
  void initState() {
    super.initState();
    _upiVpaController = TextEditingController();
    _upiDisplayNameController = TextEditingController();
    _instructionsController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _upiVpaController.dispose();
    _upiDisplayNameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await widget.repository.getProfile();
      setState(() {
        _upiEnabled = profile.upiEnabled;
        _upiVpaController.text = profile.upiVpa ?? profile.upiId;
        _upiDisplayNameController.text = profile.upiDisplayName ?? profile.storeName;
        _instructionsController.text = profile.paymentInstructions ?? '';
        _isLoading = false;
      });
    } catch (err) {
      setState(() {
        _errorMessage = err.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.updateUpiSettings(
        upiEnabled: _upiEnabled,
        upiVpa: _upiVpaController.text.trim(),
        upiDisplayName: _upiDisplayNameController.text.trim().isEmpty
            ? null
            : _upiDisplayNameController.text.trim(),
        paymentInstructions: _instructionsController.text.trim().isEmpty
            ? null
            : _instructionsController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('UPI payment settings saved successfully!'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (err) {
      setState(() {
        _errorMessage = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Settings'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Direct UPI Architecture Information Card
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, color: Color(0xFF16A34A), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Direct Peer-to-Peer UPI Rail',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF166534),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Buyers pay directly into your personal or business UPI-linked bank account. '
                            'LiveDrop never custodies your money and charges zero gateway fees. '
                            'You inspect your bank transaction history to manually verify receipt.',
                            style: TextStyle(
                              color: Color(0xFF166534),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // UPI Feature Toggle
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Accept UPI Payments',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: const Text(
                        'Allow buyers to pay via Google Pay, PhonePe, Paytm, BHIM, etc.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      value: _upiEnabled,
                      activeThumbColor: const Color(0xFF16A34A),
                      onChanged: (val) {
                        setState(() {
                          _upiEnabled = val;
                        });
                      },
                    ),
                    const Divider(height: 32),

                    // Authoritative UPI ID (VPA) Field
                    const Text(
                      'Authoritative UPI ID (VPA) *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _upiVpaController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. boutique@oksbi or artisan@upi',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payment),
                        helperText: 'Dynamic QR codes and payment links will route to this exact VPA.',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'UPI ID is required to receive payments.';
                        }
                        if (!_vpaRegex.hasMatch(val.trim())) {
                          return 'Please enter a valid UPI format (e.g. name@bank).';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Payee Display Name Field
                    const Text(
                      'Payee Display Name',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _upiDisplayNameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Mother\'s Boutique Official',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.storefront),
                        helperText: 'Displayed to buyers on the payment QR screen.',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Optional Payment Instructions
                    const Text(
                      'Optional Payment Note',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _instructionsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Please mention your LiveDrop reference in the payment note.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error Message Banner
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isSaving ? null : _saveSettings,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Save Payment Settings',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
