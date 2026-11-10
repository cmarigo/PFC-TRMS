% ==============================================================================
% identifica_dinamica_yaw.m
%
% Identifica os parametros dinamicos do eixo de guinada a partir dos
% transitorios dos ensaios de degrau, na mesma metodologia usada no eixo de
% arfagem (degraus para identificacao, PRBS para validacao independente).
%
% MODELO AJUSTADO A CADA TRANSITORIO:
%
%   phi(t) = phi_inf + A_s*exp(-t/tau_s) + A_o*exp(-sigma*t)*cos(w_d*t + ph)
%
%   Tres componentes, e a separacao delas e' o ponto do metodo:
%     phi_inf  equilibrio
%     modo lento   primeira ordem com tau_s -- observado em todos os degraus,
%                  mecanismo nao confirmado (hipotese principal:
%                  viscoelasticidade do cabo). NAO esta no modelo do Tastemirov.
%     oscilacao    segunda ordem, de onde saem w_n, zeta, C_c e f_vphi
%
%   Ajustar so a oscilacao, ignorando o modo lento, enviesa zeta -- parte da
%   deriva lenta seria absorvida como amortecimento.
%
% INERCIA EFETIVA: a conversao para C_c e f_vphi usa
%   I_ef = I_phi + I_c*cos(psi)^2, com a arfagem em repouso a -38 graus
%   (eq. 29 do Tastemirov), e nao I_phi sozinho. w_n, zeta e tau_s nao
%   dependem da inercia; C_c e f_vphi escalam com ela (fator 3,45).
%
% AJUSTE POR fminsearch (Nelder-Mead): nao exige Optimization Toolbox.
%
% AMORTECIMENTO COM E SEM ROTOR:
%   A oscilacao livre (motores desligados) da zeta ~ 0,12; os degraus, com o
%   rotor de cauda girando, dao zeta ~ 0,27. Uma hipotese, NAO verificada, e'
%   a modulacao aerodinamica do empuxo pela velocidade da viga. A tabela de
%   saida mostra o zeta de CADA degrau: se ele crescer com a tensao, a
%   hipotese ganha apoio; se ficar constante, o excesso de amortecimento nao
%   escala com a rotacao.
%
% DADOS: os cinco degraus de 80 s da segunda sessao (mesmo estado da bancada
%   dos PRBS de validacao).
%
% SAIDA EM DISCO: dinamica_yaw_resultados.mat.
%
% Clara Temponi Marigo -- PFC, gemeo digital do TRMS
% ==============================================================================

clear; close all; clc;

%% Configuracao ----------------------------------------------------------------
P         = caminhos_dados();
DIR_DADOS = P.yaw;           % sessoes de identificacao do yaw
I_PHI     = 2.1117e-2;    % parcela fixa da inercia de guinada [kg.m^2]
I_C       = 8.3286e-2;    % inercia da viga transversal [kg.m^2]
PSI_REST  = -0.663;       % arfagem em repouso [rad] -- -38 graus, transferidor
I_EF      = I_PHI + I_C*cos(PSI_REST)^2;   % ~7,28e-2 kg.m^2
F_V_NOM   = 1.12e-4;      % f_vphi nominal do Tastemirov, para comparacao
T_DEGRAU  = 10;           % instante do degrau [s]

fprintf('I_ef = %.4e kg.m^2  (%.2fx I_phi, psi = %.1f graus)\n\n', ...
        I_EF, I_EF/I_PHI, PSI_REST*180/pi);

ENSAIOS = { ...
    'out_025_v2.mat',   0.250; ...
    'out_050_v2.mat',   0.500; ...
    'out_075_v2.mat',   0.750; ...
    'out_n0375_v2.mat', -0.375; ...
    'out_n05_v2.mat',   -0.500  ...
};

ARQ_LIVRE = 'out_livre.mat';   % oscilacao livre, motores desligados

n   = size(ENSAIOS,1);
res = zeros(n,7);   % [u wn zeta tau_s C_c f_v rms]
PAR = zeros(n,7);   % parametros do ajuste de cada degrau
X   = cell(n,1);    % tempo apos o degrau
Y   = cell(n,1);    % phi medido apos o degrau

%% Ajuste de cada transitorio --------------------------------------------------
fprintf('=== Ajuste dos transitorios de degrau ===\n\n');
fprintf('%8s %8s %8s %8s %8s %12s %10s\n', ...
        'u [V]','w_n','zeta','tau_s','T [s]','C_c','RMS');

figure('Color','w','Position',[80 80 1000 700]);

