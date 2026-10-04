import '../../domain/models/models.dart';

/// What the seller can do with an order next (SA-ORD-005).
enum OrderAction {
  /// WhatsApp the buyer their order link and the amount due.
  remindPayment,

  /// Release the hold (only without a buyer payment claim).
  releaseHold,

  /// Advance paid, balance outstanding: ask the buyer for the balance.
  collectBalance,

  /// Fully paid and not packed yet: `mark_order_ready_to_ship`.
  markPacked,

  /// Packed: enter courier and AWB, then `mark_order_shipped`.
  dispatch,

  /// Print the label (before dispatch, without a barcode until there is an AWB).
  printLabel,

  /// Shipped: print the label again.
  reprintLabel,
}

/// Derives the order's actions exactly as the server RPCs allow them
/// (migrations 015/026/035): packing and dispatch need a fully paid order
/// (payment_status `paid`, no balance due), dispatch needs a packed order,
/// release needs a pending order without a payment claim.
class OrderActions {
  OrderActions._();

  /// Cancelled or expired: shown under "Closed" (SA-ORD-004).
  static bool isClosed(SellerOrder o) => o.status == OrderStatus.cancelled || o.status == OrderStatus.expired;

  /// Why a closed order is closed, in the seller's words (SA-ORD-004).
  static String closedReason(SellerOrder o) {
    String rupees(int paisa) => '₹${(paisa / 100).toStringAsFixed(0)}';
    if (o.refundStatus == RefundStatus.required) {
      return 'Refund owed: ${rupees(o.refundAmountPaisa)}. The buyer paid after the piece was gone.';
    }
    if (o.refundStatus == RefundStatus.refunded) {
      return 'Refunded ${rupees(o.refundAmountPaisa)}.';
    }
    if (o.status == OrderStatus.expired) {
      return o.advancePaidPaisa > 0
          ? 'Expired: the balance was not paid in time; the ${rupees(o.advancePaidPaisa)} advance was kept.'
          : 'Expired.';
    }
    return o.totalPaidPaisa > 0
        ? 'Cancelled after ${rupees(o.totalPaidPaisa)} was paid. Check Payments.'
        : 'Cancelled: no payment, the piece went back on sale.';
  }

  static bool isFullyPaid(SellerOrder o) =>
      o.paymentStatus == OrderPaymentStatus.paid && o.balanceDuePaisa <= 0;

  static List<OrderAction> forOrder(SellerOrder o) {
    if (o.status == OrderStatus.cancelled || o.status == OrderStatus.expired) {
      return const [];
    }
    if (o.status == OrderStatus.shipped || o.fulfilmentStatus == OrderFulfilmentStatus.shipped) {
      return const [OrderAction.reprintLabel];
    }
    if (o.status == OrderStatus.pending && o.paymentStatus == OrderPaymentStatus.unpaid) {
      return [
        OrderAction.remindPayment,
        if (!o.hasPendingPaymentClaim) OrderAction.releaseHold,
      ];
    }
    if (!isFullyPaid(o)) {
      // Advance paid (or a claim on the balance in flight): no packing yet.
      return o.balanceDuePaisa > 0 ? const [OrderAction.collectBalance] : const [];
    }
    if (o.fulfilmentStatus == OrderFulfilmentStatus.readyToShip) {
      return const [OrderAction.dispatch, OrderAction.printLabel];
    }
    return const [OrderAction.markPacked];
  }
}
