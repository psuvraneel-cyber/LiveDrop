import Link from 'next/link';
import type { Metadata } from 'next';
import { LegalPage, Section } from '../../components/legal/LegalPage';
import { legalValue } from '../../lib/legal/legal-config';

export const metadata: Metadata = {
  title: 'Terms of Use',
  description: 'The terms for buying and selling on LiveDrop.',
};

export default function TermsPage() {
  return (
    <LegalPage title="Terms of Use">
      <p>
        These terms apply to everyone who uses LiveDrop, operated by {legalValue('operatorName')}. By placing an order or
        opening a seller account you accept them, together with our <Link href="/privacy">Privacy Policy</Link> and{' '}
        <Link href="/refund-policy">Refunds &amp; Returns</Link> policy.
      </p>

      <Section title="1. What LiveDrop is">
        <p>
          LiveDrop is a marketplace platform. Each piece is sold by the independent boutique shown on the drop and store
          page (the seller), not by LiveDrop. The seller is responsible for the piece, its description, price, photos,
          packing, shipping and returns. LiveDrop provides the website, the seller app, reservations and payment tracking,
          and helps resolve problems between buyers and sellers.
        </p>
      </Section>

      <Section title="2. Reserving and paying">
        <ul style={{ paddingLeft: '20px', display: 'grid', gap: '6px' }}>
          <li>
            Placing an order reserves the pieces for a limited time, shown on the order page. If no payment is submitted in
            time, the reservation ends and the pieces return to sale.
          </li>
          <li>
            You pay the seller directly by UPI (including WhatsApp payments), either the advance the seller asks for or the
            full amount. LiveDrop does not collect or hold your money.
          </li>
          <li>
            After paying, submit the 12-digit UPI transaction reference (UTR) on the order page. The seller checks it against
            their bank account and confirms. Submit only references for payments you actually made; false references may
            lead to the order being cancelled and the matter being reported.
          </li>
          <li>Prices include the shipping fee shown at checkout. Sellers may offer free shipping above a stated amount.</li>
        </ul>
      </Section>

      <Section title="3. Buyer responsibilities">
        <p>
          Give a correct name, WhatsApp number and delivery address, keep your order link private, and do not place orders
          you do not intend to pay for. Repeated unpaid reservations may be blocked.
        </p>
      </Section>

      <Section title="4. Seller responsibilities">
        <p>
          Sellers must be approved by LiveDrop, list only goods they own and may lawfully sell, describe them honestly
          (including defects), honour reservations and confirmed orders, verify payments promptly, ship within the time they
          promise, refund money owed under our refunds policy, use buyers&apos; personal data only to fulfil their orders,
          and comply with applicable laws, including consumer protection and tax laws. LiveDrop may suspend sellers who break
          these terms; suspension closes their live drops.
        </p>
      </Section>

      <Section title="5. Acceptable use">
        <p>
          Do not misuse LiveDrop: no fraud, fake orders or payment references, harassment, illegal or counterfeit goods,
          attempts to break security, or automated scraping of the site.
        </p>
      </Section>

      <Section title="6. Liability">
        <p>
          LiveDrop is provided as available. To the extent the law allows, LiveDrop is not liable for the goods sold by
          sellers or for losses caused by a seller, a payment app, a bank or a courier; we will help you raise and resolve
          complaints with the seller. Nothing in these terms limits rights you have under the Consumer Protection Act, 2019.
        </p>
      </Section>

      <Section title="7. Law and disputes">
        <p>
          These terms are governed by the laws of India. Please first contact the Grievance Officer (see{' '}
          <Link href="/grievance">Grievances &amp; Contact</Link>). Disputes are subject to the courts at{' '}
          {legalValue('jurisdictionCity')}, without affecting your right to approach a consumer commission.
        </p>
      </Section>

      <Section title="8. Changes">
        <p>We may update these terms; the effective date above shows the current version.</p>
      </Section>
    </LegalPage>
  );
}
