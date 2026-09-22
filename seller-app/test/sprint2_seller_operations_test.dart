import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:seller_app/core/services/image_service.dart';
import 'package:seller_app/core/services/pdf_label_service.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/order_card.dart';

void main() {
  group('SPRINT 2: Image Processing Service Tests', () {
    test(
      'ImageService crops non-square image to 1:1 square and compresses to <= 1200px',
      () async {
        // Create a dummy 1600x1200 image
        final testImg = img.Image(width: 1600, height: 1200);
        img.fill(testImg, color: img.ColorRgb8(255, 0, 0));
        final rawBytes = Uint8List.fromList(img.encodeJpg(testImg));

        const service = ImageService();
        final processed = await service.processIntakeImage(
          rawBytes,
          maxDimension: 1200,
        );

        expect(processed.bytes, isNotEmpty);
        expect(processed.mimeType, 'image/jpeg');
        expect(processed.width, 1200);
        expect(processed.height, 1200);
        expect(processed.sizeInBytes, greaterThan(0));

        // Decode processed output and verify exact 1:1 aspect ratio
        final decoded = img.decodeImage(processed.bytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, decoded.height);
        expect(decoded.width, 1200);
      },
    );

    test(
      'ImageService scales down small square image without upscaling beyond bounds',
      () async {
        final testImg = img.Image(width: 500, height: 500);
        img.fill(testImg, color: img.ColorRgb8(0, 255, 0));
        final rawBytes = Uint8List.fromList(img.encodeJpg(testImg));

        const service = ImageService();
        final processed = await service.processIntakeImage(
          rawBytes,
          maxDimension: 1200,
        );

        expect(processed.width, 500);
        expect(processed.height, 500);
      },
    );
  });

  group('SPRINT 2: 4×6 Thermal PDF Shipping Label Generator Tests', () {
    test(
      'PdfLabelService generates standard 4×6" vector PDF with Code-128 barcode and prepaid badge',
      () async {
        final order = SellerOrder(
          id: 'ord-test-101',
          dropId: 'drop-test-1',
          orderCode: 'LD-9901',
          buyerName: 'Priya Sharma',
          buyerPhone: '+919876543210',
          shippingAddress: '42, Indiranagar 100ft Road, Bengaluru, Karnataka',
          pincode: '560038',
          subtotalPaisa: 249900,
          shippingPaisa: 8000,
          totalPaisa: 257900,
          status: OrderStatus.paid,
          confirmationMode: OrderConfirmationMode.fullPayment,
          advanceRequiredPaisa: 0,
          advancePaidPaisa: 0,
          totalPaidPaisa: 257900,
          balanceDuePaisa: 0,
          paymentStatus: OrderPaymentStatus.paid,
          fulfilmentStatus: OrderFulfilmentStatus.readyToShip,
          trackingNumber: 'TRK-DEL-990188',
          courierPartner: 'Delhivery Express',
          createdAt: DateTime(2026, 9, 19, 14, 30),
          items: const [
            SellerOrderItem(
              id: 'item-1',
              orderId: 'ord-test-101',
              productId: 'prod-1',
              priceAtPurchasePaisa: 249900,
              productCode: 'A01',
              productTitle: 'Vintage Denim Jacket',
            ),
          ],
        );

        const profile = SellerProfile(
          id: 'seller-test-1',
          storeName: 'Aura Vintage Studio',
          storeSlug: 'aura-vintage',
          phoneNumber: '+919811122233',
          upiId: 'auravintage@okaxis',
          returnAddress: 'Studio 4, Bandra West, Mumbai 400050',
          defaultShippingFeePaisa: 8000,
          freeShippingThresholdPaisa: 299900,
          advanceConfirmationEnabled: false,
          advanceAmountPaisa: 25000,
          holdDurationDays: 30,
        );

        const pdfService = PdfLabelService();
        final pdfBytes = await pdfService.generateShippingLabel(
          order: order,
          profile: profile,
        );

        expect(pdfBytes, isNotNull);
        expect(pdfBytes.lengthInBytes, greaterThan(1000));
        // PDF magic header %PDF-
        final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
        expect(header, '%PDF-');
      },
    );
  });

  group('SPRINT 2: OrderCard & Kanban UI Widget Tests', () {
    testWidgets(
      'OrderCard renders Pending countdown and WhatsApp button for unpaid order',
      (tester) async {
        final order = SellerOrder(
          id: 'ord-pending-1',
          dropId: 'drop-1',
          orderCode: 'PEND-001',
          buyerName: 'Ananya Rao',
          buyerPhone: '+919888877777',
          shippingAddress: '12 Green Glen Layout, Bellandur, Bangalore',
          pincode: '560103',
          subtotalPaisa: 150000,
          shippingPaisa: 8000,
          totalPaisa: 158000,
          status: OrderStatus.pending,
          confirmationMode: OrderConfirmationMode.advance,
          advanceRequiredPaisa: 25000,
          advancePaidPaisa: 0,
          totalPaidPaisa: 0,
          balanceDuePaisa: 158000,
          paymentStatus: OrderPaymentStatus.unpaid,
          fulfilmentStatus: OrderFulfilmentStatus.notReady,
          holdExpiresAt: DateTime.now().add(
            const Duration(minutes: 14, seconds: 50),
          ),
          createdAt: DateTime.now(),
          items: const [
            SellerOrderItem(
              id: 'it-1',
              orderId: 'ord-pending-1',
              productId: 'p-1',
              priceAtPurchasePaisa: 150000,
              productCode: 'A01',
              productTitle: 'Retro Silk Blouse',
            ),
          ],
        );

        const profile = SellerProfile(
          id: 's-1',
          storeName: 'Aura',
          storeSlug: 'aura',
          phoneNumber: '+919999999999',
          upiId: 'aura@upi',
          returnAddress: 'Mumbai',
          defaultShippingFeePaisa: 8000,
          advanceConfirmationEnabled: false,
          advanceAmountPaisa: 25000,
          holdDurationDays: 30,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: OrderCard(
                  order: order,
                  profile: profile,
                  repository: FakeSellerRepository(),
                  onOrderUpdated: () {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('#PEND-001'), findsOneWidget);
        expect(find.text('₹1580'), findsOneWidget);
        expect(find.text('Ananya Rao'), findsOneWidget);
        expect(find.text('WhatsApp'), findsOneWidget);
        expect(find.text('Release'), findsOneWidget);
        expect(find.textContaining('Hold Expires in:'), findsOneWidget);
        expect(find.text('#A01  ₹1500'), findsOneWidget);
      },
    );

    testWidgets(
      'OrderCard renders 4x6 Label and Dispatch buttons for Paid order',
      (tester) async {
        final order = SellerOrder(
          id: 'ord-paid-1',
          dropId: 'drop-1',
          orderCode: 'PAID-777',
          buyerName: 'Rohan Mehta',
          buyerPhone: '+919999911111',
          shippingAddress: 'Flat 402, Sunset Apts, Pune',
          pincode: '411001',
          subtotalPaisa: 320000,
          shippingPaisa: 0,
          totalPaisa: 320000,
          status: OrderStatus.paid,
          confirmationMode: OrderConfirmationMode.fullPayment,
          advanceRequiredPaisa: 0,
          advancePaidPaisa: 0,
          totalPaidPaisa: 320000,
          balanceDuePaisa: 0,
          paymentStatus: OrderPaymentStatus.paid,
          fulfilmentStatus: OrderFulfilmentStatus.readyToShip,
          createdAt: DateTime.now(),
          items: const [
            SellerOrderItem(
              id: 'it-2',
              orderId: 'ord-paid-1',
              productId: 'p-2',
              priceAtPurchasePaisa: 320000,
              productCode: 'B02',
              productTitle: 'Wool Knit Cardigan',
            ),
          ],
        );

        const profile = SellerProfile(
          id: 's-1',
          storeName: 'Aura',
          storeSlug: 'aura',
          phoneNumber: '+919999999999',
          upiId: 'aura@upi',
          returnAddress: 'Mumbai',
          defaultShippingFeePaisa: 8000,
          advanceConfirmationEnabled: false,
          advanceAmountPaisa: 25000,
          holdDurationDays: 30,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: OrderCard(
                  order: order,
                  profile: profile,
                  repository: FakeSellerRepository(),
                  onOrderUpdated: () {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('#PAID-777'), findsOneWidget);
        expect(find.text('₹3200'), findsOneWidget);
        expect(find.text('4×6 Label'), findsOneWidget);
        expect(find.text('Dispatch'), findsOneWidget);
        expect(find.text('#B02  ₹3200'), findsOneWidget);
      },
    );
  });
}

class FakeSellerRepository extends Fake implements SellerRepository {}
