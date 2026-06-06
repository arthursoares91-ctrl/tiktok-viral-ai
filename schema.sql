-- ══════════════════════════════════════════════════════════════════
-- TIKTOK VIRAL AI — Schema do Banco de Dados (Supabase / PostgreSQL)
-- ══════════════════════════════════════════════════════════════════
-- Execute este arquivo no Supabase SQL Editor:
-- supabase.com → seu projeto → SQL Editor → New query → Cole e execute
-- ══════════════════════════════════════════════════════════════════

-- ─── EXTENSÕES ────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";      -- para reset automático de créditos

-- ─── TABELA: profiles ─────────────────────────────────────────────
-- Estende auth.users com dados de plano, créditos e IDs de pagamento

CREATE TABLE IF NOT EXISTS public.profiles (
  id                  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name                TEXT,
  plan                TEXT        NOT NULL DEFAULT 'free'
                                  CHECK (plan IN ('free', 'pro', 'premium')),
  credits_today       INT         NOT NULL DEFAULT 5 CHECK (credits_today >= 0),
  credits_reset_at    TIMESTAMPTZ,
  stripe_customer_id  TEXT        UNIQUE,
  stripe_sub_id       TEXT        UNIQUE,
  mp_subscription_id  TEXT        UNIQUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);

-- ─── TABELA: generations ──────────────────────────────────────────
-- Histórico de todas as gerações de cada usuário

CREATE TABLE IF NOT EXISTS public.generations (
  id          UUID        NOT NULL DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        TEXT        NOT NULL
              CHECK (type IN ('ideias','roteiro','legenda','hashtags','calendario','analisador','serie')),
  input       JSONB,
  output      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT generations_pkey PRIMARY KEY (id)
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_generations_user_id    ON public.generations(user_id);
CREATE INDEX IF NOT EXISTS idx_generations_type       ON public.generations(type);
CREATE INDEX IF NOT EXISTS idx_generations_created_at ON public.generations(created_at DESC);

-- ─── TRIGGER: atualiza updated_at automaticamente ─────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── TRIGGER: cria profile automaticamente no cadastro ────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'name',
      split_part(NEW.email, '@', 1)
    )
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── ROW LEVEL SECURITY ───────────────────────────────────────────

ALTER TABLE public.profiles    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generations ENABLE ROW LEVEL SECURITY;

-- Profiles: usuário acessa apenas o próprio registro
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Generations: usuário acessa apenas as próprias gerações
DROP POLICY IF EXISTS "generations_select_own" ON public.generations;
CREATE POLICY "generations_select_own"
  ON public.generations FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "generations_insert_own" ON public.generations;
CREATE POLICY "generations_insert_own"
  ON public.generations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "generations_delete_own" ON public.generations;
CREATE POLICY "generations_delete_own"
  ON public.generations FOR DELETE
  USING (auth.uid() = user_id);

-- ─── FUNÇÃO: reset diário de créditos ────────────────────────────
CREATE OR REPLACE FUNCTION public.reset_daily_credits()
RETURNS void AS $$
BEGIN
  UPDATE public.profiles
  SET
    credits_today    = 5,
    credits_reset_at = NOW(),
    updated_at       = NOW()
  WHERE plan = 'free';

  RAISE NOTICE 'Créditos resetados para todos os usuários free em %', NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── CRON JOB: reset automático todo dia 00:00 BRT (03:00 UTC) ───
-- Requer extensão pg_cron habilitada no Supabase
SELECT cron.schedule(
  'reset-daily-credits',
  '0 3 * * *',
  'SELECT public.reset_daily_credits();'
);

-- ─── VIEW: estatísticas de uso por usuário ────────────────────────
CREATE OR REPLACE VIEW public.user_stats AS
SELECT
  p.id,
  p.name,
  p.plan,
  p.credits_today,
  COUNT(g.id)                                        AS total_generations,
  COUNT(g.id) FILTER (WHERE g.type = 'ideias')       AS ideias_count,
  COUNT(g.id) FILTER (WHERE g.type = 'roteiro')      AS roteiros_count,
  COUNT(g.id) FILTER (WHERE g.type = 'legenda')      AS legendas_count,
  COUNT(g.id) FILTER (WHERE g.type = 'hashtags')     AS hashtags_count,
  COUNT(g.id) FILTER (WHERE g.type = 'analisador')   AS analises_count,
  COUNT(g.id) FILTER (WHERE g.type = 'serie')        AS series_count,
  MAX(g.created_at)                                  AS last_generation_at
FROM public.profiles p
LEFT JOIN public.generations g ON g.user_id = p.id
GROUP BY p.id, p.name, p.plan, p.credits_today;
