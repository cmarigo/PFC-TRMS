function R = otimiza_fvpsi_fcpsi(varargin)
% ==============================================================================
% otimiza_fvpsi_fcpsi.m
%
% Otimizacao CONJUNTA dos coeficientes de atrito do eixo de pitch
% (f_vpsi e f_cpsi) via fminsearch, partindo dos valores do Tastemirov et
% al. (2017) carregados por trms_params.m. Os demais parametros ficam
% fixos no nominal. E' a primeira tentativa de identificacao do atrito,
% descrita em sub:nao_identificabilidade.
%
% Antes do fminsearch, o diagnostico de sensibilidade (secao 2.5) varre
% cada parametro sozinho, de 0,1x a 10x o nominal, com o outro fixo no
% nominal, e plota J contra cada um.
%
% METODO:
%   - atrito de Coulomb puro (f_s = f_cpsi a cada avaliacao, que anula o
%     termo estatico);
%   - otimizacao em ESPACO LOG (q = log(p)), para manter f_vpsi e f_cpsi
%     positivos; chute inicial no nominal;
%   - optimset('TolX', 1e-6, 'TolFun', 1e-8);
%   - custo: MSE ABSOLUTO a partir de T_SETTLE = 20 s, com desvios
%     referenciados a media dos 2 s anteriores (win_ref); com varios
%     ensaios numa mesma execucao, soma dos erros quadraticos dividida
%     pelo total de amostras;
%   - varredura univariada logspace(-1, 1, 15) para cada parametro;
%   - uma otimizacao independente por ensaio. As tres execucoes citadas no
%     texto (PRBS 0, PRBS +5 e degrau 0) rodam em sequencia;
%   - fminsearch com Display 'off' (o resumo de cada execucao e' impresso
%     no fim, com o numero de avaliacoes).
%
% MODELO: trms_model_pid_bancada pelo simula_trms (modo 0), guinada TRAVADA
% (mascara [1 0 1 1 1 0]), como na bancada, e x0 no equilibrio do ponto de
% operacao (trms_equilibrium). E' FUNCAO para isolar as variaveis do
% workspace base.
%
% USO
%   R = otimiza_fvpsi_fcpsi;                       % as tres execucoes do texto
%   R = otimiza_fvpsi_fcpsi('execucoes', {{'out_step_opp0deg_amp03.mat'}});
%   R = otimiza_fvpsi_fcpsi('sensibilidade', false, 'graficos', false);
%
%   Cada elemento de 'execucoes' e' uma lista de arquivos otimizados JUNTOS
%   (custo somado).
% ==============================================================================

clc; close all;

%% CONFIGURACAO ------------------------------------------------------------------
P          = caminhos_dados();
IN_DIR     = P.pitch;
T_SETTLE   = 20.0;
TS_MODEL   = 0.001;
MASCARA    = [1 0 1 1 1 0]';

OP_ANG = [-10 -5 0 5 10 15 20];
OP_V   = [-0.884 -0.485 0 0.294 0.541 0.754 1.027];

EXECUCOES = { ...
    {'out_prbs_opp0deg_amp03.mat'}, ...
    {'out_prbs_opp5deg_amp03.mat'}, ...
    {'out_step_opp0deg_amp03.mat'} };
FAZER_DIAGNOSTICO_SENSIBILIDADE = true;
GRAFICOS = true;

for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'execucoes',     EXECUCOES = varargin{k+1};
        case 'sensibilidade', FAZER_DIAGNOSTICO_SENSIBILIDADE = logical(varargin{k+1});
        case 'graficos',      GRAFICOS = logical(varargin{k+1});
        otherwise, error('opcao desconhecida: %s', varargin{k});
    end
end

