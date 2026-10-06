/**
 * Official tracking page for the courier a seller chose when shipping (seller app shipping
 * dialog). LiveDrop does not receive courier updates, so after "Shipped" the buyer checks the
 * courier's own page, which shows out-for-delivery and delivered. Links open the courier's
 * tracking page; the buyer pastes the tracking number copied from the order page.
 */
export interface CourierTrackingPage {
  name: string;
  url: string;
}

const PAGES: { match: RegExp; page: CourierTrackingPage }[] = [
  { match: /delhivery/i, page: { name: 'Delhivery', url: 'https://www.delhivery.com/tracking' } },
  { match: /blue\s*dart/i, page: { name: 'Blue Dart', url: 'https://www.bluedart.com/tracking' } },
  { match: /xpress\s*bees/i, page: { name: 'Xpressbees', url: 'https://www.xpressbees.com/shipment/tracking' } },
  { match: /dtdc/i, page: { name: 'DTDC', url: 'https://www.dtdc.com/track-your-shipment/' } },
  { match: /shadowfax/i, page: { name: 'Shadowfax', url: 'https://tracker.shadowfax.in/' } },
  // India Post's tracking box is on its home page (deep links to the tracking form are unreliable).
  { match: /india\s*post|speed\s*post/i, page: { name: 'India Post', url: 'https://www.indiapost.gov.in/' } },
];

export function courierTrackingPage(courier: string | null | undefined): CourierTrackingPage | null {
  if (!courier) return null;
  return PAGES.find((p) => p.match.test(courier))?.page ?? null;
}
