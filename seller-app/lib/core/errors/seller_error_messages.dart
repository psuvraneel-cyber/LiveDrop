import 'dart:async';
import 'dart:io';

import 'exceptions.dart';

/// LiveDrop Seller App — seller-facing error copy.
///
/// RPC error codes are mapped to plain-language messages so the seller never
/// sees raw exception text such as `LiveDropException[...]` or a SQL message.
class SellerErrorMessages {
  SellerErrorMessages._();

  static const String _network =
      'No connection to LiveDrop. Check your internet and try again.';

  /// Error code of [error] when it is a [LiveDropException], else `null`.
  static String? codeOf(Object error) => error is LiveDropException ? error.code : null;

  /// True when [error] means the phone could not reach LiveDrop.
  static bool isNetworkError(Object? error) => error != null && _isNetwork(error);

  static bool _isNetwork(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      (error is LiveDropException && error.code == 'NETWORK_ERROR');

  /// Messages for `force_release_hold` (SA-PAY-005).
  static String releaseHold(Object error) {
    if (_isNetwork(error)) return _network;
    switch (codeOf(error)) {
      case 'PAYMENT_CLAIM_PENDING':
        return 'The buyer has already submitted a payment for this order. '
            'Verify or reject it in Payments before releasing the piece.';
      case 'ONLY_PENDING_CAN_BE_RELEASED':
        return 'Only orders still waiting for payment can be released. '
            'This order has already moved on — pull down to refresh.';
      case 'ORDER_NOT_FOUND_OR_UNAUTHORIZED':
        return 'This order could not be found in your boutique. '
            'It may have been released already — pull down to refresh.';
      case 'UNAUTHORIZED':
        return 'Your session has expired. Please sign in again to release holds.';
      default:
        return 'Could not release the hold right now. Please try again.';
    }
  }

  /// Messages for `mark_order_ready_to_ship` / `mark_order_shipped` (SA-ORD-005).
  static String fulfilment(Object error) {
    if (_isNetwork(error)) return _network;
    switch (codeOf(error)) {
      case 'ORDER_NOT_PAID':
        return 'This order is not fully paid yet. Collect the balance before packing or shipping.';
      case 'ORDER_NOT_READY_TO_SHIP':
        return 'Mark the order as packed before dispatching it.';
      case 'ALREADY_SHIPPED':
        return 'This order has already been shipped. Pull down to refresh.';
      case 'INVALID_ORDER_STATE':
        return 'This order can no longer be packed or shipped. Pull down to refresh.';
      case 'UNAUTHORIZED':
        return 'Your session has expired. Please sign in again.';
      default:
        return 'Could not update this order right now. Please try again.';
    }
  }

  /// Messages for `verify_manual_upi_payment`.
  static String verifyPayment(Object error) {
    if (_isNetwork(error)) return _network;
    switch (codeOf(error)) {
      case 'INVENTORY_CONFLICT':
        return 'The piece is no longer reserved for this order, so the payment '
            'could not be confirmed. Pull down to refresh and check the order.';
      case 'PAYMENT_ATTEMPT_EXPIRED':
        return 'This payment request expired before the buyer paid. '
            'Ask the buyer to place the order again.';
      case 'INVALID_ORDER_STATE':
      case 'INVALID_PAYMENT_STATE':
        return 'This order is no longer waiting for this payment. '
            'Pull down to refresh.';
      case 'REFERENCE_USED_ON_ANOTHER_ORDER':
        return 'This UTR has already been used for another order. '
            'Check your bank statement before verifying.';
      case 'INVALID_UTR':
      case 'INVALID_UTR_FORMAT':
        return 'The UTR on this claim is not valid. Check it against your bank statement.';
      case 'AMOUNT_MISMATCH':
      case 'PAYMENT_AMOUNT_MISMATCH':
        return 'The claimed amount does not match what this order expects. '
            'Nothing was recorded. Reject this claim and settle any extra '
            'money with the buyer directly.';
      case 'LEDGER_INCONSISTENT':
        return 'This order\'s payment records do not add up, so nothing was '
            'recorded. Please contact LiveDrop support before verifying.';
      case 'PAYMENT_ATTEMPT_NOT_FOUND':
      case 'ORDER_NOT_FOUND':
      case 'ORDER_NOT_FOUND_OR_UNAUTHORIZED':
        return 'This payment claim could not be found. Pull down to refresh.';
      case 'UNAUTHORIZED':
        return 'Your session has expired. Please sign in again.';
      default:
        return 'Could not verify this payment right now. Please try again.';
    }
  }

  /// Messages for `reject_manual_upi_payment`.
  static String rejectPayment(Object error) {
    if (_isNetwork(error)) return _network;
    switch (codeOf(error)) {
      case 'INVALID_ORDER_STATE':
      case 'INVALID_PAYMENT_STATE':
      case 'CANNOT_REJECT_VERIFIED':
        return 'This claim was already handled. Pull down to refresh.';
      case 'PAYMENT_ATTEMPT_NOT_FOUND':
        return 'This payment claim could not be found. Pull down to refresh.';
      case 'UNAUTHORIZED':
        return 'Your session has expired. Please sign in again.';
      default:
        return 'Could not reject this claim right now. Please try again.';
    }
  }

  /// Messages for `record_refund` (SA-PAY-004, contract §10).
  static String recordRefund(Object error) {
    if (_isNetwork(error)) return _network;
    switch (codeOf(error)) {
      case 'INVALID_REFUND_REFERENCE':
        return 'Enter the UPI reference of your refund: 4–64 letters, digits, '
            'spaces or . _ / -';
      case 'NO_REFUND_DUE':
        return 'No refund is due on this order any more (it may already be marked '
            'refunded with a different reference). Pull down to refresh.';
      case 'ORDER_NOT_FOUND_OR_UNAUTHORIZED':
        return 'This order could not be found in your boutique.';
      case 'UNAUTHORIZED':
        return 'Your session has expired. Please sign in again.';
      default:
        return 'Could not record the refund right now. Please try again.';
    }
  }
}
