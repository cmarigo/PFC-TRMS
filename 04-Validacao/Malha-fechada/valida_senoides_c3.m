function R = valida_senoides_c3(pasta)
%VALIDA_SENOIDES_C3 Validacao do yaw do gemeo com a soma de senoides do
%   MainYaw_Ident (sessao c3, parafuso do yaw solto, rotor principal
%   desligado).
%
%   R = valida_senoides_c3          % pasta P.c3 do caminhos_dados
%   R = valida_senoides_c3(pasta)
%
%   Ensaios:
%     out_yaw_sen_g019_c3_solto.mat   ganho de saida 0,19 (u2 de -0,27 a +0,37 V)
%                                     -> validacao, dentro da faixa do PRBS
%     out_yaw_sen_g05_c3_solto.mat    ganho de saida 0,5  (u2 de -0,70 a +0,96 V)
%                                     -> extrapolacao
%
%   Formato dos arquivos: variavel u [N x 3] = [u2, phi, psi], SEM coluna
%   de tempo; amostragem de 0,1 s, t = (0:N-1)'*0,1.
%
%   O u2 do gemeo e gerado pela formula das senoides a 1 kHz (o script
%   confere antes que a formula reproduz o u2 gravado). O gemeo roda com
%   as duas malhas abertas (modo 0) e u1 = 0, como na bancada.
%
%   Metricas, iguais as do valida_yaw (PRBS):
%     J     = MSE / variancia do medido, em %
%     ganho = inclinacao da regressao gemeo x bancada
%     vies  = intercepto dessa regressao
%   e, por frequencia, ganho e fase de phi em relacao a u2 na bancada e
%   no gemeo (ajuste por minimos quadrados a partir de 20 s).
%
%   E funcao, e nao script, para isolar as variaveis locais do workspace
%   base, onde o trms_params e carregado.

P = caminhos_dados();
if nargin < 1, pasta = P.c3; end

% --- Configuracao ---------------------------------------------------------
% Modelo e nomes de variaveis/saidas do .slx ficam no simula_trms.m
% (trms_model_pid_bancada, modo 0 = malhas abertas).

Q        = 2*pi/2048;   % resolucao dos encoders [rad]
TS_LOG   = 0.1;         % [s] amostragem dos arquivos da bancada
TS_SIM   = 0.001;       % [s] passo do sinal de entrada do gemeo
T_TRANS  = 20;          % [s] descartado na analise por frequencia
WN_YAW   = 0.623;       % [rad/s] omega_n do yaw na sessao c3 (so para a figura)
DIR_FIG  = fullfile(P.resultados, 'figuras_c3');

% Sinal do MainYaw_Ident: u2 = G * sum( g_i * sin(2*pi*f_i*t + fase_i) )
SEN.f    = [0.19  0.078 0.053 0.027 0.14 0.25];   % [Hz]
SEN.g    = [0.20  0.36  0.45  0.25  0.40 0.60];
SEN.fase = [-0.35 0     0     0     1.5  1.5];    % [rad]

ens = struct( ...
    'arquivo', {'out_yaw_sen_g019_c3_solto.mat', 'out_yaw_sen_g05_c3_solto.mat'}, ...
    'G',       {0.19, 0.5}, ...
    'rotulo',  {'G=0,19', 'G=0,5'}, ...
    'papel',   {'validacao', 'extrapolacao'});

[f_ord, ord] = sort(SEN.f);

% --- Parametros da planta no workspace base --------------------------------
evalin('base', 'trms_params;');
confere_params('identificado');   % C_c, f_vphi, x0 etc. usados pelo gemeo

R = struct([]);

