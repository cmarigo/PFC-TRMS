function sensibilidade_i_psi()
% ==============================================================================
% sensibilidade_i_psi.m
%
% Testa DIRETAMENTE a hipotese de que a divergencia de fase observada em
% t > ~50s (nos testes de otimizacao de atrito com STEP em 0 graus) vem de
% um erro em I_psi (inercia de pitch), e nao de atrito.
%
% Aqui varremos I_psi sozinho -- f_vpsi e f_cpsi ficam FIXOS NO NOMINAL
% (mudar uma coisa de cada vez, mesmo principio das varreduras anteriores)
% -- e medimos o MSE em DUAS janelas separadas, alem do total:
%   - JANELA INICIAL (T_SETTLE ate T_SPLIT): onde o ajuste ja era bom
%   - JANELA TARDIA  (T_SPLIT ate o fim):     onde a divergencia aparece
%
% Se I_psi for de fato a causa, esperamos:
%   (a) um minimo de custo bem definido;
%   (b) a MELHORA concentrada na janela tardia, sem piorar a inicial.
%
% METODO: STEP 0 grau, faixa logspace(-0.5, 0.5, 15) (de ~0,3x a ~3x, com
% 1,0x e 1,18x na grade), janelas separadas em T_SPLIT = 50 s, MSE
% ABSOLUTO, atrito nominal: f_s = f_cpsi, que anula o termo estatico (o
% trms_params traz f_s = 3,48 f_cpsi).
%
% MODELO: trms_model_pid_bancada pelo simula_trms (modo 0), guinada TRAVADA
% (mascara [1 0 1 1 1 0]), como na bancada, e x0 no equilibrio do ponto de
% operacao (trms_equilibrium). E' FUNCAO para isolar as variaveis do
% workspace base.
%
% Alem do MSE absoluto, imprime a reducao relativa a I_psi nominal em cada
% janela.
% ==============================================================================

clc; close all;

%% CONFIGURACAO ------------------------------------------------------------------
P          = caminhos_dados();
IN_DIR     = P.pitch;
T_SETTLE   = 20.0;
T_SPLIT    = 50.0;   % onde a divergencia de fase comeca a aparecer visualmente
TS_MODEL   = 0.001;
MASCARA    = [1 0 1 1 1 0]';

OP_ANG = [-10 -5 0 5 10 15 20];
OP_V   = [-0.884 -0.485 0 0.294 0.541 0.754 1.027];

arquivo = 'out_step_opp0deg_amp03.mat';   % mesmo dataset onde a divergencia foi vista

%% Parametros nominais -------------------------------------------------------------
evalin('base', 'trms_params;');
par.f_vpsi   = evalin('base', 'f_vpsi');     % NAO otimizado -- nominal
par.f_cpsi   = evalin('base', 'f_cpsi');     % NAO otimizado -- nominal
par.CT_m_pos = evalin('base', 'CT_m_pos');
par.f_s      = par.f_cpsi;                   % sem termo estatico
par.v_s      = 0.05;                         % irrelevante com f_s = f_cpsi
I_psi_nom    = evalin('base', 'I_psi');

