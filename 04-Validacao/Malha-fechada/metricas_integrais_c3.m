function T = metricas_integrais_c3(R, mostra_figura)
%METRICAS_INTEGRAIS_C3 IAE e ISE da arfagem nos ensaios de PID da sessao c3.
%
%   T = metricas_integrais_c3            % le resultados/compara_pid_c3_resultados.mat
%   T = metricas_integrais_c3(R)         % usa a saida de R = compara_pid_c3
%   T = metricas_integrais_c3(R, false)  % sem a figura
%
%   Calcula, para a bancada e para o gemeo, as mesmas integrais do app:
%     IAE = integral de |ref - psi|      [rad.s]
%     ISE = integral de (ref - psi)^2    [rad^2.s]
%   sobre os sinais que o COMPARA_PID_C3 ja deixou alinhados: bancada a
%   10 Hz e gemeo amostrado nos mesmos instantes e quantizado como o
%   encoder. Os dois lados passam pelo mesmo tratamento, entao a comparacao
%   e justa. Os valores do gemeo nao sao identicos aos do app, que integra
%   a 1 ms sem quantizar.
%
%   JANELAS
%     4/6/8 e 5/8/10: do degrau ate o fim do registro, com a MESMA duracao
%       nas duas rodadas (a menor das duas), porque o IAE cresce com a
%       janela.
%     Teste 6: do degrau ate o degrau de u2, como no app.
%   A coluna "IAE regime" integra so a partir de T_REGIME s apos o degrau:
%   e a parcela da oscilacao residual (alternancia de contagens do
%   encoder), que nenhuma sintonia remove.
%
%   O QUE E IMPRESSO
%     - tabela bancada x gemeo por rodada;
%     - direcao 4/6/8 -> 5/8/10 nas duas fontes (o gemeo acerta o sentido
%       e a ordem de grandeza da mudanca?);
%     - piso de repetibilidade da bancada: 4/6/8 contra o Teste 6 antes do
%       u2 (mesmos ganhos, mesma janela). A direcao tambem e impressa nessa
%       janela curta, para comparar com o piso na mesma base. Diferencas
%       entre ganhos menores que o piso nao se distinguem da variacao da
%       propria bancada.
%
%   Campos usados de R(k): B.t, B.psi, M.t, M.psi, ref, rotulo e, se
%   existirem, t_deg (instante do degrau), t2 (instante do degrau de u2) e
%   B.u1 (para achar o degrau quando t_deg nao existir). psi e ref no
%   referencial do encoder (zero no repouso), em rad.
%
%   Salva a tabela em resultados/metricas_integrais_c3.mat.
%
%   E funcao, e nao script, para isolar as variaveis do workspace base.
%
%   Ver tambem COMPARA_PID_C3, CAMINHOS_DADOS.

if nargin < 2 || isempty(mostra_figura)
    mostra_figura = true;
end

T_REGIME = 30;   % [s] apos o degrau: dai em diante conta como regime

% --- Resultado do compara_pid_c3 ----------------------------------------
if nargin < 1 || isempty(R)
    P = caminhos_dados();
    arq = fullfile(P.resultados, 'compara_pid_c3_resultados.mat');
    if ~isfile(arq)
        error('metricas_integrais_c3:sem_resultado', ...
              'Nao achei %s.\nRode antes: R = compara_pid_c3;', arq);
    end
    S = load(arq, 'R');
    R = S.R;
end

n = numel(R);
rot = {R.rotulo};

% --- Instantes do degrau de referencia e do degrau de u2 -----------------
t_deg = zeros(1, n);
t_u2  = nan(1, n);
for k = 1:n
    t_deg(k) = instante_degrau(R(k));
    if isfield(R(k), 't2') && ~isempty(R(k).t2) && isfinite(R(k).t2)
        t_u2(k) = R(k).t2;
    end
end

% --- Janelas ----------------------------------------------------------------
% Rodadas sem u2: mesma duracao apos o degrau (a menor entre elas).
sem_u2  = isnan(t_u2);
dur_fim = inf;
for k = find(sem_u2)
    dur_fim = min(dur_fim, min(R(k).B.t(end), R(k).M.t(end)) - t_deg(k));
end

jan = zeros(n, 2);
Ib  = cell(1, n);
Im  = cell(1, n);
for k = 1:n
    if sem_u2(k)
        jan(k, :) = t_deg(k) + [0 dur_fim];
    else
        jan(k, :) = [t_deg(k) t_u2(k)];
    end
    Ib{k} = integrais(R(k).B.t, R(k).B.psi, R(k).ref, jan(k, :), T_REGIME);
    Im{k} = integrais(R(k).M.t, R(k).M.psi, R(k).ref, jan(k, :), T_REGIME);
