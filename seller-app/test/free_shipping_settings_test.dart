// SA-PAY-008: the seller can see, edit and clear the shop free-shipping
// threshold, and a drop's own threshold is independent of it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/drops/create_drop_screen.dart';
import 'package:seller_app/presentation/settings/seller_settings_screen.dart';

SellerProfile _profile({int? threshold}) => SellerProfile(
      id: 'seller-1',
      storeName: 'Aarohi Boutique',
      storeSlug: 'aarohi',
      phoneNumber: '9876500001',
      upiId: 'aarohi@okaxis',
      returnAddress: 'Kolkata',
      defaultShippingFeePaisa: 8000,
      freeShippingThresholdPaisa: threshold,
      advanceConfirmationEnabled: false,
      advanceAmountPaisa: 25000,
      holdDurationDays: 30,
      isApproved: true,
    );

class _Repo extends Fake implements SellerRepository {
  _Repo(this.profile);

  SellerProfile profile;
  final List<Map<String, Object?>> profileUpdates = [];
  final List<Map<String, Object?>> dropUpdates = [];

  @override
  Future<SellerProfile> getProfile() async => profile;

  @override
  Future<SellerProfile> updateProfile({
    String? storeName,
    String? phoneNumber,
    String? returnAddress,
    int? defaultShippingFeePaisa,
    int? freeShippingThresholdPaisa,
    bool clearFreeShippingThreshold = false,
    bool? advanceConfirmationEnabled,
    int? advanceAmountPaisa,
    int? holdDurationDays,
    String? upiId,
  }) async {
    profileUpdates.add({
      'threshold': freeShippingThresholdPaisa,
      'clear': clearFreeShippingThreshold,
    });
    profile = _profile(threshold: clearFreeShippingThreshold ? null : freeShippingThresholdPaisa);
    return profile;
  }

  @override
  Future<SellerDrop> updateDrop({
    required String dropId,
    required String title,
    required String slug,
    required int shippingFeePaisa,
    int? freeShippingThresholdPaisa,
    String? streamUrl,
  }) async {
    dropUpdates.add({'dropId': dropId, 'threshold': freeShippingThresholdPaisa});
    return SellerDrop(
      id: dropId,
      sellerId: 'seller-1',
      title: title,
      slug: slug,
      status: DropStatus.draft,
      shippingFeePaisa: shippingFeePaisa,
      freeShippingThresholdPaisa: freeShippingThresholdPaisa,
      createdAt: DateTime.utc(2026, 10, 1),
    );
  }
}

Future<void> _openDefaults(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(1600, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: SellerSettingsScreen(repository: repo)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Order & Shipping Defaults'));
  await tester.tap(find.text('Order & Shipping Defaults'));
  await tester.pumpAndSettle();
}

Finder _thresholdField() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Leave blank for no free shipping',
    );

void main() {
  group('Settings → Order & Shipping Defaults', () {
    testWidgets('shows the current shop threshold and saves an edit', (tester) async {
      final repo = _Repo(_profile(threshold: 200000));
      await _openDefaults(tester, repo);

      expect(tester.widget<TextField>(_thresholdField()).controller!.text, '2000');
      expect(find.textContaining('Shop setting: Free shipping above ₹2,000'), findsOneWidget);

      await tester.enterText(_thresholdField(), '3500');
      await tester.pump();
      expect(find.textContaining('Shop setting: Free shipping above ₹3,500'), findsOneWidget);
      await tester.ensureVisible(find.text('Save Order Defaults'));
      await tester.tap(find.text('Save Order Defaults'));
      await tester.pumpAndSettle();
      expect(repo.profileUpdates.single, {'threshold': 350000, 'clear': false});
    });

    testWidgets('clearing the field turns shop free shipping off', (tester) async {
      final repo = _Repo(_profile(threshold: 200000));
      await _openDefaults(tester, repo);

      await tester.tap(find.byKey(const ValueKey('clear-shop-free-shipping')));
      await tester.pump();
      expect(find.textContaining('Shop setting: No free shipping'), findsOneWidget);
      await tester.ensureVisible(find.text('Save Order Defaults'));
      await tester.tap(find.text('Save Order Defaults'));
      await tester.pumpAndSettle();
      expect(repo.profileUpdates.single, {'threshold': null, 'clear': true});
      expect(find.textContaining('no free shipping'), findsOneWidget); // tile subtitle
    });

    testWidgets('an invalid amount is refused and nothing is saved', (tester) async {
      final repo = _Repo(_profile());
      await _openDefaults(tester, repo);
      expect(tester.widget<TextField>(_thresholdField()).controller!.text, isEmpty);

      await tester.enterText(_thresholdField(), '0');
      await tester.ensureVisible(find.text('Save Order Defaults'));
      await tester.tap(find.text('Save Order Defaults'));
      await tester.pumpAndSettle();
      expect(repo.profileUpdates, isEmpty);
      expect(find.text('Enter a whole rupee amount above 0, or leave it blank'), findsOneWidget);
    });
  });

  group('Create / edit drop threshold', () {
    final dropWithoutThreshold = SellerDrop(
      id: 'drop-1',
      sellerId: 'seller-1',
      title: 'Saturday Live',
      slug: 'saturday-live',
      status: DropStatus.draft,
      shippingFeePaisa: 8000,
      createdAt: DateTime.utc(2026, 10, 1),
    );

    Finder dropThresholdField() => find.byWidgetPredicate(
          (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Free Shipping Threshold'),
        );

    testWidgets('does not prefill the shop value into the drop field', (tester) async {
      final repo = _Repo(_profile(threshold: 200000));
      await tester.pumpWidget(MaterialApp(
        home: CreateDropScreen(repository: repo, profile: repo.profile, existingDrop: dropWithoutThreshold),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(dropThresholdField()).controller!.text, isEmpty);
      expect(find.text('Blank uses your shop setting: Free shipping above ₹2,000'), findsOneWidget);
    });

    testWidgets('clearing a drop threshold saves null (= use shop setting)', (tester) async {
      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final repo = _Repo(_profile());
      final drop = SellerDrop(
        id: 'drop-2',
        sellerId: 'seller-1',
        title: 'Diwali Live',
        slug: 'diwali-live',
        status: DropStatus.draft,
        shippingFeePaisa: 8000,
        freeShippingThresholdPaisa: 299900,
        createdAt: DateTime.utc(2026, 10, 1),
      );
      await tester.pumpWidget(MaterialApp(
        home: CreateDropScreen(repository: repo, profile: repo.profile, existingDrop: drop),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(dropThresholdField()).controller!.text, '2999');
      expect(find.text('This drop: Free shipping above ₹2,999'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear (use shop setting)'));
      await tester.pump();
      expect(find.text('Blank uses your shop setting: No free shipping'), findsOneWidget);

      final save = find.byType(ElevatedButton);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.dropUpdates.single, {'dropId': 'drop-2', 'threshold': null});
    });
  });
}
