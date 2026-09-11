/// LiveDrop Seller Mobile App — Environment Configuration Contract
///
/// Loads and validates runtime configuration passed via `--dart-define` or environment.
/// Under no circumstances may a service-role key or database secret be included.
class EnvConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// Validates that all required configuration variables are present and well-formed.
  static void validate() {
    if (supabaseUrl.trim().isEmpty) {
      throw StateError(
        '[ENV CONFIG ERROR] Missing required configuration: SUPABASE_URL. '
        'Provide via --dart-define=SUPABASE_URL=... during build/run.',
      );
    }

    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw StateError(
        '[ENV CONFIG ERROR] SUPABASE_URL must be a valid http or https URL: $supabaseUrl',
      );
    }

    if (supabaseAnonKey.trim().isEmpty) {
      throw StateError(
        '[ENV CONFIG ERROR] Missing required configuration: SUPABASE_ANON_KEY. '
        'Provide via --dart-define=SUPABASE_ANON_KEY=... during build/run.',
      );
    }

    // Safety guard: prevent accidental service role key embedding
    if (supabaseAnonKey.contains('service_role') ||
        supabaseAnonKey.toUpperCase().contains('SERVICE_KEY')) {
      throw StateError(
        '[SECURITY VIOLATION] Detected service_role credential in mobile app configuration. '
        'Only public anon keys may be used by the mobile client.',
      );
    }
  }
}