for k = 1:numel(ens)
    E = ens(k);
    B = le_bancada(acha_dados(pasta, E.arquivo), TS_LOG);

    % A formula tem de reproduzir o u2 gravado
    erro_u = max(abs(soma_senoides(B.t, SEN, E.G) - B.u2));
    if erro_u > 1e-6
        error('valida_senoides_c3:sinal', ...
            '%s: a formula difere do u2 gravado em %.2e V.', ...
            E.rotulo, erro_u);
    end

    % --- Simulacao ---------------------------------------------------------
    T_FIM = B.t(end);
    t1k   = (0:TS_SIM:T_FIM).';
    u2_ts = timeseries(soma_senoides(t1k, SEN, E.G), t1k);

    opc = struct();
    opc.T_fim   = T_FIM;
    opc.modo    = 0;                  % duas malhas abertas
    opc.mascara = ones(6,1);
    opc.u_m     = timeseries([0; 0], [0; T_FIM]);
    opc.u_t     = u2_ts;

    fprintf('Simulando %s ...\n', E.rotulo);
    S = simula_trms(opc);

    % Confere se o u2 chegou a entrada da planta (tolerancia cobre 1 passo
    % de 1 ms). u_planta e' a saida do trms_sel_entrada.
    if ~isempty(S.u_planta)
        tc = S.t_up;  u2c = S.u_planta;
        if max(abs(u2c - soma_senoides(tc, SEN, E.G))) > 5e-3
            diagnostica_u2(tc, u2c, SEN, E.G);
            error('valida_senoides_c3:u2', ...
                '%s: a entrada do tail nao corresponde ao sinal de senoides (ver diagnostico acima).', ...
                E.rotulo);
        end
    else
        warning('valida_senoides_c3:sem_u2', ...
            '%s: u_planta nao esta logado.', E.rotulo);
    end

    tp = S.t_phi;  phi_s = S.phi;
    ts = S.t_psi;  psi_s = S.psi;

    % Referencial dos encoders: zero na condicao inicial, como na bancada
    phi_s = phi_s - phi_s(1);
    psi_s = psi_s - psi_s(1);

    % Se o u2 nao tiver chegado ao tail, o yaw fica parado
    if std(phi_s) < 10*Q
        error('valida_senoides_c3:yaw', ...
            '%s: o yaw do gemeo nao respondeu ao u2 (desvio-padrao %.4f rad).', ...
            E.rotulo, std(phi_s));
    end

    M.t   = B.t;
    M.u2  = B.u2;
    M.phi = Q*round(interp1(tp, phi_s, B.t, 'nearest', 'extrap')/Q);
    M.psi = Q*round(interp1(ts, psi_s, B.t, 'nearest', 'extrap')/Q);

    % --- Metricas no tempo -------------------------------------------------
    todo = true(size(B.t));
    apos = B.t >= T_TRANS;
    [J, rms_e, ganho, vies] = metricas(B.phi, M.phi, todo);
    J20 = metricas(B.phi, M.phi, apos);

    % --- Resposta por frequencia ------------------------------------------
    [Au, ~]   = amplitudes_complexas(B.t, B.u2,  SEN.f, apos);
    [Ab, r2b] = amplitudes_complexas(B.t, B.phi, SEN.f, apos);
    [Am, r2m] = amplitudes_complexas(M.t, M.phi, SEN.f, apos);
    Hb = Ab ./ Au;
    Hm = Am ./ Au;

    R(k).rotulo = E.rotulo;
    R(k).papel  = E.papel;
    R(k).G      = E.G;
    R(k).B      = B;
    R(k).M      = M;
    R(k).J      = J;
    R(k).J20    = J20;
    R(k).rms    = rms_e;
    R(k).ganho  = ganho;
    R(k).vies   = vies;
    R(k).f      = SEN.f;
    R(k).Hb     = Hb;
    R(k).Hm     = Hm;
    R(k).r2b    = r2b;
    R(k).r2m    = r2m;
end

% --- Tabelas ---------------------------------------------------------------
fprintf('\n=== Yaw: soma de senoides, sessao c3, parafuso solto ===\n');
fprintf('%-7s %-12s | %7s %8s %7s %9s | %8s\n', ...
    'ensaio', 'papel', 'J [%]', 'RMS rad', 'ganho', 'vies rad', 'J>20s %');
fprintf('%s\n', repmat('-', 1, 72));
for k = 1:numel(R)
    fprintf('%-7s %-12s | %7.1f %8.4f %7.3f %+9.4f | %8.1f\n', ...
        R(k).rotulo, R(k).papel, R(k).J, R(k).rms, R(k).ganho, R(k).vies, R(k).J20);
end

