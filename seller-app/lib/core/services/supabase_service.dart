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

  /// Initializes the Supabase client.
  /// Falls back to validated [EnvConfig] if credentials are not explicitly supplied.
  Future<void> initialize({
    String? url,
    String? anonKey,
  }) async {
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
  }

  /// Returns the underlying SupabaseClient.
  SupabaseClient get client => Supabase.instance.client;

  /// Returns current authenticated user or null.
  User? get currentUser => client.auth.currentUser;

  /// Returns current authenticated seller ID (`auth.uid()`) or null.
  String? get currentSellerId => client.auth.currentUser?.id;

  /// Returns true if a valid authenticated seller session exists.
  bool get isAuthenticated => client.auth.currentSession != null;

  /// Terminates the seller session and clears credentials.
  Future<void> signOut() async {
    await client.auth.signOut();
  }
}
