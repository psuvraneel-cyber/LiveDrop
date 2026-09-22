import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';

/// Screen 10: Luxury Boutique Analytics & Sales Performance Screen
class SellerAnalyticsScreen extends StatefulWidget {
  final SellerRepository repository;

  const SellerAnalyticsScreen({super.key, required this.repository});

  @override
  State<SellerAnalyticsScreen> createState() => _SellerAnalyticsScreenState();
}

class _SellerAnalyticsScreenState extends State<SellerAnalyticsScreen> {
  String _selectedRange = 'Last 7 days';
  bool _isLoading = true;
  SellerAnalytics? _analytics;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final analytics = await widget.repository.getSellerAnalytics(range: _selectedRange);
      if (mounted) {
        setState(() {
          _analytics = analytics;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final revenuePaisa = _analytics?.totalRevenuePaisa ?? 0;
    final revenueFormatted = '₹${(revenuePaisa / 100).toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'),
          (m) => '${m[1]},',
        )}';
    final itemsSold = _analytics?.itemsSoldCount ?? 0;
    final activeHolds = _analytics?.activeHoldsCount ?? 0;
    final paymentClaims = _analytics?.paymentClaimsCount ?? 0;
    final peakPaisa = _analytics?.peakRevenuePaisa ?? 0;
    final peakFormatted = '₹${(peakPaisa / 100).toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'),
          (m) => '${m[1]},',
        )} Peak';

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.obsidianSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedRange,
                dropdownColor: AppColors.obsidianSurface,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'Today', child: Text('Today')),
                  DropdownMenuItem(value: 'Last 7 days', child: Text('Last 7 days')),
                  DropdownMenuItem(value: 'Last 30 days', child: Text('Last 30 days')),
                  DropdownMenuItem(value: 'This Month', child: Text('This Month')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedRange = val);
                    _loadAnalytics();
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldPrimary))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.crimson),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.goldPrimary,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _loadAnalytics,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.goldPrimary,
                  backgroundColor: AppColors.obsidianSurface,
                  onRefresh: _loadAnalytics,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 4 KPI Cards Grid
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.35,
                          children: [
                            _buildKpiCard(
                              title: 'Total Revenue',
                              value: revenueFormatted,
                              valueColor: AppColors.goldPrimary,
                            ),
                            _buildKpiCard(
                              title: 'Items Sold',
                              value: '$itemsSold',
                            ),
                            _buildKpiCard(
                              title: 'Active Holds',
                              value: '$activeHolds',
                              valueColor: AppColors.amber,
                            ),
                            _buildKpiCard(
                              title: 'Payment Claims',
                              value: '$paymentClaims',
                              valueColor: AppColors.crimson,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Sales Trend Graph Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: AppTheme.cardDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Sales Trend',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.goldMuted,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.goldPrimary, width: 0.8),
                                    ),
                                    child: Text(
                                      peakFormatted,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.goldPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Trend Graph Area
                              SizedBox(
                                height: 160,
                                width: double.infinity,
                                child: CustomPaint(
                                  painter: SalesTrendChartPainter(
                                    dailySales: _analytics?.dailySales ?? const [],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Day Axis Labels
                              if (_analytics != null && _analytics!.dailySales.isNotEmpty)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: _analytics!.dailySales.map((d) {
                                    final isPeak = peakPaisa > 0 && d.totalPaisa == peakPaisa;
                                    return Text(
                                      d.dayLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isPeak ? FontWeight.bold : FontWeight.normal,
                                        color: isPeak ? AppColors.goldPrimary : AppColors.textMuted,
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Top Performing Products
                        const Text(
                          'Top Performing Products',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (_analytics == null || _analytics!.topProducts.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                            decoration: AppTheme.cardDecoration(),
                            child: const Center(
                              child: Column(
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.textMuted),
                                  SizedBox(height: 8),
                                  Text(
                                    'No sales in this period',
                                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Top selling pieces will be ranked here as orders are confirmed.',
                                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._analytics!.topProducts.map((p) {
                            final rev = '₹${(p.revenuePaisa / 100).toStringAsFixed(0).replaceAllMapped(
                                  RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'),
                                  (m) => '${m[1]},',
                                )}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildTopProductItem(
                                '#${p.productCode} ${p.title}',
                                '${p.soldCount} sold',
                                rev,
                                imageUrl: p.imageUrl,
                              ),
                            );
                          }),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    String? badge,
    Color badgeColor = AppColors.emerald,
    Color valueColor = AppColors.textPrimary,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductItem(String title, String count, String revenue, {String? imageUrl}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 44,
              color: AppColors.obsidianElevated,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.checkroom_rounded,
                        color: AppColors.goldPrimary,
                        size: 24,
                      ),
                    )
                  : const Icon(Icons.checkroom_rounded, color: AppColors.goldPrimary, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            revenue,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.goldPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom Vector Painter for Smooth Gold Sales Trend Curve
class SalesTrendChartPainter extends CustomPainter {
  final List<DailySalesStat> dailySales;

  const SalesTrendChartPainter({this.dailySales = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Grid lines (horizontal)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, h * 0.25), Offset(w, h * 0.25), gridPaint);
    canvas.drawLine(Offset(0, h * 0.50), Offset(w, h * 0.50), gridPaint);
    canvas.drawLine(Offset(0, h * 0.75), Offset(w, h * 0.75), gridPaint);

    if (dailySales.isEmpty) {
      // Draw flat baseline
      final basePaint = Paint()
        ..color = AppColors.goldPrimary.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(0, h * 0.8), Offset(w, h * 0.8), basePaint);
      return;
    }

    int maxPaisa = 0;
    int peakIndex = 0;
    for (int i = 0; i < dailySales.length; i++) {
      if (dailySales[i].totalPaisa > maxPaisa) {
        maxPaisa = dailySales[i].totalPaisa;
        peakIndex = i;
      }
    }

    final points = <Offset>[];
    final count = dailySales.length;
    for (int i = 0; i < count; i++) {
      final x = count > 1 ? (w / (count - 1)) * i : w / 2;
      final ratio = maxPaisa > 0 ? (dailySales[i].totalPaisa / maxPaisa) : 0.0;
      final y = h * 0.85 - (ratio * (h * 0.65));
      points.add(Offset(x, y));
    }

    if (points.length == 1) {
      points.add(Offset(w, points.first.dy));
    }

    // Build smooth Bezier path
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPointX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlPointX, p0.dy, controlPointX, p1.dy, p1.dx, p1.dy);
    }

    // Gradient fill under line
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.goldPrimary.withValues(alpha: 0.35),
        Colors.transparent,
      ],
    );

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill,
    );

    // Stroke line
    final linePaint = Paint()
      ..shader = AppColors.goldGradient.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Peak dot highlight if there is a non-zero peak
    if (maxPaisa > 0 && peakIndex < points.length) {
      final peak = points[peakIndex];
      canvas.drawCircle(
        peak,
        6.0,
        Paint()..color = AppColors.goldPrimary,
      );
      canvas.drawCircle(
        peak,
        2.5,
        Paint()..color = Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SalesTrendChartPainter oldDelegate) {
    return oldDelegate.dailySales != dailySales;
  }
}
