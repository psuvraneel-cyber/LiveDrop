/// LiveDrop Seller Mobile App — Typed Exceptions Hierarchy
///
/// Maps PostgREST, Auth, and transactional RPC errors to structured Dart exceptions.
class LiveDropException implements Exception {
  final String message;
  final String code;

  const LiveDropException(this.message, {this.code = 'UNKNOWN_ERROR'});

  @override
  String toString() => 'LiveDropException[$code]: $message';
}

class StockUnavailableException extends LiveDropException {
  final List<String> unavailableProductIds;

  const StockUnavailableException(
    super.message, {
    this.unavailableProductIds = const [],
  }) : super(code: 'STOCK_UNAVAILABLE');
}

class ProductReclaimedException extends LiveDropException {
  const ProductReclaimedException([
    super.message =
        'One or more items in this order were claimed by another buyer after the hold expired.',
  ]) : super(code: 'PRODUCT_ALREADY_RECLAIMED');
}

class UnauthorizedException extends LiveDropException {
  const UnauthorizedException([
    super.message = 'You are not authorized to perform this operation.',
  ]) : super(code: 'UNAUTHORIZED');
}

class OrderNotFoundException extends LiveDropException {
  const OrderNotFoundException([
    super.message = 'Requested order could not be found.',
  ]) : super(code: 'ORDER_NOT_FOUND');
}

class NetworkException extends LiveDropException {
  const NetworkException([
    super.message = 'Network connection failure. Please verify internet access.',
  ]) : super(code: 'NETWORK_ERROR');
}
