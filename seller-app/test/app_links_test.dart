// SA-AND-003: livedrop-seller://open/<section> links open the right tab.
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/services/app_link_service.dart';

void main() {
  test('our links name a tab; anything else is ignored', () {
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://open/payments')), 3);
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://open/orders')), 2);
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://open/Products')), 1);
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://open/settings')), 4);
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://open/home')), 0);
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://open')), isNull);
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://open/unknown')), isNull);
    expect(AppLinkRoute.tabFor(Uri.parse('livedrop-seller://other/payments')), isNull);
    expect(AppLinkRoute.tabFor(Uri.parse('https://livedrop.store/open/payments')), isNull);
  });

  test('without a platform implementation the service does nothing and never throws', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final service = AppLinkService();
    expect(() => service.start((_) {}), returnsNormally);
    await service.stop();
  });
}