fprintf('f_vpsi fixo:   %.6g\n', par.f_vpsi);
fprintf('f_cpsi fixo:   %.6g\n', par.f_cpsi);
fprintf('f_s:           %.6g (= f_cpsi, sem termo estatico)\n', par.f_s);
fprintf('I_psi nominal: %.6g\n', I_psi_nom);
fprintf('guinada:       %s no modelo\n\n', mat2str(MASCARA.'));

%% Carrega o ensaio ------------------------------------------------------------------
e = carrega_ensaio(acha_dados(IN_DIR, arquivo), OP_ANG, OP_V, TS_MODEL);
fprintf('[Carregado] %s  %+d deg  u_offset=%+.4f V  (%d amostras)\n\n', ...
    e.nome, e.ang, e.u_offset, numel(e.t_exp));

%% Varredura de sensibilidade de I_psi -----------------------------------------------
fator       = logspace(-0.5, 0.5, 15);       % ~0.3x a 3x o nominal
I_psi_faixa = I_psi_nom * fator;

J_total   = zeros(size(I_psi_faixa));
J_inicial = zeros(size(I_psi_faixa));
J_tardio  = zeros(size(I_psi_faixa));

fprintf('--- Varredura de I_psi (f_vpsi e f_cpsi fixos no nominal) ---\n');
for k = 1:numel(I_psi_faixa)
    p = par;
    p.I_psi = I_psi_faixa(k);
    [J_total(k), J_inicial(k), J_tardio(k)] = custo_i_psi(p, e, T_SETTLE, T_SPLIT, MASCARA);
    fprintf('  I_psi = %.4e (%.2fx)  ->  J_total = %.4e | J_inicial = %.4e | J_tardio = %.4e\n', ...
        I_psi_faixa(k), fator(k), J_total(k), J_inicial(k), J_tardio(k));
end

%% Plot -----------------------------------------------------------------------------
figure('Color', 'w');
subplot(1, 3, 1);
semilogx(I_psi_faixa, J_total, 'o-', 'LineWidth', 1.3); hold on;
xline(I_psi_nom, 'k--');
xlabel('I_{\psi}'); ylabel('J (MSE absoluto)');
title('Custo total (t \geq T_{SETTLE})'); grid on;

subplot(1, 3, 2);
semilogx(I_psi_faixa, J_inicial, 'o-', 'LineWidth', 1.3); hold on;
xline(I_psi_nom, 'k--');
xlabel('I_{\psi}');
title(sprintf('Janela inicial (%.0f-%.0f s)', T_SETTLE, T_SPLIT)); grid on;

subplot(1, 3, 3);
semilogx(I_psi_faixa, J_tardio, 'o-', 'LineWidth', 1.3); hold on;
xline(I_psi_nom, 'k--');
xlabel('I_{\psi}');
title(sprintf('Janela tardia (%.0f-fim)', T_SPLIT)); grid on;

[~, k_nom] = min(abs(fator - 1));
nomes = {'total', 'inicial', 'tardio'};
J     = {J_total, J_inicial, J_tardio};
fprintf('\n');
for w = 1:3
    [jm, km] = min(J{w});
    fprintf('Minimo (%-7s): I_psi = %.4e  (%.2fx o nominal) | reducao em relacao ao nominal: %.1f%%\n', ...
        nomes{w}, I_psi_faixa(km), fator(km), 100*(J{w}(k_nom) - jm)/J{w}(k_nom));
end

arq_res = fullfile(P.resultados, 'sensibilidade_i_psi.mat');
save(arq_res, 'I_psi_faixa', 'fator', 'J_total', 'J_inicial', 'J_tardio', 'I_psi_nom', 'MASCARA');
fprintf('\nResultados salvos em %s\n', arq_res);
end


%% ====================================================================================
%% FUNCOES LOCAIS
%% ====================================================================================

function [J_total, J_inicial, J_tardio] = custo_i_psi(p, e, T_SETTLE, T_SPLIT, mascara)
% Roda a simulacao com o I_psi candidato e calcula o MSE absoluto em tres
% janelas: total, inicial e tardia, com referencia na media dos 2 s
% anteriores a T_SETTLE.
    opc.T_fim   = e.T_sim;
    opc.modo    = 0;
    opc.mascara = mascara;
    opc.x0      = e.x0;
    opc.u_m     = timeseries(e.u_m_in, e.t_in);
    opc.par     = p;
    S = simula_trms(opc);

    psi_sim = interp1(S.t_psi, S.psi, e.t_exp, 'linear', 'extrap');

    win_ref     = (e.t_exp >= T_SETTLE - 2) & (e.t_exp <= T_SETTLE);
    psi_exp_dev = e.psi_exp - mean(e.psi_exp(win_ref));
    psi_sim_dev = psi_sim   - mean(psi_sim(win_ref));

    idx_total   = e.t_exp >= T_SETTLE;
    idx_inicial = (e.t_exp >= T_SETTLE) & (e.t_exp < T_SPLIT);
    idx_tardio  = e.t_exp >= T_SPLIT;

    erro = psi_sim_dev - psi_exp_dev;

    J_total   = mean(erro(idx_total).^2);
    J_inicial = mean(erro(idx_inicial).^2);
    J_tardio  = mean(erro(idx_tardio).^2);
end


function e = carrega_ensaio(caminho, OP_ANG, OP_V, Ts)
%CARREGA_ENSAIO Le o ensaio e identifica o ponto de operacao pela TENSAO de
%   polarizacao registrada (antes de 19 s), e nao so pelo nome do arquivo.
%   Na Coleta 1, o arquivo out_prbs_opn10deg_amp03 foi coletado com a
%   polarizacao de -5 graus (-0,485 V); com isso ele e' tratado como
%   repeticao do ensaio de -5 graus.
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
    e.ang_nome = ang_nome;
    e.u_offset = u_pol;
    e.t_exp    = t_exp;
    e.psi_exp  = psi_exp;
    e.t_in     = t_in;
    e.u_m_in   = u_m_in;
    e.T_sim    = t_in(end);
    evalc('x0_eq = trms_equilibrium(u_pol);');          % equilibrio do ponto (sem o texto impresso)
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
%READ_OUTPUT Tempo e angulo de arfagem do ensaio.
%   Nos chirp da Coleta 1, a variavel 'pitch' guarda a TENSAO aplicada
%   (identica ao simin) e o angulo de arfagem esta em 'yaw'. O caso e'
%   detectado pela coincidencia com o simin e corrigido aqui.
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