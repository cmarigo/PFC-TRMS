function R = sensibilidade_fs_vs(varargin)
% ==============================================================================
% sensibilidade_fs_vs.m
%
% Varredura de sensibilidade dos parametros do atrito estatico suave
% (f_s = nivel estatico, v_s = velocidade de Stribeck) no modelo de atrito
% Coulomb + viscoso + estatico. Cada parametro e' varrido sozinho, com o
% outro (e f_cpsi, f_vpsi, I_psi) fixos.
%
% Objetivo: ver se os DADOS conseguem identificar f_s e v_s (curva de
% custo com minimo bem definido) ou se ficam mal identificados (curva
% chata). E' a varredura univariada que justifica v_s = 0,05 rad/s na
% tab:param_final.
%
% METODO:
%   - ensaio STEP 0 grau;
%   - f_s = linspace(f_cpsi, 3 f_cpsi, 15), com v_s no valor do trms_params
%     (0,05);
%   - v_s = logspace(-2, 0, 15) (0,01 a 1 rad/s), com f_s no valor do
%     trms_params;
%   - f_vpsi, f_cpsi e I_psi nominais; MSE ABSOLUTO a partir de T_SETTLE,
%     com referencia na media dos 2 s anteriores.
%
% A varredura de v_s usa o f_s do trms_params (3,48 f_cpsi). Para outro
% valor: sensibilidade_fs_vs('f_s_vs', 1.1743e-3).
%
% FAIXA DE f_s: se o minimo cair na borda de 3x (o otimo isolado do STEP 0
% e' 3,03x), o script avisa; estenda com
% sensibilidade_fs_vs('fs_max', 6).
%
% MODELO: trms_model_pid_bancada pelo simula_trms (modo 0), guinada TRAVADA
% (mascara [1 0 1 1 1 0]), como na bancada, e x0 no equilibrio do ponto de
% operacao (trms_equilibrium). E' FUNCAO para isolar as variaveis do
% workspace base.
% ==============================================================================

clc; close all;

%% CONFIGURACAO ------------------------------------------------------------------
P          = caminhos_dados();
IN_DIR     = P.pitch;
T_SETTLE   = 20.0;
TS_MODEL   = 0.001;
MASCARA    = [1 0 1 1 1 0]';
FS_MAX     = 3;          % limite superior da varredura de f_s, em f_cpsi

OP_ANG = [-10 -5 0 5 10 15 20];
OP_V   = [-0.884 -0.485 0 0.294 0.541 0.754 1.027];

arquivo = 'out_step_opp0deg_amp03.mat';

f_s_vs = [];
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'fs_max', FS_MAX = varargin{k+1};
        case 'f_s_vs', f_s_vs = varargin{k+1};
        otherwise, error('opcao desconhecida: %s', varargin{k});
    end
end

%% Parametros nominais -------------------------------------------------------------
evalin('base', 'trms_params;');
par.f_vpsi   = evalin('base', 'f_vpsi');
par.f_cpsi   = evalin('base', 'f_cpsi');
par.I_psi    = evalin('base', 'I_psi');
par.CT_m_pos = evalin('base', 'CT_m_pos');
f_s_nom      = evalin('base', 'f_s');
v_s_nom      = evalin('base', 'v_s');
if ~isempty(f_s_vs), f_s_nom = f_s_vs; end
f_cpsi_fixo  = par.f_cpsi;

fprintf('Fixos: f_vpsi=%.5g  f_cpsi=%.5g  I_psi=%.5g\n', par.f_vpsi, par.f_cpsi, par.I_psi);
fprintf('Valores de referencia: f_s=%.5g (%.2fx f_cpsi)  v_s=%.5g\n', f_s_nom, f_s_nom/f_cpsi_fixo, v_s_nom);
fprintf('guinada: %s no modelo\n\n', mat2str(MASCARA.'));

%% Carrega o ensaio ------------------------------------------------------------------
e = carrega_ensaio(acha_dados(IN_DIR, arquivo), OP_ANG, OP_V, TS_MODEL);
fprintf('[Carregado] %s  %+d deg  u_offset=%+.4f V  (%d amostras)\n\n', ...
    e.nome, e.ang, e.u_offset, numel(e.t_exp));

%% Varredura de f_s (v_s fixo) -------------------------------------------------------
% f_s varre de 1x f_cpsi (sem efeito estatico) ate FS_MAX x f_cpsi
fs_faixa = linspace(f_cpsi_fixo, FS_MAX*f_cpsi_fixo, 15);
J_fs = zeros(size(fs_faixa));

fprintf('--- Varredura de f_s (v_s fixo em %.4g) ---\n', v_s_nom);
for k = 1:numel(fs_faixa)
    p = par;  p.f_s = fs_faixa(k);  p.v_s = v_s_nom;
    J_fs(k) = custo(p, e, T_SETTLE, MASCARA);
    fprintf('  f_s = %.4e (%.2fx f_cpsi)  ->  J = %.6e\n', ...
        fs_faixa(k), fs_faixa(k)/f_cpsi_fixo, J_fs(k));
end

%% Varredura de v_s (f_s fixo) -------------------------------------------------------
% v_s varre de 0.01 (so' repouso) a 1.0 rad/s (age em boa parte da oscilacao)
vs_faixa = logspace(-2, 0, 15);
J_vs = zeros(size(vs_faixa));

fprintf('\n--- Varredura de v_s (f_s fixo em %.4g = %.2fx f_cpsi) ---\n', f_s_nom, f_s_nom/f_cpsi_fixo);
for k = 1:numel(vs_faixa)
    p = par;  p.f_s = f_s_nom;  p.v_s = vs_faixa(k);
    J_vs(k) = custo(p, e, T_SETTLE, MASCARA);
    fprintf('  v_s = %.4e  ->  J = %.6e\n', vs_faixa(k), J_vs(k));
end

%% Plots -----------------------------------------------------------------------------
figure('Color', 'w');

subplot(1, 2, 1);
plot(fs_faixa/f_cpsi_fixo, J_fs, 'o-', 'LineWidth', 1.3); hold on;
xline(f_s_nom/f_cpsi_fixo, 'k--');
xlabel('f_s / f_{c\psi}'); ylabel('J (MSE absoluto)');
title(sprintf('Sensibilidade a f_s (v_s = %.3g)', v_s_nom)); grid on;

subplot(1, 2, 2);
semilogx(vs_faixa, J_vs, 'o-', 'LineWidth', 1.3); hold on;
xline(v_s_nom, 'k--');
xlabel('v_s [rad/s]'); ylabel('J (MSE absoluto)');
title(sprintf('Sensibilidade a v_s (f_s = %.2fx f_{c\\psi})', f_s_nom/f_cpsi_fixo)); grid on;

varfs = 100 * (max(J_fs) - min(J_fs)) / min(J_fs);
varvs = 100 * (max(J_vs) - min(J_vs)) / min(J_vs);

[~, kfs] = min(J_fs);
[~, kvs] = min(J_vs);

fprintf('\n--- Resumo ---\n');
fprintf('  f_s: variacao de J = %.1f%%  | minimo em %.4e (%.2fx f_cpsi)%s\n', ...
    varfs, fs_faixa(kfs), fs_faixa(kfs)/f_cpsi_fixo, borda(kfs, numel(fs_faixa)));
fprintf('  v_s: variacao de J = %.1f%%  | minimo em %.4e%s\n', ...
    varvs, vs_faixa(kvs), borda(kvs, numel(vs_faixa)));
fprintf('  J em v_s = 0,05 (interpolado): %.4e  (minimo da varredura: %.4e)\n', ...
    interp1(log(vs_faixa), J_vs, log(0.05)), min(J_vs));

R = struct('fs_faixa', fs_faixa, 'J_fs', J_fs, 'vs_faixa', vs_faixa, 'J_vs', J_vs, ...
           'f_s_nom', f_s_nom, 'v_s_nom', v_s_nom, 'f_cpsi_fixo', f_cpsi_fixo);
arq_res = fullfile(P.resultados, 'sensibilidade_fs_vs.mat');
save(arq_res, 'fs_faixa', 'J_fs', 'vs_faixa', 'J_vs', ...
     'f_s_nom', 'v_s_nom', 'f_cpsi_fixo', 'MASCARA');
fprintf('\nResultados salvos em %s\n', arq_res);
end


%% ====================================================================================
%% FUNCOES LOCAIS
%% ====================================================================================

function s = borda(k, n)
    if k == 1 || k == n
        s = '  [NA BORDA da faixa]';
    else
        s = '';
    end
end


function J = custo(p, e, T_SETTLE, mascara)
% MSE absoluto entre pitch medido e simulado, com o atrito Coulomb +
% estatico. Todos os campos de p vao para o modelo por setVariable.
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

    idx  = e.t_exp >= T_SETTLE;
    erro = psi_sim_dev(idx) - psi_exp_dev(idx);
    J = mean(erro.^2);
end


function e = carrega_ensaio(caminho, OP_ANG, OP_V, Ts)
%CARREGA_ENSAIO Le o ensaio e identifica o ponto de operacao pela TENSAO de
%   polarizacao registrada (antes de 19 s), e nao so pelo nome do arquivo.
    [~, base, ext] = fileparts(caminho);
    [ang_nome, ~] = op_from_name(base, OP_ANG, OP_V);

    plant = load(caminho);
    [t_exp, psi_exp] = read_output(plant, [base ext]);
    [t_in, u_m_in]   = read_input(plant, t_exp, Ts);

    u_pol  = median(u_m_in(t_in < 19));
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
    evalc('x0_eq = trms_equilibrium(u_pol);');
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
