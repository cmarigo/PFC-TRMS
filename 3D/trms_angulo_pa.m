function ang = trms_angulo_pa(t, omega, opcoes)
%TRMS_ANGULO_PA Converte velocidade de rotor em angulo de pa para animacao.
%
%   ang = TRMS_ANGULO_PA(t, omega) devolve o angulo acumulado [rad] das pas.
%   ang = TRMS_ANGULO_PA(t, omega, opcoes) com:
%
%       opcoes.rpm_max    taxa visual maxima [rpm]. Padrao 300.
%       opcoes.omega_ref  velocidade [rad/s] em que a taxa visual atinge
%                         cerca de 76% de rpm_max. Padrao: metade do pico
%                         de |omega| nos dados.
%       opcoes.n_pas      numero de pas, usado so no aviso de aliasing.
%                         Padrao 2.
%       opcoes.fps        taxa de quadros prevista, idem. Padrao 30.
%
%   A velocidade real dos rotores, na casa dos milhares de rpm, nao pode ser
%   representada a 30 quadros por segundo: o avanco por quadro passaria de
%   meia volta e o giro pareceria lento ou invertido. Por isso a velocidade
%   e comprimida antes de integrar:
%
%       omega_vis = w_max * tanh(omega / omega_ref)
%       ang       = integral de omega_vis
%
%   A tangente hiperbolica preserva o sentido de rotacao, e nula em zero e
%   satura de forma suave. A saturacao vem antes da integral para nao criar
%   descontinuidade no angulo.
%
%   O omega_ref padrao depende dos dados; para comparar ensaios, use o mesmo
%   omega_ref em todos.
%
%   Ver tambem TRMS_CENA_ATUALIZAR.

if nargin < 3, opcoes = struct(); end
opcoes = preencher(opcoes, 'rpm_max',   300);
opcoes = preencher(opcoes, 'n_pas',     2);
opcoes = preencher(opcoes, 'fps',       30);
opcoes = preencher(opcoes, 'omega_ref', []);

t     = t(:);
omega = omega(:);
if numel(t) ~= numel(omega)
    error('trms:dim', 't e omega devem ter o mesmo comprimento.');
end

pico = max(abs(omega));
if isempty(opcoes.omega_ref)
    if pico <= 0
        ang = zeros(size(t));   % rotor parado o tempo todo
        return
    end
    opcoes.omega_ref = pico / 2;
end
if opcoes.omega_ref <= 0
    error('trms:ref', 'omega_ref deve ser positivo.');
end

% Verificacao de aliasing: com n_pas pas, o padrao se repete a cada
% 2*pi/n_pas. O avanco por quadro precisa ficar bem abaixo de metade disso
% para o sentido de giro ser lido corretamente.
w_max      = opcoes.rpm_max * 2*pi / 60;              % rad/s visuais
av_quadro  = w_max / opcoes.fps;                      % rad por quadro
lim_seguro = (2*pi / opcoes.n_pas) / 3;
if av_quadro > lim_seguro
    warning('trms:aliasing', ...
        ['rpm_max = %.0f avanca %.0f graus por quadro a %.0f fps, acima ', ...
         'do limite de %.0f graus para %d pas.'], ...
        opcoes.rpm_max, av_quadro*180/pi, opcoes.fps, ...
        lim_seguro*180/pi, opcoes.n_pas);
end

omega_vis = w_max * tanh(omega / opcoes.omega_ref);
ang       = cumtrapz(t, omega_vis);

end


function s = preencher(s, campo, valor)
if ~isfield(s, campo)
    s.(campo) = valor;
end
end
