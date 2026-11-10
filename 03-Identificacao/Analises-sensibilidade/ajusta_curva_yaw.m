% ==============================================================================
% ajusta_curva_yaw.m
%
% Ajusta os parametros da equacao de equilibrio estatico do eixo de guinada
% aos ensaios de patamar longo, usando a rigidez medida por oscilacao livre
% para quebrar a degenerescencia de escala.
%
% EQUACAO DE EQUILIBRIO (eq. 29, termo estatico):
%     CT_t * omega_t^2(u) * l_t * cos(psi) = C_c(phi) * (phi - phi_0)
%
% ESTRUTURA DO AJUSTE:
%
%   Ramo positivo. Os quatro pontos seguem lei de potencia limpa
%   phi = A*u^n. Com C_c+ medido independentemente pela oscilacao livre, o
%   torque em cada nivel sai por C_c+*(phi-phi_0), o que entrega
%   CT_t+*omega_t^2(u) em unidades absolutas -- nao apenas a razao CT_t/C_c.
%
%   Ramo negativo. NAO segue lei de potencia. O que se calcula aqui e' a
%   rigidez relativa C_c(phi)/C_c+, como caracterizacao. O ramo negativo
%   nao reproduziu entre sessoes e esta fora da validacao quantitativa.
%
% POR QUE A DEGENERESCENCIA SE QUEBRA AQUI E NAO NO PITCH:
%   A curva estatica sozinha so da a razao CT_t/C_c -- a condicao de
%   equilibrio e' invariante a escalar os dois pelo mesmo fator, exatamente
%   como G_z/G_y/CT_m_pos no pitch. A oscilacao livre mede C_c sem envolver
%   o rotor (CT_t nao aparece na equacao de oscilacao livre), fornecendo a
%   escala que falta.
%
% INERCIA EFETIVA:
%   O lado esquerdo da eq. (29) do Tastemirov traz (I_phi + I_c*cos(psi)^2)
%   multiplicando ddphi, e nao I_phi sozinho. Com a arfagem em repouso a -38
%   graus, I_eff = 3,45 * I_phi. Toda grandeza derivada de omega_n (C_c,
%   tau_at, CT_t*omega_t^2) escala com a inercia. Razoes, expoentes e phi_0
%   nao, porque neles o C_c se cancela.
%
% DADOS DE ENTRADA: os NOVE ensaios de patamar de 80 s (10 s em zero, 80 s
%   no nivel) e o ensaio de oscilacao livre. Ensaios com patamar de 18 s
%   medem estado transitorio (vies de ate 18% verificado) e NAO entram.
%
% ==============================================================================

clear; close all; clc;

%% Configuracao ----------------------------------------------------------------
P         = caminhos_dados();
DIR_DADOS = P.yaw;        % Coleta 2 (procura tambem em subpastas)
T_MEDIA   = 9.5;          % janela de media no fim do patamar [s] (1 periodo)
L_T       = 0.275;        % braco do rotor de cauda [m] (nominal Tastemirov)
C_C_NOM   = 9.87e-3;      % C_c nominal do Tastemirov, para comparacao

% Inercia efetiva de guinada
I_PHI    = 2.1117e-2;     % parcela fixa da inercia de guinada [kg.m^2]
I_C      = 8.3286e-2;     % inercia da viga transversal [kg.m^2]
PSI_REST = -0.663;        % arfagem em repouso [rad] -- -38 graus, transferidor
                          % usar -0.5369 para o valor devolvido pelo modelo
I_EFF    = I_PHI + I_C*cos(PSI_REST)^2;
COS_PSI  = cos(PSI_REST); % escala o torque de cauda na eq. de equilibrio

fprintf('I_eff = %.4e kg.m^2  (%.2fx I_phi, psi = %.1f graus)\n\n', ...
        I_EFF, I_EFF/I_PHI, PSI_REST*180/pi);

% Ensaios de patamar longo: {arquivo, tensao nominal}
ENSAIOS = { ...
    'out_n075.mat',  -0.750; ...
    'out_n0675.mat', -0.675; ...
    'out_n05.mat',   -0.500; ...
    'out_n0375.mat', -0.375; ...
    'out_n0.25.mat', -0.250; ...
    'out_025.mat',    0.250; ...
    'out_050.mat',    0.500; ...
    'out_075.mat',    0.750; ...
    'out_1.mat',      1.000  ...
};

