-- ==============================================================================
-- Fix AI Database Migration: User Quotas & ECU VIN Locking / Licensing
-- ==============================================================================

-- 1. Table: user_quotas
CREATE TABLE IF NOT EXISTS public.user_quotas (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    monthly_ai_scans INTEGER NOT NULL DEFAULT 50,
    remaining_scans INTEGER NOT NULL DEFAULT 50,
    last_reset TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.user_quotas ENABLE ROW LEVEL SECURITY;

-- Users can only read their own quota
CREATE POLICY "Users can read own quota"
    ON public.user_quotas
    FOR SELECT
    USING (auth.uid() = user_id);

-- Only service_role can modify or reset quotas
CREATE POLICY "Service role manages quotas"
    ON public.user_quotas
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- 2. Table: ecu_licenses (VIN-Locking & Tuning License Registry)
CREATE TABLE IF NOT EXISTS public.ecu_licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vin VARCHAR(17) NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    active_stage VARCHAR(32) NOT NULL DEFAULT 'stage0',
    signature TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_vin_user UNIQUE (vin, user_id)
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.ecu_licenses ENABLE ROW LEVEL SECURITY;

-- Users can only read their own registered vehicle licenses
CREATE POLICY "Users can read own licenses"
    ON public.ecu_licenses
    FOR SELECT
    USING (auth.uid() = user_id);

-- Only service_role (Edge Functions or backend billing) can create/update licenses
CREATE POLICY "Service role manages licenses"
    ON public.ecu_licenses
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Indexes for high-performance lookup
CREATE INDEX IF NOT EXISTS idx_ecu_licenses_vin_user ON public.ecu_licenses(vin, user_id);
CREATE INDEX IF NOT EXISTS idx_user_quotas_user ON public.user_quotas(user_id);
