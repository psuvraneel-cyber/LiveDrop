import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env_config.dart';

/// LiveDrop Seller Mobile App — Supabase Client Service
///
/// Wraps Supabase client lifecycle and authentication session management.
/// Only public anon keys are permitted; service-role keys are strictly prohibited.
class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  bool _isInitialized = false;

  /// Returns true if the underlying Supabase client has been successfully initialized.
  bool get isInitialized => _isInitialized;

  /// Initializes the Supabase client.
  /// Falls back to validated [EnvConfig] if credentials are not explicitly supplied.
  Future<void> initialize({
    String? url,
    String? anonKey,
  }) async {
    if (_isInitialized) return;

    final targetUrl = url ?? EnvConfig.supabaseUrl;
    final targetAnonKey = anonKey ?? EnvConfig.supabaseAnonKey;

    if (targetUrl.isEmpty || targetAnonKey.isEmpty) {
      EnvConfig.validate();
    }

    await Supabase.initialize(
      url: targetUrl,
      // ignore: deprecated_member_use
      anonKey: targetAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );

    _isInitialized = true;
  }

  /// Returns the underlying SupabaseClient.
  /// Throws [StateError] if accessed before [initialize] completes.
  SupabaseClient get client {
    if (!_isInitialized) {
      throw StateError(
        'SupabaseService has not been initialized. '
        'Call initialize() before accessing client.',
      );
    }
    return Supabase.instance.client;
  }

  /// Returns current authenticated user or null.
  User? get currentUser => _isInitialized ? client.auth.currentUser : null;

  /// Returns current authenticated seller ID (`auth.uid()`) or null.
  String? get currentSellerId => _isInitialized ? client.auth.currentUser?.id : null;

  /// Returns true if a valid authenticated seller session exists.
  bool get isAuthenticated => _isInitialized && client.auth.currentSession != null;

  /// Stream of authentication state changes. Emits empty stream if uninitialized.
  Stream<AuthState> get authStateChanges {
    if (!_isInitialized) {
      return const Stream.empty();
    }
    return client.auth.onAuthStateChange;
  }

  /// Terminates the seller session and clears credentials.
  Future<void> signOut() async {
    if (_isInitialized) {
      await client.auth.signOut();
    }
  }
}
