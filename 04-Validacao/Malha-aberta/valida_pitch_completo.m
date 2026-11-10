% ==============================================================================
% valida_pitch_completo.m
%
% Validacao final do eixo de arfagem: conjunto de parametros CONGELADO,
% aplicado sem nenhuma otimizacao a todos os pontos de operacao e sinais.
% Gera a Tabela tab:validacao e os dados das figuras fig:val_nominal,
% fig:val_step, fig:val_prbs e fig:val_chirp.
%
% REGRA DA ETAPA: nada e' otimizado aqui. Um unico vetor de parametros e'
% usado em todos os cenarios.
%
% CONJUNTO CONGELADO
%   f_vpsi, f_cpsi, I_psi, CT_m_pos : nominais do Tastemirov
%   v_s   : 0,05 rad/s
%   f_s   : 3,48 x f_cpsi -- identificacao multiexperimento (degraus em 0,
%           +5 e -5 graus e PRBS em +5 e -5 graus; PRBS 0 grau excluido).
%   Modelo nominal de referencia: f_s = f_cpsi, que anula o termo estatico.
%
% ESTIMACAO x VALIDACAO
%   Estimacao : STEP em 0, +5, -5 e PRBS em +5, -5
%   Validacao : todo o resto (STEP em -10, +10, +15; PRBS em 0, +10, +15;
%               todos os chirp)
%   Repeticao [R]: o arquivo out_prbs_opn10deg_amp03 foi coletado com a
%   polarizacao de -5 graus; o ponto de operacao e' lido da tensao
%   registrada, e o ensaio aparece como repeticao do PRBS de -5 graus.
%
% CHIRP: nos arquivos da Coleta 1, a variavel 'pitch' guarda a tensao e o
%   angulo esta em 'yaw'; o read_output detecta e corrige. A varredura
%   registrada no simin e' LOGARITMICA, de 0,1 a 2,01 Hz (0,1*e^3) em 60 s,
%   a partir de 20 s -- bem abaixo do Nyquist de 5 Hz da aquisicao a 10 Hz.
%
% METRICAS: J relativo (% da variancia do desvio medido), sobre os desvios
%   referenciados a media dos 2 s anteriores a perturbacao, a partir de
%   T_SETTLE. RMSE em graus ao lado. Sempre em par: NOMINAL vs IDENTIFICADO.
%
% MODELO: trms_model_pid_bancada, em malhas abertas (modo 0), pelo simula_trms. A
%   guinada e' TRAVADA no modelo (mascara [1 0 1 1 1 0]), como estava
%   travada mecanicamente na bancada. O x0 de cada ponto de operacao vem do
%   trms_equilibrium(u_offset) (trms_equilibrium.m precisa estar no path).
%
% USO:
%   valida_pitch_completo                          % configuracao da monografia
%   valida_pitch_completo('f_s_razao', 4.1)        % outro f_s (x f_cpsi)
%   valida_pitch_completo('mascara', ones(6,1), 'salvar', false)
%                                                  % diagnostico: guinada livre,
%                                                  % sem sobrescrever os resultados
%
% E' FUNCAO para isolar as variaveis locais do workspace base.
% ==============================================================================

function valida_pitch_completo(varargin)

clc; close all;

%% CONFIGURACAO ------------------------------------------------------------------
P          = caminhos_dados();
IN_DIR     = P.pitch;            % Coleta 1 - Pitch (procura tambem em subpastas)
T_SETTLE   = 20.0;
TS_MODEL   = 0.001;
F_S_RAZAO  = 3.48;
V_S_FIXO   = 0.05;
MASCARA    = [1 0 1 1 1 0]';     % guinada travada, como na bancada
SALVAR     = true;

% Sobrescritas por argumento (nome, valor)
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'f_s_razao', F_S_RAZAO = varargin{k+1};
        case 'mascara',   MASCARA   = varargin{k+1}(:);
        case 'salvar',    SALVAR    = varargin{k+1};
        otherwise, error('opcao desconhecida: %s', varargin{k});
    end
end

% Chirp: so para a metrica restrita ao trecho abaixo da banda.
% Varredura logaritmica conferida no simin dos arquivos (ajuste exato).
CHIRP_F0   = 0.1;           % Hz, em t = T_SETTLE
CHIRP_F1   = 0.1*exp(3);    % Hz (2,01), em t = T_SETTLE + CHIRP_T
CHIRP_T    = 60;            % s, duracao da varredura
BW_PITCH   = 0.35;          % Hz

