function R = compara_pid_c3(pasta)
%COMPARA_PID_C3 Gemeo x bancada nos ensaios de PID de arfagem da sessao c3.
%
%   R = compara_pid_c3          % pasta P.c3 do caminhos_dados
%   R = compara_pid_c3(pasta)
%
%   Para cada ensaio, simula o gemeo com os mesmos ganhos, referencia e
%   perturbacao, amostra a saida nos instantes da bancada (10 Hz),
%   quantiza psi e phi com a resolucao do encoder e compara:
%     - sobressinal, instante de pico, subida 10-90%, acomodacao 5% e 2%
%     - u1 de regime (mediana de 30 a 50 s) e contagens de psi em regime
%     - erro relativo de psi de 10 a 50 s
%     - Teste 6: contagens de psi antes/depois do degrau de u2 e deflexao
%       do yaw
%   Imprime tambem o piso de repetibilidade da bancada (4/6/8 x primeiros
%   50 s do Teste 6) e o teste de direcao (4/6/8 -> 5/8/10).
%
%   Colunas do simout_pitch da bancada (10 Hz):
%     [t, u1 (antes da saturacao), ref, psi, phi]   (+ u2 no Teste 6)
%
%   Pre-requisitos: trms_params com psi_0 derivado e x0(1) = psi_0, e o
%   trms_model_pid_bancada com o Controller discreto equivalente ao da
%   bancada.
%
%   E funcao, e nao script, para isolar as variaveis locais do workspace
%   base, onde o trms_params e carregado.
 
P = caminhos_dados();
if nargin < 1, pasta = P.c3; end
 
% --- Configuracao ---------------------------------------------------------
% Modelo e nomes de variaveis/saidas do .slx ficam no simula_trms.m
% (trms_model_pid_bancada, modo 1 = arfagem em malha fechada).

Q         = 2*pi/2048;  % resolucao dos encoders [rad]
T_FIM     = 100;        % [s] duracao simulada
JAN_PASSO = 40;         % [s] janela apos o degrau para os indices
                        %     (termina antes do u2 do Teste 6)
JAN_REG   = [30 50];    % [s] janela de regime
JAN_ERRO  = [10 50];    % [s] janela do erro relativo de psi
DIR_FIG   = fullfile(P.resultados, 'figuras_c3');
 
ens = struct( ...
    'arquivo', {'out_pitch_pid_04_c3.mat', ...
                'out_pitch_pid_04_original_c3.mat', ...
                'out_pitch_pid_com_yaw_c3.mat'}, ...
    'ganhos',  {[4 6 8], [5 8 10], [4 6 8]}, ...
    'rotulo',  {'4/6/8', '5/8/10', 'Teste 6'});
 
% --- Parametros da planta no workspace base --------------------------------
% O InitFcn esta vazio: o trms_params precisa ser carregado aqui. As
% variaveis de cada ensaio vao por setVariable, que tem prioridade.
evalin('base', 'trms_params;');
confere_params('identificado');   % C_c, f_vphi, f_s, x0 etc. usados pelo gemeo
 
R = struct([]);
 
