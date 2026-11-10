function R = trms_cena_ref_criar(cena, opcoes)
%TRMS_CENA_REF_CRIAR Linhas de referencia angular e fantasma da referencia na cena 3D.
%
%   R = TRMS_CENA_REF_CRIAR(cena) acrescenta, a uma cena de TRMS_CENA_CRIAR:
%
%     LINHAS (de onde os angulos sao medidos)
%       - eixo de guinada: vertical, acima do pivo;
%       - phi = 0: horizontal, fixa na mesa, na direcao em que phi e zero;
%       - psi = 0: horizontal no plano vertical da viga, dos dois lados do
%         pivo. Gira junto com a guinada, entao mostra a arfagem em
%         qualquer phi;
%       - arcos de psi (no plano da viga) e de phi (no plano horizontal do
%         pivo), do zero ate a viga, atualizados a cada quadro.
%     FANTASMA
%       - contorno da viga e dos dois rotores na pose da referencia de
%         arfagem, com discos translucidos no lugar das protecoes. Fica no
%         plano vertical da viga, porque a guinada esta em malha aberta e
%         nao tem referencia. Quando psi = psi_ref, a viga do fantasma some
%         dentro da viga real e sobram so os discos em volta dos rotores.
%
%   R = TRMS_CENA_REF_CRIAR(cena, opcoes) com:
%     opcoes.linhas    cria as linhas (padrao true)
%     opcoes.fantasma  cria o fantasma (padrao true)
%     opcoes.cor_ref   cor do fantasma (padrao cinza claro [0.70 0.70 0.70])
%     opcoes.cor_psi   cor das linhas de psi (padrao azul [0.13 0.40 0.75])
%     opcoes.cor_phi   cor das linhas de phi (padrao vermelho [0.80 0.30 0.20])
%     opcoes.alfa      opacidade dos discos do fantasma (padrao 0.25)
%     opcoes.rotulos   escreve 'psi = 0', 'phi = 0' e os nomes dos arcos
%                      (padrao true)
%   As cores padrao das linhas sao as do app: azul para psi e vermelho
%   para phi, as mesmas dos graficos.
%
%   Depois de criado, chame TRMS_CENA_REF_ATUALIZAR a cada quadro e
%   TRMS_CENA_REF_MOSTRAR para ligar e desligar as linhas e o fantasma.
%   Nada aqui calcula dinamica: so desenha os angulos recebidos.
%
%   ORGANIZACAO DOS OBJETOS
%   O fantasma, a linha de psi = 0 e o arco de psi sao filhos de
%   cena.t_yaw: giram com a viga sem custo por quadro. O eixo de guinada, a
%   linha de phi = 0 e o arco de phi ficam no referencial da mesa. A pose
%   do fantasma so e recalculada quando a referencia muda.
%
%   TRANSPARENCIA
%   A cena usa SortMethod 'childorder', escolhido supondo tudo opaco. So os
%   dois discos do fantasma sao translucidos; como sao criados depois da
%   planta, sao desenhados por ultimo e a mistura sai correta. Os discos
%   ficam 12 mm fora do plano das pas e das protecoes, para nao disputar
%   profundidade com elas quando a viga chega na referencia (o que faria a
%   imagem piscar).
%
%   Ver tambem TRMS_CENA_REF_ATUALIZAR, TRMS_CENA_REF_MOSTRAR,
%   TRMS_CENA_CRIAR.

if nargin < 2 || isempty(opcoes)
    opcoes = struct();
end
op.linhas   = campo(opcoes, 'linhas', true);
op.fantasma = campo(opcoes, 'fantasma', true);
op.cor_ref  = campo(opcoes, 'cor_ref', [0.70 0.70 0.70]);
op.cor_psi  = campo(opcoes, 'cor_psi', [0.13 0.40 0.75]);
op.cor_phi  = campo(opcoes, 'cor_phi', [0.80 0.30 0.20]);
op.alfa     = campo(opcoes, 'alfa', 0.25);
op.rotulos  = campo(opcoes, 'rotulos', true);

geo = cena.geo;
ax  = cena.ax;

% Mesma conversao de angulos da TRMS_CENA_ATUALIZAR.
g.h            = geo.h_pivo;
g.sinal_pitch  = geo.sinal_pitch;
g.sinal_yaw    = geo.sinal_yaw;
g.offset_pitch = geo.offset_pitch;
g.offset_yaw   = geo.offset_yaw;

% Comprimento das linhas: um pouco alem das protecoes, para aparecerem
% para fora da planta.
L = max(geo.l_main + geo.guarda_raio_main, geo.l_tail + geo.guarda_raio_tail) + 0.04;

R.g      = g;
R.op     = op;
R.r_psi  = 0.16;           % raio do arco de psi [m]
R.r_phi  = 0.22;           % raio do arco de phi [m]
R.mesa   = gobjects(0);    % grupo das linhas no referencial da mesa
R.viga   = gobjects(0);    % grupo das linhas que seguem a guinada
R.arco_psi = gobjects(0);
R.arco_phi = gobjects(0);
R.txt_psi  = gobjects(0);
R.txt_phi  = gobjects(0);
R.fant_on   = gobjects(0); % liga/desliga do fantasma (usuario)
R.fant_pose = gobjects(0); % pose do fantasma (referencia)

