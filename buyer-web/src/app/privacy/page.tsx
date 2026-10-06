import Link from 'next/link';
import type { Metadata } from 'next';
import { LegalPage, Section } from '../../components/legal/LegalPage';
import { AnalyticsPreference } from '../../components/legal/AnalyticsPreference';
import { legalValue } from '../../lib/legal/legal-config';

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description: 'How LiveDrop collects, uses and protects personal data.',
};

export default function PrivacyPage() {
  return (
    <LegalPage title="Privacy Policy">
      <p>
        LiveDrop (operated by {legalValue('operatorName')}, &quot;we&quot;) is a website where independent boutiques
        (&quot;sellers&quot;) sell pieces during live drops, and buyers reserve and pay for them. This policy explains
        what personal data we process, why, and your rights under the Digital Personal Data Protection Act, 2023.
      </p>

      <Section title="1. Data we collect from buyers">
        <ul style={{ paddingLeft: '20px', display: 'grid', gap: '6px' }}>
          <li>
            <strong>Order details you enter at checkout:</strong> name, WhatsApp mobile number, delivery address and
            pincode.
          </li>
          <li>
            <strong>Order and payment records:</strong> the pieces you reserved, amounts, order status, and the UPI
            transaction reference (UTR) you submit after paying. We never see your UPI PIN, bank account or card details:
            you pay the seller directly in your own UPI or WhatsApp app.
          </li>
          <li>
            <strong>Stored in your own browser:</strong> your bag, your delivery details if you choose to save them, and
            links to orders you placed, so you can come back to them. You can clear these from the bag and the order page,
            or by clearing your browser data.
          </li>
          <li>
            <strong>Anonymous visit counts:</strong> a random visitor id kept in your browser, the kind of page you view,
            the drop, where the visit came from (for example WhatsApp or Facebook), whether you use a phone, tablet or
            computer, and whether this browser has placed an order before. This is not linked to your name, number, orders
            or IP address. Visit records are deleted after 180 days. You can turn this off below.
          </li>
        </ul>
      </Section>

      <Section title="2. Data we collect from sellers">
        <p>
          Account e-mail and password (handled by our authentication provider), store name and link, phone number, UPI ID,
          return address, the onboarding-fee payment reference, product photos and descriptions, and records of the
          seller&apos;s drops, orders and payment checks. The seller app also sends crash reports and uses push
          notifications for new orders and payments.
        </p>
      </Section>

      <Section title="3. Why we use it">
        <ul style={{ paddingLeft: '20px', display: 'grid', gap: '6px' }}>
          <li>To reserve pieces, record payments, and let the seller pack, ship and contact you about your order.</li>
          <li>To handle refunds, cancellations, complaints and fraud prevention.</li>
          <li>To run, secure and improve LiveDrop, using anonymous visit counts and crash reports.</li>
          <li>To meet legal, tax and accounting obligations.</li>
        </ul>
        <p>We do not sell personal data and do not use it for advertising.</p>
      </Section>

      <Section title="4. Who receives it">
        <ul style={{ paddingLeft: '20px', display: 'grid', gap: '6px' }}>
          <li>
            <strong>The seller of your order</strong> receives your name, number, address and order details to fulfil it.
            The seller is responsible for how they use them, for example when booking a courier.
          </li>
          <li>
            <strong>Service providers who host LiveDrop for us:</strong> Supabase (database, accounts, file storage),
            Vercel (website hosting and cookie-free visit statistics) and Google Firebase (seller-app notifications and crash
            reports). They may process data outside India, under their security and privacy terms.
          </li>
          <li>
            <strong>Apps you choose to open:</strong> WhatsApp, Facebook and UPI apps handle data under their own policies.
            A drop page may show the seller&apos;s Facebook Live video using Facebook&apos;s player, which Facebook may use
            to set its own cookies.
          </li>
          <li>Authorities, when the law requires it.</li>
        </ul>
      </Section>

      <Section title="5. How long we keep it">
        <p>
          Order records are kept for as long as needed to complete the order, handle returns and refunds, and meet legal
          and tax requirements, and are then deleted or anonymised. Anonymous visit records are deleted after 180 days.
          Seller account data is kept while the account is active.
        </p>
      </Section>

      <Section title="6. Your rights">
        <p>
          You can ask us for a summary of your personal data and how it is used, to correct or update it, to erase it
          (unless we must keep it by law or for an open order or refund), and to have a grievance resolved. You may also
          nominate someone to exercise these rights for you. Write to the Grievance Officer (see{' '}
          <Link href="/grievance">Grievances &amp; Contact</Link>) and include your order code so we can find your data.
        </p>
      </Section>

      <Section title="7. Children">
        <p>
          LiveDrop is meant for people aged 18 or over. If you are under 18, please use it only with a parent or guardian,
          who should place the order.
        </p>
      </Section>

      <Section title="8. Security">
        <p>
          Data is encrypted in transit, access is limited by database security rules, order pages need a private order
          link, and administrators must sign in again before sensitive actions. No method is perfectly secure; please keep
          your order links private.
        </p>
      </Section>

      <Section title="9. Visit counting choice">
        <AnalyticsPreference />
        <p className="ld-form-hint">
          Visits are also not counted when your browser sends &quot;Do Not Track&quot; or Global Privacy Control.
        </p>
      </Section>

      <Section title="10. Changes and contact">
        <p>
          We will update this page when our practices change and show the new effective date. Questions:{' '}
          {legalValue('supportEmail')}.
        </p>
      </Section>
    </LegalPage>
  );
}