ARQ_LIVRE = 'out_solto.mat';   % ensaio de oscilacao livre

%% 1. Leitura dos equilibrios --------------------------------------------------
n = size(ENSAIOS, 1);
u   = zeros(n,1);
phi = zeros(n,1);
sd  = zeros(n,1);

fprintf('=== Equilibrios (media dos ultimos %.1f s) ===\n', T_MEDIA);
for k = 1:n
    S = load(acha_dados(DIR_DADOS, ENSAIOS{k,1}));
    M = S.simout_tail;
    t = M(:,1);  y = M(:,3);

    m = (t >= max(t) - T_MEDIA);
    u(k)   = ENSAIOS{k,2};
    phi(k) = mean(y(m));
    sd(k)  = std(y(m));

    fprintf('  u = %+.3f V   phi = %+.4f rad (%+7.1f deg)   desvio = %.4f\n', ...
            u(k), phi(k), phi(k)*180/pi, sd(k));
    if sd(k) > 0.02
        fprintf('    AVISO: desvio alto\n');
    end
end

pos = u > 0;
neg = u < 0;

%% 2. Oscilacao livre: rigidez por meio periodo --------------------------------
% Sem rotor no circuito, CT_t nao entra. Cada meio periodo pertence a um so
% lado da curva -- por isso NAO se usa periodo completo: ele misturaria o
% ramo mole com o rigido e entregaria uma media sem significado fisico.
% A conversao usa I_EFF: C_c = I_eff * omega_n^2.

S = load(acha_dados(DIR_DADOS, ARQ_LIVRE));
M = S.simout_tail;
tl = M(:,1);  yl = M(:,3);

phi_rep = mean(yl(tl >= max(tl) - T_MEDIA));   % repouso ao fim do ensaio
d = yl - phi_rep;

% Cruzamentos pelo repouso, com interpolacao linear
ic = find(d(1:end-1) .* d(2:end) < 0);
tc = tl(ic) - d(ic) .* (tl(ic+1) - tl(ic)) ./ (d(ic+1) - d(ic));

amp_l = []; Cc_l = []; lado_l = [];
for k = 1:(length(tc)-1)
    seg = (tl >= tc(k)) & (tl <= tc(k+1));
    if sum(seg) < 3, continue; end

    ds = d(seg);
    [~, ip] = max(abs(ds));
    pico = ds(ip);

    T_meio = tc(k+1) - tc(k);
    wn = 2*pi / (2*T_meio);

    amp_l(end+1,1)  = pico;                 %#ok<SAGROW>
    Cc_l(end+1,1)   = I_EFF * wn^2;         %#ok<SAGROW>
    lado_l(end+1,1) = sign(pico);           %#ok<SAGROW>
end

% Atrito domina nas amplitudes pequenas e encurta o meio periodo, imitando
% enrijecimento. Descartar os ciclos de amplitude baixa.
AMP_MIN = 0.25;
val = abs(amp_l) >= AMP_MIN;

fprintf('\n=== Oscilacao livre: rigidez por meio periodo ===\n');
for k = 1:length(amp_l)
    marca = '';
    if ~val(k), marca = '  (descartado: amplitude baixa, atrito domina)'; end
    fprintf('  lado %s  amp = %+.3f rad   C_c = %.3e N.m/rad%s\n', ...
            ternario(lado_l(k) > 0, 'POS', 'NEG'), amp_l(k), Cc_l(k), marca);
end

Cc_pos = mean(Cc_l(val & lado_l > 0));
fprintf('\n  C_c+ (media, lado positivo) = %.3e N.m/rad\n', Cc_pos);
fprintf('  razao para o nominal do Tastemirov = %.2f\n', Cc_pos / C_C_NOM);

