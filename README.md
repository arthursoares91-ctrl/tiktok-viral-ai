# TikTok Viral AI 🚀

> Plataforma de IA para criação de conteúdo viral no TikTok — ideias, roteiros, legendas, hashtags, calendário de 30 dias, analisador viral e série conectada.

---

## Índice

- [Visão geral do projeto](#visão-geral-do-projeto)
- [Arquitetura](#arquitetura)
- [Pré-requisitos](#pré-requisitos)
- [Configuração do Supabase](#configuração-do-supabase)
- [Configuração do Stripe](#configuração-do-stripe)
- [Configuração do Mercado Pago](#configuração-do-mercado-pago)
- [Variáveis de ambiente](#variáveis-de-ambiente)
- [Deploy no Vercel](#deploy-no-vercel)
- [Estrutura de arquivos](#estrutura-de-arquivos)
- [Funcionalidades](#funcionalidades)
- [Sistema de créditos](#sistema-de-créditos)
- [Solução de problemas](#solução-de-problemas)

---

## Visão geral do projeto

O TikTok Viral AI é composto por dois arquivos principais:

| Arquivo | Descrição |
|---|---|
| `landing.html` | Landing page pública com hero, benefícios, planos e FAQ |
| `app.html` | Aplicação principal com auth, ferramentas de IA e histórico |

A stack é **100% frontend** (HTML + JS puro), o que significa que não há servidor Node.js nem build step. O Vercel serve os arquivos estáticos diretamente. Toda a lógica de backend é delegada ao **Supabase** (auth + banco de dados) e às APIs externas (Anthropic, Stripe, Mercado Pago).

---

## Arquitetura

```
┌─────────────────────────────────────────────────────┐
│                   Vercel (CDN)                      │
│              landing.html  /  app.html              │
└───────────────────────┬─────────────────────────────┘
                        │ HTTPS
          ┌─────────────┼──────────────┐
          │             │              │
    ┌─────▼──────┐ ┌────▼────┐ ┌──────▼──────┐
    │  Supabase  │ │Anthropic│ │   Stripe /  │
    │  Auth + DB │ │  API    │ │ Mercado Pago│
    └────────────┘ └─────────┘ └─────────────┘
```

---

## Pré-requisitos

Antes de fazer o deploy, você precisa criar contas em:

- [Vercel](https://vercel.com) — hospedagem (gratuito)
- [Supabase](https://supabase.com) — banco de dados e autenticação (gratuito até certo limite)
- [Anthropic](https://console.anthropic.com) — API da IA (pago por uso)
- [Stripe](https://stripe.com) — pagamentos internacionais (opcional)
- [Mercado Pago](https://www.mercadopago.com.br/developers) — pagamentos brasileiros (opcional)

---

## Configuração do Supabase

### 1. Criar o projeto

1. Acesse [supabase.com](https://supabase.com) e clique em **New project**
2. Escolha um nome, senha forte para o banco e região **South America (São Paulo)**
3. Aguarde o projeto inicializar (~2 minutos)

### 2. Executar o schema SQL

No painel do Supabase, vá em **SQL Editor → New query** e execute o SQL abaixo:

```sql
-- ─── PROFILES ───────────────────────────────────────────────────────────────
-- Estende a tabela auth.users com dados de plano e créditos

CREATE TABLE public.profiles (
  id                  UUID        REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name                TEXT,
  plan                TEXT        NOT NULL DEFAULT 'free',   -- 'free' | 'pro' | 'premium'
  credits_today       INT         NOT NULL DEFAULT 5,
  credits_reset_at    TIMESTAMPTZ,
  stripe_customer_id  TEXT,
  stripe_sub_id       TEXT,
  mp_subscription_id  TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Garante que todo novo usuário ganhe um profile automaticamente
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── GENERATIONS ─────────────────────────────────────────────────────────────
-- Histórico de todas as gerações de cada usuário

CREATE TABLE public.generations (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        TEXT        NOT NULL,   -- 'ideias' | 'roteiro' | 'legenda' | 'hashtags' | 'calendario' | 'analisador' | 'serie'
  input       JSONB,
  output      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índice para buscas rápidas por usuário
CREATE INDEX idx_generations_user_id ON public.generations(user_id);
CREATE INDEX idx_generations_created_at ON public.generations(created_at DESC);

-- ─── ROW LEVEL SECURITY ───────────────────────────────────────────────────────
-- Cada usuário só vê e edita os próprios dados

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generations ENABLE ROW LEVEL SECURITY;

-- Profiles: usuário lê e atualiza apenas o próprio
CREATE POLICY "profiles: leitura própria"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "profiles: atualização própria"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- Generations: usuário lê, insere e deleta apenas as próprias
CREATE POLICY "generations: leitura própria"
  ON public.generations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "generations: inserção própria"
  ON public.generations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "generations: deleção própria"
  ON public.generations FOR DELETE
  USING (auth.uid() = user_id);

-- ─── FUNÇÃO DE RESET DE CRÉDITOS ─────────────────────────────────────────────
-- Pode ser chamada via cron job (Supabase Edge Functions ou serviço externo)
-- para resetar os créditos de todos os usuários free todo dia à meia-noite

CREATE OR REPLACE FUNCTION public.reset_daily_credits()
RETURNS void AS $$
BEGIN
  UPDATE public.profiles
  SET credits_today = 5,
      credits_reset_at = now()
  WHERE plan = 'free';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 3. Obter as chaves

No painel do Supabase, vá em **Settings → API** e copie:

- **Project URL** → será `NEXT_PUBLIC_SUPABASE_URL`
- **anon / public key** → será `NEXT_PUBLIC_SUPABASE_ANON_KEY`

> ⚠️ **Nunca exponha a `service_role` key no frontend.** Use apenas a `anon` key.

### 4. Configurar autenticação

Em **Authentication → Providers**:

- **Email** já vem habilitado por padrão — deixe ativo
- Configure o **Site URL** para `https://seu-dominio.vercel.app`
- Em **Email Templates**, personalize os emails de confirmação e recuperação de senha com sua marca

Em **Authentication → URL Configuration**:
```
Site URL: https://seu-app.vercel.app
Redirect URLs: https://seu-app.vercel.app/app.html
```

---

## Configuração do Stripe

> Necessário apenas se quiser aceitar cartão de crédito internacional.

### 1. Criar os produtos

No [Stripe Dashboard](https://dashboard.stripe.com):

1. Vá em **Products → Add product**
2. Crie o plano **Pro**:
   - Nome: `TikTok Viral AI Pro`
   - Preço: `R$ 29,00 / mês` (recorrente)
   - Copie o `price_id` gerado (ex: `price_1AbcDef...`)
3. Crie o plano **Premium**:
   - Nome: `TikTok Viral AI Premium`
   - Preço: `R$ 49,00 / mês` (recorrente)
   - Copie o `price_id`

### 2. Criar Payment Links (método mais simples para HTML estático)

Como o projeto é HTML puro (sem servidor), a forma mais simples de integrar o Stripe é via **Payment Links**:

1. No Stripe Dashboard, vá em **Payment Links → Create**
2. Selecione o produto Pro e configure:
   - Após pagamento: redirecione para `https://seu-app.vercel.app/app.html?plan=pro&session={CHECKOUT_SESSION_ID}`
3. Copie o link gerado e substitua no botão "Assinar Pro" em `app.html`
4. Repita para o Premium

### 3. Webhook para atualizar o plano (recomendado)

Para atualizar o plano do usuário automaticamente após pagamento, crie uma **Supabase Edge Function**:

```bash
# No terminal, dentro do projeto Supabase
supabase functions new stripe-webhook
```

```typescript
// supabase/functions/stripe-webhook/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import Stripe from "https://esm.sh/stripe@12"

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!)
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
)

serve(async (req) => {
  const sig = req.headers.get("stripe-signature")!
  const body = await req.text()
  const event = stripe.webhooks.constructEvent(body, sig, Deno.env.get("STRIPE_WEBHOOK_SECRET")!)

  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session
    const customerEmail = session.customer_details?.email
    const plan = session.metadata?.plan || "pro"

    if (customerEmail) {
      // Busca o usuário pelo email
      const { data: user } = await supabase.auth.admin.getUserByEmail(customerEmail)
      if (user?.user) {
        await supabase.from("profiles").update({
          plan,
          stripe_customer_id: session.customer as string,
          stripe_sub_id: session.subscription as string,
        }).eq("id", user.user.id)
      }
    }
  }

  if (event.type === "customer.subscription.deleted") {
    const sub = event.data.object as Stripe.Subscription
    await supabase.from("profiles").update({ plan: "free" })
      .eq("stripe_sub_id", sub.id)
  }

  return new Response(JSON.stringify({ received: true }), { status: 200 })
})
```

---

## Configuração do Mercado Pago

> Recomendado para o mercado brasileiro (aceita PIX, boleto e cartões nacionais).

### 1. Criar a aplicação

1. Acesse [mercadopago.com.br/developers](https://www.mercadopago.com.br/developers)
2. Vá em **Suas integrações → Criar aplicação**
3. Escolha **Checkout Pro** (mais simples para começar)

### 2. Criar preferências de pagamento

O Mercado Pago requer um backend para criar preferências. Use uma **Supabase Edge Function**:

```typescript
// supabase/functions/mp-create-preference/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const { plan, userId, userEmail } = await req.json()

  const prices = { pro: 2900, premium: 4900 }  // centavos
  const names  = { pro: "TikTok Viral AI Pro", premium: "TikTok Viral AI Premium" }

  const response = await fetch("https://api.mercadopago.com/checkout/preferences", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${Deno.env.get("MP_ACCESS_TOKEN")}`,
    },
    body: JSON.stringify({
      items: [{
        title: names[plan],
        unit_price: prices[plan] / 100,
        quantity: 1,
        currency_id: "BRL",
      }],
      payer: { email: userEmail },
      back_urls: {
        success: `https://seu-app.vercel.app/app.html?plan=${plan}&mp=success`,
        failure: `https://seu-app.vercel.app/app.html?mp=failure`,
      },
      auto_return: "approved",
      metadata: { user_id: userId, plan },
      notification_url: `https://<seu-projeto>.supabase.co/functions/v1/mp-webhook`,
    }),
  })

  const data = await response.json()
  return new Response(JSON.stringify({ init_point: data.init_point }), {
    headers: { "Content-Type": "application/json" },
  })
})
```

### 3. Webhook do Mercado Pago

```typescript
// supabase/functions/mp-webhook/index.ts
serve(async (req) => {
  const { type, data } = await req.json()

  if (type === "payment") {
    const paymentRes = await fetch(`https://api.mercadopago.com/v1/payments/${data.id}`, {
      headers: { "Authorization": `Bearer ${Deno.env.get("MP_ACCESS_TOKEN")}` },
    })
    const payment = await paymentRes.json()

    if (payment.status === "approved") {
      const { user_id, plan } = payment.metadata
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
      )
      await supabase.from("profiles").update({
        plan,
        mp_subscription_id: String(data.id),
      }).eq("id", user_id)
    }
  }

  return new Response("ok", { status: 200 })
})
```

---

## Variáveis de ambiente

Estas são **todas** as variáveis que o projeto usa. Copie a tabela abaixo e preencha antes de fazer o deploy.

### Frontend (app.html)

Estas variáveis são inseridas diretamente no código JavaScript de `app.html`. Localize as linhas comentadas com `CONFIGURAÇÃO` no início do `<script>` e substitua os valores:

```javascript
// app.html — seção CONFIGURAÇÃO (linha ~450)
const SUPABASE_URL  = 'https://xxxxxxxxxxxx.supabase.co';
const SUPABASE_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
const CLAUDE_MODEL  = 'claude-sonnet-4-20250514';
```

> A chave Anthropic **não** fica no frontend — a chamada à API da Claude é feita diretamente do browser usando a `anon key` do Supabase para autenticar o usuário, e o backend (Edge Function) faz a chamada real à Anthropic. Veja a seção de arquitetura segura abaixo.

### Variáveis do Vercel (Environment Variables)

No painel do Vercel, vá em **Project → Settings → Environment Variables** e adicione:

| Variável | Exemplo | Descrição |
|---|---|---|
| `SUPABASE_URL` | `https://abc123.supabase.co` | URL do seu projeto Supabase |
| `SUPABASE_ANON_KEY` | `eyJhbGci...` | Chave pública (anon) do Supabase |
| `ANTHROPIC_API_KEY` | `sk-ant-api03-...` | Chave da API da Anthropic (Claude) |
| `STRIPE_SECRET_KEY` | `sk_live_...` | Chave secreta do Stripe (use `sk_test_` para testes) |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` | Secret do webhook do Stripe |
| `STRIPE_PRICE_PRO` | `price_1AbcDef...` | Price ID do plano Pro no Stripe |
| `STRIPE_PRICE_PREMIUM` | `price_1XyzAbc...` | Price ID do plano Premium no Stripe |
| `MP_ACCESS_TOKEN` | `APP_USR-1234...` | Access token do Mercado Pago |
| `MP_PUBLIC_KEY` | `APP_USR-abc...` | Chave pública do Mercado Pago |
| `NEXT_PUBLIC_APP_URL` | `https://seuapp.vercel.app` | URL pública do app (sem barra final) |

> ℹ️ Variáveis prefixadas com `NEXT_PUBLIC_` são expostas no browser. As demais são acessíveis apenas no servidor (Edge Functions).

### Variáveis das Supabase Edge Functions

No painel do Supabase, vá em **Settings → Edge Functions → Secrets** e adicione:

| Variável | Descrição |
|---|---|
| `ANTHROPIC_API_KEY` | Chave da Anthropic para chamadas seguras no servidor |
| `STRIPE_SECRET_KEY` | Chave secreta do Stripe |
| `STRIPE_WEBHOOK_SECRET` | Webhook signing secret do Stripe |
| `MP_ACCESS_TOKEN` | Access token do Mercado Pago |
| `SUPABASE_SERVICE_ROLE_KEY` | Chave service_role do Supabase (para Edge Functions) |

---

## Deploy no Vercel

### Opção A — Deploy via GitHub (recomendado)

Este é o método mais robusto: qualquer `git push` faz re-deploy automático.

**1. Preparar o repositório**

```bash
# Crie a pasta do projeto localmente
mkdir tiktok-viral-ai
cd tiktok-viral-ai

# Copie os arquivos do projeto
cp /caminho/para/landing.html .
cp /caminho/para/app.html .

# Inicialize o git
git init
git add .
git commit -m "feat: initial commit — TikTok Viral AI"

# Crie um repositório no GitHub e suba
git remote add origin https://github.com/seu-usuario/tiktok-viral-ai.git
git push -u origin main
```

**2. Criar arquivo `vercel.json`** (configuração de rotas)

```json
{
  "version": 2,
  "routes": [
    {
      "src": "/",
      "dest": "/landing.html"
    },
    {
      "src": "/app",
      "dest": "/app.html"
    },
    {
      "src": "/app.html",
      "dest": "/app.html"
    }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-XSS-Protection", "value": "1; mode=block" },
        {
          "key": "Content-Security-Policy",
          "value": "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; connect-src 'self' https://*.supabase.co https://api.anthropic.com https://api.mercadopago.com https://api.stripe.com;"
        }
      ]
    }
  ]
}
```

**3. Importar no Vercel**

1. Acesse [vercel.com/new](https://vercel.com/new)
2. Clique em **Import Git Repository**
3. Selecione o repositório `tiktok-viral-ai`
4. Em **Framework Preset**, escolha **Other**
5. Deixe **Build Command** e **Output Directory** em branco (projeto estático)
6. Clique em **Add Environment Variables** e adicione todas as variáveis listadas acima
7. Clique em **Deploy**

---

### Opção B — Deploy via Vercel CLI

```bash
# Instalar a CLI do Vercel
npm install -g vercel

# Na pasta do projeto
vercel

# Siga as instruções interativas:
# ? Set up and deploy? → Yes
# ? Which scope? → seu-usuario
# ? Link to existing project? → No
# ? What's your project's name? → tiktok-viral-ai
# ? In which directory is your code located? → ./
# ? Want to modify settings? → No

# Para produção (com variáveis de ambiente já configuradas no painel)
vercel --prod
```

**Adicionar variáveis via CLI:**

```bash
vercel env add SUPABASE_URL production
vercel env add SUPABASE_ANON_KEY production
vercel env add ANTHROPIC_API_KEY production
vercel env add STRIPE_SECRET_KEY production
vercel env add MP_ACCESS_TOKEN production
```

---

### Opção C — Upload direto (mais simples, sem CI/CD)

1. Acesse [vercel.com/new](https://vercel.com/new)
2. Arraste a pasta do projeto para a área de upload
3. Adicione as variáveis de ambiente quando solicitado
4. Clique em **Deploy**

---

## Configurar domínio personalizado

Após o deploy, para apontar seu domínio:

1. No painel do Vercel, vá em **Project → Settings → Domains**
2. Clique em **Add Domain** e digite `seudominio.com.br`
3. No painel do seu registrador de domínio (Registro.br, GoDaddy, etc.), adicione:

```
Tipo: A
Nome: @
Valor: 76.76.21.21

Tipo: CNAME
Nome: www
Valor: cname.vercel-dns.com
```

4. Aguarde a propagação DNS (até 24h, geralmente menos de 30 minutos)

---

## Estrutura de arquivos

```
tiktok-viral-ai/
├── landing.html          # Landing page pública
├── app.html              # Aplicação principal
├── vercel.json           # Configuração de rotas e headers do Vercel
├── README.md             # Este arquivo
└── supabase/             # (opcional) Edge Functions
    └── functions/
        ├── stripe-webhook/
        │   └── index.ts
        ├── mp-webhook/
        │   └── index.ts
        └── mp-create-preference/
            └── index.ts
```

---

## Funcionalidades

| Ferramenta | Plano | Descrição |
|---|---|---|
| Gerador de Ideias | Grátis | 30 ideias virais por nicho/público/objetivo |
| Gerador de Roteiro | Grátis | Gancho 3s, desenvolvimento e CTA |
| Gerador de Legenda | Grátis | Legenda com emojis e CTA personalizado |
| Gerador de Hashtags | Grátis | 15 hashtags estratégicas |
| Calendário 30 dias | Pro | Planejamento por formato e tema |
| Analisador Viral | Pro | Dissecção de vídeos virais |
| Série Conectada | Premium | 30 episódios com narrativa sequencial |
| Histórico | Todos | Gerações salvas na conta (limitado no free) |

---

## Sistema de créditos

O sistema de créditos controla o uso de usuários do plano gratuito:

- **Plano Free:** 5 gerações por dia (reset à meia-noite)
- **Plano Pro / Premium:** ilimitado

O reset diário funciona da seguinte forma:

1. Ao carregar o app, `loadProfile()` compara `credits_reset_at` com a meia-noite do dia atual
2. Se `credits_reset_at` for anterior à meia-noite, os créditos são resetados para 5 no Supabase
3. Para garantir o reset mesmo sem acesso, configure um **cron job** no Supabase:

```sql
-- Em Supabase → Database → Extensions, habilite pg_cron:
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Agendar reset de créditos todo dia à meia-noite (horário de Brasília = UTC-3)
SELECT cron.schedule(
  'reset-daily-credits',
  '0 3 * * *',   -- 03:00 UTC = 00:00 BRT
  'SELECT public.reset_daily_credits();'
);
```

---

## Arquitetura segura para a API da Anthropic

> ⚠️ Em produção, **nunca** exponha sua `ANTHROPIC_API_KEY` no frontend. O código atual faz chamadas diretas do browser para facilitar o desenvolvimento. Para produção, use uma Edge Function como proxy:

```typescript
// supabase/functions/generate/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  // Verifica se o usuário está autenticado
  const authHeader = req.headers.get("Authorization")
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader! } } }
  )

  const { data: { user }, error } = await supabase.auth.getUser()
  if (error || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 })
  }

  // Verifica créditos
  const { data: profile } = await supabase.from("profiles").select("plan, credits_today").eq("id", user.id).single()
  if (profile?.plan === "free" && profile.credits_today <= 0) {
    return new Response(JSON.stringify({ error: "No credits left" }), { status: 429 })
  }

  // Faz a chamada à Anthropic no servidor
  const { prompt } = await req.json()
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-20250514",
      max_tokens: 1000,
      messages: [{ role: "user", content: prompt }],
    }),
  })

  const data = await response.json()

  // Decrementa créditos se for usuário free
  if (profile?.plan === "free") {
    await supabase.from("profiles").update({ credits_today: profile.credits_today - 1 }).eq("id", user.id)
  }

  // Salva no histórico
  // ... (lógica de saveToHistory)

  return new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json" },
  })
})
```

No `app.html`, substitua a função `callClaude` para chamar esta Edge Function:

```javascript
async function callClaude(prompt, btnId, progId, fillId) {
  // ...setup loading state...

  const { data: { session } } = await supabase.auth.getSession()
  const res = await fetch(`${SUPABASE_URL}/functions/v1/generate`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session.access_token}`,
    },
    body: JSON.stringify({ prompt }),
  })

  // ...handle response...
}
```

---

## Solução de problemas

**Erro: `Failed to fetch` ao chamar a API da Anthropic**
- Verifique se a chave `ANTHROPIC_API_KEY` está correta
- A chave deve começar com `sk-ant-api03-`
- Verifique se há saldo na sua conta Anthropic

**Erro: `Invalid API key` no Supabase**
- Use a chave `anon/public`, não a `service_role`
- Verifique se a URL do projeto está correta (sem barra no final)

**Usuário criado mas `profiles` não foi gerado**
- Verifique se o trigger `on_auth_user_created` foi criado corretamente
- Execute manualmente: `SELECT public.handle_new_user()` para testar

**Deploy no Vercel com erro de CORS**
- Adicione o domínio do Vercel nas configurações de `Allowed Origins` do Supabase em **Authentication → URL Configuration**

**Pagamento aprovado mas plano não atualizou**
- Verifique se o webhook está configurado corretamente
- No Stripe/MP Dashboard, veja o log de eventos do webhook
- Certifique-se de que a Edge Function está deployed: `supabase functions deploy stripe-webhook`

**Créditos não resetando**
- Verifique se a extensão `pg_cron` está habilitada no Supabase
- Confirme o timezone: o cron usa UTC, Brasília é UTC-3
- Teste manual: `SELECT public.reset_daily_credits();` no SQL Editor

---

## Checklist de deploy

Antes de ir ao ar, verifique:

- [ ] Schema SQL executado no Supabase
- [ ] Trigger `on_auth_user_created` funcionando (crie um usuário de teste)
- [ ] RLS (Row Level Security) habilitado nas tabelas
- [ ] Variáveis de ambiente adicionadas no Vercel
- [ ] `SUPABASE_URL` e `SUPABASE_KEY` substituídas em `app.html`
- [ ] URL do site configurada no Supabase Auth (Site URL + Redirect URLs)
- [ ] `vercel.json` criado e commitado
- [ ] Domínio personalizado apontado (se aplicável)
- [ ] Payment Links criados no Stripe/MP (se pagamentos ativos)
- [ ] Webhooks configurados e testados
- [ ] Cron job de reset de créditos agendado
- [ ] Edge Function `generate` deployed para proteção da API key (produção)
- [ ] Teste completo: cadastro → geração → histórico → logout

---

## Suporte

Em caso de dúvidas sobre as integrações:

- **Supabase:** [supabase.com/docs](https://supabase.com/docs)
- **Vercel:** [vercel.com/docs](https://vercel.com/docs)
- **Anthropic:** [docs.anthropic.com](https://docs.anthropic.com)
- **Stripe:** [stripe.com/docs](https://stripe.com/docs)
- **Mercado Pago:** [mercadopago.com.br/developers/pt/docs](https://www.mercadopago.com.br/developers/pt/docs)

---

*TikTok Viral AI — Nunca mais fique sem ideias para postar.*
