import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/exceptions.dart';
import '../validation/product_rules.dart';

/// How the offline intake queue must treat a failure (SA-INT-001).
enum IntakeFailureKind {
  /// Network, timeout, 5xx, expired session… — retried with backoff.
  transient,

  /// Validation / permission failure the seller must fix — never auto-retried.
  permanent,

  /// `UNIQUE(drop_id, code)` violation — either our own earlier insert whose
  /// response was lost (then the piece is already live) or a real duplicate.
  duplicateCode,
}

class IntakeFailure {
  final IntakeFailureKind kind;

  /// SQLSTATE, HTTP status or app error code when known.
  final String? code;

  /// Seller-facing explanation shown in the inventory.
  final String reason;

  const IntakeFailure(this.kind, this.reason, {this.code});

  bool get isPermanent => kind == IntakeFailureKind.permanent;
  bool get isTransient => kind == IntakeFailureKind.transient;
}

/// Classifies errors thrown while uploading photos / creating a product.
///
/// Permanent: PostgreSQL integrity/data errors (23514, 23502, 23503, 22001,
/// 22003, 22P02, …), RLS / privilege errors (42501), trigger rejections
/// (P0001) and storage 400/403/413/415. `23505` is reported separately as
/// [IntakeFailureKind.duplicateCode]. Everything else (network, timeouts,
/// 5xx, 401/408/429, unknown) is transient and keeps the backoff retries.
class IntakeErrorClassifier {
  IntakeErrorClassifier._();

  static const Set<String> _permanentSqlStates = {
    '23514', // check_violation (code / title / size / price rules)
    '23502', // not_null_violation
    '23503', // foreign_key_violation (drop deleted)
    '23P01', // exclusion_violation
    '22001', // string_data_right_truncation
    '22003', // numeric_value_out_of_range
    '22007', // invalid_datetime_format
    '22008', // datetime_field_overflow
    '22023', // invalid_parameter_value
    '22P02', // invalid_text_representation
    '42501', // insufficient_privilege / RLS violation
    'P0001', // raise_exception from a business-rule trigger
  };

  static const Set<String> _permanentHttpStatuses = {'400', '403', '413', '415'};

  static final RegExp _embeddedCode = RegExp(
    r'(?<![0-9A-Za-z])(23514|23505|23502|23503|23P01|22001|22003|22007|22008|22023|22P02|42501|P0001)(?![0-9A-Za-z])',
  );

  static IntakeFailure classify(Object error, {String productCode = ''}) {
    final displayCode = ProductRules.normalizeCode(productCode);

    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException ||
        error is HandshakeException) {
      return const IntakeFailure(
        IntakeFailureKind.transient,
        'No connection — will retry automatically.',
        code: 'NETWORK_ERROR',
      );
    }

    String? code;
    String message;
    if (error is PostgrestException) {
      code = error.code;
      message = '${error.message} ${error.details ?? ''} ${error.hint ?? ''}';
    } else if (error is StorageException) {
      return _classifyHttpStatus(error.statusCode, error.message);
    } else if (error is LiveDropException) {
      code = error.code;
      message = error.message;
    } else {
      message = error.toString();
    }

    if (code == 'DUPLICATE_PRODUCT_CODE' ||
        (code == null && message.contains('DUPLICATE_PRODUCT_CODE'))) {
      code = '23505';
    }
    code ??= _embeddedCode.firstMatch(message)?.group(1);

    if (code == null) {
      return IntakeFailure(
        IntakeFailureKind.transient,
        'Upload interrupted — will retry automatically.',
        code: error is LiveDropException ? error.code : null,
      );
    }

    if (code == '23505') {
      return IntakeFailure(
        IntakeFailureKind.duplicateCode,
        'Code ${displayCode.isEmpty ? '' : '$displayCode '}is already used by another '
            'piece in this drop. Change the code.',
        code: '23505',
      );
    }

    if (_permanentSqlStates.contains(code)) {
      return IntakeFailure(
        IntakeFailureKind.permanent,
        _reasonForSqlState(code, message, displayCode),
        code: code,
      );
    }

    if (RegExp(r'^\d{3}$').hasMatch(code)) {
      return _classifyHttpStatus(code, message);
    }

    // PGRST301/302 (expired JWT), UNAUTHORIZED (no session yet),
    // POSTGREST_ERROR, STORAGE_ERROR and anything unknown: retry.
    return IntakeFailure(
      IntakeFailureKind.transient,
      code == 'UNAUTHORIZED'
          ? 'Waiting for you to sign in again — will retry automatically.'
          : 'Upload interrupted — will retry automatically.',
      code: code,
    );
  }

  static IntakeFailure _classifyHttpStatus(String? status, String message) {
    final lower = message.toLowerCase();
    if (status != null && _permanentHttpStatuses.contains(status)) {
      String reason;
      if (status == '413' || lower.contains('exceeded') || lower.contains('too large')) {
        reason = 'The photo is too large to upload. Discard this piece and capture it again.';
      } else if (status == '415' || lower.contains('mime')) {
        reason = 'The photo format was rejected. Discard this piece and capture it again.';
      } else if (status == '403' || lower.contains('row-level security') || lower.contains('unauthorized')) {
        reason = 'Not allowed to upload photos for this drop. Check that your seller account is '
            'approved and the drop is yours, then tap Try again.';
      } else {
        reason = 'The photo upload was rejected by the server. Tap Try again or discard the piece.';
      }
      return IntakeFailure(IntakeFailureKind.permanent, reason, code: status);
    }
    return IntakeFailure(
      IntakeFailureKind.transient,
      'Server busy or offline — will retry automatically.',
      code: status,
    );
  }

  static String _reasonForSqlState(String code, String message, String displayCode) {
    final lower = message.toLowerCase();
    switch (code) {
      case '23514':
        if (lower.contains('code')) {
          return 'Code ${displayCode.isEmpty ? '' : '$displayCode '}is not valid. '
              'Use # followed by 1–6 letters or digits (e.g. #A01).';
        }
        if (lower.contains('title')) {
          return 'Title is longer than ${ProductRules.maxTitleLength} characters.';
        }
        if (lower.contains('size')) {
          return 'Size is longer than ${ProductRules.maxSizeLength} characters.';
        }
        if (lower.contains('price')) {
          return 'Price must be more than ₹0.';
        }
        if (lower.contains('image')) {
          return 'The photo link was rejected. Discard this piece and capture it again.';
        }
        return 'The server rejected this piece. Check the code, title, size and price.';
      case '22001':
        return 'A field is too long (title max ${ProductRules.maxTitleLength}, '
            'size max ${ProductRules.maxSizeLength} characters).';
      case '23502':
        return 'A required detail is missing (code, price or photo).';
      case '23503':
        return 'The drop for this piece no longer exists. Discard the piece.';
      case '42501':
        return 'Not allowed: this drop is not in your account or your seller account '
            'is not approved yet. Fix that, then tap Try again.';
      case 'P0001':
        final trimmed = message.trim();
        final short = trimmed.length > 140 ? '${trimmed.substring(0, 140)}…' : trimmed;
        return 'The server refused this piece: $short';
      default:
        return 'A field has an invalid value. Check the code and price.';
    }
  }
}