%% 3. phi_0 e atrito de ruptura, a partir da assimetria de u* ------------------
% phi_0 e' o angulo de torque nulo do cabo, lido na escala do encoder -- o
% mesmo phi_0 que aparece em (phi - phi_0) nas secoes 4 e 5 e no modelo.
%
% METODO: com o torque do cabo -C_c*(phi - phi_0), na posicao de repouso
% (phi = 0) o cabo ja exerce +C_c*phi_0, que o atrito segura. Na ruptura:
%     tau(u*+) = tau_at - C_c*phi_0     (cabo ajuda o sentido + se phi_0 > 0)
%     tau(u*-) = tau_at + C_c*phi_0
% Duas rupturas medidas, duas equacoes, duas incognitas. A diferenca isola a
% pre-carga; a media isola o atrito de ruptura.
%
% A validacao dinamica nao depende deste valor: phi_0 e' estruturalmente
% nao observavel nela.
%
% Sensibilidade do ramo negativo a phi_0 (verificado nos dados):
%   phi_0 = 0       -> razao de empuxo 0,73   rigidez relativa 1,00 .. 0,36
%   phi_0 = +0,030  -> razao de empuxo 1,03   rigidez relativa 1,00 .. 0,48
%
% O calculo precisa da lei de empuxo, que por sua vez precisa de phi_0.
% Resolve-se por iteracao de ponto fixo.
%
% ROBUSTEZ: fixando a razao de empuxo entre 0,6 e 1,0 e o expoente entre 1,0
% e 2,0, phi_0 fica entre +0,002 e +0,061 rad -- sempre positivo, sempre
% abaixo de 3,5 graus.
%
% LIMITACAO: supoe atrito de ruptura igual nos dois sentidos. Atrito
% assimetrico produziria o mesmo efeito. Tratar como ordem de grandeza.

U_STAR_POS =  0.106;   % tensao de ruptura, sentido positivo [V]
U_STAR_NEG = -0.180;   % tensao de ruptura, sentido negativo [V]

phi_0 = 0;
for it = 1:100
    php_i = phi(pos) - phi_0;
    cf_i  = polyfit(log(u(pos)), log(php_i), 1);
    n_i   = cf_i(1);
    A_i   = exp(cf_i(2));

    un_i  = abs(u(neg));
    phn_i = abs(phi(neg) - phi_0);
    [~, j] = min(un_i);
    r_i = phn_i(j) / (A_i * un_i(j)^n_i);

    tau_p = Cc_pos * A_i * abs(U_STAR_POS)^n_i;         % torque na ruptura +
    tau_n = r_i * Cc_pos * A_i * abs(U_STAR_NEG)^n_i;   % torque na ruptura -

    phi_0_novo = (tau_n - tau_p) / (2 * Cc_pos);
    tau_at     = (tau_p + tau_n) / 2;

    conv = abs(phi_0_novo - phi_0) < 1e-7;
    phi_0 = phi_0_novo;
    if conv, break; end
end

fprintf('\n=== phi_0 e atrito de ruptura (assimetria de u*) ===\n');
fprintf('  convergiu em %d iteracoes\n', it);
fprintf('  phi_0  = %+.5f rad (%+.2f deg)\n', phi_0, phi_0*180/pi);
fprintf('  tau_at = %.4e N.m  (atrito de ruptura)\n', tau_at);
fprintf('  repouso da oscilacao livre: %+.4f rad\n', phi_rep);

%% 4. Ramo positivo: lei de potencia e torque absoluto -------------------------
% Ajuste log-log de phi - phi_0 = A*u^n
up = u(pos);  php = phi(pos) - phi_0;
cf = polyfit(log(up), log(php), 1);
n_exp = cf(1);
A_pot = exp(cf(2));

fprintf('\n=== Ramo positivo ===\n');
fprintf('  phi - phi_0 = %.4f * u^%.3f\n', A_pot, n_exp);

% Torque de cauda em unidades absolutas, usando C_c+ da oscilacao livre
tau_t  = Cc_pos * php;
CT_om2 = tau_t ./ (L_T * COS_PSI);    % = CT_t+ * omega_t^2(u)

fprintf('\n  u [V]   phi-phi_0 [rad]   tau [N.m]   CT_t*omega_t^2 [N]\n');
for k = 1:length(up)
    fprintf('  %+.3f     %+.4f         %.4e     %.4e\n', ...
            up(k), php(k), tau_t(k), CT_om2(k));
end

