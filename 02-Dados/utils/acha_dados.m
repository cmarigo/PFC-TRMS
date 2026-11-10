function arqs = acha_dados(pasta, padrao, unico)
%ACHA_DADOS Procura arquivos de dados pelo nome (ou padrao com *), na pasta
%   e em todas as subpastas.
%
%   arq  = acha_dados(pasta, 'out_025.mat')            % exatamente um; char
%   arqs = acha_dados(pasta, 'out_step_opp0deg*', false) % todos; cell
%
%   Com unico = true (padrao), exige exatamente um arquivo: nenhum ou mais
%   de um geram erro, com a lista dos encontrados. Isso evita usar, sem
%   aviso, um arquivo homonimo de outra subpasta.

if nargin < 3, unico = true; end
d = dir(fullfile(pasta, '**', padrao));
d = d(~[d.isdir]);
arqs = fullfile({d.folder}, {d.name});

if unico
    if isempty(arqs)
        error('acha_dados:ausente', '"%s" nao encontrado em %s (nem em subpastas).', padrao, pasta);
    end
    if numel(arqs) > 1
        error('acha_dados:duplicado', '%d arquivos "%s" em %s:\n  %s', ...
              numel(arqs), padrao, pasta, strjoin(arqs, '\n  '));
    end
    arqs = arqs{1};
end
end
