/// LiveDrop Seller App — product field rules (SA-INT-001).
///
/// Client-side mirror of the `products` table constraints so that the seller
/// gets an inline, human-readable message *before* a piece is queued.
/// The database stays authoritative (docs/19-validation-and-business-rules.md):
///
/// * RULE-PRD-01 — `CHECK (code ~ '^#[A-Z0-9]{1,6}$')`
/// * RULE-PRD-02 — `UNIQUE (drop_id, code)` (client checks the local drop list)
/// * RULE-PRD-03 — `CHECK (price_paisa > 0)` on an `INT` column
/// * `CHECK (char_length(title) <= 100)` and `CHECK (char_length(size) <= 30)`
library;

class ProductRules {
  ProductRules._();

  /// Maximum letters/digits allowed after the leading `#`.
  static const int maxCodeChars = 6;
  static const int maxTitleLength = 100;
  static const int maxSizeLength = 30;

  /// Largest value a PostgreSQL `INT` column (price_paisa) can hold.
  static const int maxPricePaisa = 2147483647;

  /// Largest whole-rupee price that still fits in [maxPricePaisa].
  static const int maxPriceRupees = maxPricePaisa ~/ 100;

  static final RegExp codePattern = RegExp(r'^#[A-Z0-9]{1,6}$');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _codeBody = RegExp(r'^[A-Z0-9]+$');

  /// Normalises a typed code: trim, drop every space, uppercase and add the
  /// leading `#` when it is missing. `' a 01 '` → `'#A01'`, `'101'` → `'#101'`.
  /// An empty input stays empty so that it can be reported as missing.
  static String normalizeCode(String raw) {
    final compact = raw.replaceAll(_whitespace, '').toUpperCase();
    if (compact.isEmpty) return '';
    return compact.startsWith('#') ? compact : '#$compact';
  }

  /// True when [code] (already normalised) satisfies RULE-PRD-01.
  static bool isValidCode(String code) => codePattern.hasMatch(code);

  /// Returns a seller-facing error for [raw] (validated after normalisation),
  /// or `null` when the code is acceptable.
  static String? validateCode(String raw) {
    final code = normalizeCode(raw);
    if (code.isEmpty) {
      return 'Enter a code, e.g. #A01.';
    }
    final body = code.substring(1);
    if (body.isEmpty) {
      return 'Add 1–6 letters or digits after #, e.g. #A01.';
    }
    if (!_codeBody.hasMatch(body)) {
      return 'Use only letters A–Z and digits 0–9 after # (no dashes or symbols).';
    }
    if (body.length > maxCodeChars) {
      return 'Codes can have at most $maxCodeChars letters/digits after # '
          '(${body.length} entered).';
    }
    return null;
  }

  /// Returns an error when the normalised [code] is already used by another
  /// piece of the same drop (RULE-PRD-02), using the codes the app knows about.
  static String? validateCodeUnique(String raw, Iterable<String> existingCodes) {
    final code = normalizeCode(raw);
    if (code.isEmpty) return null;
    for (final existing in existingCodes) {
      if (normalizeCode(existing) == code) {
        return 'Code $code is already used in this drop. Choose another code.';
      }
    }
    return null;
  }

  /// Title is optional; when given it must be ≤ 100 characters after trim.
  static String? validateTitle(String raw, {bool required = false}) {
    final title = raw.trim();
    if (title.isEmpty) {
      return required ? 'Enter a title.' : null;
    }
    if (title.length > maxTitleLength) {
      return 'Title can be at most $maxTitleLength characters (${title.length} entered).';
    }
    return null;
  }

  /// Size must be ≤ 30 characters after trim.
  static String? validateSize(String raw, {bool required = false}) {
    final size = raw.trim();
    if (size.isEmpty) {
      return required ? 'Enter a size (e.g. Free Size, M, L).' : null;
    }
    if (size.length > maxSizeLength) {
      return 'Size can be at most $maxSizeLength characters (${size.length} entered).';
    }
    return null;
  }

  /// Price in integer paisa: must be > 0 and fit the database `INT`.
  static String? validatePricePaisa(int? pricePaisa) {
    if (pricePaisa == null || pricePaisa <= 0) {
      return 'Enter a price above ₹0.';
    }
    if (pricePaisa > maxPricePaisa) {
      return 'Price is too large.';
    }
    return null;
  }

  /// Parses a whole-rupee price typed by the seller into integer paisa.
  /// Returns `null` for anything that is not a positive whole number.
  static int? parseRupeesToPaisa(String raw) {
    final text = raw.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+$').hasMatch(text)) return null;
    final rupees = int.tryParse(text);
    if (rupees == null || rupees <= 0 || rupees > maxPriceRupees) return null;
    return rupees * 100;
  }

  /// Seller-facing error for a whole-rupee price field, or `null` when valid.
  static String? validatePriceRupees(String raw) {
    final text = raw.trim().replaceAll(',', '');
    if (text.isEmpty) return 'Enter a price in ₹.';
    if (!RegExp(r'^\d+$').hasMatch(text)) {
      return 'Enter the price as a whole number of rupees.';
    }
    final rupees = int.tryParse(text);
    if (rupees == null || rupees > maxPriceRupees) return 'Price is too large.';
    if (rupees <= 0) return 'Enter a price above ₹0.';
    return null;
  }

  /// Validates a complete piece. Returns field → message for every problem
  /// (empty map when the piece can be saved).
  static Map<String, String> validatePiece({
    required String code,
    required String title,
    required String size,
    required int? pricePaisa,
  }) {
    final errors = <String, String>{};
    final codeError = validateCode(code);
    if (codeError != null) errors['code'] = codeError;
    final titleError = validateTitle(title);
    if (titleError != null) errors['title'] = titleError;
    final sizeError = validateSize(size);
    if (sizeError != null) errors['size'] = sizeError;
    final priceError = validatePricePaisa(pricePaisa);
    if (priceError != null) errors['price'] = priceError;
    return errors;
  }
}
