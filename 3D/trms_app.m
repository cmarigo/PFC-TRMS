function trms_app
%TRMS_APP Gemeo digital do TRMS: projeto do PID de arfagem, simulacao e analise.
%
%   TRMS_APP abre a janela. O aluno informa os ganhos do PID de arfagem, a
%   referencia e a perturbacao em u2, simula, e:
%     - na aba SIMULACAO, ve a animacao em tres vistas 3D (isometrica,
%       lateral e superior), sincronizada com os graficos de psi e phi;
%     - na aba ANALISE, compara a execucao com as anteriores (psi, u1 e
%       phi sobrepostos) e le as metricas de desempenho.
%
%   ESCOPO: controlador de ARFAGEM apenas. A guinada fica em malha aberta.
%
%   UNIDADES: angulos em rad, como no roteiro (referencia de 0 para 0.4
%   rad). As vistas mostram tambem o valor em graus, entre parenteses.
%
%   LAYOUT
%     Barra lateral fixa: cabecalho, configuracao e Simular. Fica fora das
%       abas, entao da para simular de qualquer uma. Na aba Simulacao o
%       botao tambem toca a animacao ao fim; na aba Analise so simula.
%     Play/Stop e o tempo ficam logo acima do Simular, so na aba
%       Simulacao. Play sempre comeca do inicio; Stop para no quadro atual.
%     Erros aparecem em texto vermelho acima do Play/Stop, so quando
%       existem. O texto completo do erro vai para a Command Window.
%     Abas: Simulacao | Analise.
%
%   VISTAS
%     Isometrica: pose completa, projecao ortografica, elevacao isometrica.
%       Aceita girar com o mouse.
%     Lateral: so ARFAGEM. Recebe guinada zero, como uma camera que gira
%       junto com a viga. Com camera fixa, a guinada distorceria o angulo
%       de arfagem na tela (o angulo aparente vira atan(tan psi / cos phi)).
%     Superior: pose completa vista de cima. A viga aponta na direcao de
%       phi qualquer que seja psi, entao a leitura da guinada e exata.
%   Cada vista e uma copia da cena de TRMS_CENA_CRIAR, porque um objeto
%   grafico pertence a um eixo so. Sinais e offsets vem da mesma geo.
%
%   REFERENCIAS (caixas em Opcoes, valem na hora, sem simular de novo)
%     Linhas de referencia no 3D: na isometrica, eixo de guinada,
%       phi = 0, psi = 0 no plano da viga e arcos de psi e phi
%       (TRMS_CENA_REF_*). As guias da lateral (horizontal, repouso e raio
%       da referencia) e a escala da superior ficam sempre ligadas.
%     Fantasma da referencia: viga e rotores na pose de psi_ref, na
%       isometrica e na lateral, a partir do degrau. Cor em COR.fantasma.
%
%   PASTAS: ao abrir, o app poe no path a propria pasta e a pasta mae, com
%   a do app na frente, e ao fechar tira o que acrescentou. Pode ser aberto
%   de qualquer pasta corrente.
%
%   NOMES DO MODELO: NOME_MODELO, VAR e SAIDA_* ficam na Configuracao.
%   Sem SAIDA_U1 registrada, o grafico de u1 e as metricas de esforco ficam
%   vazios.
%
%   METRICAS (aba Analise), calculadas sobre psi relativo ao repouso, na
%   janela que vai do degrau de referencia ate a perturbacao (ou ate o fim).
%   Depois de u2 a resposta deixa de ser a do degrau de referencia, por
%   isso a janela termina na perturbacao.
%     sobressinal   (pico - amplitude)/amplitude, amplitude = ref - psi(t_deg)
%     tempo de pico instante do pico, contado a partir do degrau
%     acomodacao    ultimo instante fora da faixa de 2% da amplitude
%     erro regime   media dos ultimos 10% da janela (minimo 1 s) - ref
%     IAE           integral de |ref - psi| na janela        [rad.s]
%     ISE           integral de (ref - psi)^2 na janela      [rad^2.s]
%   IAE e ISE dependem da duracao da janela.
%
%   TEXTOS COM ACENTO
%   O arquivo e ASCII puro. Os textos da tela usam entidades HTML
%   ('Simula&ccedil;&atilde;o'), convertidas pela funcao TX no fim do
%   arquivo.
%
%   Ver tambem TRMS_CENA_CRIAR, TRMS_CENA_ATUALIZAR, TRMS_PARAMS.

% =========================================================================
% Pastas: a do app na frente, a mae logo atras
% =========================================================================
% Antes de qualquer chamada a trms_params, trms_cena_* ou sim. A pasta do
% app fica no topo do path. So acrescenta o que ainda nao estiver no path
% e guarda a lista para tirar ao fechar.
pasta_app = fileparts(mfilename('fullpath'));
pastas_add = poe_no_path({fileparts(pasta_app), pasta_app});

% =========================================================================
% Configuracao
% =========================================================================

NOME_MODELO = 'trms_model_pid_bancada';   % malha fechada; 'trms_model' e o de identificacao

% Nomes das variaveis do modelo. Deixe '' para o app nao sobrescrever.
VAR = struct( ...
    'u_main',  'u_m_ts', ...       % From Workspace1
    'u_tail',  'u_t_ts', ...       % From Workspace2
    'ref',     'ref_pitch', ...    % Final value do Step
    'tdeg',    't_degrau', ...     % Step time do Step
    'kp',      'Kp_pitch', ...
    'ki',      'Ki_pitch', ...
    'kd',      'Kd_pitch', ...
    'modo',    'modo', ...
    'mascara', 'mascara');

% Saidas logadas aceitas, em ordem de preferencia.
SAIDA_PSI     = {'psi_sim', 'pitch_sim'};
SAIDA_PHI     = {'phi_sim', 'yaw_sim'};
SAIDA_U1      = {'u1_sim', 'u_pitch_cmd', 'u_m_sim', 'u_main_sim'};   % opcional
SAIDA_ROTORES = {'om_m_sim', 'om_t_sim'};                             % opcional

% Giro das pas (indicativo, ver trms_angulo_pa).
RPM_PAS   = 150;
OMEGA_REF = [];

% Limite do atuador: manual 33-949S, p. 7, [-2.5 V, +2.5 V]. Se o
% trms_params definir um destes nomes, o valor dele prevalece. [] desliga
% as linhas de saturacao do grafico de u1.
SAT_U1    = 2.5;
SAT_NOMES = {'u_sat', 'u_max', 'Umax', 'sat_u1'};

% Batente positivo da guinada medido na bancada: +2.05 rad (+117 graus),
% aproximado. O gemeo nao modela batente; a marca na vista superior vem
% desligada.
PHI_BATENTE    = 2.05;
MOSTRA_BATENTE = false;

FPS_ANIM     = 50;      % reamostragem da animacao [Hz]
PASSO_TEXTO  = 3;       % leituras, tempo e barra a cada N quadros
AUTO_TOCAR   = true;    % toca a animacao ao fim de cada simulacao
ISO_ELEVACAO = 35.26;   % elevacao da vista isometrica [graus]; atan(1/sqrt(2))
HIST_MAX     = 5;       % execucoes guardadas na aba Analise

% Referencia em rad, como no roteiro (degrau de 0 para 0.4 rad).
PADRAO = struct('kp', 4, 'ki', 6, 'kd', 8, 'ref', 0.4, 'tdeg', 10, ...
                'tf', 100, 'pert', false, 'pt', 50, 'pa', 0.5, 'trava', false, ...
                'linhas', true, 'fantasma', true);

COR = struct( ...
    'psi',   [0.13 0.40 0.75], ...
    'phi',   [0.80 0.30 0.20], ...
    'ref',   [0.10 0.56 0.36], ...
    'cinza', [0.55 0.55 0.58], ...
    'texto', [0.20 0.20 0.23], ...
    'fantasma', [0.70 0.70 0.70], ...
    'valor', [0 0 0], ...
    'lado',  [0.95 0.95 0.96], ...
    'erro',  [0.75 0.15 0.15]);

% Uma cor por execucao na aba Analise (a mesma em psi, u1 e phi).
PALETA = [0.13 0.40 0.75; 0.80 0.30 0.20; 0.10 0.56 0.36; ...
          0.55 0.35 0.75; 0.85 0.55 0.10];

% =========================================================================
% Estado compartilhado pelas callbacks
% =========================================================================
% Variaveis compartilhadas com as funcoes aninhadas (por isso nao ha nomes
% curtos de laco neste corpo).