for k = 1:numel(ens)
    E = ens(k);
    B = le_bancada(acha_dados(pasta, E.arquivo));
 
    % Degrau de referencia, lido do proprio registro
    i_deg = find(B.ref > 0.5*B.ref(end), 1);
    t_deg = round(B.t(i_deg)*1e3)/1e3;
    ref   = B.ref(end);
 
    % No instante do degrau so o proporcional atua: confere os ganhos
    kp_dado = B.u1(i_deg)/ref;
    if abs(kp_dado - E.ganhos(1)) > 0.05*E.ganhos(1)
        warning('compara_pid_c3:ganho', ...
            '%s: o u1 no degrau indica Kp = %.2f, e nao %.2f.', ...
            E.rotulo, kp_dado, E.ganhos(1));
    end
 
    % Perturbacao em u2 (Teste 6), tambem lida do registro
    tem_u2 = any(B.u2 ~= 0);
    if tem_u2
        i2 = find(B.u2 > 0.5*B.u2(end), 1);
        t2 = round(B.t(i2)*1e3)/1e3;
        a2 = B.u2(end);
        % Ponto extra 1 us antes: degrau exato com ou sem interpolacao
        % ligada no From Workspace
        u2_ts = timeseries([0; 0; a2; a2], [0; t2 - 1e-6; t2; T_FIM]);
    else
        t2 = NaN;
        a2 = 0;
        u2_ts = timeseries([0; 0], [0; T_FIM]);
    end
 
    % --- Simulacao ---------------------------------------------------------
    opc = struct();
    opc.T_fim   = T_FIM;
    opc.modo    = 1;                  % arfagem fechada, yaw aberto
    opc.mascara = ones(6,1);          % yaw livre, como na bancada
    opc.u_m     = timeseries([0; 0], [0; T_FIM]);
    opc.u_t     = u2_ts;
    opc.pid     = struct('kp', E.ganhos(1), 'ki', E.ganhos(2), 'kd', E.ganhos(3), ...
                         'ref', ref, 't_degrau', t_deg);

    fprintf('Simulando %s ...\n', E.rotulo);
    S = simula_trms(opc);
    if isempty(S.u1)
        error('compara_pid_c3:u1', 'O modelo nao loga u1_pid (ver simula_trms.m).');
    end
    ts = S.t_psi;  psi_s = S.psi;
    tp = S.t_phi;  phi_s = S.phi;
    tu = S.t_u1;   u1_s  = S.u1;

    % Confere se o u2 pedido chegou a entrada da planta (u_planta = saida do
    % trms_sel_entrada). Ignora 1,5 ms em torno do degrau.
    if ~isempty(S.u_planta)
        tc = S.t_up;  u2_s = S.u_planta;
        if tem_u2
            u2_esp = a2*(tc >= t2);
            longe  = abs(tc - t2) > 1.5e-3;
        else
            u2_esp = zeros(size(tc));
            longe  = true(size(tc));
        end
        if numel(tc) < 10 || max(abs(u2_s(longe) - u2_esp(longe))) > 1e-6
            error('compara_pid_c3:u2', ...
                '%s: a entrada do tail (%d amostras) nao corresponde ao u2 do ensaio.', ...
                E.rotulo, numel(tc));
        end
    else
        warning('compara_pid_c3:sem_u2', ...
            '%s: u_planta nao esta logado.', E.rotulo);
    end
 
    % Referencial dos encoders: zero no repouso inicial, como na bancada.
    % Vale tanto se psi_sim sair no angulo fisico quanto depois do Bias.
    psi_s = psi_s - psi_s(1);
    phi_s = phi_s - phi_s(1);
 
    % No Teste 6, o yaw tem de se mover depois do degrau de u2
    if tem_u2
        antes  = tp >= t2 - 9.5 & tp < t2;
        depois = tp >= t2 + 10;
        if abs(mean(phi_s(depois)) - mean(phi_s(antes))) < 10*Q
            error('compara_pid_c3:yaw', ...
                '%s: o yaw do gemeo nao respondeu ao degrau de u2.', E.rotulo);
        end
    end
 
    % Amostragem nos instantes da bancada e quantizacao do encoder
    M.t   = B.t;
    M.psi = Q*round(interp1(ts, psi_s, B.t, 'nearest', 'extrap')/Q);
    M.phi = Q*round(interp1(tp, phi_s, B.t, 'nearest', 'extrap')/Q);
    M.u1  = interp1(tu, u1_s, B.t, 'nearest', 'extrap');
 
    % Checagem da replica do controlador: ate t_deg + 0,1 s a viga da
    % bancada nao se moveu, entao u1 so depende do PID
    i1 = find(abs(B.t - (t_deg + 0.1)) < 1e-6, 1);
    fprintf('  u1 em %.1f s e %.1f s: bancada %7.3f / %7.3f | gemeo %7.3f / %7.3f\n', ...
        t_deg, t_deg + 0.1, B.u1(i_deg), B.u1(i1), M.u1(i_deg), M.u1(i1));
 
    % --- Indices -----------------------------------------------------------
    R(k).rotulo = E.rotulo;
    R(k).ganhos = E.ganhos;
    R(k).ref    = ref;
    R(k).t_deg  = t_deg;
    R(k).t2     = t2;
    R(k).a2     = a2;
    R(k).B      = B;
    R(k).M      = M;
    R(k).Ib     = indices(B, t_deg, ref, JAN_PASSO, JAN_REG, Q);
    R(k).Im     = indices(M, t_deg, ref, JAN_PASSO, JAN_REG, Q);
    R(k).J_psi  = erro_relativo(B.psi, M.psi, ...
                      B.t >= JAN_ERRO(1) & B.t < JAN_ERRO(2));
    if tem_u2
        R(k).Pb = perturbacao(B, t2, Q);
        R(k).Pm = perturbacao(M, t2, Q);
    else
        R(k).Pb = [];
        R(k).Pm = [];
    end
