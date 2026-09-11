/**
 * LiveDrop — Monetary Formatting Utility
 *
 * All monetary amounts are non-negative integers in Paisa (1 INR = 100 Paisa).
 * Floating-point arithmetic is strictly prohibited (ADR-009).
 */

/**
 * Formats an integer amount in Paisa into a standard Indian Rupee string (e.g., 185000 -> "₹1,850").
 * If the amount includes non-zero paisa, displays the two-digit decimal (e.g., 185050 -> "₹1,850.50").
 */
export function formatPaisaToINR(paisa: number): string {
  if (typeof paisa !== 'number' || isNaN(paisa) || paisa < 0) {
    return '₹0';
  }

  // Integer arithmetic only (ADR-009)
  const integerPaisa = Math.floor(paisa);
  const rupees = Math.floor(integerPaisa / 100);
  const remainder = integerPaisa % 100;

  // Format rupees with Indian numbering system (e.g., 1,85,000)
  const formattedRupees = new Intl.NumberFormat('en-IN').format(rupees);

  if (remainder === 0) {
    return `₹${formattedRupees}`;
  }

  const remainderStr = remainder.toString().padStart(2, '0');
  return `₹${formattedRupees}.${remainderStr}`;
}