%% 1. Parametros nominais (Tastemirov) ------------------------------------------
evalin('base', 'trms_params;');
base_par.f_vpsi   = evalin('base', 'f_vpsi');
base_par.f_cpsi   = evalin('base', 'f_cpsi');
base_par.CT_m_pos = evalin('base', 'CT_m_pos');
base_par.I_psi    = evalin('base', 'I_psi');
base_par.v_s      = 0.05;                    % irrelevante com f_s = f_cpsi
p0 = [base_par.f_vpsi, base_par.f_cpsi];

fprintf('Chute inicial (Tastemirov):\n');
fprintf('  f_vpsi = %.6g\n', p0(1));
fprintf('  f_cpsi = %.6g\n', p0(2));
fprintf('Atrito de Coulomb puro (f_s = f_cpsi), guinada %s no modelo\n', mat2str(MASCARA.'));

opts = optimset('Display', 'off', 'TolX', 1e-6, 'TolFun', 1e-8);

R = struct('arquivos', {}, 'f_vpsi', {}, 'f_cpsi', {}, 'rel_fv', {}, 'rel_fc', {}, ...
           'J_nominal', {}, 'J_otimo', {}, 'reducao', {}, 'n_aval', {}, ...
           'fvpsi_faixa', {}, 'J_fvpsi', {}, 'fcpsi_faixa', {}, 'J_fcpsi', {});

for x = 1:numel(EXECUCOES)
    arquivos = cellstr(EXECUCOES{x});
    fprintf('\n==================================================================\n');
    fprintf(' Execucao %d/%d: %s\n', x, numel(EXECUCOES), strjoin(arquivos, ' + '));
    fprintf('==================================================================\n');

    %% 2. Pre-carrega entrada/saida de cada ensaio ------------------------------
    ensaios = cell(numel(arquivos), 1);
    for i = 1:numel(arquivos)
        e = carrega_ensaio(acha_dados(IN_DIR, arquivos{i}), OP_ANG, OP_V, TS_MODEL);
        ensaios{i} = e;
        fprintf('[Carregado] %-28s  %+d deg  u_offset=%+.4f V  (%d amostras)\n', ...
            e.nome, e.ang, e.u_offset, numel(e.t_exp));
    end

    %% 2.5 Diagnostico de sensibilidade ------------------------------------------
    % Varre cada parametro individualmente (mantendo o outro fixo no nominal)
    % para verificar se a funcao de custo realmente enxerga cada um deles.
    fvpsi_faixa = []; J_fvpsi = []; fcpsi_faixa = []; J_fcpsi = [];
    if FAZER_DIAGNOSTICO_SENSIBILIDADE
        fprintf('\n--- Diagnostico de sensibilidade: f_vpsi (f_cpsi fixo no nominal) ---\n');
        fvpsi_faixa = p0(1) * logspace(-1, 1, 15);   % 0.1x a 10x o nominal
        J_fvpsi = zeros(size(fvpsi_faixa));
        for k = 1:numel(fvpsi_faixa)
            J_fvpsi(k) = custo_atrito_pitch([fvpsi_faixa(k), p0(2)], ensaios, base_par, T_SETTLE, MASCARA);
            fprintf('  f_vpsi = %.4e (%5.2fx)  ->  J = %.6e\n', fvpsi_faixa(k), fvpsi_faixa(k)/p0(1), J_fvpsi(k));
        end

        fprintf('\n--- Diagnostico de sensibilidade: f_cpsi (f_vpsi fixo no nominal) ---\n');
        fcpsi_faixa = p0(2) * logspace(-1, 1, 15);
        J_fcpsi = zeros(size(fcpsi_faixa));
        for k = 1:numel(fcpsi_faixa)
            J_fcpsi(k) = custo_atrito_pitch([p0(1), fcpsi_faixa(k)], ensaios, base_par, T_SETTLE, MASCARA);
            fprintf('  f_cpsi = %.4e (%5.2fx)  ->  J = %.6e\n', fcpsi_faixa(k), fcpsi_faixa(k)/p0(2), J_fcpsi(k));
        end

        resumo_varredura('f_vpsi', fvpsi_faixa/p0(1), J_fvpsi);
        resumo_varredura('f_cpsi', fcpsi_faixa/p0(2), J_fcpsi);

        if GRAFICOS
            figure('Color', 'w', 'Name', sprintf('Sensibilidade -- %s', strjoin(arquivos, ' + ')));
            subplot(1, 2, 1);
            semilogx(fvpsi_faixa, J_fvpsi, 'o-', 'LineWidth', 1.3); hold on;
            xline(p0(1), 'k--');
            xlabel('f_{v\psi}'); ylabel('J (MSE absoluto)');
            title('Sensibilidade a f_{v\psi}'); grid on;

            subplot(1, 2, 2);
            semilogx(fcpsi_faixa, J_fcpsi, 'o-', 'LineWidth', 1.3); hold on;
            xline(p0(2), 'k--');
            xlabel('f_{c\psi}'); ylabel('J (MSE absoluto)');
            title('Sensibilidade a f_{c\psi}'); grid on;
        end
    end

    %% 3. fminsearch em espaco log -------------------------------------------------
    funcao_custo_log = @(q) custo_atrito_pitch(exp(q), ensaios, base_par, T_SETTLE, MASCARA);

    tic;
    [q_otimo, ~, ~, info] = fminsearch(funcao_custo_log, log(p0), opts);
    tempo_otimizacao = toc;
    p_otimo = exp(q_otimo);

    fprintf('\n--- Resultado da otimizacao (%.1f s, %d avaliacoes) ---\n', ...
        tempo_otimizacao, info.funcCount);
    fprintf('  f_vpsi: %.6g  ->  %.6g   (%.3gx o nominal)\n', p0(1), p_otimo(1), p_otimo(1)/p0(1));
    fprintf('  f_cpsi: %.6g  ->  %.6g   (%.3gx o nominal)\n', p0(2), p_otimo(2), p_otimo(2)/p0(2));

    %% 4. Custo antes/depois e grafico -----------------------------------------------
    J_nominal = custo_atrito_pitch(p0,      ensaios, base_par, T_SETTLE, MASCARA);
    J_otimo   = custo_atrito_pitch(p_otimo, ensaios, base_par, T_SETTLE, MASCARA);
    fprintf('\n  MSE (nominal): %.6e rad^2\n', J_nominal);
    fprintf('  MSE (otimo):   %.6e rad^2\n', J_otimo);
    fprintf('  Reducao:       %.1f%%\n', 100*(J_nominal - J_otimo)/J_nominal);

    if GRAFICOS
        plota_comparacao(p0, p_otimo, ensaios{1}, base_par, T_SETTLE, MASCARA);
    end

    R(end+1) = struct('arquivos', {arquivos}, 'f_vpsi', p_otimo(1), 'f_cpsi', p_otimo(2), ...  %#ok<AGROW>
        'rel_fv', p_otimo(1)/p0(1), 'rel_fc', p_otimo(2)/p0(2), ...
        'J_nominal', J_nominal, 'J_otimo', J_otimo, ...
        'reducao', 100*(J_nominal - J_otimo)/J_nominal, 'n_aval', info.funcCount, ...
        'fvpsi_faixa', fvpsi_faixa, 'J_fvpsi', J_fvpsi, ...
        'fcpsi_faixa', fcpsi_faixa, 'J_fcpsi', J_fcpsi);
end

%% Resumo -------------------------------------------------------------------------
fprintf('\n==================================================================\n');
fprintf(' RESUMO: otimizacao conjunta (f_vpsi, f_cpsi), Coulomb puro\n');
fprintf('==================================================================\n');
fprintf(' %-36s %12s %12s %10s\n', 'Execucao', 'f_vpsi/nom', 'f_cpsi/nom', 'reducao J');
for x = 1:numel(R)
    fprintf(' %-36s %12.3g %12.3g %9.1f%%\n', strjoin(R(x).arquivos, ' + '), ...
        R(x).rel_fv, R(x).rel_fc, R(x).reducao);
end

arq_res = fullfile(P.resultados, 'otimiza_fvpsi_fcpsi.mat');
save(arq_res, 'R', 'p0', 'MASCARA');
fprintf('\nResultados salvos em %s\n', arq_res);
end


%% ================================================================================
%% FUNCOES LOCAIS
%% ================================================================================

function J = custo_atrito_pitch(p, ensaios, base_par, T_SETTLE, mascara)
% MSE absoluto somado sobre todos os ensaios (soma dos erros quadraticos
% dividida pelo total de amostras). Coulomb puro: f_s acompanha f_cpsi, o
% que anula o termo estatico.
    par        = base_par;
    par.f_vpsi = p(1);
    par.f_cpsi = p(2);
    par.f_s    = p(2);

    soma_erro2 = 0;
    n_total    = 0;
    for i = 1:numel(ensaios)
        [ed, sd] = desvios(par, ensaios{i}, T_SETTLE, mascara);
        idx  = ensaios{i}.t_exp >= T_SETTLE;
        erro = sd(idx) - ed(idx);
        soma_erro2 = soma_erro2 + sum(erro.^2);
        n_total    = n_total + numel(erro);
    end
    J = soma_erro2 / n_total;
end


function [ed, sd] = desvios(par, e, T_SETTLE, mascara)
%DESVIOS Desvios medido e simulado, referenciados a media de win_ref.
    opc.T_fim   = e.T_sim;
    opc.modo    = 0;
    opc.mascara = mascara;
    opc.x0      = e.x0;
    opc.u_m     = timeseries(e.u_m_in, e.t_in);
    opc.par     = par;
    S = simula_trms(opc);

    psi_sim = interp1(S.t_psi, S.psi, e.t_exp, 'linear', 'extrap');
    win_ref = (e.t_exp >= T_SETTLE - 2) & (e.t_exp <= T_SETTLE);
    ed = e.psi_exp - mean(e.psi_exp(win_ref));
    sd = psi_sim   - mean(psi_sim(win_ref));
end


function resumo_varredura(nome, fator, J)
%RESUMO_VARREDURA Variacao de J na faixa e posicao do minimo.
    [jm, km] = min(J);
    var_pct  = 100 * (max(J) - jm) / jm;
    if km == 1 || km == numel(J)
        onde = 'NA BORDA da faixa (sem minimo interior)';
    else
        onde = 'minimo interior';
    end
    fprintf('%s: variacao de J na faixa = %.1f%% | minimo em %.3gx (%s)\n', nome, var_pct, fator(km), onde);
end


function plota_comparacao(p_nominal, p_otimo, e, base_par, T_SETTLE, mascara)
% Real x modelo nominal x modelo otimizado (primeiro ensaio da execucao).
    pn = base_par;  pn.f_vpsi = p_nominal(1);  pn.f_cpsi = p_nominal(2);  pn.f_s = p_nominal(2);
    po = base_par;  po.f_vpsi = p_otimo(1);    po.f_cpsi = p_otimo(2);    po.f_s = p_otimo(2);
    [ed, sd_nom] = desvios(pn, e, T_SETTLE, mascara);
    [~,  sd_ot]  = desvios(po, e, T_SETTLE, mascara);

    figure('Color', 'w');
    plot(e.t_exp, ed,     'b',   'LineWidth', 1.3); hold on;
    plot(e.t_exp, sd_nom, 'r--', 'LineWidth', 1.2);
    plot(e.t_exp, sd_ot,  'g-',  'LineWidth', 1.2);
    xline(T_SETTLE, 'k:');
    legend('Planta (experimental)', 'Modelo (nominal)', 'Modelo (otimizado)', 'Location', 'best');
    xlabel('Tempo (s)'); ylabel('\Delta\psi (rad)');
    title(sprintf('%s  (%+d deg)  --  antes/depois da otimizacao de atrito', ...
                  strrep(e.nome, '_', '\_'), e.ang));
    grid on;
end


function e = carrega_ensaio(caminho, OP_ANG, OP_V, Ts)
%CARREGA_ENSAIO Le o ensaio e identifica o ponto de operacao pela TENSAO de
%   polarizacao registrada (antes de 19 s), e nao so pelo nome do arquivo.
    [~, base, ext] = fileparts(caminho);
    [ang_nome, ~] = op_from_name(base, OP_ANG, OP_V);

    plant = load(caminho);
    [t_exp, psi_exp] = read_output(plant, [base ext]);
    [t_in, u_m_in]   = read_input(plant, t_exp, Ts);

    u_pol  = median(u_m_in(t_in < 19));          % polarizacao realmente aplicada
    [~, k] = min(abs(OP_V - u_pol));
    ang    = OP_ANG(k);
    if ang ~= ang_nome
        fprintf(['[AVISO] %s: o nome indica %+d graus, mas a polarizacao registrada e'' ' ...
                 '%+.3f V (%+d graus). Tratado como ensaio de %+d graus.\n'], ...
                [base ext], ang_nome, u_pol, ang, ang);
    end

    e.nome     = [base ext];
    e.ang      = ang;
    e.u_offset = u_pol;
    e.t_exp    = t_exp;
    e.psi_exp  = psi_exp;
    e.t_in     = t_in;
    e.u_m_in   = u_m_in;
    e.T_sim    = t_in(end);
    evalc('x0_eq = trms_equilibrium(u_pol);');   % equilibrio do ponto (sem o texto impresso)
    e.x0 = x0_eq;
end


function [ang, volt] = op_from_name(name, ANG, V)
    tok = regexpi(name, 'op([pn]?)(\d+)', 'tokens', 'once');
    if isempty(tok)
        error('ponto de operacao nao identificado (esperado op[p/n]<ang> no nome)');
    end
    s = 1;
    if strcmpi(tok{1}, 'n'), s = -1; end
    ang = s * str2double(tok{2});
    k = find(ANG == ang, 1);
    if isempty(k)
        error('angulo %+d deg fora da tabela de pontos de operacao', ang);
    end
    volt = V(k);
end


function [t, psi] = read_output(p, nome)
%READ_OUTPUT Tempo e angulo de arfagem do ensaio (corrige a troca
%   pitch/yaw dos chirp da Coleta 1).
    if nargin < 2, nome = ''; end
    if isfield(p, 't_out') && isfield(p, 'pitch')
        t = p.t_out(:);  psi = p.pitch(:);
        if isfield(p, 'simin') && isfield(p, 'yaw')
            u = interp1(p.simin(:,1), p.simin(:,2), t, 'linear', 'extrap');
            if max(abs(psi - u)) < 1e-3
                fprintf('[AVISO] %s: ''pitch'' contem a tensao; usando ''yaw'' como angulo de arfagem.\n', nome);
                psi = p.yaw(:);
            end
        end
    elseif isfield(p, 'tout') && isfield(p, 'pitch')
        t = p.tout(:);   psi = p.pitch(:);
    elseif isfield(p, 'simout_main')
        M = p.simout_main; t = M(:, 1); psi = M(:, 2);
    else
        error('sem saida de pitch reconhecivel (campos: %s)', strjoin(fieldnames(p), ', '));
    end
end


function [t_in, u_m] = read_input(p, t_exp, Ts)
    if isfield(p, 'simin')
        t_in = p.simin(:, 1);  u_m = p.simin(:, 2);
    elseif isfield(p, 'u_applied')
        t_in = (t_exp(1):Ts:t_exp(end))';
        u_m  = interp1(t_exp, p.u_applied(:), t_in, 'previous', 'extrap');
    else
        error('sem entrada (simin/u_applied) reconhecivel (campos: %s)', strjoin(fieldnames(p), ', '));
    end
end
