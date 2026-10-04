// P1 round 4: account safety, drop lifecycle and inventory (SA-AUTH-004,
// SA-DROP-001/002/004, SA-INV-001/002). The database side is covered by
// audit/seller-app/tests/sql/21_p1_round4.sql.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/core/services/offline_intake_queue.dart';
import 'package:seller_app/core/validation/drop_rules.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/drops/create_drop_screen.dart';
import 'package:seller_app/presentation/drops/drops_list_screen.dart';
import 'package:seller_app/presentation/drops/go_live_checklist.dart';
import 'package:seller_app/presentation/payment_settings_screen.dart';
import 'package:seller_app/presentation/products/product_details_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/p0_fakes.dart';

SellerProduct _piece({
  String id = 'p1',
  String dropId = 'drop-1',
  ProductStatus status = ProductStatus.available,
  DateTime? soldOfflineAt,
}) =>
    SellerProduct(
      id: id,
      dropId: dropId,
      code: '#A0${id.substring(1)}',
      title: 'Kantha Saree',
      pricePaisa: 150000,
      size: 'Free Size',
      imageUrl: 'https://x.supabase.co/a.jpg',
      status: status,
      version: 1,
      soldOfflineAt: soldOfflineAt,
    );

IntakeQueueItem _queued(String dropId, IntakeQueueStatus status) => IntakeQueueItem(
      id: 'q-$dropId-${status.name}',
      dropId: dropId,
      code: '#Q01',
      title: 'Queued',
      pricePaisa: 100000,
      size: 'M',
      localImagePaths: const [],
      remoteImageUrls: const [],
      status: status,
      retryCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

class _Repo extends P0FakeRepo {
  _Repo({super.drops});

  final List<String> markSoldCalls = [];
  final List<String> undoCalls = [];
  final List<String> reauthPasswords = [];
  final List<String> savedVpas = [];
  Object? reauthError;

  @override
  Future<bool> markProductSoldOffline(String productId) async {
    markSoldCalls.add(productId);
    return true;
  }

  @override
  Future<void> undoMarkProductSoldOffline(String productId) async {
    undoCalls.add(productId);
  }

  @override
  Future<void> reauthenticate(String password) async {
    reauthPasswords.add(password);
    final error = reauthError;
    if (error != null) throw error;
  }

  @override
  Future<List<PayeeChange>> getPayeeChangeLog({int limit = 10}) async => const [];

  @override
  Future<void> updateUpiSettings({
    required bool upiEnabled,
    required String upiVpa,
    String? upiDisplayName,
    String? paymentInstructions,
  }) async {
    savedVpas.add(upiVpa);
  }
}

void main() {
  group('DropRules (SA-INV-002, SA-DROP-002)', () {
    test('new pieces never go to a closed drop', () {
      final closed = testDrop(id: 'c', status: DropStatus.closed);
      final draft = testDrop(id: 'd', status: DropStatus.draft);
      final live = testDrop(id: 'l', status: DropStatus.live);
      expect(DropRules.intakeTarget([closed]), isNull);
      expect(DropRules.intakeTarget([closed, draft])?.id, 'd');
      expect(DropRules.intakeTarget([draft, live, closed])?.id, 'l');
      expect(DropRules.acceptsNewPieces(closed), isFalse);
      expect(DropRules.acceptsNewPieces(draft), isTrue);
    });

    test('the drop link is editable only while the drop is a draft', () {
      expect(DropRules.slugEditable(null), isTrue); // creating a new drop
      expect(DropRules.slugEditable(testDrop(status: DropStatus.draft)), isTrue);
      expect(DropRules.slugEditable(testDrop(status: DropStatus.live)), isFalse);
      expect(DropRules.slugEditable(testDrop(status: DropStatus.closed)), isFalse);
    });
  });

  group('GoLiveReadiness (SA-DROP-004)', () {
    final draft = testDrop(id: 'd', status: DropStatus.draft);

    test('ready when pieces are on sale, uploads finished, UPI on and no other live drop', () {
      final r = GoLiveReadiness.evaluate(
        drop: draft,
        products: [_piece(dropId: 'd')],
        queuedItems: [_queued('d', IntakeQueueStatus.completed), _queued('other', IntakeQueueStatus.pending)],
        profile: testProfile,
        allDrops: [draft],
      );
      expect(r.canGoLive, isTrue);
      // The missing stream link is only a warning.
      expect(r.checks.where((c) => !c.passed).map((c) => c.blocking), [false]);
    });

    test('blocks with no piece on sale, unfinished uploads, UPI off or another live drop', () {
      const upiOff = SellerProfile(
        id: 'seller-1', storeName: 'Aarohi Boutique', storeSlug: 'aarohi-boutique', phoneNumber: '9876500001',
        upiId: 'aarohi@okaxis', returnAddress: '12 MG Road, Kolkata 700001', defaultShippingFeePaisa: 8000,
        advanceConfirmationEnabled: false, advanceAmountPaisa: 25000, holdDurationDays: 30, isApproved: true,
        upiEnabled: false,
      );
      final otherLive = testDrop(id: 'l', title: 'Friday Live', status: DropStatus.live);
      final r = GoLiveReadiness.evaluate(
        drop: draft,
        products: [_piece(dropId: 'd', status: ProductStatus.sold)],
        queuedItems: [_queued('d', IntakeQueueStatus.needsAttention)],
        profile: upiOff,
        allDrops: [draft, otherLive],
      );
      expect(r.canGoLive, isFalse);
      final failedBlocking = r.checks.where((c) => c.blocking && !c.passed).map((c) => c.label).toList();
      expect(failedBlocking, ['0 pieces on sale', '1 still uploading', 'UPI payments are off', '"Friday Live" is still live']);
    });
  });

  test('trigger hints become error codes (migration 039)', () {
    final e = liveDropExceptionFrom(const PostgrestException(
      message: 'The drop link cannot be changed once the drop has gone live.',
      code: '42501',
      hint: 'DROP_SLUG_LOCKED',
    ));
    expect(e.code, 'DROP_SLUG_LOCKED');
    expect(liveDropExceptionFrom(const PostgrestException(message: 'x', code: '23505', hint: 'other')).code, '23505');
  });

  test('an offline sale can be undone for 30 minutes (ADR-014)', () {
    final now = DateTime(2026, 10, 4, 12);
    expect(_piece(status: ProductStatus.sold, soldOfflineAt: now.subtract(const Duration(minutes: 29))).canUndoOfflineSale(now), isTrue);
    expect(_piece(status: ProductStatus.sold, soldOfflineAt: now.subtract(const Duration(minutes: 31))).canUndoOfflineSale(now), isFalse);
    expect(_piece(status: ProductStatus.sold).canUndoOfflineSale(now), isFalse); // sold through an order
    expect(_piece(soldOfflineAt: now).canUndoOfflineSale(now), isFalse); // available again
  });

  group('Product details: Mark Sold (SA-INV-001)', () {
    testWidgets('a reserved piece offers no Mark Sold and says why', (tester) async {
      final repo = _Repo();
      await tester.pumpWidget(testApp(ProductDetailsScreen(product: _piece(status: ProductStatus.reserved), repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Reserved'), findsWidgets);
      expect(find.byKey(const Key('product-reserved-note')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('product-mark-sold')));
      await tester.tap(find.byKey(const Key('product-mark-sold')));
      await tester.pumpAndSettle();
      expect(repo.markSoldCalls, isEmpty);
    });

    testWidgets('Mark Sold asks first, then offers Undo', (tester) async {
      final repo = _Repo();
      await tester.pumpWidget(testApp(ProductDetailsScreen(product: _piece(), repository: repo)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('product-mark-sold')));
      await tester.tap(find.byKey(const Key('product-mark-sold')));
      await tester.pumpAndSettle();
      expect(find.textContaining('undo it for 30 minutes'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.markSoldCalls, ['p1']);
      expect(find.text('Undo sale'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('product-mark-sold')));
      await tester.tap(find.byKey(const Key('product-mark-sold')));
      await tester.pumpAndSettle();
      expect(repo.undoCalls, ['p1']);
      expect(find.text('Mark Sold'), findsOneWidget);
    });

    testWidgets('a piece sold offline over 30 minutes ago shows Sold, no Undo', (tester) async {
      final repo = _Repo();
      final old = _piece(status: ProductStatus.sold, soldOfflineAt: DateTime.now().subtract(const Duration(hours: 2)));
      await tester.pumpWidget(testApp(ProductDetailsScreen(product: old, repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Undo sale'), findsNothing);
      expect(find.text('Sold'), findsWidgets);
    });
  });

  group('Payment settings: new UPI ID needs the password (SA-AUTH-004)', () {
    Future<void> changeVpaAndSave(WidgetTester tester, _Repo repo) async {
      await tester.pumpWidget(testApp(PaymentSettingsScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'aarohi@okaxis'), 'aarohi.new@okaxis');
      await tester.ensureVisible(find.text('Save Payment Settings'));
      await tester.tap(find.text('Save Payment Settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the new UPI ID, asks for the password, then saves', (tester) async {
      final repo = _Repo();
      await changeVpaAndSave(tester, repo);
      expect(find.text('Change your UPI ID?'), findsOneWidget);
      expect(find.textContaining('aarohi.new@okaxis'), findsWidgets);
      expect(repo.savedVpas, isEmpty);

      await tester.enterText(find.byKey(const Key('confirm-password-field')), 'correct horse');
      await tester.tap(find.byKey(const Key('confirm-password-submit')));
      await tester.pumpAndSettle();
      expect(repo.reauthPasswords, ['correct horse']);
      expect(repo.savedVpas, ['aarohi.new@okaxis']);
    });

    testWidgets('a wrong password keeps the dialog open and saves nothing', (tester) async {
      final repo = _Repo()..reauthError = const LiveDropException('That password is not correct.', code: 'WRONG_PASSWORD');
      await changeVpaAndSave(tester, repo);
      await tester.enterText(find.byKey(const Key('confirm-password-field')), 'wrong');
      await tester.tap(find.byKey(const Key('confirm-password-submit')));
      await tester.pumpAndSettle();
      expect(find.text('That password is not correct.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.savedVpas, isEmpty);
    });

    testWidgets('saving other settings with the same UPI ID asks for nothing', (tester) async {
      final repo = _Repo();
      await tester.pumpWidget(testApp(PaymentSettingsScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save Payment Settings'));
      await tester.tap(find.text('Save Payment Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Change your UPI ID?'), findsNothing);
      expect(repo.savedVpas, ['aarohi@okaxis']);
    });
  });

  group('Drops list (SA-DROP-001, SA-DROP-004, SA-INV-002)', () {
    testWidgets('a closed drop offers "New drop", never "Re-open Draft", and no camera intake', (tester) async {
      final repo = _Repo(drops: [testDrop(status: DropStatus.closed)]);
      await tester.pumpWidget(testApp(DropsListScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Re-open Draft'), findsNothing);
      expect(find.text('New drop'), findsOneWidget);
      final intake = tester.widget<ElevatedButton>(find.ancestor(of: find.text('Camera Intake'), matching: find.byType(ElevatedButton)));
      expect(intake.onPressed, isNull);
    });

    testWidgets('Go Live opens the checklist and blocks a drop with nothing on sale', (tester) async {
      final repo = _Repo(drops: [testDrop(id: 'd', status: DropStatus.draft)]);
      await tester.pumpWidget(testApp(DropsListScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go Live'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ready to go live'), findsOneWidget);
      expect(find.text('0 pieces on sale'), findsOneWidget);
      final confirm = tester.widget<ElevatedButton>(find.byKey(const Key('go-live-confirm')));
      expect(confirm.onPressed, isNull);
    });
  });

  testWidgets('the drop link field is read-only once the drop has gone live (SA-DROP-002)', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(testApp(CreateDropScreen(repository: repo, existingDrop: testDrop(status: DropStatus.live))));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.descendant(of: find.byKey(const Key('drop-slug-field')), matching: find.byType(TextField)));
    expect(field.readOnly, isTrue);
    expect(find.textContaining('Locked'), findsOneWidget);
  });
}
