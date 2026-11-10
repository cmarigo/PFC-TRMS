function cena = trms_cena_criar(geo, ax)
%TRMS_CENA_CRIAR Monta a cena 3D do TRMS e devolve os handles de transformacao.
%
%   cena = TRMS_CENA_CRIAR() cria uma figura nova com a geometria padrao.
%   cena = TRMS_CENA_CRIAR(geo) usa a estrutura devolvida por
%          TRMS_CENA_GEOMETRIA.
%   cena = TRMS_CENA_CRIAR(geo, ax) desenha nos eixos ax (util para embutir
%          num App Designer / uifigure).
%
%   ESTRUTURA DA CENA
%
%     eixos (referencial fixo da mesa)
%       |-- base fixa: pedestal + coluna vertical   [estatico]
%       |-- cena.t_yaw          rotacao em torno de +z
%             |-- cena.t_pitch      rotacao em torno de +y LOCAL
%                   |-- haste dos rotores
%                   |-- bloco do pivo (deslocado no y local)
%                   |-- protecoes circulares dos dois rotores
%                   |-- cena.t_pa_main   giro da helice principal (+z local)
%                   |-- cena.t_pa_tail   giro da helice de cauda  (+y local)
%                   |-- haste e peso do contrapeso
%
%   Como t_pitch e filho de t_yaw, o eixo de pitch acompanha a rotacao de
%   yaw.
%
%   Tudo que na bancada e uma peca so esta sob t_pitch: haste dos rotores,
%   bloco do pivo, contrapeso e protecoes. O unico corpo rigido movel da
%   cena e esse conjunto. As protecoes nao sao filhas de t_pa_main /
%   t_pa_tail porque o aro e fixo a haste e so a helice gira dentro dele.
%
%   Esta funcao NAO contem dinamica: apenas posiciona geometria a partir de
%   angulos calculados externamente pelo modelo identificado.
%
%   Ver tambem TRMS_CENA_ATUALIZAR.

if nargin < 1 || isempty(geo)
    geo = trms_cena_geometria();
end

if nargin < 2 || isempty(ax)
    fig = figure('Name', 'TRMS - representacao 3D', ...
                 'Color', geo.cor_fundo, ...
                 'NumberTitle', 'off');
    ax = axes('Parent', fig);
end

cla(ax);
hold(ax, 'on');

% --- Referencial fixo ----------------------------------------------------
% Pedestal e coluna nao giram: no TRMS a coluna e fixa e o conjunto gira em
% torno dela. A base e retangular, como na bancada.
prim_caixa(ax, [geo.base_x geo.base_y geo.base_altura], ...
           [0 0 geo.base_altura/2], geo.cor_base);

prim_cilindro(ax, geo.coluna_raio, geo.h_pivo - geo.base_altura, [0 0 1], ...
              [0 0 (geo.h_pivo + geo.base_altura)/2], geo.cor_coluna);

% --- Cadeia cinematica ---------------------------------------------------
cena.ax      = ax;
cena.geo     = geo;
cena.t_yaw   = hgtransform('Parent', ax);
cena.t_pitch = hgtransform('Parent', cena.t_yaw);

% A partir daqui a origem local e o proprio pivo de pitch.
% Haste dos rotores ao longo de x: +x = rotor principal, -x = rotor de cauda.
comp_viga = geo.l_main + geo.l_tail;
prim_caixa(cena.t_pitch, [comp_viga geo.viga_lado geo.viga_lado], ...
           [(geo.l_main - geo.l_tail)/2 0 0], geo.cor_viga);

% Bloco do pivo: peca unica, rigida com a haste. Deslocada no y local, larga
% o bastante para atravessar o eixo e alcancar a fixacao do contrapeso.
prim_caixa(cena.t_pitch, geo.bloco_pivo, geo.bloco_pivo_pos, geo.cor_hub);

% --- Rotor principal -----------------------------------------------------
% Empuxo perpendicular a haste, no plano vertical -> eixo do rotor em +z local.
p_main = [geo.l_main 0 0];
prim_cilindro(cena.t_pitch, geo.carcaca_raio, geo.carcaca_comp, [0 0 1], ...
              p_main, geo.cor_main);

desenha_guarda(cena.t_pitch, p_main, geo.guarda_raio_main, geo.guarda_tubo, ...
               geo.guarda_n_barras_main, 'z', geo.cor_guarda);

cena.t_pa_main = hgtransform('Parent', cena.t_pitch);
set(cena.t_pa_main, 'Matrix', makehgtform('translate', p_main));
desenha_pas(cena.t_pa_main, geo.rotor_main_raio, geo.pa_largura, ...
            geo.pa_espessura, geo.n_pas, 'z', geo.cor_pa);

