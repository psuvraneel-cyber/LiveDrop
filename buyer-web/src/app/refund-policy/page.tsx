import Link from 'next/link';
import type { Metadata } from 'next';
import { LegalPage, Section } from '../../components/legal/LegalPage';
import { legalValue } from '../../lib/legal/legal-config';

export const metadata: Metadata = {
  title: 'Refunds & Returns',
  description: 'Cancellations, refunds and returns on LiveDrop.',
};

export default function RefundPolicyPage() {
  return (
    <LegalPage title="Refunds & Returns">
      <p>
        Pieces on LiveDrop are sold by independent boutiques. This policy sets the minimum every seller follows; a seller
        may offer more generous terms on their store page.
      </p>

      <Section title="1. Reservations that end">
        <p>
          If your reservation ends before you submit a payment, the order is cancelled and nothing is charged. If you paid
          but did not submit the UTR in time, submit it anyway on the order page: the seller will check it and either
          complete the order or refund you.
        </p>
      </Section>

      <Section title="2. When you are refunded">
        <ul style={{ paddingLeft: '20px', display: 'grid', gap: '6px' }}>
          <li>Your payment arrived after the piece was sold to someone else.</li>
          <li>The seller cancels your order, or cannot ship it.</li>
          <li>You paid more than the amount due.</li>
          <li>A return is accepted under section 3.</li>
        </ul>
        <p>
          The seller refunds the amount owed to the UPI account you paid from within{' '}
          {legalValue('refundWithinDays')} days, and LiveDrop records the refund reference. Your order page shows when a
          refund is owed and when it has been paid. Refunds are made by the seller because payments go directly to them.
        </p>
      </Section>

      <Section title="3. Damaged, wrong or missing items">
        <p>
          Each piece is usually one of a kind, so returns for a change of mind depend on the seller&apos;s own terms. If
          your item arrives damaged, different from its description, or incomplete, tell the seller on WhatsApp within{' '}
          {legalValue('damageReportWithinHours')} hours of delivery, with your order code and photos (an unboxing video
          helps). The seller will offer a return with a refund, or a resolution you agree to.
        </p>
      </Section>

      <Section title="4. Cancelling an order">
        <p>
          You may cancel before the seller ships by messaging the seller with your order code. Money you already paid is
          refunded under section 2. After shipping, section 3 applies.
        </p>
      </Section>

      <Section title="5. If the seller does not respond">
        <p>
          Contact the Grievance Officer (see <Link href="/grievance">Grievances &amp; Contact</Link>) with your order code. LiveDrop
          follows up with the seller and can suspend sellers who do not refund money owed.
        </p>
      </Section>
    </LegalPage>
  );
}
