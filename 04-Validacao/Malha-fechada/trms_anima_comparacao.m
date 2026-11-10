function trms_anima_comparacao(Rk, opcoes)
%TRMS_ANIMA_COMPARACAO Anima bancada e gemeo lado a lado, no mesmo relogio.
%
%   R = compara_pid_c3(pasta);
%   trms_anima_comparacao(R(1))                          % 4/6/8, tempo real
%   trms_anima_comparacao(R(1), struct('velocidade', 4)) % 4x mais rapido
%   trms_anima_comparacao(R(3))                          % Teste 6 (u2 aos 50 s)
%
%   Rk e UM elemento da saida do COMPARA_PID_C3. Campos usados:
%     Rk.B.t, Rk.B.psi, Rk.B.phi   bancada, referencial dos encoders [rad]
%     Rk.M.t, Rk.M.psi, Rk.M.phi   gemeo, ja quantizado e amostrado nos
%                                  instantes da bancada
%     Rk.rotulo, Rk.ref, Rk.t_deg  (opcionais) titulo e degrau de referencia
%   Os dois lados saem do mesmo pipeline que gerou a tabela de indices,
%   entao a animacao mostra exatamente o que foi comparado.
%
%   opcoes:
%     velocidade   fator de tempo (1 = tempo real). Padrao 1.
%     fps          quadros por segundo alvo. Padrao 25.
%     repouso      angulo fisico de repouso desenhado [rad]. Escalar (vale
%                  para os dois lados) ou [bancada gemeo]. Padrao: psi_0
%                  do trms_params (-30,8 graus). Use [-38*pi/180, psi_0]
%                  para desenhar a bancada no repouso medido.
%     travar_yaw   true desenha os dois com guinada zero, isolando a
%                  arfagem. Padrao false: cada lado com a propria guinada.
%     video        nome de arquivo .mp4. Se informado, grava quadro a
%                  quadro, sem depender do relogio, em vez de reproduzir.
%                  Nao redimensione a janela durante a gravacao.
%     titulo       false omite o titulo geral (ganhos, repouso desenhado e
%                  guinada), para figuras em que a legenda ja declara isso.
%                  Padrao true.
%
%   ROTULOS
%   Os textos sao em portugues, com virgula decimal. Os angulos sobre cada
%   cena (psi e phi fisicos desenhados) sao escritos por esta funcao; o
%   texto de angulos criado pelo trms_cena_criar fica oculto nas duas
%   cenas, sem alterar as funcoes da cena usadas pelo app.
%
%   Exemplo para a monografia (ultimo quadro, sem titulo geral):
%     trms_anima_comparacao(R(1), struct('velocidade', 4, 'titulo', false))
%     exportgraphics(gcf, 'anim_comparacao.png', 'Resolution', 300)
%
%   REFERENCIAIS
%   Os dois registros estao no referencial dos encoders (zero no repouso).
%   Para a cena soma-se um repouso fisico. Com o mesmo repouso nos dois
%   lados, as vigas partem juntas e so a dinamica difere. Com o repouso
%   medido na bancada, aparecem tambem os 7 graus do G_y em aberto. A
%   escolha vai no titulo da figura; declare-a em qualquer imagem que for
%   para a monografia.
%
%   GUINADA
%   Com travar_yaw = false, o gemeo gira cerca de -40 graus durante o
%   controle de arfagem e a bancada volta para perto de zero. E a limitacao
%   conhecida do torque de reacao do rotor principal (CR_m nominal), nao
%   defeito da animacao.
%
%   Ver tambem COMPARA_PID_C3, TRMS_CENA_CRIAR, TRMS_CENA_ATUALIZAR.

if nargin < 2, opcoes = struct(); end
if numel(Rk) ~= 1
    error('trms:comparacao', 'Passe um ensaio so, por exemplo R(1).');
end
if ~isfield(Rk, 'B') || ~isfield(Rk, 'M')
    error('trms:comparacao', 'Rk precisa dos campos B e M do compara_pid_c3.');
end

opcoes = padrao(opcoes, 'velocidade', 1);
opcoes = padrao(opcoes, 'fps',        25);
opcoes = padrao(opcoes, 'travar_yaw', false);
opcoes = padrao(opcoes, 'video',      '');
opcoes = padrao(opcoes, 'titulo',     true);
if ~isfield(opcoes, 'repouso') || isempty(opcoes.repouso)
    opcoes.repouso = psi0_modelo();
end
rep = opcoes.repouso;
if isscalar(rep), rep = [rep rep]; end