% --- Rotor de cauda ------------------------------------------------------
% Empuxo horizontal perpendicular a haste -> eixo do rotor em +y local.
p_tail = [-geo.l_tail 0 0];
prim_cilindro(cena.t_pitch, geo.carcaca_raio, geo.carcaca_comp, [0 1 0], ...
              p_tail, geo.cor_tail);

desenha_guarda(cena.t_pitch, p_tail, geo.guarda_raio_tail, geo.guarda_tubo, ...
               geo.guarda_n_barras_tail, 'y', geo.cor_guarda);

cena.t_pa_tail = hgtransform('Parent', cena.t_pitch);
set(cena.t_pa_tail, 'Matrix', makehgtform('translate', p_tail));
desenha_pas(cena.t_pa_tail, geo.rotor_tail_raio, geo.pa_largura, ...
            geo.pa_espessura, geo.n_pas, 'y', geo.cor_pa);

% --- Haste e peso do contrapeso ------------------------------------------
% Saem da borda externa do bloco do pivo, e nao do eixo da haste.
o_cp   = geo.cp_origem;
dir_cp = [cos(geo.cp_angulo) 0 sin(geo.cp_angulo)];
prim_cilindro(cena.t_pitch, geo.cp_haste_raio, geo.cp_haste_comp, dir_cp, ...
              o_cp + dir_cp * geo.cp_haste_comp/2, geo.cor_cp);
prim_cilindro(cena.t_pitch, geo.cp_raio, geo.cp_comp, dir_cp, ...
              o_cp + dir_cp * geo.cp_haste_comp * geo.cp_pos, geo.cor_cp);

% --- Ajustes de visualizacao --------------------------------------------
% O alcance considera as protecoes, que ultrapassam as pontas da haste.
alcance = max([geo.l_main + geo.guarda_raio_main, ...
               geo.l_tail + geo.guarda_raio_tail, ...
               geo.cp_haste_comp, ...
               geo.base_x/2]) * 1.25;
set(ax, 'XLim', [-alcance alcance], ...
        'YLim', [-alcance alcance], ...
        'ZLim', [0 geo.h_pivo + alcance*0.75]);
daspect(ax, [1 1 1]);
axis(ax, 'manual');
grid(ax, 'on');
box(ax, 'on');
if isfield(geo, 'vista')
    view(ax, geo.vista(1), geo.vista(2));
else
    view(ax, 135, 18);
end
xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
zlabel(ax, 'z [m]');

% Iluminacao, criada uma unica vez.
light('Parent', ax, 'Position', [1 -1 1.5], 'Style', 'infinite');
light('Parent', ax, 'Position', [-1 1 0.5], 'Style', 'infinite');
lighting(ax, 'gouraud');
material(ax, 'dull');

% Desempenho: SortMethod 'childorder' dispensa a ordenacao por profundidade
% a cada quadro; a geometria e opaca e a oclusao fica com o buffer de
% profundidade.
set(ax, 'SortMethod', 'childorder');
f = ancestor(ax, 'figure');
if isprop(f, 'GraphicsSmoothing')
    set(f, 'GraphicsSmoothing', 'off');
end

% Texto de estado. Um objeto text em coordenadas normalizadas e mais barato
% de reescrever que o title, que forca remanejo do layout dos eixos.
cena.h_texto = text('Parent', ax, 'Units', 'normalized', ...
                    'Position', [0.02 0.97], 'String', '', ...
                    'HorizontalAlignment', 'left', ...
                    'VerticalAlignment', 'top', ...
                    'FontName', 'FixedWidth', 'FontSize', 10, ...
                    'Interpreter', 'none');

% Estado inicial.
trms_cena_atualizar(cena, 0, 0);

hold(ax, 'off');

end


% =========================================================================
% Funcoes locais
% =========================================================================

function h = prim_caixa(pai, dims, centro, cor)
%PRIM_CAIXA Paralelepipedo alinhado aos eixos locais.
d = dims(:)' / 2;
V = [-1 -1 -1; 1 -1 -1; 1 1 -1; -1 1 -1; ...
     -1 -1  1; 1 -1  1; 1 1  1; -1 1  1];