for k = 1:n
    S = load(acha_dados(DIR_DADOS, ENSAIOS{k,1}));
    M = S.simout_tail;
    t = M(:,1);  y = M(:,3);
    u = ENSAIOS{k,2};

    m  = (t >= T_DEGRAU);
    x  = t(m) - T_DEGRAU;
    yy = y(m);

    % Inicializacao: periodo de ~10 s e tau_s de ~25 s
    p0 = [yy(end); -0.15*sign(u); 25; -0.30*sign(u); 0.15; 2*pi/10; 0];

    custo = @(p) mean( (modelo(p,x) - yy).^2 );
    opt = optimset('MaxIter',40000,'MaxFunEvals',40000, ...
                   'TolX',1e-9,'TolFun',1e-12);
    p = fminsearch(custo, p0, opt);

    phi_inf = p(1);  tau_s = p(3);
    sigma   = p(5);  w_d   = p(6);
    w_n  = hypot(w_d, sigma);
    zeta = sigma / w_n;
    C_c  = I_EF * w_n^2;
    f_v  = 2 * sigma * I_EF;         % amortecimento viscoso equivalente
    rms  = sqrt(custo(p));

    res(k,:) = [u w_n zeta tau_s C_c f_v rms];
    PAR(k,:) = p(:).';
    X{k}     = x;
    Y{k}     = yy;

    fprintf('%+8.3f %8.4f %8.3f %8.1f %8.2f %12.3e %10.5f\n', ...
            u, w_n, zeta, tau_s, 2*pi/w_d, C_c, rms);

    subplot(3,2,k);
    plot(x, yy, 'b', 'LineWidth', 1); hold on;
    plot(x, modelo(p,x), 'r--', 'LineWidth', 1.2);
    plot(x, phi_inf + p(2)*exp(-x/tau_s), 'k:', 'LineWidth', 1);
    grid on; xlabel('t apos o degrau [s]'); ylabel('\phi [rad]');
    title(sprintf('u_t = %+.3f V   \\zeta = %.3f', u, zeta));
    if k == 1
        legend('medido','ajuste','modo lento','Location','Best');
    end
end

%% Consolidacao ----------------------------------------------------------------
pos = res(:,1) > 0;

fprintf('\n=== Ramo positivo (tres ensaios) ===\n');
fprintf('  w_n   = %.4f +- %.4f rad/s\n', mean(res(pos,2)), std(res(pos,2)));
fprintf('  zeta  = %.3f  +- %.3f   (por nivel: %s)\n', mean(res(pos,3)), std(res(pos,3)), ...
        mat2str(res(pos,3).', 3));
fprintf('  tau_s = %.1f  +- %.1f s\n',    mean(res(pos,4)), std(res(pos,4)));
fprintf('  C_c   = %.3e +- %.3e N.m/rad\n', mean(res(pos,5)), std(res(pos,5)));
fprintf('  f_v   = %.3e +- %.3e N.m.s/rad\n', mean(res(pos,6)), std(res(pos,6)));
fprintf('  razao para o f_vphi nominal do Tastemirov: %.0fx\n', ...
        mean(res(pos,6))/F_V_NOM);

%% Amortecimento sem rotor, da oscilacao livre ---------------------------------
% Cruzamentos pelo repouso, meio periodo a meio periodo. Aqui interessa o
% DECAIMENTO, nao o periodo.
S = load(acha_dados(DIR_DADOS, ARQ_LIVRE));
M = S.simout_tail;
tl = M(:,1);  yl = M(:,3);
rep = mean(yl(tl >= max(tl) - 9.5));
d = yl - rep;

ic = find(d(1:end-1).*d(2:end) < 0);
tc = tl(ic) - d(ic).*(tl(ic+1)-tl(ic))./(d(ic+1)-d(ic));

amp = []; tpk = [];
for k = 1:(length(tc)-1)
    seg = (tl >= tc(k)) & (tl <= tc(k+1));
    if sum(seg) < 3, continue; end
    ds = d(seg);  ts = tl(seg);
    [~,ip] = max(abs(ds));
    amp(end+1,1) = abs(ds(ip));   %#ok<SAGROW>
    tpk(end+1,1) = ts(ip);        %#ok<SAGROW>
end

% Decaimento por pares CONSECUTIVOS de picos, dentro da mesma soltada
sig = [];
for k = 1:(length(amp)-1)
    if amp(k+1) < amp(k) && amp(k+1) >= 0.20
        sig(end+1,1) = log(amp(k)/amp(k+1)) / (tpk(k+1)-tpk(k));   %#ok<SAGROW>
    end
end

if length(sig) >= 3
    sigma_livre = mean(sig);
    fprintf('\n=== Oscilacao livre (motores desligados) ===\n');
    fprintf('  pares de picos usados: %d\n', length(sig));
    fprintf('  sigma = %.4f +- %.4f 1/s   f_v = %.3e N.m.s/rad\n', ...
            sigma_livre, std(sig), 2*sigma_livre*I_EF);
    fprintf('  zeta  = %.3f  (contra %.3f com o rotor girando)\n', ...
            sigma_livre/mean(res(pos,2)), mean(res(pos,3)));
    fprintf('  razao de amortecimento com/sem rotor: %.1fx\n', ...
            mean(res(pos,6))/(2*sigma_livre*I_EF));
    fprintf('  sigma entre %.3f e %.3f 1/s\n', ...
            min(sig), max(sig));
end

%% Parametros para o trms_params -----------------------------------------------
fprintf('\n===== PARAMETROS DINAMICOS IDENTIFICADOS =====\n');
fprintf('  f_vphi_rotor = %.4e;  %% N.m.s/rad -- com rotor de cauda ativo\n', ...
        mean(res(pos,6)));
if exist('sigma_livre','var')
    fprintf('  f_vphi_livre = %.4e;  %% N.m.s/rad -- motores desligados\n', ...
            2*sigma_livre*I_EF);
end
fprintf('  tau_lento    = %.1f;        %% s -- modo lento\n', ...
        mean(res(pos,4)));

arq_res = fullfile(P.resultados, 'dinamica_yaw_resultados.mat');
save(arq_res, 'ENSAIOS', 'res', 'PAR', 'X', 'Y', 'I_EF', 'T_DEGRAU');
fprintf('\nResultados salvos em %s\n', arq_res);

%% Funcao do modelo ------------------------------------------------------------
function y = modelo(p, x)
    y = p(1) + p(2)*exp(-x/p(3)) + p(4)*exp(-p(5)*x).*cos(p(6)*x + p(7));
end