end

% --- Tabela -------------------------------------------------------------------
fprintf('\nIAE e ISE da arfagem, sessao c3 (e = ref - psi, 10 Hz, psi quantizado)\n\n');
fprintf('%-8s  %-14s | %-30s | %-33s | %s\n', 'rodada', 'janela [s]', ...
        'IAE [rad.s]  banc / gem / dif', 'ISE [rad^2.s]  banc / gem / dif', ...
        sprintf('IAE regime (>%d s) banc / gem', T_REGIME));
for k = 1:n
    fprintf('%-8s  %5.1f a %5.1f | %7.3f / %7.3f / %+6.1f%% | %8.4f / %8.4f / %+6.1f%% | %6.3f / %6.3f\n', ...
            rot{k}, jan(k, 1), jan(k, 2), ...
            Ib{k}.iae, Im{k}.iae, pct(Im{k}.iae, Ib{k}.iae), ...
            Ib{k}.ise, Im{k}.ise, pct(Im{k}.ise, Ib{k}.ise), ...
            Ib{k}.iae_reg, Im{k}.iae_reg);
end

k1 = acha(rot, '4/6/8');
k2 = acha(rot, '5/8/10');
k6 = acha(rot, 'Teste 6');

% --- Direcao 4/6/8 -> 5/8/10 -------------------------------------------------
if ~isempty(k1) && ~isempty(k2)
    fprintf('\nDirecao 4/6/8 -> 5/8/10 (janela de %.0f s apos o degrau):\n', dur_fim);
    fprintf('  IAE: bancada %+.1f%% | gemeo %+.1f%%\n', ...
            pct(Ib{k2}.iae, Ib{k1}.iae), pct(Im{k2}.iae, Im{k1}.iae));
    fprintf('  ISE: bancada %+.1f%% | gemeo %+.1f%%\n', ...
            pct(Ib{k2}.ise, Ib{k1}.ise), pct(Im{k2}.ise, Im{k1}.ise));
end

% --- Piso de repetibilidade da bancada ----------------------------------------
% 4/6/8 e Teste 6 tem os mesmos ganhos e a mesma referencia; ate o u2 sao
% repeticoes do mesmo ensaio. A janela e a do Teste 6, aplicada a partir
% do degrau de cada rodada.
if ~isempty(k1) && ~isempty(k6)
    dur6 = jan(k6, 2) - jan(k6, 1);
    jr1  = t_deg(k1) + [0 dur6];
    Ir1  = integrais(R(k1).B.t, R(k1).B.psi, R(k1).ref, jr1, T_REGIME);
    fprintf('\nRepetibilidade da bancada (4/6/8 x Teste 6 ate o u2, %.0f s apos o degrau):\n', dur6);
    fprintf('  IAE %.3f x %.3f (%.1f%%) | ISE %.4f x %.4f (%.1f%%)\n', ...
            Ir1.iae, Ib{k6}.iae, abs(pct(Ib{k6}.iae, Ir1.iae)), ...
            Ir1.ise, Ib{k6}.ise, abs(pct(Ib{k6}.ise, Ir1.ise)));

    if ~isempty(k2)
        % Direcao na mesma janela curta do piso, para comparar na mesma base.
        jr2 = t_deg(k2) + [0 dur6];
        Ib1 = Ir1;
        Ib2 = integrais(R(k2).B.t, R(k2).B.psi, R(k2).ref, jr2, T_REGIME);
        Im1 = integrais(R(k1).M.t, R(k1).M.psi, R(k1).ref, jr1, T_REGIME);
        Im2 = integrais(R(k2).M.t, R(k2).M.psi, R(k2).ref, jr2, T_REGIME);
        fprintf('  Direcao 4/6/8 -> 5/8/10 nessa mesma janela: IAE bancada %+.1f%% | gemeo %+.1f%%;', ...
                pct(Ib2.iae, Ib1.iae), pct(Im2.iae, Im1.iae));
        fprintf(' ISE bancada %+.1f%% | gemeo %+.1f%%\n', ...
                pct(Ib2.ise, Ib1.ise), pct(Im2.ise, Im1.ise));
    end
end

% --- Saida ----------------------------------------------------------------------
T = table(string(rot(:)), jan(:, 1), jan(:, 2), ...
          campo(Ib, 'iae'), campo(Im, 'iae'), ...
          campo(Ib, 'ise'), campo(Im, 'ise'), ...
          campo(Ib, 'iae_reg'), campo(Im, 'iae_reg'), ...
          'VariableNames', {'rodada', 't_ini', 't_fim', ...
                            'IAE_bancada', 'IAE_gemeo', ...
                            'ISE_bancada', 'ISE_gemeo', ...
                            'IAE_regime_bancada', 'IAE_regime_gemeo'});