% --- Series no mesmo vetor de tempo ---------------------------------------
B = Rk.B;
M = Rk.M;
t = B.t(:);
if numel(M.t) ~= numel(t) || any(abs(M.t(:) - t) > 1e-9)
    M.psi = interp1(M.t(:), M.psi(:), t, 'nearest', 'extrap');
    M.phi = interp1(M.t(:), M.phi(:), t, 'nearest', 'extrap');
end
[t, iu] = unique(t);                 % griddedInterpolant exige t crescente
psi_b = B.psi(iu);  psi_m = M.psi(iu);
phi_b = B.phi(iu) - B.phi(iu(1));
phi_m = M.phi(iu) - M.phi(iu(1));

% Angulos da cena: encoder + repouso fisico.
cena_psi_b = psi_b(:) + rep(1);
cena_psi_m = psi_m(:) + rep(2);
if opcoes.travar_yaw
    cena_phi_b = zeros(size(t));
    cena_phi_m = zeros(size(t));
else
    cena_phi_b = phi_b(:);
    cena_phi_m = phi_m(:);
end

F.pb = griddedInterpolant(t, cena_psi_b, 'linear', 'nearest');
F.pm = griddedInterpolant(t, cena_psi_m, 'linear', 'nearest');
F.fb = griddedInterpolant(t, cena_phi_b, 'linear', 'nearest');
F.fm = griddedInterpolant(t, cena_phi_m, 'linear', 'nearest');

% --- Figura ----------------------------------------------------------------
% Figura classica, nao uifigure: renderiza bem mais quadros por segundo.
g     = 180/pi;
cor_b = [0.15 0.15 0.15];
cor_m = [0.85 0.33 0.10];
rotulo = '';
if isfield(Rk, 'rotulo'), rotulo = Rk.rotulo; end
if contains(rotulo, '/'), rotulo = ['Ganhos ' rotulo]; end

% Acentos por codigo de caractere, para o arquivo continuar ASCII
GEMEO = ['G' char(234) 'meo'];            % Gemeo com circunflexo
REFER = ['Refer' char(234) 'ncia'];       % Referencia com circunflexo
GRAU  = char(176);                        % simbolo de grau

fig = figure('Name', 'TRMS - bancada x gemeo', 'Color', 'w', ...
             'NumberTitle', 'off', 'Position', [60 60 1300 760]);
tl  = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

geo  = trms_cena_geometria();
ax_b = nexttile(tl, 1, [2 1]);
cb   = trms_cena_criar(geo, ax_b);
title(ax_b, 'Bancada (medida)');
ax_m = nexttile(tl, 2, [2 1]);
cm   = trms_cena_criar(geo, ax_m);
title(ax_m, [GEMEO ' (simulado)']);

% Angulos sobre cada cena: o texto da cena (pitch/yaw em deg) fica oculto
% e e' substituido por psi e phi em graus, com virgula decimal.
esconde_texto_cena(ax_b);
esconde_texto_cena(ax_m);
txt_b = text(ax_b, 0.03, 0.97, '', 'Units', 'normalized', ...
             'VerticalAlignment', 'top', 'FontSize', 11);
txt_m = text(ax_m, 0.03, 0.97, '', 'Units', 'normalized', ...
             'VerticalAlignment', 'top', 'FontSize', 11);

if opcoes.titulo
    txt_yaw = 'cada lado com a sua guinada';
    if opcoes.travar_yaw, txt_yaw = 'guinada travada na cena'; end
    title(tl, sprintf('%s | repouso desenhado: bancada %s%s, %s %s%s | %s', ...
          rotulo, num_br(rep(1)*g), GRAU, lower(GEMEO), num_br(rep(2)*g), ...
          GRAU, txt_yaw));
end

% Arfagem no referencial do encoder, como nas tabelas.
ax_p = nexttile(tl, 5);
hold(ax_p, 'on');  grid(ax_p, 'on');
stairs(ax_p, t, psi_b*g, 'Color', cor_b, 'DisplayName', 'Bancada');
plot(ax_p, t, psi_m*g, 'Color', cor_m, 'LineWidth', 1.2, 'DisplayName', GEMEO);
if isfield(Rk, 'ref') && isfield(Rk, 't_deg')
    stairs(ax_p, [t(1) Rk.t_deg t(end)], [0 Rk.ref Rk.ref]*g, 'k--', ...
           'DisplayName', REFER);
end
cur_p = xline(ax_p, t(1), 'k-', 'HandleVisibility', 'off');
xlabel(ax_p, 't (s)');  ylabel(ax_p, '\psi encoder (graus)');
legend(ax_p, 'Location', 'southeast');
xlim(ax_p, [t(1) t(end)]);

