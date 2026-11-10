function R = sensibilidade_fvpsi_com_fs(varargin)
% ==============================================================================
% sensibilidade_fvpsi_com_fs.m
%
% Varredura de sensibilidade de f_vpsi no STEP 0 graus.
% Hipotese: o crescimento de f_vpsi no modelo sem atrito estatico nao e'
% uma propriedade de f_vpsi, mas f_vpsi tentando preencher o papel do
% atrito estatico, que o modelo nao tinha.
%
% Duas curvas, sobrepostas para comparacao direta:
%   - "sem f_s" (f_s = f_cpsi, termo estatico anulado);
%   - "com f_s" (f_s = valor identificado ISOLADAMENTE no STEP 0 graus).
% O script detecta se cada curva tem minimo interior ou se o minimo cai
% numa das pontas da faixa.
%
% METODO: STEP 0 grau, f_vpsi = nominal * logspace(-1, 1.5, 20) (de 0,1x a
% ~31,6x), f_cpsi nominal, v_s = 0,05, MSE ABSOLUTO a partir de T_SETTLE com
% referencia na media dos 2 s anteriores.
%
% O f_s "com efeito" e' o otimo ISOLADO do STEP 0 grau, lido da varredura do
% identifica_fs_multiexperimento (resultados/fs_multiexperimento.mat,
% guinada travada): 3,03 f_cpsi. Se o arquivo nao existir ou tiver sido
% gerado com a guinada livre, usa 3,03.
% Para outro valor: sensibilidade_fvpsi_com_fs('f_s_razao', 3.48).
%
% MODELO: trms_model_pid_bancada pelo simula_trms (modo 0), guinada TRAVADA
% (mascara [1 0 1 1 1 0]), como na bancada, e x0 no equilibrio do ponto de
% operacao (trms_equilibrium). E' FUNCAO para isolar as variaveis do
% workspace base.
%
% Imprime tambem a variacao de J da curva "com f_s" abaixo do nominal
% (de 0,1x a 1x), que e' o achatamento citado no texto.
% ==============================================================================

clc; close all;

%% CONFIGURACAO ------------------------------------------------------------------
P          = caminhos_dados();
IN_DIR     = P.pitch;
T_SETTLE   = 20.0;
TS_MODEL   = 0.001;
MASCARA    = [1 0 1 1 1 0]';
FS_RAZAO_FALLBACK = 3.03;      % otimo isolado do STEP 0 (identifica_fs)

OP_ANG = [-10 -5 0 5 10 15 20];
OP_V   = [-0.884 -0.485 0 0.294 0.541 0.754 1.027];

arquivo = 'out_step_opp0deg_amp03.mat';

f_s_razao = [];
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'f_s_razao', f_s_razao = varargin{k+1};
        otherwise, error('opcao desconhecida: %s', varargin{k});
    end
end

%% Parametros nominais e fixos ------------------------------------------------------
evalin('base', 'trms_params;');
par.f_cpsi   = evalin('base', 'f_cpsi');     % nominal, fixo
par.CT_m_pos = evalin('base', 'CT_m_pos');
par.I_psi    = evalin('base', 'I_psi');
par.v_s      = 0.05;                         % fixo
f_vpsi_nom   = evalin('base', 'f_vpsi');

if isempty(f_s_razao)
    f_s_razao = razao_fs_isolada(P, MASCARA, 'STEP opp0deg', FS_RAZAO_FALLBACK);
end
f_s_identificado = f_s_razao * par.f_cpsi;   % otimo isolado do STEP 0 grau
f_s_sem_efeito   = par.f_cpsi;               % f_s = f_cpsi -> termo estatico zera