p          = le_params();
geo        = trms_cena_geometria();
cena_6     = nargin('trms_cena_atualizar') >= 6;
A          = struct('t', [], 'psi', [], 'phi', [], 'ref', [], ...
                    'ang_m', [], 'ang_t', [], 'psi0', p.psi_0);
execs      = {};        % execucoes, da mais antiga para a mais nova
n_exec     = 0;
sel        = 0;         % execucao mostrada no cartao de desempenho
tem_dados  = false;
tocando    = false;
k_atual    = 1;
t_ini      = 0;
relogio    = tic;
ref_atual  = NaN;
sat        = SAT_U1;
ver_linhas = PADRAO.linhas;     % linhas de referencia angular visiveis
ver_fant   = PADRAO.fantasma;   % fantasma da referencia visivel

% =========================================================================
% Janela
% =========================================================================

fig = uifigure('Name', tx('G&ecirc;meo digital - rotor duplo'), ...
               'Position', [40 40 1280 720], ...
               'CloseRequestFcn', @(~, ~) fechar());
try
    fig.Theme = 'light';    % cenas e graficos usam cores fixas sobre branco
catch
end

gl = uigridlayout(fig, [1 2]);
gl.ColumnWidth   = {260, '1x'};
gl.RowHeight     = {'1x'};
gl.Padding       = [0 0 0 0];
gl.ColumnSpacing = 0;

% --- Barra lateral --------------------------------------------------------
% Linha do erro: altura zero sem erro, 'fit' com erro.
% Linha do Play/Stop: altura zero na aba Analise, onde ele nao aparece.
LINHA_ERRO   = 21;
LINHA_PLAYER = 22;
ALTURA_PLAYER = 30;
gs = uigridlayout(gl, [23 2]);
gs.Layout.Row     = 1;
gs.Layout.Column  = 1;
gs.RowHeight      = {26, 20, 24, 26, 24, 24, 24, 26, 24, 24, 24, ...
                     26, 22, 24, 24, 26, 22, 22, 22, '1x', 0, ALTURA_PLAYER, 36};
gs.ColumnWidth    = {'1.45x', '1x'};
gs.Padding        = [14 12 12 12];
gs.RowSpacing     = 4;
gs.ColumnSpacing  = 6;
gs.Scrollable     = 'on';
gs.BackgroundColor = COR.lado;

poe_em(uilabel(gs, 'Text', 'UFMG', ...
               'FontSize', 18, 'FontWeight', 'bold'), 1);
poe_em(uilabel(gs, 'Text', tx('Lab. de Controle e Automa&ccedil;&atilde;o I'), ...
               'FontSize', 12, 'FontColor', COR.texto), 2);
poe_em(uilabel(gs, 'Text', 'Rotor Duplo - TRMS', ...
               'FontSize', 14, 'FontWeight', 'bold', 'FontColor', COR.texto), 3);

secao(gs, 4, 'PID de arfagem', COR);
e_kp = campo_em(gs, 5, 'Kp [V/rad]',   PADRAO.kp, [0 Inf]);
e_ki = campo_em(gs, 6, 'Ki [V/rad/s]', PADRAO.ki, [0 Inf]);
e_kd = campo_em(gs, 7, 'Kd [V.s/rad]', PADRAO.kd, [0 Inf]);

secao(gs, 8, 'Ensaio', COR);
e_ref  = campo_em(gs, 9,  tx('Refer&ecirc;ncia [rad]'), PADRAO.ref, [-Inf Inf]);
e_ref.Tooltip = tx('Em rela&ccedil;&atilde;o ao repouso, como no roteiro e no software da bancada');
e_tdeg = campo_em(gs, 10, 'Degrau em [s]', PADRAO.tdeg, [0 Inf]);
e_tf   = campo_em(gs, 11, tx('Dura&ccedil;&atilde;o [s]'), PADRAO.tf, [1 1000]);

% Teste 6 do roteiro: degrau em u2 (rotor de cauda), que chega a arfagem
% por acoplamento cruzado. Padrao de 0,5 V, o valor usado na bancada.
secao(gs, 12, tx('Perturba&ccedil;&atilde;o no rotor de cauda'), COR);
c_pert = uicheckbox(gs, 'Text', 'Degrau ativo', 'Value', PADRAO.pert);
poe_em(c_pert, 13);
e_pt = campo_em(gs, 14, 'Instante [s]',  PADRAO.pt, [0 Inf]);
e_pa = campo_em(gs, 15, 'Amplitude [V]', PADRAO.pa, [-2.5 2.5]);

secao(gs, 16, tx('Op&ccedil;&otilde;es'), COR);
c_trava = uicheckbox(gs, 'Text', 'Travar guinada', 'Value', PADRAO.trava);
poe_em(c_trava, 17);
% Linhas de onde os angulos sao medidos e fantasma da viga na pose da
% referencia. So mudam o desenho, sem simular de novo.
c_linhas = uicheckbox(gs, 'Text', tx('Linhas de refer&ecirc;ncia no 3D'), ...
                      'Value', PADRAO.linhas, ...
                      'ValueChangedFcn', @(~, ~) aplica_referencias());
poe_em(c_linhas, 18);
c_fant = uicheckbox(gs, 'Text', tx('Fantasma da refer&ecirc;ncia'), ...
                    'Value', PADRAO.fantasma, ...
                    'ValueChangedFcn', @(~, ~) aplica_referencias());
poe_em(c_fant, 19);

% Erro: so texto, sem caixa, e a linha fica com altura zero sem erro.
l_erro = uilabel(gs, 'Text', '', 'FontColor', COR.erro, 'WordWrap', 'on', ...
                 'VerticalAlignment', 'bottom');
poe_em(l_erro, LINHA_ERRO);

% Play/Stop e tempo, a esquerda, logo acima do Simular. Simbolos de texto
% (U+25BA e U+25A0): nao dependem de arquivo de icone e nao viram emoji.
gp = uigridlayout(gs, [1 2]);
gp.ColumnWidth   = {44, '1x'};
gp.Padding       = [0 0 0 0];
gp.ColumnSpacing = 8;
gp.BackgroundColor = COR.lado;
poe_em(gp, LINHA_PLAYER);
b_tocar = uibutton(gp, 'push', 'Text', char(9658), 'FontSize', 14, ...
                   'Tooltip', 'Play', 'Enable', 'off', ...
                   'ButtonPushedFcn', @(~, ~) alterna_tocar());
l_tempo = uilabel(gp, 'Text', 't = --', 'FontName', 'Consolas', 'FontSize', 13);

b_sim = uibutton(gs, 'push', 'Text', 'Simular', ...
                 'FontSize', 14, 'FontWeight', 'bold', ...
                 'BackgroundColor', COR.psi, 'FontColor', [1 1 1], ...
                 'ButtonPushedFcn', @(~, ~) simular());
poe_em(b_sim, LINHA_PLAYER + 1);

% --- Abas -------------------------------------------------------------------
tg = uitabgroup(gl, 'SelectionChangedFcn', @(~, ~) troca_aba());
tg.Layout.Row    = 1;
tg.Layout.Column = 2;
aba_sim = uitab(tg, 'Title', tx('Simula&ccedil;&atilde;o'));
aba_ana = uitab(tg, 'Title', tx('An&aacute;lise'));

% --- Aba 1: simulacao -------------------------------------------------------
% Vistas espaciais em linha em cima, tempo embaixo.
g1 = uigridlayout(aba_sim, [2 1]);
g1.RowHeight  = {'1.2x', '1x'};
g1.Padding    = [8 6 8 6];
g1.RowSpacing = 6;

gv = uigridlayout(g1, [1 3]);
gv.ColumnWidth   = {'1.3x', '1x', '1x'};
gv.Padding       = [0 0 0 0];
gv.ColumnSpacing = 6;
ax_iso = uiaxes(gv);
ax_lat = uiaxes(gv);
ax_sup = uiaxes(gv);

cena_iso = trms_cena_criar(geo, ax_iso);
cena_lat = trms_cena_criar(geo, ax_lat);
cena_sup = trms_cena_criar(geo, ax_sup);
prepara_iso(ax_iso, cena_iso, geo, ISO_ELEVACAO, COR);
V_lat = prepara_lateral(ax_lat, cena_lat, geo, p.psi_0, COR);

% Linhas de referencia e fantasma: os dois na isometrica; na lateral so o
% fantasma, porque ela ja tem as proprias guias (horizontal, repouso e
% raio da referencia), sempre ligadas. A superior fica sem: a escala
% angular dela ja e a referencia da guinada. A caixa das linhas so mexe
% na isometrica.
op_ref = struct('cor_ref', COR.fantasma, 'cor_psi', COR.psi, 'cor_phi', COR.phi);
refs_iso = trms_cena_ref_criar(cena_iso, op_ref);
op_ref.linhas = false;
refs_lat = trms_cena_ref_criar(cena_lat, op_ref);
if MOSTRA_BATENTE
    V_sup = prepara_superior(ax_sup, cena_sup, geo, PHI_BATENTE, COR);
