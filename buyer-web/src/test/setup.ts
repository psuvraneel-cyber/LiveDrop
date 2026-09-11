import '@testing-library/jest-dom/vitest';

// Provide default test environment configuration for jsdom
process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://test-project.supabase.co';
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key-12345';
process.env.NEXT_PUBLIC_APP_ENV = 'development';
