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

  /// Base URL of the public buyer webfront.
  /// Defaults to canonical production URL, customizable via `--dart-define=BUYER_BASE_URL=...`.
  static const String buyerBaseUrl = String.fromEnvironment(
    'BUYER_BASE_URL',
    defaultValue: 'https://livedrop-in.vercel.app',
  );

  /// Generates the canonical public drop URL for buyers.
  static String getDropUrl(String slug) {
    final base = buyerBaseUrl.endsWith('/')
        ? buyerBaseUrl.substring(0, buyerBaseUrl.length - 1)
        : buyerBaseUrl;
    final cleanSlug = slug.startsWith('/') ? slug.substring(1) : slug;
    return '$base/drop/$cleanSlug';
  }

  /// Generates the direct product flash link for buyers.
  static String getProductUrl(String dropSlug, String productCode) {
    final cleanCode = productCode.replaceAll('#', '');
    return '${getDropUrl(dropSlug)}#$cleanCode';
  }

  /// Generates the canonical public storefront URL for a boutique.
  static String getStorefrontUrl(String storeSlug) {
    final base = buyerBaseUrl.trim().endsWith('/')
        ? buyerBaseUrl.trim().substring(0, buyerBaseUrl.trim().length - 1)
        : buyerBaseUrl.trim();
    var cleanSlug = storeSlug.trim();
    while (cleanSlug.startsWith('/')) {
      cleanSlug = cleanSlug.substring(1);
    }
    while (cleanSlug.endsWith('/')) {
      cleanSlug = cleanSlug.substring(0, cleanSlug.length - 1);
    }
    return '$base/$cleanSlug';
  }

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