for k = 1:numel(R)
    fprintf('\n%s (%s): ganho e fase de phi/u2, a partir de %g s\n', ...
        R(k).rotulo, R(k).papel, T_TRANS);
    fprintf('  %7s %7s | %9s %9s %7s | %9s %9s %8s\n', ...
        'f [Hz]', 'w rad/s', '|H| banc', '|H| gem', 'razao', 'fase banc', 'fase gem', 'dif');
    for i = ord
        hb = R(k).Hb(i);  hm = R(k).Hm(i);
        fprintf('  %7.3f %7.3f | %9.3f %9.3f %7.3f | %8.0f%s %8.0f%s %7.0f%s\n', ...
            SEN.f(i), 2*pi*SEN.f(i), abs(hb), abs(hm), abs(hm)/abs(hb), ...
            rad2deg(angle(hb)), char(176), rad2deg(angle(hm)), char(176), ...
            rad2deg(angle(hm/hb)), char(176));
    end
    fprintf('  variancia de phi explicada pelas 6 senoides: bancada %.0f%% | gemeo %.0f%%\n', ...
        100*R(k).r2b, 100*R(k).r2m);
    fprintf('  psi com u1 = 0: bancada %d a %d contagens | gemeo %d a %d contagens\n', ...
        round(min(R(k).B.psi)/Q), round(max(R(k).B.psi)/Q), ...
        round(min(R(k).M.psi)/Q), round(max(R(k).M.psi)/Q));
end

% --- Figuras ---------------------------------------------------------------
if ~exist(DIR_FIG, 'dir'), mkdir(DIR_FIG); end
cor_b = [0 0 0];
cor_m = [0.85 0.20 0.10];

f1 = figure('Name', 'Yaw - soma de senoides c3', 'Color', 'w', ...
            'Position', [100 100 1100 750]);
tl = tiledlayout(f1, 3, numel(R), 'TileSpacing', 'compact');
for k = 1:numel(R)
    B = R(k).B;  M = R(k).M;

    ax = nexttile(tl, k);
    plot(ax, B.t, B.u2, 'Color', [0.3 0.3 0.3]);
    grid(ax, 'on');  ylabel(ax, 'u_2 (V)');
    title(ax, sprintf('%s (%s)', R(k).rotulo, R(k).papel));

    ax = nexttile(tl, k + numel(R));
    h1 = plot(ax, B.t, B.phi, 'Color', cor_b);  hold(ax, 'on');
    h2 = plot(ax, M.t, M.phi, 'Color', cor_m);
    grid(ax, 'on');  ylabel(ax, '\phi (rad, encoder)');
    title(ax, sprintf('J = %.1f%%, ganho %.2f', R(k).J, R(k).ganho));
    if k == 1
        legend(ax, [h1 h2], {'bancada', 'gemeo'}, 'Location', 'best');
    end

    ax = nexttile(tl, k + 2*numel(R));
    stairs(ax, B.t, B.psi/Q, 'Color', cor_b);  hold(ax, 'on');
    stairs(ax, M.t, M.psi/Q, 'Color', cor_m);
    grid(ax, 'on');  ylabel(ax, '\psi (contagens)');  xlabel(ax, 't (s)');
    title(ax, '\psi com u_1 = 0');
end
exportgraphics(f1, fullfile(DIR_FIG, 'yaw_senoides_c3_tempo.png'), 'Resolution', 200);

f2 = figure('Name', 'Yaw - resposta por frequencia c3', 'Color', 'w', ...
            'Position', [150 150 900 650]);
tl = tiledlayout(f2, 2, 1, 'TileSpacing', 'compact');
marc = {'o', 's'};

ax = nexttile(tl);
hold(ax, 'on');
leg = {};
for k = 1:numel(R)
    loglog(ax, f_ord, abs(R(k).Hb(ord)), ['-' marc{k}], 'Color', cor_b);
    loglog(ax, f_ord, abs(R(k).Hm(ord)), ['--' marc{k}], 'Color', cor_m);
    leg = [leg, {sprintf('bancada %s', R(k).rotulo), sprintf('gemeo %s', R(k).rotulo)}]; %#ok<AGROW>
end
set(ax, 'XScale', 'log', 'YScale', 'log');
xline(ax, WN_YAW/(2*pi), ':', '\omega_n');
grid(ax, 'on');  ylabel(ax, '|\phi/u_2| (rad/V)');
legend(ax, leg, 'Location', 'southwest');
title(ax, 'Ganho de \phi em relacao a u_2 nas seis frequencias');

ax = nexttile(tl);
hold(ax, 'on');
for k = 1:numel(R)
    plot(ax, f_ord, rad2deg(angle(R(k).Hm(ord)./R(k).Hb(ord))), ['-' marc{k}], ...
        'Color', cor_m);
end
set(ax, 'XScale', 'log');
yline(ax, 0, 'k:');
xline(ax, WN_YAW/(2*pi), ':', '\omega_n');
grid(ax, 'on');  xlabel(ax, 'f (Hz)');  ylabel(ax, 'fase gemeo - bancada (graus)');
legend(ax, {R.rotulo}, 'Location', 'best');
exportgraphics(f2, fullfile(DIR_FIG, 'yaw_senoides_c3_freq.png'), 'Resolution', 200);