fprintf('f_cpsi fixo: %.5g\n', par.f_cpsi);
fprintf('v_s fixo:    %.5g\n', par.v_s);
fprintf('f_s (com efeito, isolado no STEP 0deg): %.5g (%.2fx f_cpsi)\n', f_s_identificado, f_s_razao);
fprintf('f_vpsi nominal: %.5g\n', f_vpsi_nom);
fprintf('guinada: %s no modelo\n\n', mat2str(MASCARA.'));

%% Carrega o ensaio ------------------------------------------------------------------
e = carrega_ensaio(acha_dados(IN_DIR, arquivo), OP_ANG, OP_V, TS_MODEL);
fprintf('[Carregado] %s  %+d deg  u_offset=%+.4f V  (%d amostras)\n\n', ...
    e.nome, e.ang, e.u_offset, numel(e.t_exp));

%% Varredura de f_vpsi, com e sem f_s ------------------------------------------------
fvpsi_faixa = f_vpsi_nom * logspace(-1, 1.5, 20);

J_sem_fs = zeros(size(fvpsi_faixa));
J_com_fs = zeros(size(fvpsi_faixa));

fprintf('--- Varredura de f_vpsi SEM f_s (f_s = f_cpsi, termo estatico zerado) ---\n');
for k = 1:numel(fvpsi_faixa)
    p = par;  p.f_vpsi = fvpsi_faixa(k);  p.f_s = f_s_sem_efeito;
    J_sem_fs(k) = custo(p, e, T_SETTLE, MASCARA);
    fprintf('  f_vpsi = %.4e (%.2fx nom)  ->  J = %.6e\n', ...
        fvpsi_faixa(k), fvpsi_faixa(k)/f_vpsi_nom, J_sem_fs(k));
end

fprintf('\n--- Varredura de f_vpsi COM f_s (f_s = %.4g, isolado) ---\n', f_s_identificado);
for k = 1:numel(fvpsi_faixa)
    p = par;  p.f_vpsi = fvpsi_faixa(k);  p.f_s = f_s_identificado;
    J_com_fs(k) = custo(p, e, T_SETTLE, MASCARA);
    fprintf('  f_vpsi = %.4e (%.2fx nom)  ->  J = %.6e\n', ...
        fvpsi_faixa(k), fvpsi_faixa(k)/f_vpsi_nom, J_com_fs(k));
end

%% Plot comparativo -------------------------------------------------------------------
figure('Color', 'w');
semilogx(fvpsi_faixa/f_vpsi_nom, J_sem_fs, 'o-', 'LineWidth', 1.3, ...
    'DisplayName', 'sem f_s (f_s = f_{c\psi})'); hold on;
semilogx(fvpsi_faixa/f_vpsi_nom, J_com_fs, 's-', 'LineWidth', 1.3, ...
    'DisplayName', sprintf('com f_s = %.2fx f_{c\\psi}', f_s_razao));
xline(1, 'k--', 'HandleVisibility', 'off');
xlabel('f_{v\psi} / nominal'); ylabel('J (MSE absoluto)');
title('Sensibilidade a f_{v\psi} no STEP 0 graus -- com e sem atrito estatico');
legend('Location', 'best');
grid on;

%% Deteccao de minimo interior --------------------------------------------------------
[~, k_sem] = min(J_sem_fs);
[~, k_com] = min(J_com_fs);

monotonica_sem = (k_sem == 1) || (k_sem == numel(fvpsi_faixa));
monotonica_com = (k_com == 1) || (k_com == numel(fvpsi_faixa));

fprintf('\n--- Resultado ---\n');
fprintf('SEM f_s: minimo em f_vpsi = %.3fx nominal  (%s)\n', ...
    fvpsi_faixa(k_sem)/f_vpsi_nom, cond_str(monotonica_sem));
fprintf('COM f_s: minimo em f_vpsi = %.3fx nominal  (%s)\n', ...
    fvpsi_faixa(k_com)/f_vpsi_nom, cond_str(monotonica_com));

% Achatamento da curva com f_s abaixo do nominal (0,1x a 1x)
baixo = fvpsi_faixa <= f_vpsi_nom * (1 + 1e-9);
var_baixo_com = 100 * (max(J_com_fs(baixo)) - min(J_com_fs(baixo))) / min(J_com_fs(baixo));
var_baixo_sem = 100 * (max(J_sem_fs(baixo)) - min(J_sem_fs(baixo))) / min(J_sem_fs(baixo));
fprintf('\nVariacao de J entre 0,1x e 1x o nominal: sem f_s %.1f%% | com f_s %.1f%%\n', ...
    var_baixo_sem, var_baixo_com);
fprintf('J no nominal: sem f_s %.4e | com f_s %.4e\n', ...
    interp1(fvpsi_faixa, J_sem_fs, f_vpsi_nom), interp1(fvpsi_faixa, J_com_fs, f_vpsi_nom));

R = struct('fvpsi_faixa', fvpsi_faixa, 'J_sem_fs', J_sem_fs, 'J_com_fs', J_com_fs, ...
           'f_vpsi_nom', f_vpsi_nom, 'f_s_identificado', f_s_identificado, 'f_s_razao', f_s_razao);
arq_res = fullfile(P.resultados, 'sensibilidade_fvpsi_com_fs.mat');
save(arq_res, 'fvpsi_faixa', 'J_sem_fs', 'J_com_fs', 'f_vpsi_nom', ...
     'f_s_identificado', 'f_s_razao', 'MASCARA');
fprintf('\nResultados salvos em %s\n', arq_res);
end


%% ====================================================================================
%% FUNCOES LOCAIS
%% ====================================================================================

function s = cond_str(monotonica)
    if monotonica
        s = 'minimo na borda da faixa, sem minimo interior';
    else
        s = 'MINIMO INTERIOR encontrado';
    end
end


function r = razao_fs_isolada(P, mascara, rotulo, fallback)
%RAZAO_FS_ISOLADA Otimo isolado de f_s/f_cpsi de um ensaio, lido da grade
%   do identifica_fs_multiexperimento (o mesmo valor da tab:fs_isolado).
    r   = fallback;
    arq = fullfile(P.resultados, 'fs_multiexperimento.mat');
    if exist(arq, 'file') ~= 2
        fprintf('[AVISO] %s nao encontrado -- usando f_s/f_cpsi = %.2f.\n', arq, fallback);
        return;
    end
    S = load(arq);
    if isfield(S, 'p') && isfield(S.p, 'mascara') && ~isequal(S.p.mascara(:), mascara(:))
        fprintf(['[AVISO] %s foi gerado com mascara %s (nao a guinada travada) -- ' ...
                 'usando f_s/f_cpsi = %.2f.\n'], arq, mat2str(S.p.mascara(:).'), fallback);
        return;
    end
    k = find(strcmp(S.rotulos, rotulo), 1);
    if isempty(k)
        fprintf('[AVISO] "%s" ausente em %s -- usando f_s/f_cpsi = %.2f.\n', rotulo, arq, fallback);
        return;
    end
    [~, im] = min(S.Jrel(k, :));
    r = S.razoes(im);
    fprintf('f_s/f_cpsi isolado de "%s" lido de %s: %.2f\n', rotulo, arq, r);
end


function J = custo(p, e, T_SETTLE, mascara)
% MSE absoluto entre pitch medido e simulado, a partir de T_SETTLE.
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
