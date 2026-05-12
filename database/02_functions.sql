-- =============================================================
-- BANCADA HIDRÁULICA - HIDRÁULICOS FENILI
-- Funções RPC chamadas pelo frontend via Supabase
-- Execute APÓS o 01_schema.sql
-- =============================================================

-- =============================================================
-- RPC: solicitar_acesso
-- Cliente preenche o formulário de cadastro no app
-- Retorna: { ok: bool, mensagem: text }
-- =============================================================
CREATE OR REPLACE FUNCTION public.solicitar_acesso(
    p_nome     TEXT,
    p_email    TEXT,
    p_empresa  TEXT DEFAULT NULL,
    p_telefone TEXT DEFAULT NULL,
    p_ip       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cliente_id UUID;
    v_existe     BOOLEAN;
BEGIN
    -- Validações básicas
    IF p_nome IS NULL OR trim(p_nome) = '' THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Nome é obrigatório.');
    END IF;

    IF p_email IS NULL OR trim(p_email) = '' OR p_email NOT LIKE '%@%.%' THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Email inválido.');
    END IF;

    -- Verificar se email já existe
    SELECT EXISTS(SELECT 1 FROM public.clientes WHERE email = lower(trim(p_email)))
    INTO v_existe;

    IF v_existe THEN
        -- Verificar o status atual
        SELECT status INTO v_cliente_id
        FROM public.clientes
        WHERE email = lower(trim(p_email));

        RETURN jsonb_build_object(
            'ok', false,
            'mensagem', 'Este email já está cadastrado. Aguarde a aprovação ou entre em contato com o suporte.'
        );
    END IF;

    -- Inserir cliente com status pendente
    INSERT INTO public.clientes (nome, email, empresa, telefone, status)
    VALUES (trim(p_nome), lower(trim(p_email)), trim(p_empresa), trim(p_telefone), 'pendente')
    RETURNING id INTO v_cliente_id;

    -- Log de auditoria
    INSERT INTO public.auditoria (acao, detalhes, ip)
    VALUES ('cadastro_solicitado', jsonb_build_object(
        'cliente_id', v_cliente_id,
        'email', lower(trim(p_email)),
        'empresa', p_empresa
    ), p_ip);

    RETURN jsonb_build_object(
        'ok', true,
        'mensagem', 'Solicitação enviada com sucesso! Você receberá sua chave de acesso por email após aprovação.',
        'cliente_id', v_cliente_id
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Erro interno. Tente novamente.');
END;
$$;

-- =============================================================
-- RPC: validar_chave
-- App envia a chave digitada pelo usuário
-- Retorna: { ok, tipo, dias_restantes, token_sessao, mensagem }
-- =============================================================
CREATE OR REPLACE FUNCTION public.validar_chave(
    p_chave       TEXT,
    p_fingerprint TEXT DEFAULT NULL,
    p_ip          TEXT DEFAULT NULL,
    p_user_agent  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_licenca       public.licencas%ROWTYPE;
    v_cliente       public.clientes%ROWTYPE;
    v_token         TEXT;
    v_dias_restantes INT;
    v_sessao_id     UUID;
BEGIN
    -- Buscar licença pela chave (case-insensitive)
    SELECT * INTO v_licenca
    FROM public.licencas
    WHERE upper(trim(chave)) = upper(trim(p_chave))
    LIMIT 1;

    -- Licença não encontrada
    IF NOT FOUND THEN
        INSERT INTO public.auditoria (acao, detalhes, ip)
        VALUES ('chave_invalida', jsonb_build_object('chave', p_chave), p_ip);

        RETURN jsonb_build_object('ok', false, 'mensagem', 'Chave de ativação inválida.');
    END IF;

    -- Licença desativada pelo admin
    IF NOT v_licenca.ativa THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Esta chave foi desativada. Entre em contato com o suporte.');
    END IF;

    -- Verificar expiração (apenas para licenças com prazo)
    IF v_licenca.expira_em IS NOT NULL AND now() > v_licenca.expira_em THEN
        INSERT INTO public.auditoria (acao, detalhes, ip)
        VALUES ('chave_expirada', jsonb_build_object('licenca_id', v_licenca.id), p_ip);

        RETURN jsonb_build_object('ok', false, 'mensagem', 'Licença expirada. Entre em contato para renovação.');
    END IF;

    -- Verificar cliente aprovado
    SELECT * INTO v_cliente
    FROM public.clientes
    WHERE id = v_licenca.cliente_id;

    IF v_cliente.status != 'aprovado' THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Conta ainda não aprovada. Aguarde o contato da equipe Fenili.');
    END IF;

    -- Verificar limite de ativações (se já tem sessão ativa com mesmo fingerprint, reusar)
    IF p_fingerprint IS NOT NULL THEN
        SELECT token_sessao INTO v_token
        FROM public.sessoes
        WHERE licenca_id = v_licenca.id
          AND fingerprint = p_fingerprint
          AND ativa = true
          AND expira_em > now()
        LIMIT 1;
    END IF;

    -- Se não encontrou sessão existente, criar nova
    IF v_token IS NULL THEN
        -- Verificar limite de ativações simultâneas
        IF v_licenca.ativacoes_usadas >= v_licenca.max_ativacoes THEN
            RETURN jsonb_build_object(
                'ok', false,
                'mensagem', 'Limite de dispositivos atingido. Entre em contato com o suporte para liberar acesso em novo dispositivo.'
            );
        END IF;

        -- Criar sessão nova
        INSERT INTO public.sessoes (licenca_id, fingerprint, ip, user_agent)
        VALUES (v_licenca.id, p_fingerprint, p_ip, p_user_agent)
        RETURNING token_sessao INTO v_token;

        -- Incrementar contador de ativações
        UPDATE public.licencas
        SET ativacoes_usadas = ativacoes_usadas + 1,
            ativada_em = COALESCE(ativada_em, now())
        WHERE id = v_licenca.id;
    ELSE
        -- Atualizar último acesso da sessão existente
        UPDATE public.sessoes
        SET ultimo_acesso = now()
        WHERE token_sessao = v_token;
    END IF;

    -- Calcular dias restantes (para demo)
    IF v_licenca.expira_em IS NOT NULL THEN
        v_dias_restantes := GREATEST(0, EXTRACT(DAY FROM (v_licenca.expira_em - now()))::INT);
    ELSE
        v_dias_restantes := NULL; -- full sem expiração
    END IF;

    -- Log de sucesso
    INSERT INTO public.auditoria (acao, detalhes, ip)
    VALUES ('chave_valida', jsonb_build_object(
        'licenca_id', v_licenca.id,
        'tipo', v_licenca.tipo,
        'cliente_id', v_licenca.cliente_id
    ), p_ip);

    RETURN jsonb_build_object(
        'ok', true,
        'tipo', v_licenca.tipo,
        'dias_restantes', v_dias_restantes,
        'token_sessao', v_token,
        'nome_cliente', v_cliente.nome,
        'mensagem', 'Acesso liberado com sucesso!'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Erro interno. Tente novamente.');
END;
$$;

-- =============================================================
-- RPC: verificar_sessao
-- Verifica se o token de sessão ainda é válido (chamado no carregamento)
-- Retorna: { ok, tipo, dias_restantes, nome_cliente }
-- =============================================================
CREATE OR REPLACE FUNCTION public.verificar_sessao(
    p_token TEXT,
    p_ip    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sessao    public.sessoes%ROWTYPE;
    v_licenca   public.licencas%ROWTYPE;
    v_cliente   public.clientes%ROWTYPE;
    v_dias      INT;
BEGIN
    -- Buscar sessão ativa
    SELECT * INTO v_sessao
    FROM public.sessoes
    WHERE token_sessao = p_token
      AND ativa = true
      AND expira_em > now()
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Sessão expirada ou inválida.');
    END IF;

    -- Buscar licença
    SELECT * INTO v_licenca FROM public.licencas WHERE id = v_sessao.licenca_id;

    IF NOT v_licenca.ativa THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Licença desativada.');
    END IF;

    IF v_licenca.expira_em IS NOT NULL AND now() > v_licenca.expira_em THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Licença expirada.');
    END IF;

    -- Buscar cliente
    SELECT * INTO v_cliente FROM public.clientes WHERE id = v_licenca.cliente_id;

    -- Atualizar último acesso
    UPDATE public.sessoes SET ultimo_acesso = now() WHERE token_sessao = p_token;

    IF v_licenca.expira_em IS NOT NULL THEN
        v_dias := GREATEST(0, EXTRACT(DAY FROM (v_licenca.expira_em - now()))::INT);
    ELSE
        v_dias := NULL;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'tipo', v_licenca.tipo,
        'dias_restantes', v_dias,
        'nome_cliente', v_cliente.nome
    );
END;
$$;

-- =============================================================
-- RPC: gerar_chave (admin)
-- Admin gera chave para um cliente aprovado
-- Requer: passar admin_secret para evitar uso não autorizado
-- =============================================================
CREATE OR REPLACE FUNCTION public.gerar_chave(
    p_cliente_id    UUID,
    p_tipo          TEXT DEFAULT 'full',
    p_dias_validade INT DEFAULT NULL,
    p_max_ativacoes INT DEFAULT 1,
    p_admin_secret  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_secret    TEXT;
    v_chave     TEXT;
    v_expira    TIMESTAMPTZ;
    v_cliente   public.clientes%ROWTYPE;
BEGIN
    -- Verificar secret do admin (configure no Supabase Vault ou .env)
    SELECT current_setting('app.admin_secret', true) INTO v_secret;

    IF v_secret IS NULL OR v_secret = '' THEN
        -- Fallback: verificar variável de ambiente definida via SQL config
        v_secret := 'FENILI-ADMIN-2026'; -- TROCAR antes de ir para produção
    END IF;

    IF p_admin_secret IS DISTINCT FROM v_secret THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Não autorizado.');
    END IF;

    -- Verificar se cliente existe e está aprovado
    SELECT * INTO v_cliente FROM public.clientes WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Cliente não encontrado.');
    END IF;

    IF v_cliente.status != 'aprovado' THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Cliente ainda não está aprovado.');
    END IF;

    -- Gerar chave no formato FENILI-XXXX-XXXX-XXXX
    v_chave := 'FENILI-' ||
               upper(substring(encode(gen_random_bytes(4), 'hex'), 1, 4)) || '-' ||
               upper(substring(encode(gen_random_bytes(4), 'hex'), 1, 4)) || '-' ||
               upper(substring(encode(gen_random_bytes(4), 'hex'), 1, 4));

    -- Calcular data de expiração
    IF p_dias_validade IS NOT NULL THEN
        v_expira := now() + (p_dias_validade || ' days')::INTERVAL;
    END IF;

    -- Inserir licença
    INSERT INTO public.licencas (
        cliente_id, chave, tipo, expira_em, max_ativacoes
    ) VALUES (
        p_cliente_id, v_chave, p_tipo, v_expira, p_max_ativacoes
    );

    -- Log
    INSERT INTO public.auditoria (acao, detalhes)
    VALUES ('chave_gerada', jsonb_build_object(
        'cliente_id', p_cliente_id,
        'tipo', p_tipo,
        'expira_em', v_expira
    ));

    RETURN jsonb_build_object(
        'ok', true,
        'chave', v_chave,
        'tipo', p_tipo,
        'expira_em', v_expira,
        'mensagem', 'Chave gerada com sucesso!'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Erro ao gerar chave: ' || SQLERRM);
END;
$$;

-- =============================================================
-- RPC: aprovar_cliente (admin)
-- Admin aprova um cliente pendente
-- =============================================================
CREATE OR REPLACE FUNCTION public.aprovar_cliente(
    p_cliente_id   UUID,
    p_admin_secret TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_secret TEXT;
BEGIN
    SELECT current_setting('app.admin_secret', true) INTO v_secret;
    IF v_secret IS NULL OR v_secret = '' THEN
        v_secret := 'FENILI-ADMIN-2026';
    END IF;

    IF p_admin_secret IS DISTINCT FROM v_secret THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Não autorizado.');
    END IF;

    UPDATE public.clientes
    SET status = 'aprovado', aprovado_em = now()
    WHERE id = p_cliente_id AND status = 'pendente';

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'mensagem', 'Cliente não encontrado ou já processado.');
    END IF;

    INSERT INTO public.auditoria (acao, detalhes)
    VALUES ('cliente_aprovado', jsonb_build_object('cliente_id', p_cliente_id));

    RETURN jsonb_build_object('ok', true, 'mensagem', 'Cliente aprovado com sucesso!');
END;
$$;

-- =============================================================
-- RLS (Row Level Security) - Proteção das tabelas
-- As funções SECURITY DEFINER já ignoram RLS,
-- mas bloqueamos acesso direto às tabelas via API
-- =============================================================
ALTER TABLE public.clientes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.licencas  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessoes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria ENABLE ROW LEVEL SECURITY;

-- Nenhum acesso direto via API anônima (tudo via RPC)
CREATE POLICY "sem_acesso_anonimo_clientes"  ON public.clientes  FOR ALL TO anon USING (false);
CREATE POLICY "sem_acesso_anonimo_licencas"  ON public.licencas  FOR ALL TO anon USING (false);
CREATE POLICY "sem_acesso_anonimo_sessoes"   ON public.sessoes   FOR ALL TO anon USING (false);
CREATE POLICY "sem_acesso_anonimo_auditoria" ON public.auditoria FOR ALL TO anon USING (false);

-- Grant nas funções RPC para usuário anônimo do Supabase
GRANT EXECUTE ON FUNCTION public.solicitar_acesso TO anon;
GRANT EXECUTE ON FUNCTION public.validar_chave    TO anon;
GRANT EXECUTE ON FUNCTION public.verificar_sessao TO anon;
GRANT EXECUTE ON FUNCTION public.gerar_chave      TO anon;
GRANT EXECUTE ON FUNCTION public.aprovar_cliente  TO anon;
