import '../../domain/models/models.dart';
import '../config/env_config.dart';

/// WhatsApp payment reminder for a buyer (SA-PAY-013).
///
/// It quotes what the buyer has to pay next (advance, full amount or
/// balance), never the seller's raw UPI ID, and links to the buyer's own
/// order page. A payment made there creates a payment attempt the system
/// can match to the order; a payment sent straight to a UPI ID cannot be.
class PaymentReminder {
  PaymentReminder._();

  static String _rupees(int paisa) {
    final whole = paisa ~/ 100;
    final rest = paisa % 100;
    return rest == 0 ? '₹$whole' : '₹$whole.${rest.toString().padLeft(2, '0')}';
  }

  /// The reminder text, or `null` when nothing is due on [order].
  static String? message(SellerOrder order, {required String storeName}) {
    final due = order.amountDueNowPaisa;
    if (due <= 0) return null;

    final String what;
    if (order.status == OrderStatus.confirmed) {
      what = 'the balance of ${_rupees(due)}';
    } else if (order.confirmationMode == OrderConfirmationMode.advance && due < order.totalPaisa) {
      what = 'an advance of ${_rupees(due)} to confirm it (order total ${_rupees(order.totalPaisa)})';
    } else {
      what = _rupees(due);
    }

    final token = order.orderToken;
    final link = token != null && token.isNotEmpty
        ? 'Pay and send your UTR here: ${EnvConfig.getOrderUrl(order.id, token)}'
        : 'Open your order from the link you got at checkout to pay and send your UTR.';

    return 'Hi ${order.buyerName}!\n\n'
        'This is $storeName. Your order #${order.orderCode} is waiting for $what.\n\n'
        '$link\n\n'
        'Please pay only through this order page, so we can match your payment to your order.';
  }
}