try
    P = caminhos_dados();
    save(fullfile(P.resultados, 'metricas_integrais_c3.mat'), 'T');
    fprintf('\nTabela salva em %s\n', fullfile(P.resultados, 'metricas_integrais_c3.mat'));
catch err
    warning('metricas_integrais_c3:salvar', 'Tabela nao salva: %s', err.message);
end

% --- Figura: IAE e ISE acumulados -------------------------------------------------
% Mostra ONDE cada integral se acumula: o ISE quase todo na subida, o IAE
% tambem na oscilacao depois do pico e na cauda.
if mostra_figura && ~isempty(k1) && ~isempty(k2)
    f  = figure('Name', 'IAE e ISE acumulados - c3', 'Color', 'w', ...
                'Position', [100 100 1000 380]);
    tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax1 = nexttile(tl);
    ax2 = nexttile(tl);
    hold(ax1, 'on');  grid(ax1, 'on');  box(ax1, 'on');
    hold(ax2, 'on');  grid(ax2, 'on');  box(ax2, 'on');

    cores = [0.13 0.40 0.75; 0.80 0.30 0.20];
    ks    = [k1 k2];
    hs    = gobjects(0);
    nomes = {};
    for i = 1:2
        k = ks(i);
        for fonte = 1:2
            if fonte == 1
                X = R(k).B;  estilo = '-';   nome = 'bancada';
            else
                X = R(k).M;  estilo = '--';  nome = 'gemeo';
            end
            [tc, ia, is] = acumulados(X.t, X.psi, R(k).ref, jan(k, :));
            hs(end + 1) = plot(ax1, tc - t_deg(k), ia, estilo, ...
                               'Color', cores(i, :), 'LineWidth', 1.3); %#ok<AGROW>
            plot(ax2, tc - t_deg(k), is, estilo, 'Color', cores(i, :), 'LineWidth', 1.3);
            nomes{end + 1} = sprintf('%s %s', rot{k}, nome); %#ok<AGROW>
        end
    end
    xlabel(ax1, 't - t_{degrau} [s]');
    ylabel(ax1, 'IAE acumulado [rad\cdots]');
    xlabel(ax2, 't - t_{degrau} [s]');
    ylabel(ax2, 'ISE acumulado [rad^2\cdots]');
    legend(ax1, hs, nomes, 'Location', 'southeast');
end

end


% =========================================================================
% Funcoes locais
% =========================================================================

function I = integrais(t, psi, ref, jan, t_regime)
%INTEGRAIS IAE, ISE e IAE de regime de e = ref - psi na janela, por trapezio.
t   = t(:);
psi = psi(:);
j   = t >= jan(1) - 1e-9 & t <= jan(2) + 1e-9;
tj  = t(j);
e   = ref - psi(j);
I.iae = trapz(tj, abs(e));
I.ise = trapz(tj, e.^2);
c = tj >= jan(1) + t_regime;
if nnz(c) >= 2
    I.iae_reg = trapz(tj(c), abs(e(c)));
else
    I.iae_reg = NaN;
end
end

function [tj, ia, is] = acumulados(t, psi, ref, jan)
%ACUMULADOS IAE e ISE acumulados ao longo da janela.
t   = t(:);
psi = psi(:);
j   = t >= jan(1) - 1e-9 & t <= jan(2) + 1e-9;
tj  = t(j);
e   = ref - psi(j);
ia  = cumtrapz(tj, abs(e));
is  = cumtrapz(tj, e.^2);
end

function t0 = instante_degrau(Rk)
%INSTANTE_DEGRAU Instante do degrau de referencia da rodada.
%   Usa o campo t_deg do compara_pid_c3. Sem ele, acha o degrau pelo salto
%   de u1: antes do degrau o erro e zero e u1 tambem; no degrau, o chute
%   derivativo faz u1 saltar.
if isfield(Rk, 't_deg') && ~isempty(Rk.t_deg) && isfinite(Rk.t_deg)
    t0 = Rk.t_deg;
    return
end
if isfield(Rk.B, 'u1')
    j = find(abs(Rk.B.u1(:)) > 0.05, 1);
    if ~isempty(j)
        t0 = Rk.B.t(max(j - 1, 1));
        return
    end
end
t0 = 10;
warning('metricas_integrais_c3:degrau', ...
        'Rodada %s sem t_deg nem u1: usando degrau em 10 s.', Rk.rotulo);
end

function k = acha(rot, nome)
k = find(strcmp(rot, nome), 1);
end

function v = campo(C, nome)
v = cellfun(@(s) s.(nome), C(:));
end

function p = pct(a, b)
% Diferenca percentual de a em relacao a b.
p = 100 * (a - b) / b;
end
