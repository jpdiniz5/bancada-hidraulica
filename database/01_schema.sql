-- =============================================================
-- BANCADA HIDRÁULICA - HIDRÁULICOS FENILI
-- Schema Supabase / PostgreSQL
-- Execute este script no SQL Editor do Supabase
-- =============================================================

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================
-- TABELA: clientes
-- Clientes/usuários que solicitam acesso ao sistema
-- =============================================================
CREATE TABLE IF NOT EXISTS public.clientes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome        TEXT NOT NULL,
    email       TEXT UNIQUE NOT NULL,
    empresa     TEXT,
    telefone    TEXT,
    -- Status do cadastro
    status      TEXT NOT NULL DEFAULT 'pendente'
                CHECK (status IN ('pendente', 'aprovado', 'suspenso', 'rejeitado')),
    -- Controle de aprovação
    criado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    aprovado_em TIMESTAMPTZ,
    aprovado_por UUID REFERENCES public.clientes(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.clientes IS 'Clientes/usuários que solicitam acesso à bancada hidráulica';
COMMENT ON COLUMN public.clientes.status IS 'pendente=aguardando aprovação, aprovado=com acesso, suspenso=bloqueado, rejeitado=negado';

-- =============================================================
-- TABELA: licencas
-- Uma chave única por cliente aprovado
-- =============================================================
CREATE TABLE IF NOT EXISTS public.licencas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id      UUID NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
    -- A chave em si (armazenada em texto, gerada como UUID + prefixo)
    chave           TEXT UNIQUE NOT NULL,
    -- Tipo de licença
    tipo            TEXT NOT NULL DEFAULT 'demo'
                    CHECK (tipo IN ('demo', 'full', 'enterprise')),
    ativa           BOOLEAN NOT NULL DEFAULT true,
    -- Datas
    criada_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    criada_por      UUID REFERENCES public.clientes(id) ON DELETE SET NULL,
    ativada_em      TIMESTAMPTZ,
    expira_em       TIMESTAMPTZ, -- NULL = sem expiração
    -- Controle de uso
    max_ativacoes   INT NOT NULL DEFAULT 1,
    ativacoes_usadas INT NOT NULL DEFAULT 0
);

COMMENT ON TABLE public.licencas IS 'Chaves de licença geradas para cada cliente aprovado';
COMMENT ON COLUMN public.licencas.expira_em IS 'NULL = licença full sem expiração';
COMMENT ON COLUMN public.licencas.max_ativacoes IS 'Número máximo de dispositivos que podem ativar esta chave';

-- =============================================================
-- TABELA: sessoes
-- Registra onde e quando cada chave foi ativada
-- =============================================================
CREATE TABLE IF NOT EXISTS public.sessoes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    licenca_id      UUID NOT NULL REFERENCES public.licencas(id) ON DELETE CASCADE,
    -- Identificação do dispositivo/sessão
    token_sessao    TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
    fingerprint     TEXT,    -- hash do dispositivo (browser + OS)
    ip              TEXT,
    user_agent      TEXT,
    -- Datas
    iniciada_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
    ultimo_acesso   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expira_em       TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 days'),
    ativa           BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON TABLE public.sessoes IS 'Sessões ativas por dispositivo, controladas por token';

-- =============================================================
-- TABELA: auditoria
-- Log de todas as ações importantes do sistema
-- =============================================================
CREATE TABLE IF NOT EXISTS public.auditoria (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    acao        TEXT NOT NULL,   -- ex: 'chave_valida', 'chave_invalida', 'cadastro', 'aprovacao'
    detalhes    JSONB,           -- dados extras em JSON
    ip          TEXT,
    criado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.auditoria IS 'Log de auditoria de todas as ações de acesso';

-- =============================================================
-- ÍNDICES para performance
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_clientes_email  ON public.clientes(email);
CREATE INDEX IF NOT EXISTS idx_clientes_status ON public.clientes(status);
CREATE INDEX IF NOT EXISTS idx_licencas_chave  ON public.licencas(chave);
CREATE INDEX IF NOT EXISTS idx_licencas_cliente ON public.licencas(cliente_id);
CREATE INDEX IF NOT EXISTS idx_sessoes_token   ON public.sessoes(token_sessao);
CREATE INDEX IF NOT EXISTS idx_sessoes_licenca ON public.sessoes(licenca_id);
CREATE INDEX IF NOT EXISTS idx_auditoria_acao  ON public.auditoria(acao);
CREATE INDEX IF NOT EXISTS idx_auditoria_data  ON public.auditoria(criado_em DESC);