ax_f = nexttile(tl, 6);
hold(ax_f, 'on');  grid(ax_f, 'on');
stairs(ax_f, t, phi_b*g, 'Color', cor_b, 'DisplayName', 'Bancada');
plot(ax_f, t, phi_m*g, 'Color', cor_m, 'LineWidth', 1.2, 'DisplayName', GEMEO);
cur_f = xline(ax_f, t(1), 'k-', 'HandleVisibility', 'off');
xlabel(ax_f, 't (s)');  ylabel(ax_f, '\phi encoder (graus)');
legend(ax_f, 'Location', 'best');
xlim(ax_f, [t(1) t(end)]);

% --- Reproducao -------------------------------------------------------------
t0    = t(1);
t_fim = t(end);
desenha(t0);
drawnow;

if isempty(opcoes.video)
    % Dirigida pelo relogio: quadro atrasado vira salto, nao atraso.
    pause(0.5);
    dt_alvo = 1/opcoes.fps;
    n_q = 0;
    relogio = tic;
    while isvalid(fig)
        t_q = tic;
        tk  = min(t_fim, t0 + toc(relogio)*opcoes.velocidade);
        desenha(tk);
        drawnow limitrate
        n_q = n_q + 1;
        if tk >= t_fim, break, end
        pause(max(0, dt_alvo - toc(t_q)));
    end
    dur = toc(relogio);
    fprintf('animacao: %.1f s reais | %.1f s previstos | %.0f fps\n', ...
            dur, (t_fim - t0)/opcoes.velocidade, n_q/dur);
else
    % Gravacao quadro a quadro: o video sai em tempo certo mesmo que a
    % maquina nao consiga desenhar em tempo real.
    vw = VideoWriter(opcoes.video, 'MPEG-4');
    vw.FrameRate = opcoes.fps;
    open(vw);
    tq = t0:(opcoes.velocidade/opcoes.fps):t_fim;
    try
        for tk = tq
            desenha(tk);
            drawnow;
            writeVideo(vw, getframe(fig));
        end
    catch err
        close(vw);
        rethrow(err);
    end
    close(vw);
    fprintf('video gravado em %s (%d quadros, %.1f s)\n', ...
            opcoes.video, numel(tq), numel(tq)/opcoes.fps);
end

    function desenha(tk)
        trms_cena_atualizar(cb, F.pb(tk), F.fb(tk));
        trms_cena_atualizar(cm, F.pm(tk), F.fm(tk));
        set(txt_b, 'String', rotulo_angulos(F.pb(tk), F.fb(tk)));
        set(txt_m, 'String', rotulo_angulos(F.pm(tk), F.fm(tk)));
        set(cur_p, 'Value', tk);
        set(cur_f, 'Value', tk);
    end

end


% =========================================================================
% Funcoes locais
% =========================================================================

function p0 = psi0_modelo()
%PSI0_MODELO Repouso de arfagem do modelo, lido do trms_params isolado.
%   Funcao local sem funcoes aninhadas: aceita variaveis criadas por script.
trms_params;
p0 = psi_0;
end


function esconde_texto_cena(ax)
%ESCONDE_TEXTO_CENA Oculta os textos criados pelo trms_cena_criar no eixo.
%   Titulo e rotulos dos eixos nao sao filhos visiveis, logo nao sao
%   afetados. Chamar antes de criar os textos proprios desta funcao.
h = findobj(ax, 'Type', 'text');
if isempty(h)
    warning('trms:comparacao', ...
        'Texto de angulos da cena nao encontrado no eixo; ele continua visivel.');
end
set(h, 'Visible', 'off');
end


function s = rotulo_angulos(psi, phi)
%ROTULO_ANGULOS Texto "psi = x,x graus   phi = y,y graus" (interpretador TeX).
s = sprintf('\\psi = %s%s     \\phi = %s%s', ...
            num_br(psi*180/pi), char(176), num_br(phi*180/pi), char(176));
end


function s = num_br(x)
%NUM_BR Numero com uma casa e virgula decimal (sem "-0,0").
x = round(x*10)/10;
if x == 0, x = 0; end                     % troca -0 por 0
s = strrep(sprintf('%.1f', x), '.', ',');
end


function s = padrao(s, campo, valor)
%PADRAO Preenche um campo ausente ou vazio da struct de opcoes.
if ~isfield(s, campo) || isempty(s.(campo))
    s.(campo) = valor;
end
end