%% 5. Ramo negativo: rigidez relativa ------------------------------------------
% Referencia de mola simetrica: extrapola o ajuste positivo e aplica a razao
% de empuxo medida no nivel mais baixo, onde a mola ainda e' simetrica.
un = abs(u(neg));  phn = abs(phi(neg) - phi_0);

[~, imin] = min(un);
razao_empuxo = phn(imin) / (A_pot * un(imin)^n_exp);

phi_sim = razao_empuxo * A_pot * un.^n_exp;   % esperado se a mola fosse linear
excesso = phn ./ phi_sim;
rig_rel = 1 ./ excesso;

fprintf('\n=== Ramo negativo: amolecimento ===\n');
fprintf('  razao de empuxo em %.3f V: %.3f\n', ...
        un(imin), razao_empuxo);
fprintf('\n  u [V]    phi [rad]   esperado    excesso   C_c-/C_c+\n');
for k = 1:length(un)
    fprintf('  %.3f     %.4f      %.4f      %.2f       %.2f\n', ...
            un(k), phn(k), phi_sim(k), excesso(k), rig_rel(k));
end

fprintf('\n  C_c- em funcao da deflexao [N.m/rad]:\n');
for k = 1:length(un)
    fprintf('    phi = %+.3f rad  ->  C_c = %.3e\n', -phn(k), rig_rel(k)*Cc_pos);
end

%% 6. Figuras ------------------------------------------------------------------
figure('Color','w','Position',[100 100 900 700]);

subplot(2,2,1);
plot(u, phi, 'ko-', 'MarkerFaceColor','k'); grid on;
xlabel('u_t [V]'); ylabel('\phi_{eq} [rad]');
title('Curva de equilibrio estatico');

subplot(2,2,2);
uu = linspace(0.2, 1.05, 100);
loglog(up, php, 'ko', 'MarkerFaceColor','k'); hold on;
loglog(uu, A_pot*uu.^n_exp, 'r-');
loglog(un, phn, 'bs', 'MarkerFaceColor','b');
grid on; xlabel('|u_t| [V]'); ylabel('|\phi - \phi_0| [rad]');
legend('positivo','ajuste potencia','negativo','Location','NorthWest');
title(sprintf('Lei de potencia: n = %.2f', n_exp));

subplot(2,2,3);
plot(-phn, rig_rel*Cc_pos, 'bs-', 'MarkerFaceColor','b'); hold on;
plot(abs(amp_l(val & lado_l<0))*-1, Cc_l(val & lado_l<0), 'rv', ...
     'MarkerFaceColor','r');
plot([-max(phn) 0], [Cc_pos Cc_pos], 'k--');
grid on; xlabel('\phi [rad]'); ylabel('C_c [N.m/rad]');
legend('curva estatica','oscilacao livre','C_c+ (linear)','Location','Best');
title('Rigidez do cabo vs deflexao');

subplot(2,2,4);
plot(amp_l(val), Cc_l(val), 'o', 'MarkerFaceColor','auto'); grid on;
xlabel('amplitude [rad]'); ylabel('C_c [N.m/rad]');
title('Oscilacao livre: rigidez por meio periodo');

%% 7. Resumo dos parametros identificados --------------------------------------
fprintf('\n===== RESUMO =====\n');
fprintf('  I_eff    = %.4e;   %% kg.m^2 -- psi = %.1f graus\n', I_EFF, PSI_REST*180/pi);
fprintf('  C_c_pos  = %.4e;   %% N.m/rad -- oscilacao livre, lado positivo\n', Cc_pos);
fprintf('  phi_0    = %+.5f;    %% rad -- assimetria de u*\n', phi_0);
fprintf('  tau_at   = %.4e;   %% N.m -- atrito de ruptura em guinada\n', tau_at);
fprintf('  A_pot    = %.4f;      %% phi - phi_0 = A*u^n, ramo positivo\n', A_pot);
fprintf('  n_exp    = %.3f;\n', n_exp);
fprintf('  razao_CT = %.3f;       %% CT_t-/CT_t+ pelo nivel de menor deflexao\n', razao_empuxo);
fprintf('\n  cos(psi) = %.4f aplicado no torque de cauda.\n', COS_PSI);

%% Funcao auxiliar -------------------------------------------------------------
function s = ternario(cond, a, b)
    if cond, s = a; else, s = b; end
end
