import type { Metadata } from 'next';
import { LegalPage, Section } from '../../components/legal/LegalPage';
import { legalValue } from '../../lib/legal/legal-config';

export const metadata: Metadata = {
  title: 'Grievances & Contact',
  description: 'Contact LiveDrop and its Grievance Officer.',
};

export default function GrievancePage() {
  return (
    <LegalPage title="Grievances & Contact">
      <Section title="Operator">
        <p data-testid="legal-operator">
          {legalValue('operatorName')}
          <br />
          {legalValue('operatorAddress')}
        </p>
      </Section>

      <Section title="Grievance Officer">
        <p>
          Name: {legalValue('grievanceOfficerName')}
          <br />
          E-mail: {legalValue('supportEmail')}
          <br />
          Phone / WhatsApp: {legalValue('supportPhone')}
        </p>
        <p>
          For complaints about an order, a seller, a refund or your personal data (including requests to access, correct
          or erase it), write to the Grievance Officer with your order code. We acknowledge complaints within 48 hours and
          aim to resolve them within one month.
        </p>
      </Section>

      <Section title="Sellers">
        <p>
          Every piece is sold by the boutique named on its drop and store page. You can message the seller on WhatsApp from
          your order page. To report a seller, contact the Grievance Officer.
        </p>
      </Section>
    </LegalPage>
  );
}
