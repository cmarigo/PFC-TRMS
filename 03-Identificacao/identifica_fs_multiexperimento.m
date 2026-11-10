% ==============================================================================
% identifica_fs_multiexperimento.m
%
% Determina um valor UNICO de f_s a partir do custo AGREGADO de varios
% ensaios, em vez da media aritmetica dos otimos individuais.
%
% METRICA AGREGADA: media do MSE RELATIVO (normalizado pela variancia do
% desvio medido de cada ensaio).
%
% ESTRATEGIA: varredura em grade sobre f_s/f_cpsi (21 pontos log-espacados
% de 1 a 16), simulando TODOS os ensaios em CADA ponto. O agregado de
% qualquer subconjunto sai sem novas simulacoes, e a curva de custo de cada
% ensaio e' a figura da monografia (fig:custo_fs).
%
% CONJUNTO ADOTADO: degraus em 0, +5 e -5 graus e PRBS em +5 e -5 graus. O
% PRBS em 0 grau e' simulado e reportado, mas fica FORA do agregado adotado
% (baixa razao sinal-ruido: excursao de +-3 graus, na escala da quantizacao
% do encoder). Resultado com a guinada travada: 3,48 x f_cpsi.
%
% REFINO DO MINIMO: interpolacao pchip da curva agregada entre o ponto de
% minimo da grade e seus dois vizinhos.
%
% MODELO: trms_model_pid_bancada em malhas abertas (modo 0), pelo simula_trms, com
% a guinada TRAVADA (mascara [1 0 1 1 1 0]), como na bancada -- o mesmo
% arranjo do valida_pitch_completo.
%
% PRE-REQUISITOS (InitFcn do modelo VAZIO):
%   - trms_params e' carregado aqui no workspace base;
%   - o x0 de cada ensaio e' calculado por trms_equilibrium(u_offset);
%   - trms_equilibrium.m precisa estar no path.
%
% SAIDA EM DISCO: fs_multiexperimento.mat, com a grade completa de custos.
% A varredura tem 126 simulacoes.
% ==============================================================================

function identifica_fs_multiexperimento(varargin)
%   identifica_fs_multiexperimento                       % guinada travada
%   identifica_fs_multiexperimento('mascara', ones(6,1)) % diagnostico: guinada livre

clc; close all;

%% CONFIGURACAO ------------------------------------------------------------------
P          = caminhos_dados();
IN_DIR     = P.pitch;            % Coleta 1 - Pitch (procura tambem em subpastas)
T_SETTLE   = 20.0;
TS_MODEL   = 0.001;
V_S_FIXO   = 0.05;

RAZAO_MIN  = 1.0;     % f_s = f_cpsi -> sem efeito estatico (limite fisico)
RAZAO_MAX  = 16.0;
N_GRADE    = 21;      % pontos da grade (log-espacados)

% Mascara de estados [psi phi om_m om_t dpsi dphi]: guinada travada, como
% na bancada.
MASCARA    = [1 0 1 1 1 0]';
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'mascara', MASCARA = varargin{k+1}(:);
        otherwise, error('opcao desconhecida: %s', varargin{k});
    end
end

ENSAIOS = struct( ...
    'sinal', { 'step',     'step',     'step',     'prbs',     'prbs',     'prbs'     }, ...
    'op',    { 'opp0deg',  'opp5deg',  'opn5deg',  'opp0deg',  'opp5deg',  'opn5deg'  } );

OP_ANG = [-10 -5 0 5 10 15 20];
OP_V   = [-0.884 -0.485 0 0.294 0.541 0.754 1.027];

%% Nominais (workspace base) ---------------------------------------------------------
evalin('base', 'trms_params;');
p.f_vpsi   = evalin('base', 'f_vpsi');
p.f_cpsi   = evalin('base', 'f_cpsi');
p.CT_m_pos = evalin('base', 'CT_m_pos');
p.v_s      = V_S_FIXO;
p.mascara  = MASCARA;

razoes = logspace(log10(RAZAO_MIN), log10(RAZAO_MAX), N_GRADE);

fprintf('Grade: %d pontos de %.2fx a %.2fx f_cpsi (f_cpsi = %.4e)\n', ...
    N_GRADE, RAZAO_MIN, RAZAO_MAX, p.f_cpsi);

%% Carrega ensaios ------------------------------------------------------------------
E = {};
rotulos = {};
tipos   = {};
for k = 1:numel(ENSAIOS)
    padrao  = sprintf('out_%s_%s*.mat', ENSAIOS(k).sinal, ENSAIOS(k).op);
    achados = acha_dados(IN_DIR, padrao, false);
    if isempty(achados)
        fprintf('[ausente] %s\n', padrao);
        continue;
    end
    E{end+1}       = carrega_ensaio(achados{1}, OP_ANG, OP_V, TS_MODEL);         %#ok<AGROW>
    rotulos{end+1} = sprintf('%s %s', upper(ENSAIOS(k).sinal), ENSAIOS(k).op);        %#ok<AGROW>
    tipos{end+1}   = upper(ENSAIOS(k).sinal);                                         %#ok<AGROW>
end
nE = numel(E);
if nE == 0
    error('Nenhum ensaio carregado -- confira IN_DIR e os nomes.');
end
fprintf('%d ensaios carregados. Total de simulacoes: %d\n\n', nE, nE * N_GRADE);

