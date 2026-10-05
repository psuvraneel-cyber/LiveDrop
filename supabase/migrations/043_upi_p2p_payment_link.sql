-- LiveDrop Migration: 043_upi_p2p_payment_link.sql
-- Description: UPI payment links that personal (P2P) UPI IDs can actually receive; SA-PAY-015.
--
--   Found in the owner's end-to-end test (2026-10-05): paying a ₹1 advance through the link or the QR
--   failed in UPI apps with "you have exceeded your account limit", on two different phones.
--
--   The link carried `tr=<transaction reference>`. In the UPI deep-link spec `tr` (with `mc`, `url`)
--   is a merchant field. Payer apps and banks treat a payment to a personal UPI ID that carries
--   merchant fields as a risky, unverified merchant request and decline it, often with a misleading
--   limit message. Sellers on LiveDrop receive on personal UPI IDs.
--
--   generate_upi_payment_uri now builds the plain P2P form:
--       upi://pay?pa=<vpa>&pn=<name>&am=<amount>&cu=INR&tn=<note>
--   * no `tr`. The order is still identified: the note carries the order code
--     ("LiveDrop LD-XXXXXX advance"), the attempt keeps transaction_reference in the database,
--     and the seller verifies by the buyer's UTR, which never depended on `tr`;
--   * name and note keep only letters, digits, spaces and dots (a '#', '%' or '&' in a store name
--     broke the link: SA-PAY-015) and are shortened to what UPI apps display.
--
--   Same signature and volatility, so every caller (initiate_payment_attempt and others) picks it up
--   unchanged. Idempotent.
--
-- Regression: audit/seller-app/tests/sql/13_payments.sql (13.9), 25_upi_link.sql.

CREATE OR REPLACE FUNCTION public.generate_upi_payment_uri(
    p_vpa TEXT,
    p_name TEXT,
    p_amount_paisa INT,
    p_reference TEXT,
    p_note TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    -- p_reference is kept in the signature for callers; it is deliberately not put in the link.
    SELECT 'upi://pay?pa=' || lower(trim(p_vpa))
        || '&pn=' || replace(COALESCE(NULLIF(left(trim(regexp_replace(regexp_replace(COALESCE(p_name, ''), '[^A-Za-z0-9 .]', '', 'g'), '\s+', ' ', 'g')), 50), ''), 'LiveDrop Seller'), ' ', '%20')
        || '&am=' || trim(to_char(p_amount_paisa / 100.0, 'FM999999990.00'))
        || '&cu=INR'
        || '&tn=' || replace(COALESCE(NULLIF(left(trim(regexp_replace(regexp_replace(COALESCE(p_note, ''), '[^A-Za-z0-9 .-]', '', 'g'), '\s+', ' ', 'g')), 60), ''), 'LiveDrop Order'), ' ', '%20');
$$;

-- Same grants as 013 (a pure function over its arguments).
REVOKE ALL ON FUNCTION public.generate_upi_payment_uri(TEXT, TEXT, INT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_upi_payment_uri(TEXT, TEXT, INT, TEXT, TEXT) TO anon, authenticated, service_role;
