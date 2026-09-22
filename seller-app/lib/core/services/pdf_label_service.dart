import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/models/models.dart';

/// LiveDrop Seller Mobile App — 4×6" Thermal Shipping Label Generator
///
/// Produces industry-standard 100×150 mm (4×6 inch, 288×432 pt) vector PDF shipping labels
/// compatible with all ESC/POS, Bluetooth, and Wi-Fi thermal label printers.
class PdfLabelService {
  const PdfLabelService();

  /// Generates the standard 4×6" thermal label document as PDF bytes.
  Future<Uint8List> generateShippingLabel({
    required SellerOrder order,
    required SellerProfile profile,
    String? courierPartner,
    String? trackingNumber,
  }) async {
    final pdf = pw.Document();

    final courier = courierPartner ?? order.courierPartner ?? 'DELHIVERY EXPRESS';
    final tracking = trackingNumber ?? order.trackingNumber ?? 'TRK-${order.orderCode}';
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt);
    final totalRupees = (order.totalPaisa / 100).toStringAsFixed(2);

    // 4" x 6" label dimensions (288 x 432 pt)
    const labelFormat = PdfPageFormat(
      4 * PdfPageFormat.inch,
      6 * PdfPageFormat.inch,
      marginAll: 10 * PdfPageFormat.point,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: labelFormat,
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // 1. Header: Courier Partner & Store Branding
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.5)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            courier.toUpperCase(),
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Routing: SURFACE-PRIORITY-STANDARD',
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                        ],
                      ),
                      pw.Text(
                        'LiveDrop Dispatch',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Barcode & Tracking Number
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.5)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: tracking,
                        width: 220,
                        height: 38,
                        drawText: false,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'AWB / TRACKING: $tracking',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Payment Badge & Order Info Banner
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  color: PdfColors.black,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'PREPAID - DO NOT COLLECT CASH',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'INR $totalRupees',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Consignee (Deliver To) Section
                pw.Expanded(
                  flex: 5,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.5)),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'DELIVER TO / SHIP TO:',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                order.buyerName.toUpperCase(),
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                order.shippingAddress,
                                style: const pw.TextStyle(fontSize: 9),
                                maxLines: 3,
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'PHONE: ${order.buyerPhone}',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Pincode Highlight Box
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.black, width: 1.5),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'PINCODE',
                                style: const pw.TextStyle(fontSize: 7),
                              ),
                              pw.Text(
                                order.pincode,
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 5. Consignor (Shipped From / Return Address) & QR
                pw.Expanded(
                  flex: 3,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.5)),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'RETURN / SHIPPED FROM:',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                profile.storeName,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                profile.returnAddress,
                                style: const pw.TextStyle(fontSize: 7),
                                maxLines: 2,
                              ),
                              pw.Text(
                                'Contact: ${profile.phoneNumber}',
                                style: const pw.TextStyle(fontSize: 7),
                              ),
                            ],
                          ),
                        ),
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: 'LIVEDROP:${order.orderCode}:$tracking',
                          width: 44,
                          height: 44,
                        ),
                      ],
                    ),
                  ),
                ),

                // 6. Manifest / Line Items Table Footer
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'ORDER: #${order.orderCode}  |  $dateStr',
                            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            'Items: ${order.items.length}',
                            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Items Manifest: ${order.items.map((it) => "${it.productCode ?? 'ITEM'} (${it.productTitle ?? ''})").join(', ')}',
                        style: const pw.TextStyle(fontSize: 6),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Direct Android Bluetooth / Wi-Fi print spooler dispatch.
  Future<void> printLabel({
    required SellerOrder order,
    required SellerProfile profile,
    String? courierPartner,
    String? trackingNumber,
  }) async {
    final pdfBytes = await generateShippingLabel(
      order: order,
      profile: profile,
      courierPartner: courierPartner,
      trackingNumber: trackingNumber,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'ShippingLabel_${order.orderCode}.pdf',
    );
  }

  /// Shares the PDF shipping label via Android system share (e.g. WhatsApp, Drive, Bluetooth).
  Future<void> shareLabel({
    required SellerOrder order,
    required SellerProfile profile,
    String? courierPartner,
    String? trackingNumber,
  }) async {
    final pdfBytes = await generateShippingLabel(
      order: order,
      profile: profile,
      courierPartner: courierPartner,
      trackingNumber: trackingNumber,
    );

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'ShippingLabel_${order.orderCode}.pdf',
    );
  }
}
