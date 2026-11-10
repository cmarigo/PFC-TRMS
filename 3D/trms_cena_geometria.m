function geo = trms_cena_geometria()
%TRMS_CENA_GEOMETRIA Dimensoes e cores da representacao 3D do TRMS.
%
%   geo = TRMS_CENA_GEOMETRIA() devolve uma estrutura com as dimensoes
%   (em metros) usadas para desenhar a planta.
%
%   Os comprimentos da haste e do contrapeso sao os da Tabela 1 do
%   Tastemirov, os mesmos do trms_params, repetidos aqui para que a cena
%   nao dependa do modelo. As dimensoes de aparencia (protecoes, base,
%   coluna, bloco do pivo) foram estimadas por fotografias da bancada, com
%   o vao l_m + l_t = 0,529 m como escala.
%
%   Ver tambem TRMS_CENA_CRIAR, TRMS_CENA_ATUALIZAR.

% --- Convencoes de sinal -------------------------------------------------
% Unico lugar onde a convencao de sinal da cena e definida.
geo.sinal_pitch = -1;   % pitch > 0 levanta o rotor principal
geo.sinal_yaw   = +1;   % yaw > 0 gira no anti-horario visto de cima
% Offsets de zero mecanico (rad), somados antes da rotacao.
geo.offset_pitch = 0;
geo.offset_yaw   = 0;

% --- Camera e lado do contrapeso -----------------------------------------
% Vista inicial [azimute elevacao]. Com azimute 45 o rotor principal (+x)
% aparece a DIREITA e o de cauda a esquerda, como na bancada. Nessa vista a
% camera fica do lado do y local NEGATIVO.
geo.vista = [45 18];
% Lado da haste em que ficam o bloco do pivo e o contrapeso:
%   -1 = y local negativo -> voltado para a camera (na frente da haste)
%   +1 = y local positivo -> do outro lado (atras da haste)
% Na bancada o bloco fica na frente da haste, visto da posicao em que o
% rotor principal esta a direita.
geo.lado_contrapeso = -1;

% --- Base fixa -----------------------------------------------------------
geo.base_x        = 0.290;   % base retangular, nao disco
geo.base_y        = 0.190;
geo.base_altura   = 0.020;
geo.base_raio     = 0.090;   % nao usado pela base retangular
geo.coluna_raio   = 0.020;
geo.h_pivo        = 0.340;   % altura do pivo de pitch acima da mesa

% --- Bloco do pivo -------------------------------------------------------
% PECA UNICA, rigida com a haste dos rotores: e nela que a haste do
% contrapeso se fixa. Como e montada deslocada em relacao ao eixo, sua
% largura precisa ser suficiente para atravessar o eixo da haste e
% alcancar o ponto de fixacao do contrapeso.
%   Com largura 0.085 centrada em |y| = 0.030, o bloco vai de 0.012 do lado
%   oposto ate 0.072 do lado do contrapeso.
geo.bloco_pivo     = [0.060 0.085 0.055];
geo.bloco_pivo_pos = [0 0.030*geo.lado_contrapeso 0];

% --- Haste dos rotores (gira com pitch) ----------------------------------
geo.viga_lado     = 0.010;   % haste fina, como na bancada
geo.l_main        = 0.254;   % l_m: pivo -> rotor principal (eixo +x local)
geo.l_tail        = 0.275;   % l_t: pivo -> rotor de cauda  (eixo -x local)

% --- Rotores -------------------------------------------------------------
geo.rotor_main_raio    = 0.095;   % raio das pas do rotor principal
geo.rotor_tail_raio    = 0.070;   % raio das pas do rotor de cauda
geo.carcaca_raio       = 0.026;
geo.carcaca_comp       = 0.050;
geo.pa_largura         = 0.018;
geo.pa_espessura       = 0.004;
geo.n_pas              = 2;

% --- Protecoes circulares ------------------------------------------------
% Elemento visual dominante da planta real. O aro nao gira com a helice:
% fica preso a haste.
geo.guarda_raio_main     = 0.110;
geo.guarda_raio_tail     = 0.080;
geo.guarda_tubo          = 0.008;   % espessura do aro
geo.guarda_n_barras_main = 3;       % barras diametrais -> 6 bracos visiveis
geo.guarda_n_barras_tail = 2;       % 2 barras -> padrao em X, como na foto

% --- Contrapeso ----------------------------------------------------------
% Sai da borda externa do bloco do pivo, nao do eixo da haste.
geo.cp_origem     = [0 0.058*geo.lado_contrapeso 0];
geo.cp_haste_comp = 0.250;   % l_b
geo.cp_haste_raio = 0.005;
geo.cp_raio       = 0.013;   % peso cilindrico fino
geo.cp_comp       = 0.045;
geo.cp_angulo     = -pi/2;   % direcao da haste no plano x-z local
geo.cp_pos        = 0.960;          % l_cb/l_b = 0.240/0.250

% --- Cores ---------------------------------------------------------------
% As cores dos rotores NAO correspondem a planta, que e quase toda preta e
% cinza. Sao didaticas: distinguem rotor principal de rotor de cauda.
geo.cor_base    = [0.88 0.86 0.80];
geo.cor_coluna  = [0.18 0.18 0.22];
geo.cor_hub     = [0.42 0.42 0.46];
geo.cor_viga    = [0.20 0.42 0.72];
geo.cor_main    = [0.82 0.32 0.24];
geo.cor_tail    = [0.90 0.62 0.18];
geo.cor_guarda  = [0.15 0.15 0.18];
geo.cor_pa      = [0.13 0.13 0.15];
geo.cor_cp      = [0.28 0.28 0.30];
geo.cor_fundo   = [1.00 1.00 1.00];

end