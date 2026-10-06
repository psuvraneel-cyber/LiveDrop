import { describe, it, expect } from 'vitest';
import { courierTrackingPage } from '../lib/utils/courier-tracking';

describe('courierTrackingPage', () => {
  it('maps every courier the seller app offers to its official tracking page', () => {
    expect(courierTrackingPage('Delhivery Express')?.url).toBe('https://www.delhivery.com/tracking');
    expect(courierTrackingPage('Blue Dart Express')?.name).toBe('Blue Dart');
    expect(courierTrackingPage('Xpressbees Logistics')?.name).toBe('Xpressbees');
    expect(courierTrackingPage('DTDC Express')?.name).toBe('DTDC');
    expect(courierTrackingPage('Shadowfax')?.name).toBe('Shadowfax');
    expect(courierTrackingPage('India Post Speed Post')?.url).toBe('https://www.indiapost.gov.in/');
  });

  it('returns null for unknown or missing couriers', () => {
    expect(courierTrackingPage('Local bike courier')).toBeNull();
    expect(courierTrackingPage(null)).toBeNull();
  });
});
