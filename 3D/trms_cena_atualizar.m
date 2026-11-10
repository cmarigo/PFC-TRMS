function trms_cena_atualizar(cena, pitch, yaw, giro_main, giro_tail, mostrar_texto)
%TRMS_CENA_ATUALIZAR Posiciona a cena 3D para um par de angulos.
%
%   TRMS_CENA_ATUALIZAR(cena, pitch, yaw) posiciona a planta.
%   TRMS_CENA_ATUALIZAR(cena, pitch, yaw, giro_main, giro_tail) tambem gira
%   as helices (angulos em rad, apenas efeito visual). Use [] para manter.
%   TRMS_CENA_ATUALIZAR(..., mostrar_texto) com mostrar_texto = false pula
%   a reescrita do texto de estado, que e a operacao mais cara por quadro.
%
%   pitch e yaw em RADIANOS, na convencao do modelo. A conversao para a
%   convencao grafica (sinal e offset) esta concentrada em
%   TRMS_CENA_GEOMETRIA.
%
%   Ver tambem TRMS_CENA_CRIAR.

if nargin < 4, giro_main = []; end
if nargin < 5, giro_tail = []; end
if nargin < 6 || isempty(mostrar_texto), mostrar_texto = true; end

geo = cena.geo;

a_yaw   = geo.sinal_yaw   * (yaw   + geo.offset_yaw);
a_pitch = geo.sinal_pitch * (pitch + geo.offset_pitch);

% Yaw: rotacao em torno do eixo vertical fixo.
set(cena.t_yaw, 'Matrix', makehgtform('zrotate', a_yaw));

% Pitch: translada ate o pivo e gira em torno do y LOCAL (ja rotacionado
% pelo yaw, por heranca do hgtransform pai).
M_pitch = makehgtform('translate', [0 0 geo.h_pivo]) * ...
          makehgtform('yrotate', a_pitch);
set(cena.t_pitch, 'Matrix', M_pitch);

% Giro das helices (opcional, puramente estetico).
if ~isempty(giro_main)
    set(cena.t_pa_main, 'Matrix', ...
        makehgtform('translate', [geo.l_main 0 0]) * ...
        makehgtform('zrotate', giro_main));
end
if ~isempty(giro_tail)
    set(cena.t_pa_tail, 'Matrix', ...
        makehgtform('translate', [-geo.l_tail 0 0]) * ...
        makehgtform('yrotate', giro_tail));
end

if mostrar_texto && isfield(cena, 'h_texto') && ishandle(cena.h_texto)
    set(cena.h_texto, 'String', ...
        sprintf('pitch = %+6.1f deg    yaw = %+6.1f deg', ...
                pitch*180/pi, yaw*180/pi));
end

end