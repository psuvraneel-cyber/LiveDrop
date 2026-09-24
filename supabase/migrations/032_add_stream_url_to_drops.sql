-- LiveDrop Migration: 032_add_stream_url_to_drops.sql
-- Description: Add optional stream_url column to drops table for Facebook Live video broadcast embedding.
-- Parent Documentation: docs/12-database-design.md, docs/16-security-architecture.md, ADR-002

ALTER TABLE public.drops
ADD COLUMN IF NOT EXISTS stream_url TEXT;

ALTER TABLE public.drops
DROP CONSTRAINT IF EXISTS drops_stream_url_format;

ALTER TABLE public.drops
ADD CONSTRAINT drops_stream_url_format
CHECK (stream_url IS NULL OR stream_url ~* '^https?://');

COMMENT ON COLUMN public.drops.stream_url IS 'Public stream URL (e.g. Facebook Live video URL) embedded for live drop commerce sessions.';
