function ok = confere_params(modo)
%CONFERE_PARAMS Confere no workspace base os parametros que os resultados da
%   monografia supoem e avisa o que diverge. Nao altera nada.
%
%   ok = confere_params                 % conjunto identificado (padrao)
%   ok = confere_params('nominal')      % parametros do Tastemirov
%
%   Chamar depois de evalin('base', 'trms_params;'). O InitFcn do modelo
%   esta vazio, entao e' o trms_params carregado no base que vale.

if nargin < 1, modo = 'identificado'; end

F_CPSI = 4.0548e-4;
esp.f_vpsi   = 4.2150e-4;
esp.f_cpsi   = F_CPSI;
esp.CT_m_pos = 1.4971e-5;
esp.v_s      = 0.05;
esp.f_cphi   = 1.1758e-5;
switch lower(modo)
    case 'identificado'
        esp.f_s    = 3.48*F_CPSI;
        esp.C_c    = 2.10e-2;
        esp.f_vphi = 2.60e-2;
    case 'nominal'
        esp.f_s    = F_CPSI;
        esp.C_c    = 9.8664e-3;
        esp.f_vphi = 1.1243e-4;
    otherwise
        error('confere_params:modo', 'modo deve ser ''identificado'' ou ''nominal''.');
end

ok = true;
fprintf('--- Parametros no workspace base (esperado: %s) ---\n', modo);
nomes = fieldnames(esp);
for i = 1:numel(nomes)
    nome = nomes{i};
    if ~evalin('base', sprintf('exist(''%s'', ''var'')', nome))
        fprintf('  %-9s AUSENTE\n', nome);
        ok = false;
        continue;
    end
    v = evalin('base', nome);
    marca = '';
    if abs(v - esp.(nome)) > 0.01*abs(esp.(nome))
        marca = '   <-- difere';
        ok = false;
    end
    fprintf('  %-9s = %11.4e   (esperado %11.4e)%s\n', nome, v, esp.(nome), marca);
end

% Condicao inicial: x0(1) deve ser psi_0 e x0(2) deve ser phi_0
if evalin('base', 'exist(''x0'', ''var'') && exist(''psi_0'', ''var'') && exist(''phi_0'', ''var'')')
    x0    = evalin('base', 'x0');
    psi_0 = evalin('base', 'psi_0');
    phi_0 = evalin('base', 'phi_0');
    fprintf('  psi_0     = %+.4f rad (esperado -0,5369)   x0(1) = %+.4f\n', psi_0, x0(1));
    fprintf('  phi_0     = %+.4f rad                       x0(2) = %+.4f\n', phi_0, x0(2));
    if abs(psi_0 + 0.5369) > 1e-3
        fprintf('  AVISO: psi_0 diferente do derivado de G_y/G_z nominais.\n');
        ok = false;
    end
    if abs(x0(1) - psi_0) > 1e-6 || abs(x0(2) - phi_0) > 1e-6
        fprintf('  AVISO: x0 nao corresponde a psi_0/phi_0.\n');
        ok = false;
    end
else
    fprintf('  x0, psi_0 ou phi_0 ausente no workspace base.\n');
    ok = false;
end

if ok
    fprintf('  OK.\n');
else
    warning('confere_params:diverge', ...
        'Ha parametros diferentes do esperado.');
end
end
