/**
 * LiveDrop — business details used by the legal pages (/privacy, /terms, /refund-policy, /grievance).
 *
 * OWNER: fill in every null value before real customers use the site, and have a lawyer review the
 * pages. Until then the pages show a visible placeholder and /admin lists what is missing.
 */

export interface LegalConfig {
  /** Legal name of the business or proprietor operating LiveDrop. */
  operatorName: string | null;
  /** Registered or business address. */
  operatorAddress: string | null;
  /** Support e-mail shown to buyers and sellers. */
  supportEmail: string | null;
  /** Support phone / WhatsApp number. */
  supportPhone: string | null;
  /** Grievance Officer's name (Consumer Protection (E-Commerce) Rules 2020, DPDP Act 2023). */
  grievanceOfficerName: string | null;
  /** City whose courts have jurisdiction. */
  jurisdictionCity: string | null;
  /** Days within which a seller refunds money owed to a buyer. */
  refundWithinDays: number | null;
  /** Hours after delivery within which a buyer reports a damaged or wrong item. */
  damageReportWithinHours: number | null;
  /** Date these pages take effect (YYYY-MM-DD). */
  effectiveDate: string;
}

export const LEGAL: LegalConfig = {
  operatorName: null,
  operatorAddress: null,
  supportEmail: null,
  supportPhone: null,
  grievanceOfficerName: null,
  jurisdictionCity: null,
  refundWithinDays: null,
  damageReportWithinHours: null,
  effectiveDate: '2026-10-06',
};

const LABELS: Record<Exclude<keyof LegalConfig, 'effectiveDate'>, string> = {
  operatorName: 'Business / operator name',
  operatorAddress: 'Business address',
  supportEmail: 'Support e-mail',
  supportPhone: 'Support phone',
  grievanceOfficerName: 'Grievance Officer name',
  jurisdictionCity: 'Jurisdiction city',
  refundWithinDays: 'Refund timeline (days)',
  damageReportWithinHours: 'Damage report window (hours)',
};

/** Labels of the details still missing (shown in /admin). */
export function missingLegalFields(config: LegalConfig = LEGAL): string[] {
  return (Object.keys(LABELS) as (keyof typeof LABELS)[])
    .filter((key) => config[key] === null || config[key] === '')
    .map((key) => LABELS[key]);
}

/** A detail's value, or a visible placeholder naming what is missing. */
export function legalValue(key: keyof typeof LABELS, config: LegalConfig = LEGAL): string {
  const value = config[key];
  return value === null || value === '' ? `[${LABELS[key]} — to be added]` : String(value);
}