cinza = [0.45 0.45 0.48];

% =========================================================================
% Linhas
% =========================================================================
if op.linhas
    R.mesa = hggroup('Parent', ax);
    R.viga = hgtransform('Parent', cena.t_yaw);    % identidade: so herda a guinada

    % Eixo de guinada, acima do pivo.
    line('Parent', R.mesa, 'XData', [0 0], 'YData', [0 0], ...
         'ZData', g.h + [0 0.30], 'LineStyle', '-.', 'Color', cinza, ...
         'LineWidth', 1);

    % phi = 0: fixa na mesa, na altura do pivo.
    a0 = g.sinal_yaw * g.offset_yaw;
    line('Parent', R.mesa, 'XData', [0 L*cos(a0)], 'YData', [0 L*sin(a0)], ...
         'ZData', [g.h g.h], 'LineStyle', '--', 'Color', op.cor_phi, ...
         'LineWidth', 1.2);

    % psi = 0: horizontal no plano da viga, dos dois lados do pivo.
    line('Parent', R.viga, 'XData', [-L L], 'YData', [0 0], ...
         'ZData', [g.h g.h], 'LineStyle', '--', 'Color', op.cor_psi, ...
         'LineWidth', 1.2);

    % Arcos, posicionados por TRMS_CENA_REF_ATUALIZAR.
    R.arco_psi = line('Parent', R.viga, 'XData', NaN, 'YData', NaN, ...
                      'ZData', NaN, 'Color', op.cor_psi, 'LineWidth', 1.8);
    R.arco_phi = line('Parent', R.mesa, 'XData', NaN, 'YData', NaN, ...
                      'ZData', NaN, 'Color', op.cor_phi, 'LineWidth', 1.8);

    if op.rotulos
        % 'phi = 0' na ponta da linha fixa; 'psi = 0' na ponta do lado da
        % cauda, para nao sobrepor ao 'phi = 0' quando phi = 0.
        text((L + 0.02)*cos(a0), (L + 0.02)*sin(a0), g.h, '\phi = 0', ...
             'Parent', R.mesa, 'Color', op.cor_phi, 'FontSize', 9, ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
        text(-(L + 0.02), 0, g.h, '\psi = 0', 'Parent', R.viga, ...
             'Color', op.cor_psi, 'FontSize', 9, 'HorizontalAlignment', 'right', ...
             'VerticalAlignment', 'bottom');
        R.txt_psi = text(0, 0, g.h, '\psi', 'Parent', R.viga, 'Color', op.cor_psi, ...
                         'FontSize', 10, 'FontWeight', 'bold', ...
                         'HorizontalAlignment', 'center', ...
                         'VerticalAlignment', 'middle');
        R.txt_phi = text(0, 0, g.h, '\phi', 'Parent', R.mesa, 'Color', op.cor_phi, ...
                         'FontSize', 10, 'FontWeight', 'bold', ...
                         'HorizontalAlignment', 'center', ...
                         'VerticalAlignment', 'middle');
    end
end

% =========================================================================
% Fantasma
% =========================================================================
if op.fantasma
    R.fant_on   = hgtransform('Parent', cena.t_yaw);
    R.fant_pose = hgtransform('Parent', R.fant_on, 'Visible', 'off', ...
                              'UserData', NaN);    % ultima referencia desenhada

    % No referencial da viga: origem no pivo, +x para o rotor principal.
    line('Parent', R.fant_pose, 'XData', [-geo.l_tail geo.l_main], ...
         'YData', [0 0], 'ZData', [0 0], 'Color', op.cor_ref, 'LineWidth', 2.5);

    folga = 0.012;   % fora do plano das pas e do aro das protecoes [m]
    n  = 48;
    aa = linspace(0, 2*pi, n + 1);
    aa(end) = [];

    % Rotor principal: disco horizontal (eixo z local) acima das pas.
    rm = geo.guarda_raio_main;
    disco(R.fant_pose, ...
          [geo.l_main + rm*cos(aa); rm*sin(aa); folga + 0*aa].', op);

    % Rotor de cauda: disco vertical (eixo y local) ao lado das pas.
    rt = geo.guarda_raio_tail;
    disco(R.fant_pose, ...
          [-geo.l_tail + rt*cos(aa); folga + 0*aa; rt*sin(aa)].', op);
end

end


% =========================================================================
% Funcoes locais
% =========================================================================

function disco(pai, V, op)
% Disco translucido com borda opaca, na cor da referencia.
patch('Parent', pai, 'Vertices', V, 'Faces', 1:size(V, 1), ...
      'FaceColor', op.cor_ref, 'FaceAlpha', op.alfa, ...
      'EdgeColor', op.cor_ref, 'LineWidth', 1.5, 'FaceLighting', 'none');
end

function v = campo(s, nome, padrao)
if isstruct(s) && isfield(s, nome) && ~isempty(s.(nome))
    v = s.(nome);
else
    v = padrao;
end
end