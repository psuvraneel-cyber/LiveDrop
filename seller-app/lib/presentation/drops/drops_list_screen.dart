import 'package:flutter/material.dart';
import '../../core/errors/exceptions.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../../core/services/offline_intake_queue.dart';
import '../intake/camera_intake_screen.dart';
import 'create_drop_screen.dart';

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

  Future<void> _toggleDropStatus(SellerDrop drop, DropStatus targetStatus) async {
    final actionName = targetStatus == DropStatus.live
        ? 'GO LIVE'
        : targetStatus == DropStatus.closed
            ? 'CLOSE DROP'
            : 'SET TO DRAFT';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: Text(
          '$actionName: ${drop.title}?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          targetStatus == DropStatus.live
              ? 'This drop will immediately become visible to buyers on your storefront.\n\nNote: In accordance with LiveDrop rules, any other live drop must be closed first.'
              : 'Closing this drop will stop new buyer reservations. Existing orders can still be packed and dispatched.',
          style: TextStyle(color: Colors.grey.shade300),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: targetStatus == DropStatus.live
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionName),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  onPressed: () => _openCreateDropScreen(drop),
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

            // Slug & Shipping Info
            Text(
              'Slug: /drop/${drop.slug}  •  Shipping: ₹${drop.shippingFeePaisa ~/ 100}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            if (drop.freeShippingThresholdPaisa != null)
              Text(
                'Free shipping on orders above ₹${drop.freeShippingThresholdPaisa! ~/ 100}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
              ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),

            // Action Buttons Strip
            Row(
              children: [
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
                    onPressed: () => _openCameraIntake(drop),
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
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('Re-open Draft', style: TextStyle(fontSize: 12)),
                    onPressed: () => _toggleDropStatus(drop, DropStatus.draft),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