OP_ANG = [-10 -5 0 5 10 15 20];
OP_V   = [-0.884 -0.485 0 0.294 0.541 0.754 1.027];
OP_TAG = {'opn10deg', 'opn5deg', 'opp0deg', 'opp5deg', 'opp10deg', 'opp15deg', 'opp20deg'};

SINAIS = {'step', 'prbs', 'chirp'};
EST    = {'step_opp0deg', 'step_opp5deg', 'step_opn5deg', 'prbs_opp5deg', 'prbs_opn5deg'};

%% Conjunto congelado ---------------------------------------------------------------
evalin('base', 'trms_params;');
cong.f_vpsi   = evalin('base', 'f_vpsi');
cong.f_cpsi   = evalin('base', 'f_cpsi');
cong.CT_m_pos = evalin('base', 'CT_m_pos');
cong.v_s      = V_S_FIXO;
cong.f_s      = F_S_RAZAO * cong.f_cpsi;

nom     = cong;
nom.f_s = nom.f_cpsi;

fprintf('=== CONJUNTO CONGELADO ===\n');
fprintf('f_vpsi   = %.4e (nominal)\n', cong.f_vpsi);
fprintf('f_cpsi   = %.4e (nominal)\n', cong.f_cpsi);
fprintf('CT_m_pos = %.4e (nominal)\n', cong.CT_m_pos);
fprintf('v_s      = %.4g rad/s\n', cong.v_s);
fprintf('f_s      = %.4e (%.2fx f_cpsi)\n', cong.f_s, F_S_RAZAO);
fprintf('guinada  = %s no modelo\n\n', mat2str(MASCARA.'));

R = struct('sinal', {}, 'ang', {}, 'papel', {}, 'arquivo', {}, ...
           'mse_rel_nom', {}, 'mse_rel_id', {}, 'rmse_nom', {}, 'rmse_id', {}, ...
           'mse_abs_nom', {}, 'mse_abs_id', {}, 'mse_rel_id_bw', {}, 'melhora', {}, ...
           't_corte', {}, 'exc_phi', {}, 't', {}, 'exp_dev', {}, 'nom_dev', {}, 'id_dev', {});

%% Varredura ------------------------------------------------------------------------
for is = 1:numel(SINAIS)
    sinal = SINAIS{is};
    for ip = 1:numel(OP_ANG)
        padrao  = sprintf('out_%s_%s*.mat', sinal, OP_TAG{ip});
        achados = acha_dados(IN_DIR, padrao, false);
        chave   = sprintf('%s_%s', sinal, OP_TAG{ip});
        papel   = 'V';
        if any(strcmp(EST, chave)), papel = 'E'; end

        if isempty(achados)
            fprintf('[ausente] %s\n', padrao);
            continue;
        end
        if numel(achados) > 1
            fprintf('[AVISO] %d arquivos casam com %s -- usando %s\n', ...
                numel(achados), padrao, achados{1});
        end
        [~, nome_arq, ext] = fileparts(achados{1});
        arquivo = [nome_arq ext];
        try
            e = carrega_ensaio(achados{1}, OP_ANG, OP_V, TS_MODEL);
        catch ME
            fprintf('[erro] %s : %s\n', arquivo, ME.message);
            continue;
        end
        if e.ang ~= OP_ANG(ip)
            papel = 'R';      % repeticao de outro ponto (nao entra em E nem em V)
        end

        [ed, sd_nom, t] = traco(nom,  e, T_SETTLE, MASCARA);
        [~,  sd_id, ~, exc_phi] = traco(cong, e, T_SETTLE, MASCARA);
        m_nom = metricas(ed, sd_nom, t, Inf);
        m_id  = metricas(ed, sd_id,  t, Inf);

        mse_rel_bw = NaN;
        t_corte    = NaN;
        if strcmp(sinal, 'chirp')
            t_corte = tempo_corte_chirp(T_SETTLE, CHIRP_T, CHIRP_F0, CHIRP_F1, BW_PITCH);
            if ~isnan(t_corte)
                m_bw = metricas(ed, sd_id, t, t_corte);
                mse_rel_bw = m_bw.mse_rel;
            end
        end

        melhora = 100 * (m_nom.mse_abs - m_id.mse_abs) / m_nom.mse_abs;

        fprintf('%-6s %+3d deg [%s] : J %6.1f%% -> %6.1f%%  (melhora %5.1f%%)\n', ...
            upper(sinal), e.ang, papel, m_nom.mse_rel, m_id.mse_rel, melhora);
        if MASCARA(2) ~= 0 || MASCARA(6) ~= 0
            fprintf('       guinada do modelo (livre): afastamento maximo de %.3f rad (%.1f graus)\n', ...
                exc_phi, rad2deg(exc_phi));
        end

        R(end+1) = struct('sinal', sinal, 'ang', e.ang, 'papel', papel, ... %#ok<AGROW>
            'arquivo', arquivo, ...
            'mse_rel_nom', m_nom.mse_rel, 'mse_rel_id', m_id.mse_rel, ...
            'rmse_nom', m_nom.rmse_deg, 'rmse_id', m_id.rmse_deg, ...
            'mse_abs_nom', m_nom.mse_abs, 'mse_abs_id', m_id.mse_abs, ...
            'mse_rel_id_bw', mse_rel_bw, 'melhora', melhora, ...
            't_corte', t_corte, 'exc_phi', exc_phi, 't', t, 'exp_dev', ed, 'nom_dev', sd_nom, 'id_dev', sd_id);
    end
    fprintf('\n');
end

if isempty(R)
    error('Nenhum ensaio processado -- confira IN_DIR.');
end

%% Tabela principal -----------------------------------------------------------------
fprintf('================================================================================\n');
fprintf(' VALIDACAO DA ARFAGEM -- conjunto congelado (f_s = %.2fx f_cpsi)\n', F_S_RAZAO);
fprintf(' [E] estimacao   [V] validacao   [R] repeticao de um ponto ja ensaiado\n');
fprintf('================================================================================\n');
fprintf(' %-6s %5s %3s | %9s %9s | %9s %9s | %8s\n', ...
    'Sinal', 'ang', 'E/V', 'J nom', 'J id', 'RMSE nom', 'RMSE id', 'melhora');
for k = 1:numel(R)
    r = R(k);
    fprintf(' %-6s %+5d %3s | %8.1f%% %8.1f%% | %8.3f %9.3f | %6.1f%%\n', ...
        upper(r.sinal), r.ang, r.papel, r.mse_rel_nom, r.mse_rel_id, ...
        r.rmse_nom, r.rmse_id, r.melhora);
end
fprintf('--------------------------------------------------------------------------------\n');
fprintf(' RMSE em graus. J = 100 * MSE / var(desvio medido).\n');

fprintf('\n=== Estimacao vs validacao (degraus) ===\n');
for p = {'E', 'V'}
    m = strcmp({R.papel}, p{1}) & strcmp({R.sinal}, 'step');
    if ~any(m), continue; end
    fprintf(' [%s] : melhora media %5.1f%%  (n=%d)\n', p{1}, mean([R(m).melhora]), sum(m));
end

mC = find(strcmp({R.sinal}, 'chirp') & ~isnan([R.mse_rel_id_bw]));
if ~isempty(mC)
    fprintf('\n=== Chirp: janela completa vs abaixo de %.2f Hz (ate t = %.1f s) ===\n', ...
        BW_PITCH, R(mC(1)).t_corte);
    for k = mC
        fprintf(' %+3d deg : %6.1f%% (completo) -> %6.1f%% (abaixo da banda)\n', ...
            R(k).ang, R(k).mse_rel_id, R(k).mse_rel_id_bw);
    end
end

%% Figuras de conferencia ----------------------------------------------------------
for is = 1:numel(SINAIS)
    m = find(strcmp({R.sinal}, SINAIS{is}));
    if isempty(m), continue; end
    figure('Color', 'w', 'Name', upper(SINAIS{is}), 'Position', [60 40 1000 820]);
    nsp = numel(m);
    for j = 1:nsp
        r = R(m(j));
        subplot(ceil(nsp/2), 2, j);
        plot(r.t, r.exp_dev, 'k'); hold on;
        plot(r.t, r.nom_dev, 'Color', [0.55 0.55 0.55]);
        plot(r.t, r.id_dev, 'r');
        grid on;
        title(sprintf('%s %+d deg [%s]  J %.0f%% -> %.0f%%', ...
            upper(r.sinal), r.ang, r.papel, r.mse_rel_nom, r.mse_rel_id), 'FontSize', 9);
        if j == 1, legend({'medido', 'nominal', 'identificado'}, 'FontSize', 7, 'Location', 'best'); end
        if j > nsp-2, xlabel('t [s]'); end
        ylabel('\Delta\psi [rad]');
    end
end

if ~SALVAR
    fprintf('\n(salvar = false: resultados NAO gravados)\n');
    return;
end
arq_res = fullfile(P.resultados, 'validacao_pitch.mat');
save(arq_res, 'R', 'cong', 'nom', 'F_S_RAZAO', 'T_SETTLE', 'MASCARA');
fprintf('\nResultados salvos em %s\n', arq_res);

fid = fopen(fullfile(P.resultados, 'validacao_pitch.csv'), 'w');
fprintf(fid, 'sinal,angulo,papel,J_nom,J_id,rmse_nom_deg,rmse_id_deg,melhora_pct\n');
for k = 1:numel(R)
    r = R(k);
    fprintf(fid, '%s,%d,%s,%.2f,%.2f,%.4f,%.4f,%.2f\n', ...
        r.sinal, r.ang, r.papel, r.mse_rel_nom, r.mse_rel_id, r.rmse_nom, r.rmse_id, r.melhora);
end
fclose(fid);
fprintf('Tabela exportada em validacao_pitch.csv\n');

end


%% ====================================================================================
%% FUNCOES LOCAIS
%% ====================================================================================

function m = metricas(ed, sd, t, t_fim)
%METRICAS J relativo, MSE absoluto (rad^2) e RMSE em graus.
    idx  = t <= t_fim;
    erro = sd(idx) - ed(idx);
    m.mse_abs  = mean(erro.^2);
    m.mse_rel  = 100 * m.mse_abs / var(ed(idx));
    m.rmse_deg = rad2deg(sqrt(m.mse_abs));
end


function [ed, sd, t, exc_phi] = traco(p, e, T_SETTLE, mascara)
%TRACO Desvios medido e simulado (rad), referenciados a media dos 2 s
%   anteriores a perturbacao e recortados a partir de T_SETTLE.
%   exc_phi: maior afastamento da guinada SIMULADA em relacao ao valor no
%   inicio da perturbacao (zero com a guinada travada).
    opc.T_fim   = e.T_sim;
    opc.modo    = 0;
    opc.mascara = mascara;
    opc.x0      = e.x0;
    opc.u_m     = timeseries(e.u_m_in, e.t_in);
    opc.par     = struct('f_vpsi', p.f_vpsi, 'f_cpsi', p.f_cpsi, ...
                         'CT_m_pos', p.CT_m_pos, 'v_s', p.v_s, 'f_s', p.f_s);
    S = simula_trms(opc);

    psi_sim = interp1(S.t_psi, S.psi, e.t_exp, 'linear', 'extrap');

    win_ref = (e.t_exp >= T_SETTLE - 2) & (e.t_exp <= T_SETTLE);
    ed_full = e.psi_exp - mean(e.psi_exp(win_ref));
    sd_full = psi_sim   - mean(psi_sim(win_ref));

    idx = e.t_exp >= T_SETTLE;
    ed  = ed_full(idx);
    sd  = sd_full(idx);
    t   = e.t_exp(idx);

    m_phi   = S.t_phi >= T_SETTLE;
    phi_ref = interp1(S.t_phi, S.phi, T_SETTLE);
    exc_phi = max(abs(S.phi(m_phi) - phi_ref));
end


function t_corte = tempo_corte_chirp(t0, T, f0, f1, bw)
%TEMPO_CORTE_CHIRP Instante em que a varredura LOGARITMICA cruza a banda.
%   f(t) = f0*(f1/f0)^((t - t0)/T), para t0 <= t <= t0 + T.
    if bw <= f0, t_corte = NaN; return; end
    if bw >= f1, t_corte = t0 + T; return; end
    t_corte = t0 + T * log(bw/f0) / log(f1/f0);
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
