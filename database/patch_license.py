import sys
sys.stdout.reconfigure(encoding='utf-8')

with open(r'c:\Users\joaop\Projetos\BnacadaHidraulica\bancada-hidraulica\index.html', 'r', encoding='utf-8') as f:
    content = f.read()

start = content.find('        const LICENSE_CONFIG = {')
end   = content.find('        // ===== FIM DO SISTEMA DE LICENCIAMENTO =====')
end_full = content.find('\n', end) + 1

print(f'Start: {start}, End: {end_full}, Block size: {end_full - start}')

new_js = r"""        // ===== SISTEMA DE LICENCIAMENTO - SUPABASE =====
        // IMPORTANTE: Substitua as variaveis abaixo com seus dados do Supabase
        // Painel: https://app.supabase.com -> Settings -> API
        const SUPABASE_URL      = 'https://SEU_PROJETO.supabase.co'; // TROCAR
        const SUPABASE_ANON_KEY = 'SUA_CHAVE_ANON_AQUI';             // TROCAR

        const { createClient } = supabase;
        const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

        const SESSION_KEY = 'hf_session_token';

        function getFingerprint() {
            const str = [navigator.userAgent, navigator.language, screen.width, screen.height, new Date().getTimezoneOffset()].join('|');
            let hash = 0;
            for (let i = 0; i < str.length; i++) {
                hash = ((hash << 5) - hash) + str.charCodeAt(i);
                hash |= 0;
            }
            return Math.abs(hash).toString(36);
        }

        async function checkLicense() {
            const token = localStorage.getItem(SESSION_KEY);
            if (!token) { showActivationScreen(); return; }

            try {
                const { data, error } = await db.rpc('verificar_sessao', { p_token: token });
                if (error || !data?.ok) {
                    localStorage.removeItem(SESSION_KEY);
                    showActivationScreen();
                    return;
                }
                hideLicenseScreens();
                showLicenseBanner(data.tipo, data.dias_restantes);
                initApp();
            } catch (e) {
                localStorage.removeItem(SESSION_KEY);
                showActivationScreen();
            }
        }

        async function validateLicense() {
            const keyInput = document.getElementById('licenseKey');
            const errorEl  = document.getElementById('licenseError');
            const key = keyInput.value.trim().toUpperCase();
            errorEl.classList.remove('show');

            if (!key) {
                errorEl.textContent = 'Digite a chave de ativacao!';
                errorEl.classList.add('show');
                return;
            }

            const btn = document.querySelector('#licenseOverlay .license-btn-primary');
            const originalText = btn.textContent;
            btn.textContent = 'Verificando...';
            btn.disabled = true;

            try {
                const { data, error } = await db.rpc('validar_chave', {
                    p_chave:       key,
                    p_fingerprint: getFingerprint(),
                    p_user_agent:  navigator.userAgent
                });

                if (error || !data?.ok) {
                    errorEl.textContent = data?.mensagem || 'Chave invalida. Tente novamente.';
                    errorEl.classList.add('show');
                    keyInput.value = '';
                } else {
                    localStorage.setItem(SESSION_KEY, data.token_sessao);
                    hideLicenseScreens();
                    showLicenseBanner(data.tipo, data.dias_restantes);
                    initApp();
                }
            } catch (e) {
                errorEl.textContent = 'Erro de conexao. Verifique sua internet.';
                errorEl.classList.add('show');
            } finally {
                btn.textContent = originalText;
                btn.disabled = false;
            }
        }

        async function validateExpiredLicense() {
            const keyInput = document.getElementById('licenseKeyExpired');
            const errorEl  = document.getElementById('licenseErrorExpired');
            const key = keyInput.value.trim().toUpperCase();
            errorEl.classList.remove('show');

            if (!key) {
                errorEl.textContent = 'Digite a chave FULL!';
                errorEl.classList.add('show');
                return;
            }

            const btn = document.querySelector('#licenseExpiredOverlay .license-btn-primary');
            const originalText = btn.textContent;
            btn.textContent = 'Verificando...';
            btn.disabled = true;

            try {
                const { data, error } = await db.rpc('validar_chave', {
                    p_chave:       key,
                    p_fingerprint: getFingerprint(),
                    p_user_agent:  navigator.userAgent
                });

                if (error || !data?.ok) {
                    errorEl.textContent = data?.mensagem || 'Chave invalida.';
                    errorEl.classList.add('show');
                    keyInput.value = '';
                } else {
                    localStorage.setItem(SESSION_KEY, data.token_sessao);
                    hideLicenseScreens();
                    showLicenseBanner(data.tipo, data.dias_restantes);
                    initApp();
                }
            } catch (e) {
                errorEl.textContent = 'Erro de conexao. Verifique sua internet.';
                errorEl.classList.add('show');
            } finally {
                btn.textContent = originalText;
                btn.disabled = false;
            }
        }

        async function solicitarAcesso() {
            const nome      = document.getElementById('regNome').value.trim();
            const email     = document.getElementById('regEmail').value.trim();
            const empresa   = document.getElementById('regEmpresa').value.trim();
            const telefone  = document.getElementById('regTelefone').value.trim();
            const errorEl   = document.getElementById('regError');
            const successEl = document.getElementById('regSuccess');

            errorEl.classList.remove('show');
            successEl.style.display = 'none';

            if (!nome || !email) {
                errorEl.textContent = 'Nome e email sao obrigatorios.';
                errorEl.classList.add('show');
                return;
            }

            const btn = document.getElementById('regBtn');
            const originalText = btn.textContent;
            btn.textContent = 'Enviando...';
            btn.disabled = true;

            try {
                const { data, error } = await db.rpc('solicitar_acesso', {
                    p_nome:     nome,
                    p_email:    email,
                    p_empresa:  empresa  || null,
                    p_telefone: telefone || null
                });

                if (error || !data?.ok) {
                    errorEl.textContent = data?.mensagem || 'Erro ao enviar. Tente novamente.';
                    errorEl.classList.add('show');
                } else {
                    successEl.textContent = data.mensagem;
                    successEl.style.display = 'block';
                    ['regNome','regEmail','regEmpresa','regTelefone'].forEach(function(id) {
                        document.getElementById(id).value = '';
                    });
                }
            } catch (e) {
                errorEl.textContent = 'Erro de conexao. Verifique sua internet.';
                errorEl.classList.add('show');
            } finally {
                btn.textContent = originalText;
                btn.disabled = false;
            }
        }

        function showActivationScreen() {
            document.getElementById('licenseOverlay').classList.remove('hidden');
            document.getElementById('licenseExpiredOverlay').classList.add('hidden');
            document.getElementById('regOverlay').classList.add('hidden');
        }

        function showExpiredScreen() {
            document.getElementById('licenseOverlay').classList.add('hidden');
            document.getElementById('licenseExpiredOverlay').classList.remove('hidden');
            document.getElementById('regOverlay').classList.add('hidden');
        }

        function showRegScreen() {
            document.getElementById('licenseOverlay').classList.add('hidden');
            document.getElementById('licenseExpiredOverlay').classList.add('hidden');
            document.getElementById('regOverlay').classList.remove('hidden');
        }

        function hideLicenseScreens() {
            document.getElementById('licenseOverlay').classList.add('hidden');
            document.getElementById('licenseExpiredOverlay').classList.add('hidden');
            document.getElementById('regOverlay').classList.add('hidden');
        }

        function showLicenseBanner(type, daysLeft) {
            const banner     = document.getElementById('licenseBanner');
            const bannerText = document.getElementById('licenseBannerText');
            if (type === 'full' || type === 'enterprise') {
                banner.className = 'license-banner show full';
                bannerText.textContent = 'Licenca Full Ativa - Hidraulicos Fenili';
            } else {
                banner.className = 'license-banner show';
                bannerText.textContent = daysLeft != null
                    ? 'Versao DEMO - ' + daysLeft + ' dias restantes'
                    : 'Versao DEMO Ativa';
            }
        }

        // Permitir Enter nas telas de ativacao
        document.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                if (!document.getElementById('licenseOverlay').classList.contains('hidden')) {
                    validateLicense();
                } else if (!document.getElementById('licenseExpiredOverlay').classList.contains('hidden')) {
                    validateExpiredLicense();
                }
            }
        });

        // ===== FIM DO SISTEMA DE LICENCIAMENTO =====
"""

content = content[:start] + new_js + content[end_full:]

with open(r'c:\Users\joaop\Projetos\BnacadaHidraulica\bancada-hidraulica\index.html', 'w', encoding='utf-8') as f:
    f.write(content)

print('Done - JS substituido com sucesso')
