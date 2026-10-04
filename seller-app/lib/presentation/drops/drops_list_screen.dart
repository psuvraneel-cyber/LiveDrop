import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config/env_config.dart';
import '../../core/errors/exceptions.dart';
import '../../core/utils/url_launcher_helper.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../../core/services/offline_intake_queue.dart';
import '../intake/camera_intake_screen.dart';
import 'create_drop_screen.dart';
import 'go_live_checklist.dart';
import '../../core/validation/drop_rules.dart';
import '../../core/validation/free_shipping_rules.dart';
import '../../core/services/app_log.dart';

/// LiveDrop Seller Mobile App — Drops List & Drop Lifecycle Management Screen
class DropsListScreen extends StatefulWidget {
  final SellerRepository repository;
  final OfflineIntakeQueue? intakeQueue;

  const DropsListScreen({
    super.key,
    required this.repository,
    this.intakeQueue,
  });

  @override
  State<DropsListScreen> createState() => _DropsListScreenState();
}

class _DropsListScreenState extends State<DropsListScreen> {
  List<SellerDrop> _drops = [];
  SellerProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileFuture = widget.repository.getProfile();
      final dropsFuture = widget.repository.getDrops();

      final results = await Future.wait([profileFuture, dropsFuture]);
      if (mounted) {
        setState(() {
          _profile = results[0] as SellerProfile;
          _drops = results[1] as List<SellerDrop>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is LiveDropException ? e.message : e.toString();
        });
      }
    }
  }

  /// Status actions follow docs/09 §2 (enforced by migration 039):
  /// draft -> live after the go-live checklist (SA-DROP-004), live -> closed
  /// with a confirmation. A closed drop is never reopened (SA-DROP-001).
  Future<void> _toggleDropStatus(SellerDrop drop, DropStatus targetStatus) async {
    bool confirmed;
    if (targetStatus == DropStatus.live) {
      confirmed = await _confirmGoLive(drop);
    } else if (targetStatus == DropStatus.closed) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E24),
              title: Text(
                'Close "${drop.title}"?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Text(
                'Buyers can no longer reserve pieces from this drop. Pieces held without a payment go back '
                'on sale; orders that are paid or waiting for your payment check stay, and you can still '
                'pack and ship them.\n\nA closed drop cannot be reopened. For your next live, start a new drop.',
                style: TextStyle(color: Colors.grey.shade300),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Close drop'),
                ),
              ],
            ),
          ) ==
          true;
    } else {
      return;
    }

    if (!confirmed) return;

    try {
      final updated = await widget.repository.updateDropStatus(
        dropId: drop.id,
        status: targetStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Drop "${updated.title}" is now ${updated.status.name.toUpperCase()}'),
            backgroundColor: updated.status == DropStatus.live
                ? const Color(0xFF10B981)
                : const Color(0xFF3B82F6),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is LiveDropException ? e.message : 'Status update failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<bool> _confirmGoLive(SellerDrop drop) async {
    List<SellerProduct> products = const [];
    try {
      products = await widget.repository.getProducts(drop.id);
    } catch (e, st) {
      AppLog.error('drops_list_screen:148', e, st);
      // Unknown product count: the checklist then blocks with "0 pieces".
    }
    if (!mounted) return false;
    final readiness = GoLiveReadiness.evaluate(
      drop: drop,
      products: products,
      queuedItems: widget.intakeQueue?.items ?? const [],
      profile: _profile,
      allDrops: _drops,
    );
    return showGoLiveChecklist(context, drop, readiness);
  }

  void _openCreateDropScreen([SellerDrop? existingDrop]) async {
    final result = await Navigator.of(context).push<SellerDrop>(
      MaterialPageRoute(
        builder: (_) => CreateDropScreen(
          repository: widget.repository,
          profile: _profile,
          existingDrop: existingDrop,
        ),
      ),
    );

    if (result != null) {
      _loadData();
    }
  }

  void _openCameraIntake(SellerDrop drop) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraIntakeScreen(
          drop: drop,
          repository: widget.repository,
          intakeQueue: widget.intakeQueue,
        ),
      ),
    );
  }

  void _copyDropUrl(SellerDrop drop) async {
    final url = EnvConfig.getDropUrl(drop.slug);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E1E24),
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Buyer URL copied: $url',
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: const Color(0xFFF59E0B),
          onPressed: () => _openDropInBrowser(drop),
        ),
      ),
    );
  }

  void _openDropInBrowser(SellerDrop drop) {
    final url = EnvConfig.getDropUrl(drop.slug);
    UrlLauncherHelper.launchExternalWebUrl(context: context, url: url);
  }

  void _shareDropViaWhatsApp(SellerDrop drop) {
    final url = EnvConfig.getDropUrl(drop.slug);
    final storeName = _profile?.storeName ?? 'Our boutique';
    final message = '✨ Check out "$storeName"\'s live drop: ${drop.title}!\n\nBrowse catalog & shop directly: $url';
    UrlLauncherHelper.launchExternalWebUrl(
      context: context,
      url: 'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181B),
        elevation: 0,
        title: const Text(
          'Drops & Catalog Intake',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFF59E0B),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('New Drop', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openCreateDropScreen(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _drops.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white24),
                          const SizedBox(height: 16),
                          const Text(
                            'No drops created yet.',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Create your first drop to start rapid garment camera intake.',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Create First Drop'),
                            onPressed: () => _openCreateDropScreen(),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFFF59E0B),
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: _drops.length,
                        itemBuilder: (ctx, i) {
                          final drop = _drops[i];
                          return _buildDropCard(drop);
                        },
                      ),
                    ),
    );
  }

  Widget _buildDropCard(SellerDrop drop) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (drop.status) {
      case DropStatus.live:
        statusColor = const Color(0xFF10B981);
        statusLabel = 'LIVE NOW';
        statusIcon = Icons.sensors;
        break;
      case DropStatus.closed:
        statusColor = Colors.grey.shade500;
        statusLabel = 'CLOSED';
        statusIcon = Icons.lock_outline;
        break;
      case DropStatus.draft:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'DRAFT';
        statusIcon = Icons.edit_note;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: drop.status == DropStatus.live
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  color: const Color(0xFF2A2A32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) {
                    switch (value) {
                      case 'copy':
                        _copyDropUrl(drop);
                        break;
                      case 'open':
                        _openDropInBrowser(drop);
                        break;
                      case 'share_wa':
                        _shareDropViaWhatsApp(drop);
                        break;
                      case 'edit':
                        _openCreateDropScreen(drop);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.copy_rounded, color: Color(0xFFF59E0B), size: 18),
                          SizedBox(width: 10),
                          Text('Copy Buyer URL', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.open_in_browser_rounded, color: Color(0xFF10B981), size: 18),
                          SizedBox(width: 10),
                          Text('Open in Browser', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share_wa',
                      child: Row(
                        children: [
                          Icon(Icons.share_outlined, color: Color(0xFF3B82F6), size: 18),
                          SizedBox(width: 10),
                          Text('Share via WhatsApp', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
                          SizedBox(width: 10),
                          Text('Edit Drop Details', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Drop Title
            Text(
              drop.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),

            // Slug & Shipping Info (Tap to copy full URL)
            InkWell(
              onTap: () => _copyDropUrl(drop),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Slug: /drop/${drop.slug}  •  Shipping: ₹${drop.shippingFeePaisa ~/ 100}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, size: 13, color: Color(0xFFF59E0B)),
                  ],
                ),
              ),
            ),
            Builder(builder: (_) {
              final policy = FreeShippingRules.forDrop(drop, _profile);
              final suffix = policy.source == FreeShippingSource.shop ? ' (shop setting)' : '';
              return Text(
                '${policy.label}$suffix',
                style: TextStyle(
                  fontSize: 11,
                  color: policy.offersFreeShipping ? const Color(0xFF10B981) : Colors.grey.shade500,
                ),
              );
            }),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),

            // Action Buttons Strip
            Row(
              children: [
                // Quick Share URL Button
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A32),
                    foregroundColor: const Color(0xFFF59E0B),
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFF59E0B), width: 0.8),
                    ),
                  ),
                  tooltip: 'Share or Copy Drop URL',
                  icon: const Icon(Icons.share_rounded, size: 18),
                  onPressed: () => _copyDropUrl(drop),
                ),
                const SizedBox(width: 8),

                // Camera Intake Action
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A32),
                      foregroundColor: const Color(0xFFF59E0B),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text(
                      'Camera Intake',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    // A closed drop takes no new pieces (SA-INV-002).
                    onPressed: DropRules.acceptsNewPieces(drop) ? () => _openCameraIntake(drop) : null,
                  ),
                ),
                const SizedBox(width: 10),

                // Go Live or Close Action
                if (drop.status == DropStatus.draft)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Go Live', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _toggleDropStatus(drop, DropStatus.live),
                  )
                else if (drop.status == DropStatus.live)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                    ),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Close Drop', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _toggleDropStatus(drop, DropStatus.closed),
                  )
                else
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    // Closed drops are never reopened (SA-DROP-001): start a new one.
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('New drop', style: TextStyle(fontSize: 12)),
                    onPressed: () => _openCreateDropScreen(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
