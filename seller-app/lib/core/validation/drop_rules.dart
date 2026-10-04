import '../../domain/models/models.dart';

/// Drop rules shared by every screen (docs/09 §2, migration 039).
class DropRules {
  DropRules._();

  /// The drop new pieces are added to: the live drop, else a draft, never a
  /// closed drop (SA-INV-002). `null` means the seller must create a drop.
  static SellerDrop? intakeTarget(List<SellerDrop> drops) =>
      drops.where((d) => d.status == DropStatus.live).firstOrNull ??
      drops.where((d) => d.status == DropStatus.draft).firstOrNull;

  /// Pieces can be added to draft and live drops only.
  static bool acceptsNewPieces(SellerDrop? drop) =>
      drop != null && drop.status != DropStatus.closed;

  /// The public link can be changed only while the drop is a draft
  /// (SA-DROP-002, enforced by the database since migration 039).
  static bool slugEditable(SellerDrop? drop) => drop == null || drop.status == DropStatus.draft;

  /// Short label for the drop's state, used next to its title.
  static String statusLabel(DropStatus status) {
    switch (status) {
      case DropStatus.live:
        return 'LIVE';
      case DropStatus.draft:
        return 'DRAFT';
      case DropStatus.closed:
        return 'CLOSED';
    }
  }
}