V = V .* repmat(d, 8, 1) + repmat(centro(:)', 8, 1);
F = [1 2 3 4; 5 6 7 8; 1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8];
h = patch('Parent', pai, 'Vertices', V, 'Faces', F, ...
          'FaceColor', cor, 'EdgeColor', 'none', 'FaceLighting', 'gouraud');
end


function h = prim_cilindro(pai, raio, comp, direcao, centro, cor, n)
%PRIM_CILINDRO Cilindro fechado de eixo arbitrario, centrado em 'centro'.
if nargin < 7, n = 28; end

[X, Y, Z] = cylinder(raio, n);
Z = Z * comp - comp/2;
fv = surf2patch(X, Y, Z, 'triangles');
V = fv.vertices;
F = fv.faces;

% Tampas: adiciona os centros das duas extremidades e fecha com triangulos.
i0 = size(V, 1);
V = [V; 0 0 -comp/2; 0 0 comp/2];
nb = n + 1;                       % pontos por circunferencia em surf2patch
idx_inf = 1:2:(2*nb - 1);         % linha z = -comp/2
idx_sup = 2:2:(2*nb);             % linha z = +comp/2
Fi = zeros(n, 3);
Fs = zeros(n, 3);
for k = 1:n
    Fi(k, :) = [idx_inf(k)   idx_inf(k+1) i0+1];
    Fs(k, :) = [idx_sup(k+1) idx_sup(k)   i0+2];
end
F = [F; Fi; Fs];

R = rot_z_para(direcao);
V = V * R';
V = V + repmat(centro(:)', size(V, 1), 1);

h = patch('Parent', pai, 'Vertices', V, 'Faces', F, ...
          'FaceColor', cor, 'EdgeColor', 'none', 'FaceLighting', 'gouraud');
end


function h = prim_toro(pai, raio, tubo, direcao, centro, cor, nu, nv)
%PRIM_TORO Aro de secao circular, com eixo na direcao indicada.
if nargin < 7, nu = 44; end
if nargin < 8, nv = 10; end

u = linspace(0, 2*pi, nu+1);
v = linspace(0, 2*pi, nv+1);
[U, Vv] = meshgrid(u, v);
X = (raio + tubo*cos(Vv)) .* cos(U);
Y = (raio + tubo*cos(Vv)) .* sin(U);
Z = tubo * sin(Vv);

fv = surf2patch(X, Y, Z, 'triangles');
V  = fv.vertices;

R = rot_z_para(direcao);
V = V * R';
V = V + repmat(centro(:)', size(V, 1), 1);

h = patch('Parent', pai, 'Vertices', V, 'Faces', fv.faces, ...
          'FaceColor', cor, 'EdgeColor', 'none', 'FaceLighting', 'gouraud');
end


function desenha_guarda(pai, centro, raio, tubo, n_barras, eixo, cor)
%DESENHA_GUARDA Protecao circular: aro mais barras diametrais.
%   n_barras e o numero de barras que atravessam o aro de lado a lado, de
%   modo que o numero de bracos visiveis e o dobro. n_barras = 2 produz o
%   padrao em X do rotor de cauda.
switch lower(eixo)
    case 'z', dir_eixo = [0 0 1];
    case 'y', dir_eixo = [0 1 0];
    case 'x', dir_eixo = [1 0 0];
    otherwise, error('trms:eixo', 'Eixo deve ser x, y ou z.');
end

prim_toro(pai, raio, tubo, dir_eixo, centro, cor);

R = rot_z_para(dir_eixo);
for k = 1:n_barras
    a = pi*(k-1)/n_barras;
    d = (R * [cos(a); sin(a); 0])';
    prim_cilindro(pai, tubo*0.45, 2*raio, d, centro, cor, 10);
end
end


function desenha_pas(pai, raio, largura, espessura, n_pas, eixo, cor)
%DESENHA_PAS Pas simplificadas distribuidas em torno do eixo indicado.
switch lower(eixo)
    case 'z', base = eye(3);
    case 'y', base = rot_z_para([0 1 0]);
    case 'x', base = rot_z_para([1 0 0]);
    otherwise, error('trms:eixo', 'Eixo deve ser x, y ou z.');
end

for k = 1:n_pas
    a = 2*pi*(k-1)/n_pas;
    % Pa no plano perpendicular ao eixo, apontando para fora.
    V = [ 0        -largura/2 -espessura/2; ...
          raio     -largura/2 -espessura/2; ...
          raio      largura/2 -espessura/2; ...
          0         largura/2 -espessura/2; ...
          0        -largura/2  espessura/2; ...
          raio     -largura/2  espessura/2; ...
          raio      largura/2  espessura/2; ...
          0         largura/2  espessura/2];
    Rz = [cos(a) -sin(a) 0; sin(a) cos(a) 0; 0 0 1];
    V = V * Rz' * base';
    F = [1 2 3 4; 5 6 7 8; 1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8];
    patch('Parent', pai, 'Vertices', V, 'Faces', F, ...
          'FaceColor', cor, 'EdgeColor', 'none', 'FaceLighting', 'gouraud');
end
end


function R = rot_z_para(d)
%ROT_Z_PARA Matriz de rotacao que leva o eixo +z ao vetor d (Rodrigues).
d = d(:) / norm(d);
z = [0; 0; 1];
v = cross(z, d);
c = dot(z, d);
if norm(v) < 1e-12
    if c > 0
        R = eye(3);
    else
        R = diag([1 -1 -1]);   % rotacao de pi em torno de x
    end
    return
end
vx = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
R = eye(3) + vx + vx*vx * (1/(1+c));
end