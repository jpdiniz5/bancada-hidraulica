# Configuração do Banco de Dados - Bancada Hidráulica

## Passo a Passo para Colocar em Produção

---

### 1. Criar conta no Supabase

Acesse https://app.supabase.com e crie um projeto gratuito.

---

### 2. Executar os SQLs no Supabase

No painel do Supabase: **SQL Editor** → **New Query**

Execute na ordem:
1. Cole e execute o conteúdo de `01_schema.sql`
2. Cole e execute o conteúdo de `02_functions.sql`

---

### 3. Pegar as credenciais do projeto

No Supabase: **Settings → API**

Copie:
- **Project URL** → ex: `https://abcdefgh.supabase.co`
- **anon public key** → chave longa começando com `eyJ...`

---

### 4. Configurar o index.html

Abra `index.html` e procure por:

```javascript
const SUPABASE_URL      = 'https://SEU_PROJETO.supabase.co'; // TROCAR
const SUPABASE_ANON_KEY = 'SUA_CHAVE_ANON_AQUI';             // TROCAR
```

Substitua pelos seus valores reais.

---

### 5. Fluxo de uso

#### Cliente solicita acesso:
1. Abre o app → clica "Não tem chave? Solicitar acesso"
2. Preenche nome, email, empresa, telefone
3. Clica "Enviar Solicitação"
4. Dados ficam na tabela `clientes` com status `pendente`

#### Admin aprova e gera chave:
No **SQL Editor** do Supabase, execute:

```sql
-- 1. Ver solicitações pendentes
SELECT id, nome, email, empresa, criado_em
FROM clientes
WHERE status = 'pendente'
ORDER BY criado_em;

-- 2. Aprovar cliente (copie o id da consulta acima)
SELECT aprovar_cliente(
    'UUID_DO_CLIENTE_AQUI',
    'FENILI-ADMIN-2026'   -- senha admin
);

-- 3. Gerar chave para o cliente aprovado
SELECT gerar_chave(
    'UUID_DO_CLIENTE_AQUI',
    'full',               -- tipo: 'demo' ou 'full'
    NULL,                 -- dias_validade: NULL = sem expiração, 30 = 30 dias
    1,                    -- max_ativacoes: número de dispositivos
    'FENILI-ADMIN-2026'   -- senha admin
);
-- O resultado mostra a chave gerada, ex: FENILI-A3F2-BC81-7E4D
```

#### Cliente ativa com a chave:
1. Recebe a chave por email/WhatsApp
2. Abre o app → digita a chave
3. Sistema valida online e libera o acesso

---

### 6. Monitorar acessos

```sql
-- Ver todos os clientes e status de licença
SELECT c.nome, c.email, c.empresa, c.status,
       l.chave, l.tipo, l.expira_em, l.ativacoes_usadas
FROM clientes c
LEFT JOIN licencas l ON l.cliente_id = c.id
ORDER BY c.criado_em DESC;

-- Ver sessões ativas agora
SELECT c.nome, s.ip, s.user_agent, s.ultimo_acesso
FROM sessoes s
JOIN licencas l ON l.id = s.licenca_id
JOIN clientes c ON c.id = l.cliente_id
WHERE s.ativa = true AND s.expira_em > now()
ORDER BY s.ultimo_acesso DESC;

-- Log de auditoria (últimas 50 ações)
SELECT acao, detalhes, ip, criado_em
FROM auditoria
ORDER BY criado_em DESC
LIMIT 50;
```

---

### 7. Trocar a senha admin (IMPORTANTE!)

No SQL Editor, execute:

```sql
ALTER DATABASE postgres SET "app.admin_secret" = 'SUA_NOVA_SENHA_SECRETA';
```

E atualize todas as chamadas a `gerar_chave` e `aprovar_cliente` com a nova senha.

---

### Estrutura das tabelas

| Tabela     | Função                                      |
|------------|---------------------------------------------|
| clientes   | Cadastro de clientes (status: pendente/aprovado) |
| licencas   | Chaves geradas por cliente                  |
| sessoes    | Sessões ativas por dispositivo              |
| auditoria  | Log de todas as ações de acesso             |

### Tipos de licença

| Tipo        | Descrição                              |
|-------------|----------------------------------------|
| `demo`      | Prazo limitado (ex: 30 dias)           |
| `full`      | Acesso completo sem expiração          |
| `enterprise`| Múltiplos dispositivos, sem expiração  |
