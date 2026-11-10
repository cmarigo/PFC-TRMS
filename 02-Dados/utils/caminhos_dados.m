function P = caminhos_dados()
%CAMINHOS_DADOS Pastas dos dados e dos resultados, declaradas num so lugar.
%
%   P = caminhos_dados
%
%   Os dados brutos ficam nas pastas de cada sessao de laboratorio; os
%   scripts procuram cada arquivo pelo nome, inclusive em subpastas
%   (acha_dados). Os resultados (.mat) vao para uma pasta propria,
%   criada se nao existir.
%
%   Este arquivo fica em 02-Dados/utils. Os dados sao procurados em
%   02-Dados e as saidas vao para 05-Monografia, na raiz do projeto.

UTILS = fileparts(mfilename('fullpath'));   % .../02-Dados/utils
DADOS = fileparts(UTILS);                   % .../02-Dados
RAIZ  = fileparts(DADOS);                   % raiz do projeto

% Dados brutos, por sessao -- AJUSTAR os nomes se necessario
P.pitch = fullfile(DADOS, 'Coleta 1 - Pitch (Step, PRBS, CHIRP)');  % degraus, PRBS e chirp da arfagem
P.yaw   = fullfile(DADOS, 'Coleta 2 - Yaw sem soltura completa');  % sessoes 1 e 2 do yaw
                                                                 % (out_025, out_prbs_02, out_solto, out_livre, *_v2)
P.c3    = fullfile(DADOS, 'Coleta 3 - Yaw Solto e PID arfagem');  % soma de senoides, degraus c3 e PID

% Saidas
P.resultados = fullfile(RAIZ, '05-Monografia', 'resultados');

for c = {'pitch', 'yaw', 'c3'}
    if ~isfolder(P.(c{1}))
        warning('caminhos_dados:pasta', 'Pasta de dados "%s" nao encontrada: %s', c{1}, P.(c{1}));
    end
end
if ~isfolder(P.resultados), mkdir(P.resultados); end
end
