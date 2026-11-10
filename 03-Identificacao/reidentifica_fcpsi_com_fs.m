function R = reidentifica_fcpsi_com_fs(varargin)
% ==============================================================================
% reidentifica_fcpsi_com_fs.m
%
% Reidentifica f_cpsi COM f_s ativo e compara com a identificacao sem o
% termo estatico (em que f_cpsi dependia do sinal: PRBS ~1,0x e degraus
% ~1,8-1,9x o nominal).
%
% Hipotese: o excesso de f_cpsi nos degraus era o Coulomb absorvendo o
% atrito ESTATICO ausente do modelo. Se for verdade, com f_s presente o
% f_cpsi identificado deve (a) voltar para perto do nominal nos degraus e
% (b) ficar consistente entre PRBS e degrau.
%
% ESTRUTURA DO TESTE (dois cenarios de modelo, mesmos dados):
%   (A) SEM f_s : f_s amarrado a f_cpsi (f_s = f_cpsi -> sem efeito
%                 estatico), otimiza f_cpsi.
%   (B) COM f_s : f_s FIXO no otimo isolado DAQUELE ensaio
%                       (tab:fs_isolado), otimiza f_cpsi sozinho.
% Em ambos: f_vpsi nominal, v_s = 0,05. Restricao de Stribeck f_cpsi <= f_s
% em (B) por penalizacao suave; o otimo na fronteira e' marcado com '*'.
%
% CT_m_pos: a escala do empuxo positivo e' configuravel. 1,00 = nominal
% (valores do texto em "Reidentificacao do coeficiente de Coulomb"); 0,91 =
% valor da curva de equilibrio (segundo paragrafo de sub:ct_m). Por padrao
% roda as duas em sequencia e compara o ajuste no fim.
%
% METODO: seis ensaios (PRBS e degrau em 0, +5 e -5 graus, conjunto E),
% fminsearch em log(f_cpsi) a partir do nominal com TolX 1e-6 e TolFun 1e-8,
% referencias J nominal e J so' com f_s, MSE ABSOLUTO a partir de T_SETTLE
% com referencia na media dos 2 s anteriores.
%   - simulacao: trms_model_pid_bancada pelo simula_trms (modo 0), guinada
%     TRAVADA (mascara [1 0 1 1 1 0]), x0 no equilibrio do ponto,
%     recalculado com o CT_m_pos escalado;
%   - f_s de cada ensaio: o otimo isolado da grade do
%     identifica_fs_multiexperimento (resultados/fs_multiexperimento.mat,
%     guinada travada), o mesmo da tab:fs_isolado;
%   - a leitura e' pela tabela por ensaio; o script imprime tambem a
%     separacao STEP-PRBS e a dispersao de cada grupo em torno do nominal;
%   - o .mat de cada escala guarda as series da janela de custo (t,
%     exp_dev, sim_fs_so, sim_B), das figuras ct_m_custo e ct_m_degrau.
%
% USO
%   R = reidentifica_fcpsi_com_fs;                      % CT 1,00 e 0,91
%   R = reidentifica_fcpsi_com_fs('ct_escala', 1.00);   % so o nominal
%   R = reidentifica_fcpsi_com_fs('razoes_fs', [1.32 3.03 3.03 12.13 1.00 5.28]);
% ==============================================================================

clc; close all;

%% CONFIGURACAO ------------------------------------------------------------------
P          = caminhos_dados();
IN_DIR     = P.pitch;
T_SETTLE   = 20.0;
TS_MODEL   = 0.001;
MASCARA    = [1 0 1 1 1 0]';
CT_ESCALAS = [1.00 0.91];

OP_ANG = [-10 -5 0 5 10 15 20];
OP_V   = [-0.884 -0.485 0 0.294 0.541 0.754 1.027];

cenarios = struct( ...
    'nome',   { 'PRBS  0', 'STEP  0', 'PRBS +5', 'STEP +5', 'PRBS -5', 'STEP -5' }, ...
    'tipo',   { 'PRBS',    'STEP',    'PRBS',    'STEP',    'PRBS',    'STEP'    }, ...
    'sinal',  { 'prbs',    'step',    'prbs',    'step',    'prbs',    'step'    }, ...
    'op',     { 'opp0deg', 'opp0deg', 'opp5deg', 'opp5deg', 'opn5deg', 'opn5deg' } );

% Fallback: otimos isolados f_s/f_cpsi (identifica_fs, guinada travada),
% na ORDEM de 'cenarios'.
RAZOES_FS_FALLBACK = [1.32, 3.03, 3.03, 12.13, 1.00, 5.28];