else
    V_sup = prepara_superior(ax_sup, cena_sup, geo, NaN, COR);
end

% Graficos num tiledlayout, que alinha as caixas dos eixos: o cursor de
% tempo fica na mesma posicao horizontal nos dois.
pg  = uipanel(g1, 'BorderType', 'none', 'BackgroundColor', [1 1 1]);
tl1 = tiledlayout(pg, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax_psi = nexttile(tl1);
ax_phi = nexttile(tl1);
G1 = prepara_graficos_sim(ax_psi, ax_phi, COR);

% --- Aba 2: analise ---------------------------------------------------------
g2 = uigridlayout(aba_ana, [1 2]);
g2.ColumnWidth   = {'1x', 250};
g2.Padding       = [8 6 8 6];
g2.ColumnSpacing = 8;

% Mesmo motivo do tiledlayout da aba 1; psi ocupa duas linhas de quatro.
pa  = uipanel(g2, 'BorderType', 'none', 'BackgroundColor', [1 1 1]);
tl2 = tiledlayout(pa, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
axa_psi = nexttile(tl2, 1, [2 1]);
axa_u1  = nexttile(tl2, 3);
axa_phi = nexttile(tl2, 4);
G2 = prepara_graficos_analise(axa_psi, axa_u1, axa_phi, SAT_U1, COR);

gr = uigridlayout(g2, [4 1]);
gr.RowHeight  = {244, 20, '1x', 28};
gr.Padding    = [0 0 0 0];
gr.RowSpacing = 6;

% Uma linha por metrica, mais a da janela no fim.
NOMES_MET = {'Sobressinal', 'Tempo de pico', 'Acomoda&ccedil;&atilde;o (2%)', ...
             'Erro de regime', 'IAE', 'ISE', 'M&aacute;x |u1|', 'u1 saturado', ...
             'M&aacute;x |&phi;|'};
pm = uipanel(gr, 'Title', 'Desempenho');
gm = uigridlayout(pm, [numel(NOMES_MET) + 1, 2]);
gm.RowHeight   = repmat({18}, 1, numel(NOMES_MET) + 1);
gm.ColumnWidth = {'1.3x', '1x'};
gm.Padding     = [8 4 8 4];
gm.RowSpacing  = 3;
l_met = gobjects(1, numel(NOMES_MET));
for jm = 1:numel(NOMES_MET)
    lm = uilabel(gm, 'Text', tx(NOMES_MET{jm}), 'FontColor', COR.texto);
    lm.Layout.Row    = jm;
    lm.Layout.Column = 1;
    lm = uilabel(gm, 'Text', char(8212), ...
                 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    lm.Layout.Row    = jm;
    lm.Layout.Column = 2;
    l_met(jm) = lm;
end
l_janela = uilabel(gm, 'Text', '', 'FontSize', 10, 'FontColor', COR.cinza);
l_janela.Layout.Row    = numel(NOMES_MET) + 1;
l_janela.Layout.Column = [1 2];

uilabel(gr, 'Text', tx('Execu&ccedil;&otilde;es'), 'FontWeight', 'bold');
tb = uitable(gr, 'ColumnName', {'Ver', 'Kp / Ki / Kd', 'Mp [%]'}, ...
             'ColumnWidth', {36, 'auto', 58}, ...
             'ColumnEditable', [true false false], ...
             'ColumnFormat', {'logical', 'char', 'numeric'}, ...
             'RowName', {}, 'Data', cell(0, 3), ...
             'CellEditCallback', @(~, evt) muda_visivel(evt), ...
             'CellSelectionCallback', @(~, evt) seleciona(evt));
uibutton(gr, 'push', 'Text', tx('Limpar hist&oacute;rico'), ...
         'ButtonPushedFcn', @(~, ~) limpa_historico());

% --- Estado inicial ------------------------------------------------------------
pose_inicial();
aplica_referencias();
try
    fig.WindowState = 'maximized';
catch
end

% =========================================================================
% Callbacks (funcoes aninhadas: compartilham o workspace acima)
% =========================================================================

    function simular()
        pausar();
        erro('');

        % Campos e parametros. Erro de preenchimento vira mensagem curta;
        % erro no trms_params vem com o texto completo na Command Window.
        try
            p   = le_params();       % relido a cada simulacao
            cfg = le_campos();
            valida(cfg);
        catch err
            if strcmp(err.identifier, 'trms_app:campos')
                erro(err.message);
            else
                erro(primeira_linha(err), causas(err, 0));
            end
            return
        end

        b_sim.Enable = 'off';
        drawnow;

        in = [];
        try
            in  = monta_entrada(NOME_MODELO, VAR, cfg, p);
            out = sim(in);
            [t, psi, phi] = le_saida(out, SAIDA_PSI, SAIDA_PHI);
            [w_m, w_t]    = le_rotores(out, SAIDA_ROTORES, t);
            u1            = le_opcional(out, SAIDA_U1, t);
        catch err
            if ~isvalid(fig), return, end
            b_sim.Enable = 'on';
            info = {};
            if ~isempty(in)
                nomes_in = {in.Variables.Name};
                info = {sprintf('injetadas: %d variaveis | psi_0: %d | CR_m_neg: %d', ...
                        numel(nomes_in), any(strcmp(nomes_in, 'psi_0')), ...
                        any(strcmp(nomes_in, 'CR_m_neg'))); ''};
            end
            erro([tx('A simula&ccedil;&atilde;o falhou. ') primeira_linha(err)], ...
                 [info(:); causas(err, 0)]);
            return
        end
        if ~isvalid(fig), return, end
        b_sim.Enable = 'on';

        % Tempos repetidos (cruzamentos por zero) quebram o interp1.
        [t, iu] = unique(t);
        psi = psi(iu);
        phi = phi(iu);
        if ~isempty(w_m), w_m = w_m(iu); w_t = w_t(iu); end
        if ~isempty(u1),  u1  = u1(iu);  end

        % Angulo fisico (zero na horizontal) seja qual for o ponto de log: a
        % simulacao parte do repouso e o encoder zera no repouso.
        psi_0 = p.psi_0;
        psi   = psi - psi(1) + psi_0;
        psi_r = psi - psi_0;                 % rad, relativo ao repouso

        % Saturacao: o valor do trms_params prevalece sobre o do manual.
        sat = SAT_U1;
        for j = 1:numel(SAT_NOMES)
            if isfield(p, SAT_NOMES{j})
                sat = abs(p.(SAT_NOMES{j}));
                break
            end
        end

        % Angulo das pas, com escala comum aos dois rotores.
        ang_m = [];
        ang_t = [];
        if ~isempty(w_m)
            ref_w = OMEGA_REF;
            if isempty(ref_w), ref_w = max(abs([w_m; w_t]))/2; end
            if ref_w > 0
                op_pa = struct('rpm_max', RPM_PAS, 'fps', 25, 'omega_ref', ref_w);
                ang_m = trms_angulo_pa(t, w_m, op_pa);
                ang_t = trms_angulo_pa(t, w_t, op_pa);
            end
        end

        % Trajetoria da animacao, reamostrada em passo uniforme.
        ta     = (t(1) : 1/FPS_ANIM : t(end)).';
        A.t    = ta;
        A.psi  = interp1(t, psi, ta);
        A.phi  = interp1(t, phi, ta);
        A.ref  = cfg.ref_encoder * double(ta >= cfg.tdeg);
        A.psi0 = psi_0;
        if isempty(ang_m)
            A.ang_m = [];
            A.ang_t = [];
        else
            A.ang_m = interp1(t, ang_m(:), ta);
            A.ang_t = interp1(t, ang_t(:), ta);
        end

        % Metricas na janela degrau -> perturbacao (ou fim).
        if cfg.pert_ativa && cfg.pert_t > cfg.tdeg
            t_fim = cfg.pert_t;
        else
            t_fim = t(end);
        end
        m = metricas(t, psi_r, cfg.ref_encoder, cfg.tdeg, t_fim);
        m.ate_pert = cfg.pert_ativa && cfg.pert_t > cfg.tdeg;
        m.phimax   = max(abs(phi));
        if ~isempty(u1)
            m.u1max = max(abs(u1));
            if ~isempty(sat) && sat > 0
                m.sat_frac = mean(abs(u1) >= 0.999*sat);
            end
        end

        % Dados dos graficos, decimados.
        kd = max(1, round(numel(t) / 4000));
        d.t   = t(1:kd:end);
        d.psi = psi_r(1:kd:end);
        d.phi = phi(1:kd:end);
        if isempty(u1)
            d.u1 = [];
        else
            d.u1 = u1(1:kd:end);
        end

        % Aba 1: graficos de psi e phi.
        r_ref = cfg.ref_encoder;
        set(G1.psi, 'XData', d.t, 'YData', d.psi);
        set(G1.ref, 'XData', [d.t(1) cfg.tdeg cfg.tdeg d.t(end)], ...
                    'YData', [0 0 r_ref r_ref]);
        set(G1.phi, 'XData', d.t, 'YData', d.phi);
        mostra_u2(G1.u2_psi, cfg, false);
        mostra_u2(G1.u2_phi, cfg, true);
        for ax = [ax_psi ax_phi]
            ax.XLim = [t(1) t(end)];      % o cursor percorre ate t(end)
            congela_y(ax);
        end
        G1.cur_psi.Visible = 'on';
        G1.cur_phi.Visible = 'on';

        % Aba 2: nova execucao no historico.
        n_exec = n_exec + 1;
        r = struct();
        r.nome    = sprintf('%g / %g / %g', cfg.kp, cfg.ki, cfg.kd);
        r.cor     = PALETA(mod(n_exec - 1, size(PALETA, 1)) + 1, :);
        r.cfg     = cfg;
        r.d       = d;
        r.m       = m;
        r.visivel = true;
        adiciona_execucao(r);

        % Reproducao. Na aba Simulacao toca sozinha; na Analise so simula.
        tem_dados = true;
        ref_atual = NaN;
        b_tocar.Enable = 'on';
        mostra(1, true);

        if AUTO_TOCAR && tg.SelectedTab == aba_sim
            alterna_tocar();
        end
    end

    function cfg = le_campos()
        cfg.kp   = e_kp.Value;
        cfg.ki   = e_ki.Value;
        cfg.kd   = e_kd.Value;
        cfg.tf   = e_tf.Value;
        cfg.tdeg = e_tdeg.Value;
        % A referencia e digitada em RAD no referencial do ENCODER (zero no
        % repouso), que e o da malha, como no roteiro e na bancada.
        cfg.ref_encoder = e_ref.Value;
        cfg.ref_fisico  = cfg.ref_encoder + p.psi_0;
        cfg.pert_ativa  = c_pert.Value;
        cfg.pert_t      = e_pt.Value;
        cfg.pert_amp    = e_pa.Value;
        if c_trava.Value
            cfg.mascara = [1 0 1 1 1 0]';
        else
            cfg.mascara = ones(6, 1);
        end
    end

    % --- Erros ---------------------------------------------------------------

    function erro(msg, det)
        % Texto vermelho acima do Simular, so quando ha erro: sem erro, a
        % linha fica com altura zero. O texto completo (causas aninhadas)
        % vai para a Command Window, para depuracao.
        l_erro.Text = msg;
        rh = gs.RowHeight;
        if isempty(msg)
            rh{LINHA_ERRO} = 0;
        else
            rh{LINHA_ERRO} = 'fit';
        end
        gs.RowHeight = rh;
        if nargin >= 2 && ~isempty(det)
            fprintf(2, 'trms_app: %s\n', msg);
            fprintf(2, '  %s\n', det{:});
        end
    end

    function fechar()
        tocando = false;
        delete(fig);
        % Devolve o path ao estado de antes de abrir o app.
        if ~isempty(pastas_add)
            rmpath(pastas_add{:});
        end
    end

    % --- Reproducao ------------------------------------------------------------

    function pausar()
        tocando = false;
    end

    function troca_aba()
        % Play/Stop e tempo so existem na aba Simulacao: na Analise a linha
        % deles fica com altura zero, sem deixar buraco na barra lateral.
        pausar();
        na_sim = tg.SelectedTab == aba_sim;
        gp.Visible = na_sim;
        rh = gs.RowHeight;
        if na_sim
            rh{LINHA_PLAYER} = ALTURA_PLAYER;
        else
            rh{LINHA_PLAYER} = 0;
        end
        gs.RowHeight = rh;
    end

    function alterna_tocar()
        % Play/Stop classico: Play sempre comeca do inicio; Stop para e deixa
        % a cena no quadro em que parou. O Stop chega como uma segunda
        % chamada desta callback durante o drawnow do laco: so baixa a flag
        % e retorna, e o laco ve a flag e sai.
        if tocando
            tocando = false;
            return
        end
        if ~tem_dados, return, end
        k_atual = 1;
        tocando = true;
        b_tocar.Text    = char(9632);    % quadrado: Stop
        b_tocar.Tooltip = 'Stop';
        t_ini   = A.t(1);
        relogio = tic;
        k_ant = 0;
        cont  = 0;
        try
            while tocando && isvalid(fig)
                % Relogio de parede: se a maquina nao der conta, quadros sao
                % pulados e a animacao continua em tempo real.
                k = indice(t_ini + toc(relogio));
                if k ~= k_ant
                    mostra(k, mod(cont, PASSO_TEXTO) == 0);
                    k_ant = k;
                    cont  = cont + 1;
                    drawnow
                else
                    pause(0.002);
                end
                if k >= numel(A.t), break, end
            end
        catch err
            % Janela fechada no meio do laco: sai em silencio.
            if isvalid(fig), rethrow(err); end
            return
        end
        if ~isvalid(fig), return, end
        tocando = false;
        b_tocar.Text    = char(9658);    % triangulo: Play
        b_tocar.Tooltip = 'Play';
        mostra(k_atual, true);
        dur = toc(relogio);
        if dur > 0.5
            fprintf('animacao: %d quadros em %.1f s (%.0f fps)\n', cont, dur, cont/dur);
        end
    end

    function k = indice(tq)
        k = 1 + round((tq - A.t(1)) * FPS_ANIM);
        k = max(1, min(numel(A.t), k));
    end

    function mostra(k, texto)
        k_atual = k;
        psi_k = A.psi(k);
        phi_k = A.phi(k);
        if isempty(A.ang_m)
            am = [];
            at = [];
        else
            am = A.ang_m(k);
            at = A.ang_t(k);
        end
        atualiza_cena(cena_iso, psi_k, phi_k, am, at);
        atualiza_cena(cena_lat, psi_k, -geo.offset_yaw, am, at);   % so arfagem
        atualiza_cena(cena_sup, psi_k, phi_k, am, at);

        if A.ref(k) ~= ref_atual
            ref_atual = A.ref(k);
            posiciona_ref(V_lat, geo, A.psi0 + ref_atual, ref_atual ~= 0);
        end
        % Fantasma so depois do degrau: antes dele a referencia e o proprio
        % repouso, e o fantasma ficaria em cima da viga.
        if A.ref(k) ~= 0
            psi_ref_k = A.psi0 + A.ref(k);
        else
            psi_ref_k = NaN;
        end
        trms_cena_ref_atualizar(refs_iso, psi_k, phi_k, psi_ref_k, texto);
        trms_cena_ref_atualizar(refs_lat, psi_k, -geo.offset_yaw, psi_ref_k, false);

        tk = A.t(k);
        G1.cur_psi.Value = tk;
        G1.cur_phi.Value = tk;
        set(G1.m_psi, 'XData', tk, 'YData', psi_k - A.psi0);
        set(G1.m_phi, 'XData', tk, 'YData', phi_k);

        if texto
            leituras(V_lat, V_sup, psi_k, A.psi0, phi_k);
            l_tempo.Text = sprintf('t = %5.1f s', tk);
        end
    end

    function atualiza_cena(cena, psi_k, phi_k, am, at)
        if cena_6
            trms_cena_atualizar(cena, psi_k, phi_k, am, at, false);
        else
            trms_cena_atualizar(cena, psi_k, phi_k, am, at);
        end
    end

    function pose_inicial()
        atualiza_cena(cena_iso, p.psi_0, 0, [], []);
        atualiza_cena(cena_lat, p.psi_0, -geo.offset_yaw, [], []);
        atualiza_cena(cena_sup, p.psi_0, 0, [], []);
        trms_cena_ref_atualizar(refs_iso, p.psi_0, 0, NaN);
        trms_cena_ref_atualizar(refs_lat, p.psi_0, -geo.offset_yaw, NaN, false);
        leituras(V_lat, V_sup, p.psi_0, p.psi_0, 0);
    end

    function aplica_referencias()
        % Liga/desliga as linhas da isometrica e o fantasma (isometrica e
        % lateral) e redesenha o quadro atual, porque os arcos nao sao
        % recalculados enquanto estao ocultos. As guias da lateral e a
        % escala da superior nao dependem das caixas.
        ver_linhas = c_linhas.Value;
        ver_fant   = c_fant.Value;
        trms_cena_ref_mostrar(refs_iso, ver_linhas, ver_fant);
        trms_cena_ref_mostrar(refs_lat, [], ver_fant);
        ref_atual = NaN;                 % forca reposicionar o raio da referencia
        if tem_dados
            mostra(k_atual, true);
        else
            pose_inicial();
            posiciona_ref(V_lat, geo, NaN, false);
        end
    end

    % --- Analise -----------------------------------------------------------------

    function adiciona_execucao(r)
        if numel(execs) >= HIST_MAX
            apaga_linhas(execs{1});
            execs(1) = [];
        end
        % As anteriores ficam finas; a nova, grossa.
        for j = 1:numel(execs)
            set(linhas_de(execs{j}), 'LineWidth', 1.1);
        end
        r.h = struct();
        r.h.psi = plot(axa_psi, r.d.t, r.d.psi, 'Color', r.cor, 'LineWidth', 2);
        r.h.phi = plot(axa_phi, r.d.t, r.d.phi, 'Color', r.cor, 'LineWidth', 2);
        if isempty(r.d.u1)
            r.h.u1 = gobjects(0);
        else
            r.h.u1 = plot(axa_u1, r.d.t, r.d.u1, 'Color', r.cor, 'LineWidth', 2);
        end
        execs{end + 1} = r;
        sel = numel(execs);
        redesenha_analise();
        atualiza_tabela();
        atualiza_cartao();
    end

    function redesenha_analise()
        if isempty(execs), return, end
        r = execs{end};

        % Referencia e u2 da execucao mais nova.
        r_ref = r.cfg.ref_encoder;
        set(G2.ref, 'XData', [r.d.t(1) r.cfg.tdeg r.cfg.tdeg r.d.t(end)], ...
                    'YData', [0 0 r_ref r_ref]);
        mostra_u2(G2.u2, r.cfg, true);

        % Eixo de tempo comum, ate o fim da execucao visivel mais longa.
        t_max = r.d.t(end);
        u_max = 0;
        for j = 1:numel(execs)
            if execs{j}.visivel
                t_max = max(t_max, execs{j}.d.t(end));
                if ~isempty(execs{j}.d.u1)
                    u_max = max(u_max, max(abs(execs{j}.d.u1)));
                end
            end
        end
        set([axa_psi axa_u1 axa_phi], 'XLim', [0 t_max]);

        % u1 sempre com os limites de saturacao a vista.
        if ~isempty(sat) && sat > 0
            set(G2.sat(1), 'Value',  sat, 'Visible', 'on');
            set(G2.sat(2), 'Value', -sat, 'Visible', 'on');
            axa_u1.YLim = [-1 1] * max(1.15*sat, 1.05*u_max);
        else
            set(G2.sat, 'Visible', 'off');
        end
        G2.u1_vazio.Visible = isempty(r.d.u1);

        atualiza_legenda();
    end

    function atualiza_legenda()
        hs    = gobjects(0);
        nomes = {};
        for j = numel(execs):-1:1
            if execs{j}.visivel
                hs(end + 1)    = execs{j}.h.psi; %#ok<AGROW>
                nomes{end + 1} = execs{j}.nome;  %#ok<AGROW>
            end
        end
        hs(end + 1)    = G2.ref;
        nomes{end + 1} = tx('refer&ecirc;ncia');
        legend(axa_psi, hs, nomes, 'Location', 'southeast', 'Box', 'off', ...
               'Interpreter', 'none');
    end

    function atualiza_tabela()
        % Mais nova em cima; a cor do texto e a cor das curvas.
        n = numel(execs);
        D = cell(n, 3);
        for j = 1:n
            r = execs{n - j + 1};
            D(j, :) = {r.visivel, r.nome, round(r.m.sobressinal, 1)};
        end
        tb.Data = D;
        removeStyle(tb);
        for j = 1:n
            addStyle(tb, uistyle('FontColor', execs{n - j + 1}.cor), 'row', j);
        end
    end

    function atualiza_cartao()
        if sel < 1 || sel > numel(execs)
            pm.Title = 'Desempenho';
            set(l_met, 'Text', char(8212));
            l_janela.Text = '';
            return
        end
        r = execs{sel};
        m = r.m;
        pm.Title = ['Desempenho  ' char(183) '  ' r.nome];
        if isnan(m.ts) && ~isnan(m.sobressinal)
            s_ts = tx('n&atilde;o acomodou');
        else
            s_ts = num_ou_traco(m.ts, '%.1f s');
        end
        txt = {num_ou_traco(m.sobressinal, '%.1f %%'), ...
               num_ou_traco(m.tp, '%.2f s'), ...
               s_ts, ...
               num_ou_traco(arred(m.erro, 3), '%+.3f rad'), ...
               num_ou_traco(m.iae, ['%.3f rad' char(183) 's']), ...
               num_ou_traco(m.ise, ['%.4f rad' char(178) char(183) 's']), ...
               num_ou_traco(m.u1max, '%.2f V'), ...
               num_ou_traco(100*m.sat_frac, '%.0f %%'), ...
               num_ou_traco(m.phimax, '%.2f rad')};
        for j = 1:numel(l_met)
            set(l_met(j), 'Text', txt{j});
        end
        % A janela vai do degrau ate a perturbacao em u2, quando ela existe:
        % depois dela a resposta deixa de ser a do degrau de referencia.
        if m.ate_pert
            fim_txt = tx('at&eacute; u2');
        else
            fim_txt = tx('at&eacute; o fim');
        end
        l_janela.Text = sprintf('Janela: %.0f a %.0f s (do degrau %s)', ...
                                m.t_ini, m.t_fim, fim_txt);
        l_janela.Tooltip = tx(['Do degrau de refer&ecirc;ncia at&eacute; a perturba&ccedil;&atilde;o ' ...
                               'em u2 (ou at&eacute; o fim, sem perturba&ccedil;&atilde;o). Depois ' ...
                               'de u2 a resposta mistura a rejei&ccedil;&atilde;o do dist&uacute;rbio.']);
    end

    function muda_visivel(evt)
        j = numel(execs) - evt.Indices(1) + 1;
        if j < 1 || evt.Indices(2) ~= 1, return, end
        execs{j}.visivel = logical(evt.NewData);
        set(linhas_de(execs{j}), 'Visible', execs{j}.visivel);
        redesenha_analise();
    end

    function seleciona(evt)
        if isempty(evt.Indices), return, end
        j = numel(execs) - evt.Indices(1, 1) + 1;
        if j >= 1 && j <= numel(execs)
            sel = j;
            atualiza_cartao();
        end
    end

    function limpa_historico()
        % Mantem so a execucao mais nova.
        if numel(execs) <= 1, return, end
        for j = 1:numel(execs) - 1
            apaga_linhas(execs{j});
        end
        execs = execs(end);
        sel   = 1;
        redesenha_analise();
        atualiza_tabela();
        atualiza_cartao();
    end

end


% =========================================================================
% Funcoes locais: vistas 3D
% =========================================================================

function prepara_iso(ax, cena, geo, elevacao, COR)
%PREPARA_ISO Vista isometrica: pose completa, mesmo azimute da geo.
esconde_texto(cena);
az = 45;
if isfield(geo, 'vista'), az = geo.vista(1); end
view(ax, az, elevacao);
ax.Projection = 'orthographic';
xlabel(ax, '');
ylabel(ax, '');
zlabel(ax, '');
set(ax, 'XTickLabel', [], 'YTickLabel', [], 'ZTickLabel', []);
title(ax, tx('Isom&eacute;trica'), 'FontWeight', 'normal', 'Color', COR.texto);
try
    ax.Toolbar.Visible = 'off';    % girar com o mouse continua valendo
catch
end
end

function V = prepara_lateral(ax, cena, geo, psi_0, COR)
%PREPARA_LATERAL Vista lateral: camera em -y, rotor principal a direita.
%   A janela e a mesma da vista superior (quadrado de lado 2*MEIA_JANELA,
%   centrado no pivo), entao as duas ocupam a mesma area e desenham a viga
%   na mesma escala. As guias (horizontal, repouso, referencia) ficam num
%   plano atras da viga (y > 0), para que a viga passe na frente delas.
esconde_texto(cena);
view(ax, 0, 0);
ax.Projection = 'orthographic';
L = meia_janela();
set(ax, 'XLim', [-L L], 'ZLim', geo.h_pivo + [-L L]);
limpa_eixos(ax, geo, 'Lateral (arfagem)', COR);

V.yb = 0.20;            % plano das guias
V.h  = geo.h_pivo;
V.r  = 0.40;            % comprimento dos raios de repouso e referencia

% Mesa, para a base nao parecer flutuar no espaco abaixo dela.
line('Parent', ax, 'XData', [-L L], 'YData', [V.yb V.yb], 'ZData', [0 0], ...
     'Color', [0.80 0.80 0.83], 'LineWidth', 1.5);

% Guias fixas, sempre visiveis: horizontal (psi = 0) e repouso.
line('Parent', ax, 'XData', [-0.42 0.42], 'YData', [V.yb V.yb], ...
     'ZData', [V.h V.h], 'LineStyle', ':', 'Color', COR.cinza);
text(ax, 0.425, V.yb, V.h + 0.01, '0', 'FontSize', 9, ...
     'Color', COR.cinza, 'HorizontalAlignment', 'left', ...
     'VerticalAlignment', 'bottom');

th = angulo_lat(geo, psi_0);
line('Parent', ax, 'XData', [0 V.r*cos(th)], 'YData', [V.yb V.yb], ...
     'ZData', V.h + [0 V.r*sin(th)], 'LineStyle', '-.', 'Color', COR.cinza);
text(ax, (V.r + 0.012)*cos(th), V.yb, V.h + (V.r + 0.012)*sin(th), 'repouso', ...
     'FontSize', 9, 'Color', COR.cinza, 'HorizontalAlignment', 'left', ...
     'VerticalAlignment', 'middle');

V.ref = line('Parent', ax, 'XData', [0 0], 'YData', [V.yb V.yb], ...
             'ZData', [V.h V.h], 'LineStyle', '--', 'LineWidth', 1.6, ...
             'Color', COR.ref, 'Visible', 'off');
V.ref_txt = text(ax, 0, V.yb, V.h, 'ref', 'FontSize', 10, 'FontWeight', 'bold', ...
                 'Color', COR.ref, 'HorizontalAlignment', 'left', ...
                 'VerticalAlignment', 'middle', 'Visible', 'off');

[V.txt1, V.txt2] = textos_leitura(ax, COR);
end

function [t1, t2] = textos_leitura(ax, COR)
%TEXTOS_LEITURA Leitura do angulo no canto superior esquerdo, em preto.
%   Mesma posicao e estilo nas vistas lateral e superior.
t1 = text('Parent', ax, 'Units', 'normalized', 'Position', [0.03 0.97], ...
          'String', '', 'HorizontalAlignment', 'left', ...
          'VerticalAlignment', 'top', 'FontSize', 13, ...
          'FontWeight', 'bold', 'Color', COR.valor);
t2 = text('Parent', ax, 'Units', 'normalized', 'Position', [0.03 0.885], ...
          'String', '', 'HorizontalAlignment', 'left', ...
          'VerticalAlignment', 'top', 'FontSize', 9, 'Color', COR.valor);
end

function L = meia_janela()
% Meia largura [m] da janela das vistas lateral e superior. A mesma nas
% duas, para que fiquem com a mesma area e a mesma escala. A folga acima
% da escala da vista superior (raio 0.41 m + rotulos) abriga a leitura no
% canto superior esquerdo sem encostar nos rotulos pi/2 e 3pi/4.
L = 0.58;
end

function V = prepara_superior(ax, cena, geo, phi_batente, COR)
%PREPARA_SUPERIOR Vista superior: x para a direita, y para cima.
%   A escala angular fica rente a mesa, abaixo de toda a planta, com
%   rotulos em fracoes de pi (as leituras e graficos estao em rad).
esconde_texto(cena);
view(ax, 0, 90);
ax.Projection = 'orthographic';
L = meia_janela();
set(ax, 'XLim', [-L L], 'YLim', [-L L]);
limpa_eixos(ax, geo, 'Superior (guinada)', COR);

R  = 0.41;
z0 = 0.002;
a  = linspace(0, 2*pi, 181);
line('Parent', ax, 'XData', R*cos(a), 'YData', R*sin(a), 'ZData', z0 + 0*a, ...
     'Color', [0.82 0.82 0.85], 'LineWidth', 1.5);

for v = -165:15:180
    ang = geo.sinal_yaw * (v*pi/180 + geo.offset_yaw);
    if mod(v, 45) == 0
        r0 = R - 0.035;
        w  = 1.2;
    else
        r0 = R - 0.016;
        w  = 0.8;
    end
    line('Parent', ax, 'XData', [r0 R]*cos(ang), 'YData', [r0 R]*sin(ang), ...
         'ZData', [z0 z0], 'Color', COR.cinza, 'LineWidth', w);
    if mod(v, 45) == 0
        text(ax, (R + 0.055)*cos(ang), (R + 0.055)*sin(ang), z0, rotulo_pi(v), ...
             'FontSize', 8, 'Color', COR.cinza, ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end
end

% Raio de phi = 0
a0 = geo.sinal_yaw * geo.offset_yaw;
line('Parent', ax, 'XData', [0 R]*cos(a0), 'YData', [0 R]*sin(a0), ...
     'ZData', [z0 z0], 'LineStyle', '--', 'Color', COR.cinza);

% Batente medido
if isfinite(phi_batente)
    ang = geo.sinal_yaw * (phi_batente + geo.offset_yaw);
    line('Parent', ax, 'XData', [R - 0.04, R + 0.015]*cos(ang), ...
         'YData', [R - 0.04, R + 0.015]*sin(ang), 'ZData', [z0 z0], ...
         'Color', COR.erro, 'LineWidth', 3.5);
    text(ax, (R - 0.085)*cos(ang), (R - 0.085)*sin(ang), z0, 'batente', ...
         'FontSize', 8, 'Color', COR.erro, 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'middle');
end

[V.txt1, V.txt2] = textos_leitura(ax, COR);
end

function s = rotulo_pi(v)
%ROTULO_PI Rotulo da escala para um multiplo de 45 graus, em fracoes de pi.
switch v
    case 0,    s = '0';
    case 45,   s = '\pi/4';
    case 90,   s = '\pi/2';
    case 135,  s = '3\pi/4';
    case 180,  s = '\pm\pi';
    case -45,  s = '-\pi/4';
    case -90,  s = '-\pi/2';
    case -135, s = '-3\pi/4';
    otherwise, s = '';
end
end

function th = angulo_lat(geo, psi)
%ANGULO_LAT Angulo da viga no plano x-z, a mesma conversao da cena 3D.
%   A cena gira de sinal_pitch*(psi + offset) em torno do y local, o que
%   leva o +x local para [cos(th), 0, sin(th)] com th dado aqui.
th = -geo.sinal_pitch * (psi + geo.offset_pitch);
end

function posiciona_ref(V, geo, psi_abs, visivel)
%POSICIONA_REF Raio tracejado da referencia na vista lateral.
if ~visivel
    set([V.ref V.ref_txt], 'Visible', 'off');
    return
end
th = angulo_lat(geo, psi_abs);
set(V.ref, 'XData', [0 V.r*cos(th)], 'YData', [V.yb V.yb], ...
           'ZData', V.h + [0 V.r*sin(th)], 'Visible', 'on');
set(V.ref_txt, 'Position', [(V.r + 0.012)*cos(th), V.yb, V.h + (V.r + 0.012)*sin(th)], ...
               'Visible', 'on');
end

function leituras(VL, VS, psi, psi0, phi)
%LEITURAS Angulos escritos nas vistas lateral e superior, em rad.
%   O principal da lateral e relativo ao repouso, como o grafico e a
%   referencia. Embaixo vao o mesmo valor em graus e o angulo em relacao a
%   horizontal.
rel = psi - psi0;
VL.txt1.String = sprintf('\\psi = %+.3f rad', arred(rel, 3));
VL.txt2.String = {sprintf('rel. ao repouso (%+.1f\\circ)', arred(rel*180/pi, 1)), ...
                  sprintf('%+.3f rad da horizontal', arred(psi, 3))};
VS.txt1.String = sprintf('\\phi = %+.3f rad', arred(phi, 3));
VS.txt2.String = sprintf('(%+.1f\\circ)', arred(phi*180/pi, 1));
end

function v = arred(x, n)
% Arredonda a n casas; o "+ 0" troca -0 por +0 na leitura.
v = round(x*10^n)/10^n + 0;
end

function esconde_texto(cena)
% As leituras ficam nas vistas 2D-like; o texto da cena seria repetido.
if isfield(cena, 'h_texto') && isgraphics(cena.h_texto)
    cena.h_texto.Visible = 'off';
end
end

function limpa_eixos(ax, geo, titulo, COR)
grid(ax, 'off');
box(ax, 'off');
xlabel(ax, '');
ylabel(ax, '');
zlabel(ax, '');
set(ax, 'XColor', 'none', 'YColor', 'none', 'ZColor', 'none', ...
        'Color', geo.cor_fundo);
title(ax, titulo, 'FontWeight', 'normal', 'Color', COR.texto);
desliga_interacao(ax);
end

function desliga_interacao(ax)
try
    ax.Toolbar.Visible = 'off';
catch
end
try
    disableDefaultInteractivity(ax);
catch
end
end


% =========================================================================
% Funcoes locais: graficos
% =========================================================================

function G = prepara_graficos_sim(ax_psi, ax_phi, COR)
%PREPARA_GRAFICOS_SIM psi e phi empilhados, com cursor de tempo e marcador.
prepara_grafico(ax_psi, '\psi [rad] rel. ao repouso', false);
G.ref = plot(ax_psi, NaN, NaN, '--', 'Color', COR.ref, 'LineWidth', 1.2);
G.psi = plot(ax_psi, NaN, NaN, 'Color', COR.psi, 'LineWidth', 1.5);
legend(ax_psi, [G.psi G.ref], {'\psi', tx('refer&ecirc;ncia')}, ...
       'Location', 'southeast', 'Box', 'off');
G.cur_psi = xline(ax_psi, 0, '-', 'Color', COR.cinza, 'HandleVisibility', 'off', ...
                  'Visible', 'off');
G.u2_psi  = xline(ax_psi, 0, ':', 'Color', COR.cinza, 'HandleVisibility', 'off', ...
                  'Visible', 'off');
G.m_psi   = line(ax_psi, NaN, NaN, 'LineStyle', 'none', 'Marker', 'o', ...
                 'MarkerSize', 6, 'MarkerFaceColor', COR.psi, ...
                 'MarkerEdgeColor', 'w', 'HandleVisibility', 'off');

prepara_grafico(ax_phi, '\phi [rad]', true);
G.phi = plot(ax_phi, NaN, NaN, 'Color', COR.phi, 'LineWidth', 1.5);
G.cur_phi = xline(ax_phi, 0, '-', 'Color', COR.cinza, 'HandleVisibility', 'off', ...
                  'Visible', 'off');
G.u2_phi  = xline(ax_phi, 0, ':', 'Color', COR.cinza, 'HandleVisibility', 'off', ...
                  'LabelVerticalAlignment', 'bottom', 'Visible', 'off');
G.m_phi   = line(ax_phi, NaN, NaN, 'LineStyle', 'none', 'Marker', 'o', ...
                 'MarkerSize', 6, 'MarkerFaceColor', COR.phi, ...
                 'MarkerEdgeColor', 'w', 'HandleVisibility', 'off');
end

function G = prepara_graficos_analise(axa_psi, axa_u1, axa_phi, sat, COR)
%PREPARA_GRAFICOS_ANALISE psi, u1 e phi empilhados, com o tempo em comum.
prepara_grafico(axa_psi, '\psi [rad] rel. ao repouso', false);
G.ref = plot(axa_psi, NaN, NaN, '--', 'Color', COR.texto, 'LineWidth', 1);

prepara_grafico(axa_u1, 'u_1 [V]', false);
if isempty(sat), sat = 0; end
% Rotulo na linha de baixo, do lado de cima dela.
G.sat = [yline(axa_u1,  sat, '--', 'Color', COR.erro, 'HandleVisibility', 'off'), ...
         yline(axa_u1, -sat, '--', tx('satura&ccedil;&atilde;o'), 'Color', COR.erro, ...
               'LabelHorizontalAlignment', 'left', ...
               'LabelVerticalAlignment', 'top', 'HandleVisibility', 'off')];
if sat == 0
    set(G.sat, 'Visible', 'off');
end
G.u1_vazio = text('Parent', axa_u1, 'Units', 'normalized', 'Position', [0.5 0.5], ...
                  'String', tx(['u1 indispon&iacute;vel: o modelo n&atilde;o registra ' ...
                                'o sinal de controle (veja SAIDA_U1)']), ...
                  'HorizontalAlignment', 'center', 'Color', COR.cinza, ...
                  'Interpreter', 'none', 'Visible', 'off');

prepara_grafico(axa_phi, '\phi [rad]', true);
G.u2 = xline(axa_phi, 0, ':', 'Color', COR.cinza, 'HandleVisibility', 'off', ...
             'LabelVerticalAlignment', 'bottom', 'Visible', 'off');
end

function prepara_grafico(ax, rotulo_y, mostra_x)
hold(ax, 'on');
grid(ax, 'on');
box(ax, 'on');
ylabel(ax, rotulo_y);
if mostra_x
    xlabel(ax, 't [s]');
else
    ax.XTickLabel = {};
end
desliga_interacao(ax);
end

function congela_y(ax)
% Limites fixos antes de animar: mover cursor e marcador nao recalcula eixos.
ax.YLimMode = 'auto';
yl = ax.YLim;
ax.YLim = yl;
end

function mostra_u2(h, cfg, rotulo)
%MOSTRA_U2 Marca o instante do degrau em u2, se a perturbacao estiver ativa.
if cfg.pert_ativa
    h.Value = cfg.pert_t;
    if rotulo
        h.Label = sprintf('u_2 = %.2g V', cfg.pert_amp);
    end
    h.Visible = 'on';
else
    h.Visible = 'off';
end
end

function h = linhas_de(r)
h = [r.h.psi; r.h.phi];
if ~isempty(r.h.u1)
    h = [h; r.h.u1];
end
end

function apaga_linhas(r)
h = linhas_de(r);
delete(h(isvalid(h)));
end


% =========================================================================
% Funcoes locais: metricas e textos
% =========================================================================

function valida(cfg)
% Referencia acima de pi/2 rad quase sempre e alguem digitando graus.
if abs(cfg.ref_encoder) > pi/2
    error('trms_app:campos', ...
          tx(['A refer&ecirc;ncia est&aacute; em rad. %.4g rad passa de 90&deg;; ' ...
              'para %.4g&deg;, digite %.3f.']), ...
          cfg.ref_encoder, cfg.ref_encoder, cfg.ref_encoder*pi/180);
end
if cfg.tdeg >= cfg.tf
    error('trms_app:campos', ...
          tx('O degrau precisa acontecer antes do fim do ensaio (Dura&ccedil;&atilde;o).'));
end
if cfg.pert_ativa && cfg.pert_t >= cfg.tf
    error('trms_app:campos', ...
          tx('A perturba&ccedil;&atilde;o precisa acontecer antes do fim do ensaio.'));
end
end

function m = metricas(t, y, r, t_deg, t_fim)
%METRICAS Indices da resposta ao degrau. y e r em rad, relativos ao repouso.
m = struct('sobressinal', NaN, 'tp', NaN, 'ts', NaN, 'erro', NaN, ...
           'iae', NaN, 'ise', NaN, ...
           't_ini', t_deg, 't_fim', t_fim, ...
           'u1max', NaN, 'sat_frac', NaN, 'phimax', NaN);
j = find(t >= t_deg & t <= t_fim);
if numel(j) < 10, return, end
tj  = t(j);
yj  = y(j);

% Integrais do erro e = r - psi na janela, pela regra do trapezio sobre o
% passo de integracao (1 ms). Calculadas antes do teste de amplitude: com
% referencia nula (so rejeicao de disturbio) elas continuam valendo.
e = r - yj;
m.iae = trapz(tj, abs(e));
m.ise = trapz(tj, e.^2);

y0  = yj(1);
amp = r - y0;
if abs(amp) < 1e-9, return, end

s = sign(amp);
[pico, ip] = max(s*(yj - y0));
m.sobressinal = max(0, (pico - abs(amp)) / abs(amp) * 100);
m.tp = tj(ip) - t_deg;

% Acomodacao: primeiro instante depois do qual psi nao sai mais da faixa.
fora = find(abs(yj - r) > 0.02*abs(amp), 1, 'last');
if isempty(fora)
    m.ts = 0;
elseif fora < numel(j)
    m.ts = tj(fora + 1) - t_deg;
end

% Erro de regime: media dos ultimos 10% da janela, no minimo 1 s.
w = tj >= tj(end) - max(1, 0.1*(tj(end) - tj(1)));
m.erro = mean(yj(w)) - r;
end

function s = num_ou_traco(v, fmt)
if isempty(v) || isnan(v)
    s = char(8212);
else
    s = sprintf(fmt, v);
end
end

function s = primeira_linha(err)
msg = regexprep(err.message, '<[^>]*>', '');
linhas = strtrim(splitlines(msg));
linhas = linhas(~cellfun('isempty', linhas));
if isempty(linhas)
    s = err.identifier;
else
    s = linhas{1};
end
end

function s = tx(s)
%TX Converte entidades HTML em caracteres, para o arquivo ficar em ASCII.
persistent tab
if isempty(tab)
    tab = {'&aacute;', 225; '&acirc;', 226; '&atilde;', 227; '&ccedil;', 231; ...
           '&eacute;', 233; '&ecirc;', 234; '&iacute;', 237; '&oacute;', 243; ...
           '&ocirc;', 244; '&otilde;', 245; '&uacute;', 250; '&Aacute;', 193; ...
           '&deg;', 176; '&middot;', 183; '&mdash;', 8212; '&psi;', 968; ...
           '&phi;', 966; '&Delta;', 916};
end
for i = 1:size(tab, 1)
    s = strrep(s, tab{i, 1}, char(tab{i, 2}));
end
end

function poe_em(h, linha)
% Componente da barra lateral ocupando as duas colunas.
h.Layout.Row    = linha;
h.Layout.Column = [1 2];
end

function secao(pai, linha, texto, COR)
l = uilabel(pai, 'Text', texto, 'FontWeight', 'bold', ...
            'FontColor', COR.texto, 'VerticalAlignment', 'bottom');
poe_em(l, linha);
end

function h = campo_em(pai, linha, texto, valor, limites)
l = uilabel(pai, 'Text', texto);
l.Layout.Row    = linha;
l.Layout.Column = 1;
h = uieditfield(pai, 'numeric', 'Value', valor, 'Limits', limites, ...
                'HorizontalAlignment', 'right');
h.Layout.Row    = linha;
h.Layout.Column = 2;
end


% =========================================================================
% Funcoes locais: modelo
% =========================================================================

function in = monta_entrada(nome_modelo, VAR, cfg, p)
%MONTA_ENTRADA Monta o Simulink.SimulationInput a partir dos campos da tela.
%   Comeca com TODAS as variaveis do trms_params e sobrescreve, no proprio
%   struct, as que vem da tela. So no fim faz o setVariable, uma vez por
%   nome, sem repeticao.
in = Simulink.SimulationInput(nome_modelo);
in = in.setModelParameter('StopTime', sprintf('%.10g', cfg.tf));

v = p;

v = poe(v, VAR.modo,    1);              % arfagem fechada
v = poe(v, VAR.mascara, cfg.mascara);

v = poe(v, VAR.kp, cfg.kp);
v = poe(v, VAR.ki, cfg.ki);
v = poe(v, VAR.kd, cfg.kd);

% Referencia: bloco Step com Initial value = 0 (referencial do encoder),
% Step time = t_degrau e Final value = ref_pitch.
v = poe(v, VAR.ref,  cfg.ref_encoder);
v = poe(v, VAR.tdeg, cfg.tdeg);

% u_m_ts existe so para o modelo compilar: em modo = 1 o trms_sel_entrada
% usa a saida do controlador, nao esse ramo.
v = poe(v, VAR.u_main, timeseries([0; 0], [0; cfg.tf]));

% Disturbio cruzado: degrau em u2. O From Workspace precisa estar com
% interpolacao DESLIGADA e 'Holding final value', senao o degrau vira rampa.
if cfg.pert_ativa
    t_u2 = [0; cfg.pert_t; cfg.tf];
    v_u2 = [0; cfg.pert_amp; cfg.pert_amp];
else
    t_u2 = [0; cfg.tf];
    v_u2 = [0; 0];
end
v = poe(v, VAR.u_tail, timeseries(v_u2, t_u2));

nomes = fieldnames(v);
for k = 1:numel(nomes)
    in = in.setVariable(nomes{k}, v.(nomes{k}));
end
end

function adicionadas = poe_no_path(pastas)
%POE_NO_PATH Poe as pastas no topo do path, na ordem dada (a ultima fica
%   em primeiro). Devolve so as que ainda nao estavam no path, para que o
%   app tire ao fechar apenas o que ele mesmo acrescentou.
atuais = strsplit(path, pathsep);
adicionadas = {};
for i = 1:numel(pastas)
    pasta = pastas{i};
    if isempty(pasta) || ~isfolder(pasta), continue, end
    ja_estava = any(strcmpi(atuais, pasta));    % Windows ignora maiusculas
    addpath(pasta);                             % sobe para o topo de todo jeito
    if ~ja_estava
        adicionadas{end + 1} = pasta; %#ok<AGROW>
    end
end
end

function v = poe(v, nome, valor)
%POE Grava um campo no struct de variaveis, ignorando nomes vazios.
if ~isempty(nome)
    v.(nome) = valor;
end
end

function [w_m, w_t] = le_rotores(out, nomes, t)
%LE_ROTORES Velocidades dos rotores no vetor de tempo t, se o modelo as
%   registrar. Se faltar qualquer uma, devolve [] e as pas ficam paradas.
w_m = [];  w_t = [];
if ~all(ismember(nomes, out.who)), return, end
[tm, w_m] = le_sinal(out, nomes(1));
[tt, w_t] = le_sinal(out, nomes(2));
if numel(tm) ~= numel(t) || any(tm ~= t)
    w_m = interp1(tm, w_m, t, 'nearest', 'extrap');
end
if numel(tt) ~= numel(t) || any(tt ~= t)
    w_t = interp1(tt, w_t, t, 'nearest', 'extrap');
end
end

function y = le_opcional(out, nomes, t)
%LE_OPCIONAL Primeiro sinal de NOMES que existir, no vetor de tempo t.
%   Devolve [] se nenhum existir ou se o registro tiver menos de 3
%   amostras (um sinal constante registrado uma vez so nao serve).
y = [];
if ~any(ismember(nomes, out.who)), return, end
[ty, yy] = le_sinal(out, nomes);
if numel(ty) < 3, return, end
[ty, iu] = unique(ty);
yy = yy(iu);
if numel(ty) ~= numel(t) || any(ty ~= t)
    y = interp1(ty, yy, t, 'nearest', 'extrap');
else
    y = yy;
end
end

function [t, psi, phi] = le_saida(out, nomes_psi, nomes_phi)
%LE_SAIDA Extrai arfagem e guinada, no vetor de tempo da arfagem.
[t,  psi] = le_sinal(out, nomes_psi);
[t2, phi] = le_sinal(out, nomes_phi);
% As duas saidas podem ter sido registradas com tempos diferentes.
if numel(t2) ~= numel(t) || any(t2 ~= t)
    phi = interp1(t2, phi, t, 'nearest', 'extrap');
end
end

function [t, y] = le_sinal(out, candidatos)
%LE_SINAL Le o primeiro nome de CANDIDATOS que existir na saida do sim.
%   Aceita timeseries, struct com tempo ou Array (tempo em tout). Se nenhum
%   nome existir, o erro lista as saidas que o modelo registrou.
lista = out.who;
nome  = '';
for i = 1:numel(candidatos)
    if any(strcmp(lista, candidatos{i}))
        nome = candidatos{i};
        break
    end
end
if isempty(nome)
    error('trms_app:saida', ...
          'Nenhuma das saidas {%s} existe. Saidas registradas pelo modelo: %s', ...
          strjoin(candidatos, ', '), strjoin(lista, ', '));
end

s = out.get(nome);
if isa(s, 'timeseries')
    t = s.Time;
    y = squeeze(s.Data);
elseif isstruct(s) && isfield(s, 'time')
    t = s.time;
    y = s.signals.values;
else
    t = out.tout;
    y = s;
end
if ~isvector(y)
    y = y(:, 1);
end
t = double(t(:));
y = double(y(:));
end

function p = le_params()
%LE_PARAMS Roda o trms_params num workspace isolado e devolve tudo num struct.
%   E funcao local, e nao aninhada, porque um script nao roda dentro de
%   funcao aninhada.
trms_params;
nomes = setdiff(who, {'ans'});   % lido antes de criar qualquer outra variavel
for i_ = 1:numel(nomes)
    p.(nomes{i_}) = eval(nomes{i_});
end
end

function linhas = causas(err, nivel)
%CAUSAS Desdobra um MException e suas causas aninhadas em linhas de texto.
pre = repmat('  ', 1, nivel);
msg = regexprep(err.message, '<[^>]*>', '');          % tira os links
linhas = [{[pre err.identifier]}; ...
          cellfun(@(s) [pre s], splitlines(msg), 'UniformOutput', false)];
for k = 1:numel(err.cause)
    linhas = [linhas; {''}; causas(err.cause{k}, nivel + 1)]; %#ok<AGROW>
end
end