save(fullfile(P.resultados, 'valida_senoides_c3_resultados.mat'), 'R');
fprintf('\nFiguras em %s/ e resultados em valida_senoides_c3_resultados.mat\n', DIR_FIG);
end


% =========================================================================
function B = le_bancada(arquivo, ts_log)
%LE_BANCADA Le a variavel u [u2, phi, psi] e reconstroi o tempo.
S = load(arquivo);
if ~isfield(S, 'u')
    error('valida_senoides_c3:arquivo', '%s nao tem a variavel u.', arquivo);
end
X = S.u;
N = size(X, 1);
B.t   = (0:N-1).'*ts_log;
B.u2  = X(:,1);
B.phi = X(:,2);
B.psi = X(:,3);
end


function u = soma_senoides(t, SEN, G)
%SOMA_SENOIDES Sinal do MainYaw_Ident com ganho de saida G.
t = t(:);
u = zeros(size(t));
for i = 1:numel(SEN.f)
    u = u + SEN.g(i)*sin(2*pi*SEN.f(i)*t + SEN.fase(i));
end
u = G*u;
end


function diagnostica_u2(tc, u2c, SEN, G)
%DIAGNOSTICA_U2 Mostra por que o comando do tail difere do sinal pedido:
%   escala, retencao (sample time) ou atraso.
u_ref = soma_senoides(tc, SEN, G);
e     = u2c - u_ref;
fprintf('\n--- Diagnostico do comando do tail ---\n');
fprintf('  amostras %d | passo do log %.4g s | t final %.4g s\n', ...
    numel(tc), median(diff(tc)), tc(end));
fprintf('  erro maximo %.4f V | erro RMS %.4f V | RMS do sinal pedido %.4f V\n', ...
    max(abs(e)), sqrt(mean(e.^2)), sqrt(mean(u_ref.^2)));
fprintf('  fator de escala (regressao comando x pedido): %.4f\n', ...
    (u_ref.'*u2c)/(u_ref.'*u_ref));
mud = find(diff(u2c) ~= 0);
if numel(mud) > 1
    fprintf('  intervalo tipico entre mudancas do comando: %.4g s\n', ...
        median(diff(tc(mud))));
else
    fprintf('  o comando quase nao muda (%d mudancas)\n', numel(mud));
end
atrasos = 0:0.001:0.5;
erro_at = zeros(size(atrasos));
for i = 1:numel(atrasos)
    d = u2c - soma_senoides(tc - atrasos(i), SEN, G);
    erro_at(i) = sqrt(mean(d.^2));
end
[emin, imin] = min(erro_at);
fprintf('  atraso que melhor alinha: %.3f s (erro RMS restante %.4f V)\n', ...
    atrasos(imin), emin);
n4 = min(4, numel(u2c));
fprintf('  primeiros valores: comando %s | pedido %s\n', ...
    mat2str(u2c(1:n4).', 4), mat2str(u_ref(1:n4).', 4));
end


function [J, rms_e, ganho, vies] = metricas(yb, ym, m)
%METRICAS Mesmas metricas do valida_yaw: J = MSE/var(medido) em %,
%   RMS do residuo e regressao gemeo = ganho*bancada + vies.
e     = ym(m) - yb(m);
J     = 100*mean(e.^2)/var(yb(m), 1);
rms_e = sqrt(mean(e.^2));
p     = polyfit(yb(m), ym(m), 1);
ganho = p(1);
vies  = p(2);
end


function [A, r2] = amplitudes_complexas(t, y, f, m)
%AMPLITUDES_COMPLEXAS Ajusta y = sum(a_i sin(w_i t) + b_i cos(w_i t)) +
%   c + d*t na janela m. Devolve A_i = a_i + j*b_i (A_i = amplitude *
%   exp(j*fase) na convencao seno) e a fracao da variancia explicada.
%   O termo linear absorve a deriva lenta.
tt = t(m);
yy = y(m);
w  = 2*pi*f(:).';
X  = [sin(tt*w), cos(tt*w), ones(numel(tt), 1), tt];
c  = X \ yy;
n  = numel(f);
A  = (c(1:n) + 1i*c(n+1:2*n)).';
r2 = 1 - sum((yy - X*c).^2)/sum((yy - mean(yy)).^2);
end