end
 
% --- Tabela ----------------------------------------------------------------
fprintf('\n%-8s %-8s | %7s %7s %7s %7s %7s | %7s | %-10s | %7s\n', ...
    'ensaio', 'fonte', 'sobr%', 'pico s', 'sub s', 'ac5 s', 'ac2 s', ...
    'u1 reg', 'contagens', 'J psi%');
fprintf('%s\n', repmat('-', 1, 96));
for k = 1:numel(R)
    imprime_linha(R(k).rotulo, 'bancada', R(k).Ib, NaN);
    imprime_linha('',          'gemeo',   R(k).Im, R(k).J_psi);
end
 
Ib1 = R(1).Ib;  Ib3 = R(3).Ib;
fprintf(['\nPiso de repetibilidade (bancada, 4/6/8 x Teste 6 ate o u2): ' ...
         'sobressinal %.1f pp | pico %.1f s | u1 de regime %.3f V\n'], ...
    abs(Ib1.sobressinal - Ib3.sobressinal), abs(Ib1.t_pico - Ib3.t_pico), ...
    abs(Ib1.u1_regime - Ib3.u1_regime));
 
fprintf('Direcao 4/6/8 -> 5/8/10: bancada %+.1f pp e %+.1f s | gemeo %+.1f pp e %+.1f s\n', ...
    R(2).Ib.sobressinal - R(1).Ib.sobressinal, R(2).Ib.t_pico - R(1).Ib.t_pico, ...
    R(2).Im.sobressinal - R(1).Im.sobressinal, R(2).Im.t_pico - R(1).Im.t_pico);
 
fprintf('Yaw pela reacao do rotor principal (4/6/8, u2 = 0): bancada [%.3f, %.3f] | gemeo [%.3f, %.3f] rad\n', ...
    R(1).Ib.phi_faixa, R(1).Im.phi_faixa);
 
if ~isempty(R(3).Pb)
    fprintf('\nTeste 6 (u2 = %.2f V em %.1f s):\n', R(3).a2, R(3).t2);
    fprintf('  contagens de psi antes %s, depois %s na bancada | antes %s, depois %s no gemeo\n', ...
        mat2str(R(3).Pb.cont_pre), mat2str(R(3).Pb.cont_pos), ...
        mat2str(R(3).Pm.cont_pre), mat2str(R(3).Pm.cont_pos));
    fprintf('  deflexao do yaw (media de t2+10 s ao fim menos os 9,5 s antes): bancada %.3f | gemeo %.3f rad\n', ...
        R(3).Pb.dphi, R(3).Pm.dphi);
end