razoes_fs = [];
for k = 1:2:numel(varargin)
    switch lower(varargin{k})
        case 'ct_escala', CT_ESCALAS = varargin{k+1};
        case 'razoes_fs', razoes_fs  = varargin{k+1}(:).';
        otherwise, error('opcao desconhecida: %s', varargin{k});
    end
end

%% Parametros nominais -------------------------------------------------------------
evalin('base', 'trms_params;');
f_vpsi_fixo = evalin('base', 'f_vpsi');   % nominal, fixo (nao identificavel)
f_cpsi_nom  = evalin('base', 'f_cpsi');   % referencia nominal do Tastemirov
CT_m_nom    = evalin('base', 'CT_m_pos');
I_psi_nom   = evalin('base', 'I_psi');
v_s_fixo    = 0.05;                       % fixo, do minimo da varredura univariada

if isempty(razoes_fs)
    razoes_fs = carrega_razoes_fs(P, MASCARA, cenarios, RAZOES_FS_FALLBACK);
end

fprintf('Fixos: f_vpsi=%.5g (nominal)   v_s=%.5g\n', f_vpsi_fixo, v_s_fixo);
fprintf('Referencia: f_cpsi nominal = %.4e\n', f_cpsi_nom);
fprintf('guinada: %s no modelo\n\n', mat2str(MASCARA.'));

%% Carrega os ensaios (uma vez) ------------------------------------------------------
E = cell(1, numel(cenarios));
for c = 1:numel(cenarios)
    padrao  = sprintf('out_%s_%s*.mat', cenarios(c).sinal, cenarios(c).op);
    achados = acha_dados(IN_DIR, padrao, false);
    if isempty(achados)
        fprintf('[ausente] %s\n', padrao);
        continue;
    end
    if numel(achados) > 1
        fprintf('[AVISO] %d arquivos para %s; usando %s\n', numel(achados), padrao, achados{1});
    end
    E{c} = carrega_ensaio(achados{1}, OP_ANG, OP_V, TS_MODEL);
    fprintf('[Carregado] %-8s %s  (u_offset = %+.3f V)\n', cenarios(c).nome, E{c}.nome, E{c}.u_offset);
end
fprintf('\n');

opts = optimset('Display', 'off', 'TolX', 1e-6, 'TolFun', 1e-8);

R = struct('ct_escala', {}, 'resultados', {}, 'arquivo', {});

for s = 1:numel(CT_ESCALAS)
    CT_M_POS_ESCALA = CT_ESCALAS(s);

    % Parametros fixos agrupados, injetados em toda simulacao via setVariable
    fixos.f_vpsi   = f_vpsi_fixo;
    fixos.v_s      = v_s_fixo;
    fixos.CT_m_pos = CT_M_POS_ESCALA * CT_m_nom;
    fixos.I_psi    = I_psi_nom;

    fprintf('##########################################################################\n');
    fprintf(' CT_m_pos = %.5g (%.2fx nominal %.5g)\n', fixos.CT_m_pos, CT_M_POS_ESCALA, CT_m_nom);
    fprintf('##########################################################################\n');

    resultados = struct('nome', {}, 'tipo', {}, 'razao_fs', {}, ...
                        'fc_A', {}, 'rel_A', {}, 'J_A', {}, ...
                        'fc_B', {}, 'rel_B', {}, 'J_B', {}, ...
                        'J_nom_puro', {}, 'J_fs_so', {}, 'fronteira', {}, ...
                        't', {}, 'exp_dev', {}, 'sim_fs_so', {}, 'sim_B', {});

    %% Loop de cenarios ------------------------------------------------------------
    for c = 1:numel(cenarios)
        if isempty(E{c}), continue; end
        e = E{c};
        fprintf('--- %s (%s) ---\n', cenarios(c).nome, e.nome);

        if abs(CT_M_POS_ESCALA - 1) > 1e-12
            e.x0 = equilibrio_com('CT_m_pos', fixos.CT_m_pos, e.u_offset, e.x0);
        end

        f_s_cen = razoes_fs(c) * f_cpsi_nom;   % f_s isolado (absoluto) do ensaio

        % --- (A) SEM f_s: f_s amarrado a f_cpsi (sem efeito estatico) -----------
        fA = @(q) custo(fixos, exp(q), exp(q), e, T_SETTLE, MASCARA);
        qA = fminsearch(fA, log(f_cpsi_nom), opts);
        fc_A = exp(qA);
        J_A  = fA(qA);

        % --- (B) COM f_s: f_s fixo no valor isolado, otimiza f_cpsi --------------
        fB = @(q) custo_restrito(fixos, exp(q), f_s_cen, e, T_SETTLE, MASCARA);
        qB = fminsearch(fB, log(f_cpsi_nom), opts);
        fc_B = exp(qB);
        [J_B, s_B] = custo(fixos, min(fc_B, f_s_cen), f_s_cen, e, T_SETTLE, MASCARA);
        na_fronteira = (fc_B / f_s_cen) > 0.98;

        % --- Referencias de custo (sem otimizar f_cpsi) ---------------------------
        J_nom_puro = custo(fixos, f_cpsi_nom, f_cpsi_nom, e, T_SETTLE, MASCARA);
        [J_fs_so, s_fs] = custo(fixos, min(f_cpsi_nom, f_s_cen), f_s_cen, e, T_SETTLE, MASCARA);

        fprintf('  f_s fixo = %.4e (%.2fx f_cpsi nominal)\n', f_s_cen, razoes_fs(c));
        fprintf('  (A) sem f_s : f_cpsi = %.4e (%.3fx nominal)\n', fc_A, fc_A/f_cpsi_nom);
        fprintf('  (B) com f_s : f_cpsi = %.4e (%.3fx nominal)%s\n', ...
            fc_B, fc_B/f_cpsi_nom, ternario(na_fronteira, '   [NA FRONTEIRA f_cpsi=f_s]', ''));
        fprintf('  Ganho marginal de reotimizar f_cpsi sobre f_s-so: %.1f%%\n\n', ...
            100*(J_fs_so - J_B)/J_fs_so);

        resultados(end+1) = struct('nome', cenarios(c).nome, 'tipo', cenarios(c).tipo, ...   %#ok<AGROW>
            'razao_fs', razoes_fs(c), ...
            'fc_A', fc_A, 'rel_A', fc_A/f_cpsi_nom, 'J_A', J_A, ...
            'fc_B', fc_B, 'rel_B', fc_B/f_cpsi_nom, 'J_B', J_B, ...
            'J_nom_puro', J_nom_puro, 'J_fs_so', J_fs_so, 'fronteira', na_fronteira, ...
            't', s_fs.t, 'exp_dev', s_fs.exp_dev, 'sim_fs_so', s_fs.sim_dev, 'sim_B', s_B.sim_dev);
    end

    if isempty(resultados)
        error('Nenhum cenario processado -- confira IN_DIR e os nomes de arquivo.');
    end

    %% Tabela consolidada -----------------------------------------------------------
    fprintf('==========================================================================\n');
    fprintf(' f_cpsi identificado: modelo SEM f_s (A) vs modelo COM f_s fixo (B)\n');
    fprintf(' f_vpsi=%.4e (nominal), v_s=%.4g, f_cpsi nominal=%.4e\n', ...
        f_vpsi_fixo, v_s_fixo, f_cpsi_nom);
    fprintf(' CT_m_pos = %.2fx nominal\n', CT_M_POS_ESCALA);
    fprintf('==========================================================================\n');
    fprintf(' %-9s %10s %12s %12s %11s\n', 'Cenario', 'f_s/f_c', '(A) f_c/nom', '(B) f_c/nom', 'MSE B/A');
    for c = 1:numel(resultados)
        r = resultados(c);
        marca = ternario(r.fronteira, ' *', '');
        fprintf(' %-9s %10.2f %12.3f %12.3f%-2s %10.3f\n', ...
            r.nome, r.razao_fs, r.rel_A, r.rel_B, marca, r.J_B/r.J_A);
    end
    fprintf('--------------------------------------------------------------------------\n');
    if any([resultados.fronteira])
        fprintf(' * otimo na fronteira f_cpsi = f_s (restricao de Stribeck ativa)\n');
    end

    %% Dependencia de sinal do f_cpsi -----------------------------------------------
    iP = strcmp({resultados.tipo}, 'PRBS');
    iS = strcmp({resultados.tipo}, 'STEP');
    relA = [resultados.rel_A];
    relB = [resultados.rel_B];

    fprintf('\n=== Dependencia de sinal do f_cpsi ===\n');
    imprime_grupo('(A) sem f_s ', relA, iP, iS);
    imprime_grupo('(B) com f_s ', relB, iP, iS);
    if any(iP) && any(iS)
        gapA = abs(mean(relA(iS)) - mean(relA(iP)));
        gapB = abs(mean(relB(iS)) - mean(relB(iP)));
        fprintf('Separacao entre as medias STEP e PRBS: %.3f (sem f_s) -> %.3f (com f_s)\n', gapA, gapB);
    end
    fprintf('Dispersao em torno do nominal, media de |log(f_c/nom)|:\n');
    fprintf('  (A) sem f_s: PRBS %.3f | STEP %.3f\n', disp_log(relA(iP)), disp_log(relA(iS)));
    fprintf('  (B) com f_s: PRBS %.3f | STEP %.3f\n', disp_log(relB(iP)), disp_log(relB(iS)));

    %% Ganho marginal de reotimizar f_cpsi ------------------------------------------
    fprintf('\n=== Ganho de reotimizar f_cpsi ===\n');
    fprintf(' %-9s %12s %12s %12s\n', 'Cenario', 'J nominal', 'J f_s so', 'J f_s+f_c');
    for c = 1:numel(resultados)
        r = resultados(c);
        fprintf(' %-9s %12.4e %12.4e %12.4e   (ganho extra %.1f%%)\n', ...
            r.nome, r.J_nom_puro, r.J_fs_so, r.J_B, 100*(r.J_fs_so - r.J_B)/r.J_fs_so);
    end
    ganhos = 100*([resultados.J_fs_so] - [resultados.J_B]) ./ [resultados.J_fs_so];
    fprintf('--------------------------------------------------------------------------\n');
    fprintf('Ganho extra medio de reotimizar f_cpsi apos f_s: todos %.1f%% | degraus %.1f%%\n', ...
        mean(ganhos), mean(ganhos(iS)));

    %% Grafico ------------------------------------------------------------------------
    figure('Color', 'w');
    bar([relA(:), relB(:)]);
    set(gca, 'XTickLabel', {resultados.nome});
    ylabel('f_{c\psi} identificado / nominal');
    legend({'sem f_s', 'com f_s fixo'}, 'Location', 'best');
    title(sprintf('Dependencia de sinal do f_{c\\psi} -- CT_{m,pos} = %.2fx nominal', ...
        CT_M_POS_ESCALA));
    yline(1, 'k--', 'HandleVisibility', 'off');
    grid on;

    arq_saida = fullfile(P.resultados, sprintf('fcpsi_com_fs_ct%03d.mat', round(100*CT_M_POS_ESCALA)));
    save(arq_saida, 'resultados', 'f_cpsi_nom', 'fixos', 'razoes_fs', 'CT_M_POS_ESCALA', 'MASCARA');
    fprintf('\nResultados salvos em %s\n\n', arq_saida);

    R(end+1) = struct('ct_escala', CT_M_POS_ESCALA, 'resultados', resultados, ...  %#ok<AGROW>
                      'arquivo', arq_saida);
end

%% Comparacao entre escalas de CT_m_pos (segundo paragrafo de sub:ct_m) -------------
if numel(R) > 1
    i1 = find(abs([R.ct_escala] - 1) < 1e-12, 1);
    if isempty(i1), i1 = 1; end
    fprintf('==========================================================================\n');
    fprintf(' Efeito de CT_m_pos no ajuste dinamico (MSE absoluto)\n');
    fprintf('==========================================================================\n');
    for s = 1:numel(R)
        if s == i1, continue; end
        a = R(i1).resultados;  b = R(s).resultados;
        fprintf(' %-9s %13s %13s | %13s %13s\n', 'Cenario', ...
            sprintf('J f_s so %.2f', R(i1).ct_escala), sprintf('J f_s so %.2f', R(s).ct_escala), ...
            sprintf('J melhor %.2f', R(i1).ct_escala), sprintf('J melhor %.2f', R(s).ct_escala));
        piora_so = 0;  piora_ot = 0;  n_afeta = 0;
        for c = 1:numel(a)
            k = find(strcmp({b.nome}, a(c).nome), 1);
            if isempty(k), continue; end
            fprintf(' %-9s %13.4e %13.4e | %13.4e %13.4e\n', a(c).nome, ...
                a(c).J_fs_so, b(k).J_fs_so, a(c).J_B, b(k).J_B);
            if isempty(strfind(a(c).nome, '-'))     % offset >= 0: CT_m_pos atua
                n_afeta  = n_afeta + 1;
                piora_so = piora_so + (b(k).J_fs_so > a(c).J_fs_so);
                piora_ot = piora_ot + (b(k).J_B > a(c).J_B);
            end
        end
        fprintf(' Nos %d ensaios com offset >= 0, %.2fx piora:\n', n_afeta, R(s).ct_escala);
        fprintf('   com f_cpsi nominal + f_s: %d de %d | com f_cpsi reotimizado: %d de %d\n', ...
            piora_so, n_afeta, piora_ot, n_afeta);
    end
end
end


%% ====================================================================================
%% FUNCOES LOCAIS
%% ====================================================================================

function razoes = carrega_razoes_fs(P, mascara, cenarios, fallback)
%CARREGA_RAZOES_FS Otimos isolados de f_s/f_cpsi da grade do
%   identifica_fs_multiexperimento (os mesmos da tab:fs_isolado).
    razoes = fallback(:)';
    arq = fullfile(P.resultados, 'fs_multiexperimento.mat');
    if exist(arq, 'file') ~= 2
        fprintf('[AVISO] %s nao encontrado -- usando razoes de fallback do script.\n', arq);
        return;
    end
    S = load(arq);
    if isfield(S, 'p') && isfield(S.p, 'mascara') && ~isequal(S.p.mascara(:), mascara(:))
        fprintf(['[AVISO] %s foi gerado com mascara %s (nao a guinada travada) -- ' ...
                 'usando fallback.\n'], arq, mat2str(S.p.mascara(:).'));
        return;
    end
    for c = 1:numel(cenarios)
        rot = sprintf('%s %s', upper(cenarios(c).sinal), cenarios(c).op);
        k = find(strcmp(S.rotulos, rot), 1);
        if ~isempty(k)
            [~, im] = min(S.Jrel(k, :));
            razoes(c) = S.razoes(im);
        else
            fprintf('[AVISO] ensaio "%s" ausente em %s -- fallback %.2f.\n', rot, arq, razoes(c));
        end
    end
    fprintf('Razoes f_s/f_cpsi carregadas de %s: %s\n', arq, mat2str(round(100*razoes)/100));
end


function x0 = equilibrio_com(nome, valor, u, x0_atual)
%EQUILIBRIO_COM Equilibrio recalculado com um parametro alterado no base.
%   Avisa se o trms_equilibrium nao usar o parametro do base num ponto em
%   que ele deveria atuar (polarizacao positiva).
    antigo = evalin('base', nome);
    assignin('base', nome, valor);
    limpa = onCleanup(@() assignin('base', nome, antigo));
    evalc('x0_eq = trms_equilibrium(u);');
    x0 = x0_eq;
    if u > 0.05 && max(abs(x0(:) - x0_atual(:))) < 1e-12
        fprintf('   [AVISO] trms_equilibrium nao usou o %s do base; x0 do nominal.\n', nome);
    end
end


% Custo com restricao suave f_cpsi <= f_s (modelo de Stribeck).
% Simula com f_cpsi clipado e penaliza a violacao para manter gradiente.
function J = custo_restrito(fixos, f_cpsi, f_s, e, T_SETTLE, mascara)
    f_c_eff = min(f_cpsi, f_s);
    J = custo(fixos, f_c_eff, f_s, e, T_SETTLE, mascara);
    if f_cpsi > f_s
        J = J * (1 + 5 * (log(f_cpsi / f_s))^2);
    end
end


function [J, s] = custo(fixos, f_cpsi, f_s, e, T_SETTLE, mascara)
% s: series da janela de custo (t >= T_SETTLE), para as figuras ct_m_*.
% MSE absoluto a partir de T_SETTLE. fixos (f_vpsi, v_s, CT_m_pos, I_psi),
% f_cpsi e f_s vao para o modelo por setVariable (simula_trms).
    p        = fixos;
    p.f_cpsi = f_cpsi;
    p.f_s    = f_s;

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
    if nargout > 1
        s.t       = e.t_exp(idx);
        s.exp_dev = psi_exp_dev(idx);
        s.sim_dev = psi_sim_dev(idx);
    end
end


function imprime_grupo(rotulo, rel, iP, iS)
    cv = 100 * std(rel) / mean(rel);
    fprintf('%s media geral %.3f | CV %.1f%%', rotulo, mean(rel), cv);
    if any(iP), fprintf(' | PRBS %.3f', mean(rel(iP))); end
    if any(iS), fprintf(' | STEP %.3f', mean(rel(iS))); end
    fprintf('\n');
end


function d = disp_log(rel)
    if isempty(rel), d = NaN; return; end
    d = mean(abs(log(rel)));
end


function s = ternario(cond, a, b)
    if cond, s = a; else, s = b; end
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