%% Varredura em grade ---------------------------------------------------------------
Jrel = nan(nE, N_GRADE);
for j = 1:N_GRADE
    p.f_s = razoes(j) * p.f_cpsi;
    for i = 1:nE
        Jrel(i, j) = custo_relativo(p, E{i}, T_SETTLE);
    end
    fprintf('  %2d/%2d  razao %5.2fx  | media STEP %6.1f%%  media PRBS %6.1f%%\n', ...
        j, N_GRADE, razoes(j), ...
        mean(Jrel(strcmp(tipos, 'STEP'), j)), ...
        mean(Jrel(strcmp(tipos, 'PRBS'), j)));
end
fprintf('\n');

%% Otimos individuais ----------------------------------------------------------------
fprintf('=== Otimos individuais (na grade) ===\n');
for i = 1:nE
    [jm, im] = min(Jrel(i, :));
    fprintf(' %-14s otimo %5.2fx  (MSE rel %5.1f%%)  | em 1,0x: %5.1f%%\n', ...
        rotulos{i}, razoes(im), jm, Jrel(i, 1));
end

%% Agregados --------------------------------------------------------------------------
mS  = strcmp(tipos, 'STEP');
mP  = strcmp(tipos, 'PRBS');
mP0 = mP & contains(rotulos, 'opp0deg');

agg = struct('nome', {}, 'mask', {}, 'razao', {}, 'custo', {});
agg(end+1) = struct('nome', 'so STEP',          'mask', mS,         'razao', NaN, 'custo', NaN);
agg(end+1) = struct('nome', 'so PRBS',          'mask', mP,         'razao', NaN, 'custo', NaN);
agg(end+1) = struct('nome', 'STEP+PRBS',        'mask', true(1,nE), 'razao', NaN, 'custo', NaN);
agg(end+1) = struct('nome', 'STEP+PRBS sem P0', 'mask', ~mP0,       'razao', NaN, 'custo', NaN);

fprintf('\n=== Agregados (media do MSE relativo) ===\n');
for a = 1:numel(agg)
    if ~any(agg(a).mask), continue; end
    [agg(a).razao, agg(a).custo] = minimo_refinado(razoes, mean(Jrel(agg(a).mask, :), 1));
    fprintf(' %-17s : f_s otimo = %5.2fx f_cpsi   (custo agregado %5.1f%%)\n', ...
        agg(a).nome, agg(a).razao, agg(a).custo);
end

%% Preco do compromisso (conjunto adotado) ----------------------------------------------
iAd   = find(strcmp({agg.nome}, 'STEP+PRBS sem P0'), 1);
r_ad  = agg(iAd).razao;

fprintf('\n=== Preco do compromisso (f_s adotado = %.2fx) ===\n', r_ad);
fprintf(' %-14s %10s %10s %10s\n', 'Ensaio', 'otimo ind', 'com adotado', 'perda');
for i = 1:nE
    [jm, im] = min(Jrel(i, :));
    ju = interp1(razoes, Jrel(i,:), r_ad, 'pchip');
    fprintf(' %-14s %8.1f%% %9.1f%% %9.1f pp   (otimo em %.2fx)\n', ...
        rotulos{i}, jm, ju, ju - jm, razoes(im));
end

%% Figura de conferencia ---------------------------------------------------------------
figure('Color', 'w', 'Position', [80 80 900 560]);
cores = lines(nE);
for i = 1:nE
    estilo = '-';
    if strcmp(tipos{i}, 'PRBS'), estilo = '--'; end
    semilogx(razoes, Jrel(i, :), estilo, 'Color', cores(i,:), 'LineWidth', 1.5); hold on;
end
xline(r_ad, 'k-', 'LineWidth', 1.5);
xlabel('f_s / f_{c\psi}');  ylabel('MSE relativo [%]');
legend([rotulos, {'adotado (sem PRBS 0)'}], 'Location', 'northwest', 'FontSize', 8);
grid on;

arq_res = fullfile(P.resultados, 'fs_multiexperimento.mat');
save(arq_res, 'razoes', 'Jrel', 'rotulos', 'tipos', 'agg', 'p');
fprintf('\nSalvo em %s\n', arq_res);

end


%% ====================================================================================
%% FUNCOES LOCAIS
%% ====================================================================================

function [r_min, c_min] = minimo_refinado(razoes, Jag)
%MINIMO_REFINADO Minimo da grade refinado por pchip entre os vizinhos.
    [~, im] = min(Jag);
    lo = max(1, im-1);  hi = min(numel(razoes), im+1);
    rr = linspace(razoes(lo), razoes(hi), 200);
    JJ = interp1(razoes, Jag, rr, 'pchip');
    [c_min, ic] = min(JJ);
    r_min = rr(ic);
end


function Jrel = custo_relativo(p, e, T_SETTLE)
    opc = struct();
    opc.T_fim   = e.T_sim;
    opc.modo    = 0;
    opc.mascara = p.mascara;
    opc.x0      = e.x0;
    opc.u_m     = timeseries(e.u_m_in, e.t_in);
    opc.par     = struct('f_vpsi', p.f_vpsi, 'f_cpsi', p.f_cpsi, ...
                         'CT_m_pos', p.CT_m_pos, 'v_s', p.v_s, 'f_s', p.f_s);
    S = simula_trms(opc);

    psi_sim = interp1(S.t_psi, S.psi, e.t_exp, 'linear', 'extrap');

    win_ref = (e.t_exp >= T_SETTLE - 2) & (e.t_exp <= T_SETTLE);
    ed = e.psi_exp - mean(e.psi_exp(win_ref));
    sd = psi_sim   - mean(psi_sim(win_ref));

    idx  = e.t_exp >= T_SETTLE;
    erro = sd(idx) - ed(idx);
    Jrel = 100 * mean(erro.^2) / var(ed(idx));
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