% Conferencia do quantizador: com ele ativo, o psi do gemeo alterna entre
% duas contagens antes do u2 (130 e 131), como na bancada. Uma unica
% contagem indica o Quantizer em Comment Through.
if ~isempty(R(3).Pm) && R(3).Pm.cont_pre(1) == R(3).Pm.cont_pre(2)
    warning('compara_pid_c3:quantizador', ...
        'No gemeo, psi ficou numa unica contagem antes do u2 (%d).', ...
        R(3).Pm.cont_pre(1));
end
 
% --- Figuras ---------------------------------------------------------------
if ~exist(DIR_FIG, 'dir'), mkdir(DIR_FIG); end
cor_b = [0 0 0];
cor_m = [0.85 0.20 0.10];
 
f1 = figure('Name', 'PID c3 - Teste 5', 'Color', 'w', 'Position', [100 100 1000 800]);
tl = tiledlayout(f1, 3, 2, 'TileSpacing', 'compact');
for k = 1:2
    B = R(k).B;  M = R(k).M;
 
    ax = nexttile(tl, k);
    h1 = plot(ax, B.t, B.psi, 'Color', cor_b);  hold(ax, 'on');
    h2 = plot(ax, M.t, M.psi, 'Color', cor_m);
    yline(ax, R(k).ref, ':');
    xlim(ax, [5 50]);  grid(ax, 'on');
    title(ax, sprintf('\\psi, ganhos %s', R(k).rotulo));
    ylabel(ax, '\psi (rad, encoder)');
    if k == 1
        legend(ax, [h1 h2], {'bancada', 'gemeo'}, 'Location', 'southeast');
    end
 
    ax = nexttile(tl, k + 2);
    plot(ax, B.t, B.u1, 'Color', cor_b);  hold(ax, 'on');
    plot(ax, M.t, M.u1, 'Color', cor_m);
    xlim(ax, [5 50]);  ylim(ax, [-3 4]);  grid(ax, 'on');
    ylabel(ax, 'u_1 (V)');
    title(ax, 'u_1 antes da saturacao (chute derivativo fora da escala)');
 
    ax = nexttile(tl, k + 4);
    plot(ax, B.t, B.phi, 'Color', cor_b);  hold(ax, 'on');
    plot(ax, M.t, M.phi, 'Color', cor_m);
    xlim(ax, [0 100]);  grid(ax, 'on');
    ylabel(ax, '\phi (rad, encoder)');  xlabel(ax, 't (s)');
    title(ax, '\phi com u_2 = 0 (reacao do rotor principal)');
end
exportgraphics(f1, fullfile(DIR_FIG, 'pid_c3_teste5.png'), 'Resolution', 200);
 
if ~isempty(R(3).Pb)
    B = R(3).B;  M = R(3).M;
    f2 = figure('Name', 'PID c3 - Teste 6', 'Color', 'w', 'Position', [150 150 900 650]);
    tl = tiledlayout(f2, 2, 1, 'TileSpacing', 'compact');
 
    ax = nexttile(tl);
    h1 = stairs(ax, B.t, B.psi/Q, 'Color', cor_b);  hold(ax, 'on');
    h2 = stairs(ax, M.t, M.psi/Q, 'Color', cor_m);
    xline(ax, R(3).t2, '--');
    xlim(ax, [40 100]);  grid(ax, 'on');
    ylabel(ax, '\psi (contagens)');
    title(ax, sprintf('Teste 6: \\psi em contagens, degrau de u_2 = %.2f V', R(3).a2));
    legend(ax, [h1 h2], {'bancada', 'gemeo'}, 'Location', 'best');
 
    ax = nexttile(tl);
    plot(ax, B.t, B.phi, 'Color', cor_b);  hold(ax, 'on');
    plot(ax, M.t, M.phi, 'Color', cor_m);
    xline(ax, R(3).t2, '--');
    xlim(ax, [0 100]);  grid(ax, 'on');
    ylabel(ax, '\phi (rad, encoder)');  xlabel(ax, 't (s)');
    title(ax, 'Teste 6: \phi');
    exportgraphics(f2, fullfile(DIR_FIG, 'pid_c3_teste6.png'), 'Resolution', 200);
