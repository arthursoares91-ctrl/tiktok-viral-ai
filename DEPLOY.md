# 🚀 Guia de Deploy — TikTok Viral AI

Guia passo a passo para publicar o projeto no Vercel em menos de 15 minutos.

---

## Índice

1. [Pré-requisitos](#1-pré-requisitos)
2. [Configurar o Supabase](#2-configurar-o-supabase)
3. [Editar as variáveis no app.html](#3-editar-as-variáveis-no-apphtml)
4. [Publicar no GitHub](#4-publicar-no-github)
5. [Deploy no Vercel](#5-deploy-no-vercel)
6. [Configurar variáveis de ambiente no Vercel](#6-configurar-variáveis-de-ambiente-no-vercel)
7. [Deploy das Edge Functions](#7-deploy-das-edge-functions)
8. [Testar o projeto](#8-testar-o-projeto)
9. [Checklist final](#9-checklist-final)

---

## 1. Pré-requisitos

Instale as ferramentas necessárias:

```bash
# Node.js 18+ (verificar versão)
node --version

# Git
git --version

# Vercel CLI
npm install -g vercel

# Supabase CLI (para Edge Functions)
npm install -g supabase
```

Crie contas gratuitas em:
- [github.com](https://github.com)
- [vercel.com](https://vercel.com)
- [supabase.com](https://supabase.com)
- [console.anthropic.com](https://console.anthropic.com)

---

## 2. Configurar o Supabase

### 2.1 Criar projeto

1. Acesse [supabase.com](https://supabase.com) → **New project**
2. Região: **South America (São Paulo)**
3. Anote a **Project URL** e **anon key** em Settings → API

### 2.2 Executar o schema

1. No painel do Supabase → **SQL Editor** → **New query**
2. Abra o arquivo `supabase/schema.sql` deste projeto
3. Cole o conteúdo e clique em **Run**
4. Confirme que as tabelas `profiles` e `generations` foram criadas

### 2.3 Configurar autenticação

Em **Authentication → URL Configuration**:
```
Site URL:      https://SEU-PROJETO.vercel.app
Redirect URLs: https://SEU-PROJETO.vercel.app/app.html
```

---

## 3. Editar as variáveis no app.html

Abra `public/app.html` e localize a seção `CONFIGURAÇÃO` no início do `<script>` (por volta da linha 450):

```javascript
// ══════════════════════════════════════════
// CONFIGURAÇÃO — substitua com seus valores
// ══════════════════════════════════════════
const SUPABASE_URL  = 'YOUR_SUPABASE_URL';   // ← substitua
const SUPABASE_KEY  = 'YOUR_SUPABASE_ANON_KEY'; // ← substitua
const CLAUDE_MODEL  = 'claude-sonnet-4-20250514';
```

Substitua `YOUR_SUPABASE_URL` e `YOUR_SUPABASE_ANON_KEY` com os valores do passo 2.1.

> ⚠️ **Produção:** Para proteger sua API key da Anthropic, use a Edge Function
> `supabase/functions/generate/index.ts` como proxy. Veja o Passo 7.

---

## 4. Publicar no GitHub

```bash
# Entre na pasta do projeto
cd tiktok-viral-ai

# Inicialize o repositório
git init
git add .
git commit -m "feat: initial commit — TikTok Viral AI"

# Crie um repositório no GitHub em: github.com/new
# Nome sugerido: tiktok-viral-ai
# Visibilidade: Public ou Private

# Conecte e suba
git remote add origin https://github.com/SEU-USUARIO/tiktok-viral-ai.git
git branch -M main
git push -u origin main
```

---

## 5. Deploy no Vercel

### Opção A — Via painel (recomendado para iniciantes)

1. Acesse [vercel.com/new](https://vercel.com/new)
2. Clique em **"Import Git Repository"**
3. Selecione o repositório `tiktok-viral-ai`
4. Configure:
   - **Framework Preset:** `Other`
   - **Root Directory:** `./` (deixe em branco)
   - **Build Command:** deixe em branco
   - **Output Directory:** `public`
5. Clique em **"Deploy"** (sem variáveis por ora — configuramos no próximo passo)

### Opção B — Via CLI

```bash
# Dentro da pasta do projeto
vercel

# Responda as perguntas:
# ? Set up and deploy? → Y
# ? Which scope? → seu-usuario
# ? Link to existing project? → N
# ? Project name → tiktok-viral-ai
# ? In which directory is your code located? → ./
# ? Want to override settings? → N

# Para produção
vercel --prod
```

---

## 6. Configurar variáveis de ambiente no Vercel

No painel do Vercel → **seu projeto** → **Settings** → **Environment Variables**

Adicione as seguintes variáveis (todas como `Production` + `Preview`):

| Nome | Valor | Onde encontrar |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://xxx.supabase.co` | Supabase → Settings → API |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `eyJ...` | Supabase → Settings → API |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | console.anthropic.com → API Keys |
| `STRIPE_SECRET_KEY` | `sk_live_...` | dashboard.stripe.com → Developers |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` | Stripe → Webhooks |
| `STRIPE_PRICE_PRO` | `price_...` | Stripe → Products |
| `STRIPE_PRICE_PREMIUM` | `price_...` | Stripe → Products |
| `MP_ACCESS_TOKEN` | `APP_USR-...` | mercadopago.com.br/developers |
| `MP_PUBLIC_KEY` | `APP_USR-...` | mercadopago.com.br/developers |
| `NEXT_PUBLIC_APP_URL` | `https://seuapp.vercel.app` | URL do seu deploy |

Após salvar, clique em **"Redeploy"** para aplicar.

---

## 7. Deploy das Edge Functions

As Edge Functions ficam no Supabase e são necessárias para:
- Proteger a `ANTHROPIC_API_KEY` (proxy seguro)
- Processar webhooks do Stripe e Mercado Pago

```bash
# Autenticar no Supabase CLI
supabase login

# Vincular ao seu projeto
supabase link --project-ref SEU_PROJECT_REF
# (o Project Ref está em Supabase → Settings → General)

# Configurar secrets das Edge Functions
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set STRIPE_SECRET_KEY=sk_live_...
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
supabase secrets set MP_ACCESS_TOKEN=APP_USR-...
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=eyJ...

# Deploy de todas as funções
supabase functions deploy generate
supabase functions deploy stripe-webhook
supabase functions deploy mp-webhook
```

### Configurar webhooks

**Stripe:**
1. Dashboard → **Developers → Webhooks → Add endpoint**
2. URL: `https://SEU_PROJECT.supabase.co/functions/v1/stripe-webhook`
3. Eventos: `checkout.session.completed`, `customer.subscription.deleted`, `invoice.payment_succeeded`, `invoice.payment_failed`

**Mercado Pago:**
1. developers → **Notificações IPN**
2. URL: `https://SEU_PROJECT.supabase.co/functions/v1/mp-webhook`
3. Tópicos: `payment`

---

## 8. Testar o projeto

Após o deploy, teste cada etapa:

```bash
# 1. Abrir a landing page
open https://SEU-PROJETO.vercel.app

# 2. Abrir o app
open https://SEU-PROJETO.vercel.app/app.html

# 3. Criar conta e fazer login
# 4. Gerar ideias (verificar se a IA responde)
# 5. Verificar histórico (verificar se salvou no Supabase)
# 6. Testar limite de créditos (5 gerações → deve bloquear)
```

---

## 9. Checklist final

```
SUPABASE
[ ] Schema SQL executado (tabelas profiles e generations criadas)
[ ] Trigger on_auth_user_created funcionando
[ ] RLS habilitado nas duas tabelas
[ ] Site URL e Redirect URLs configurados
[ ] Cron job de reset de créditos agendado

CÓDIGO
[ ] SUPABASE_URL e SUPABASE_KEY substituídos em public/app.html
[ ] .env.local criado (não commitado)

VERCEL
[ ] Repositório importado e primeiro deploy bem-sucedido
[ ] Todas as variáveis de ambiente adicionadas
[ ] Output Directory configurado como "public"
[ ] Redeploy feito após adicionar variáveis

EDGE FUNCTIONS (opcional mas recomendado para produção)
[ ] supabase functions deploy generate
[ ] supabase functions deploy stripe-webhook
[ ] supabase functions deploy mp-webhook
[ ] Secrets configurados no Supabase

PAGAMENTOS (se quiser monetizar)
[ ] Produtos criados no Stripe
[ ] Payment Links configurados
[ ] Webhook do Stripe apontando para Edge Function
[ ] MP configurado com notificações IPN

DOMÍNIO PERSONALIZADO (opcional)
[ ] Domínio adicionado no Vercel
[ ] DNS configurado no registrador
[ ] Certificado SSL ativo (automático no Vercel)
[ ] Site URL atualizado no Supabase Auth
```

---

## Domínio personalizado (opcional)

1. Vercel → **Settings → Domains** → **Add Domain**
2. Digite `seudominio.com.br`
3. No registrador de domínio (Registro.br, GoDaddy, etc.):

```
Tipo A:
  Host: @
  Valor: 76.76.21.21

Tipo CNAME:
  Host: www
  Valor: cname.vercel-dns.com
```

4. Atualize o **Site URL** no Supabase Auth com o novo domínio.

---

*Dúvidas? Consulte o README.md completo ou a documentação:*
- *Vercel: [vercel.com/docs](https://vercel.com/docs)*
- *Supabase: [supabase.com/docs](https://supabase.com/docs)*
- *Anthropic: [docs.anthropic.com](https://docs.anthropic.com)*