end
 
save(fullfile(P.resultados, 'compara_pid_c3_resultados.mat'), 'R');
fprintf('\nFiguras em %s/ e resultados em compara_pid_c3_resultados.mat\n', DIR_FIG);
end
 
 
% =========================================================================
function B = le_bancada(arquivo)
%LE_BANCADA Le o simout_pitch de um ensaio de malha fechada da bancada.
S = load(arquivo);
if ~isfield(S, 'simout_pitch')
    error('compara_pid_c3:arquivo', '%s nao tem simout_pitch.', arquivo);
end
X = S.simout_pitch;
B.t   = X(:,1);
B.u1  = X(:,2);
B.ref = X(:,3);
B.psi = X(:,4);
B.phi = X(:,5);
if size(X, 2) >= 6
    B.u2 = X(:,6);
else
    B.u2 = zeros(size(B.t));
end
end
 
 
function I = indices(S, t_deg, ref, jan_passo, jan_reg, Q)
%INDICES Indices da resposta ao degrau e de regime, em amostras de 10 Hz.
s = S.t - t_deg;
m = s >= 0 & s < jan_passo;
y = S.psi(m);
s = s(m);
 
[I.pico, ip]  = max(y);
I.t_pico      = s(ip);
I.sobressinal = 100*(I.pico - ref)/ref;
 
i10 = find(y >= 0.1*ref, 1);
i90 = find(y >= 0.9*ref, 1);
if isempty(i10) || isempty(i90)
    I.subida = NaN;
else
    I.subida = s(i90) - s(i10);
end
I.acom5 = acomodacao(s, y, ref, 0.05);
I.acom2 = acomodacao(s, y, ref, 0.02);
 
r = S.t >= jan_reg(1) & S.t < jan_reg(2);
I.u1_regime = median(S.u1(r));
I.contagens = unique(round(S.psi(r)/Q)).';
I.phi_faixa = [min(S.phi(m)) max(S.phi(m))];
end
 
 
function ta = acomodacao(s, y, ref, banda)
%ACOMODACAO Primeiro instante a partir do qual psi fica na faixa +-banda*ref.
fora = find(abs(y - ref) > banda*abs(ref));
if isempty(fora)
    ta = 0;
elseif fora(end) == numel(y)
    ta = NaN;                       % nao acomodou dentro da janela
else
    ta = s(fora(end) + 1);
end
end
 
 
function J = erro_relativo(yb, ym, m)
%ERRO_RELATIVO Erro quadratico do gemeo normalizado pela variancia da
%   bancada na janela m, em %.
e = ym(m) - yb(m);
J = 100*sum(e.^2)/sum((yb(m) - mean(yb(m))).^2);
end
 
 
function P = perturbacao(S, t2, Q)
%PERTURBACAO Efeito do degrau de u2: contagens de psi e deflexao do yaw.
pre = S.t >= t2 - 9.5 & S.t < t2;
pos = S.t >= t2;
fim = S.t >= t2 + 10;
c_pre = round(S.psi(pre)/Q);
c_pos = round(S.psi(pos)/Q);
P.cont_pre = [min(c_pre) max(c_pre)];
P.cont_pos = [min(c_pos) max(c_pos)];
P.dphi     = mean(S.phi(fim)) - mean(S.phi(pre));
end
 
 
function imprime_linha(rotulo, fonte, I, J)
%IMPRIME_LINHA Uma linha da tabela de indices.
fprintf('%-8s %-8s | %7.1f %7.1f %7.1f %7.1f %7.1f | %7.3f | %-10s | %7.1f\n', ...
    rotulo, fonte, I.sobressinal, I.t_pico, I.subida, I.acom5, I.acom2, ...
    I.u1_regime, mat2str(I.contagens), J);
end
 
