function res = valida_yaw(varargin)
% ==============================================================================
% valida_yaw.m
%
% Compara a resposta do modelo Simulink do TRMS com a da planta nos ensaios
% PRBS do eixo de guinada, que sao o conjunto de validacao independente --
% os degraus foram usados para identificacao, seguindo a mesma metodologia
% aplicada ao eixo de arfagem.
%
% E' FUNCAO, NAO SCRIPT, para isolar as variaveis locais do workspace base.
% O InitFcn do modelo esta VAZIO: o trms_params e' carregado aqui no base, e
% os parametros identificados vao por setVariable, dentro do simula_trms.
% MODELO: trms_model_pid_bancada em malhas abertas (modo 0), com a arfagem livre.
%
% ENTRADA APLICADA: o u_t do modelo e' a sequencia PRBS regerada aqui (LFSR
% de 6 bits, taps 6 e 5, clock de 1,5 s), definida pelos instantes de
% transicao e aplicada com retencao de ordem zero, como no From Workspace da
% bancada. A coluna 2 do registro serve so para CONFERIR: o script verifica
% se o PRBS regerado coincide com a tensao registrada, tolerando descompasso
% de uma amostra em torno de cada transicao, e avisa se houver diferenca.
%
% CONDICAO INICIAL E REFERENCIAL: o modelo parte de phi = phi_0 (x0(2) =
% phi_0) e a saida e' comparada como phi_sim - phi_sim(1), isto e',
% phi - phi_0. Com isso o resultado nao depende do valor de phi_0, que e'
% estruturalmente nao observavel na validacao dinamica.
%
% PISO EXPERIMENTAL: o script calcula o J entre as duas realizacoes do PRBS
% de 0,3 V (mesma sessao, mesmo sinal). E' esse o piso comparavel ao J do
% modelo.
%
% O QUE ESPERAR DOS RESIDUOS:
%   O modo lento (tau ~ 28 s) NAO esta no modelo nominal. Nos PRBS ele aparece
%   pouco, porque a excitacao alterna a cada 1,5 s; ainda assim, uma deriva de
%   baixa frequencia no residuo e' esperada.
%
% USO:
%   res = valida_yaw();                      % parametros identificados
%   res = valida_yaw('nominal', true);       % parametros do Tastemirov
%   res = valida_yaw('f_vphi', 5e-3);        % sobrescreve um parametro
%
% SAIDA EM DISCO: valida_yaw_resultados.mat (ou valida_yaw_nominal.mat).
%
% Clara Temponi Marigo -- PFC, gemeo digital do TRMS
% ==============================================================================

%% Configuracao ----------------------------------------------------------------
P = caminhos_dados();
cfg.dir_dados    = P.yaw;          % sessoes de identificacao do yaw
cfg.usar_nominal = false;
cfg.salvar       = true;

% Parametros identificados (com a inercia efetiva em psi = -38 graus)
cfg.C_c    = 2.10e-2;    % N.m/rad   -- oscilacao livre, ramo positivo
cfg.phi_0  = 0.03011;    % rad       -- assimetria das tensoes de ruptura
cfg.f_vphi = 2.60e-2;    % N.m.s/rad -- degraus, com rotor de cauda ativo
cfg.f_cphi = [];         % vazio mantem o valor do trms_params

% Nominais do Tastemirov, para o modo de comparacao
nom.C_c    = 9.87e-3;
nom.phi_0  = 0.25;
nom.f_vphi = 1.12e-4;

% Ensaios de validacao. O de 0,15 V fica FORA: a excitacao e' comparavel a
% tensao de ruptura (u* entre 0,07 e 0,13 V), entao o atrito estatico domina.
% Para os indices dele (tab:yaw_validacao, linha "excluido da media"):
%   valida_yaw('ensaios', {'out_prbs_015.mat', 0.15}, 'salvar', false)
cfg.ensaios = { ...
    'out_prbs_02.mat',    0.20
    'out_prbs_03.mat',    0.30
    'out_prbs_03_v2.mat', 0.30
    'out_prbs_04.mat',    0.40
};

% Sobrescritas vindas dos argumentos
for k = 1:2:numel(varargin)
    cfg.(varargin{k}) = varargin{k+1};
end
if isfield(cfg, 'nominal') && cfg.nominal
    cfg.usar_nominal = true;
end
if cfg.usar_nominal
    cfg.C_c = nom.C_c;  cfg.phi_0 = nom.phi_0;  cfg.f_vphi = nom.f_vphi;
end

%% Parametros do modelo no workspace base --------------------------------------
evalin('base', 'trms_params;');
x0_base = evalin('base', 'x0');
x0_base = x0_base(:);

n = size(cfg.ensaios, 1);
res = struct('arquivo', {}, 'amplitude', {}, 'rmse_rel', {}, 'rmse_abs', {}, ...
             'ganho', {}, 'vies', {}, 't', {}, 'phi_p', {}, 'phi_sim', {});

% Sequencia PRBS: LFSR maximal de 6 bits, taps 6 e 5 -- a mesma das coletas
N_BITS = 6;  N_SEQ = 2^N_BITS - 1;  T_CLOCK = 1.5;
r = ones(1, N_BITS);  b = zeros(1, N_SEQ);
for k = 1:N_SEQ
    b(k) = r(N_BITS);
    r = [xor(r(N_BITS), r(N_BITS-1)), r(1:N_BITS-1)];
end
seq = 2*b - 1;

fprintf('=== Validacao do eixo de guinada contra os PRBS ===\n');
fprintf('Parametros: %s\n', ternario(cfg.usar_nominal, 'NOMINAIS (Tastemirov)', 'IDENTIFICADOS'));
fprintf('  C_c = %.4e   phi_0 = %+.5f   f_vphi = %.4e\n\n', cfg.C_c, cfg.phi_0, cfg.f_vphi);
fprintf('%-20s %6s %8s %10s %8s %9s\n', 'ensaio', 'amp', 'J [%]', 'RMS [rad]', 'ganho', 'vies [rad]');

figure('Color', 'w', 'Position', [80 80 1000 260*ceil(n/2)]);

for k = 1:n
    arq = cfg.ensaios{k,1};
    amp = cfg.ensaios{k,2};

    S = load(acha_dados(cfg.dir_dados, arq));
    M = S.simout_tail;
    t_p   = M(:,1);
    phi_p = M(:,3) - M(1,3);          % encoder zerado no inicio do ensaio

    % Com o PRBS correto a coluna 2 tem exatamente dois niveis; mais niveis
    % indicam "Interpolate data" marcado no From Workspace da coleta.
    niveis = unique(round(M(:,2), 3));
    if numel(niveis) > 2
        warning('valida_yaw:interpolacao', ...
            '%s: entrada com %d niveis -- interpolacao ligada na coleta?', arq, numel(niveis));
    end

    % Conferencia: o PRBS regerado tem de coincidir com a tensao registrada,
    % fora da amostra de cada transicao (tolerancia de uma amostra)
    idx   = min(floor(t_p/T_CLOCK + 1e-9) + 1, N_SEQ);
    u_rec = amp*reshape(seq(idx), [], 1);
    longe = abs(t_p - T_CLOCK*round(t_p/T_CLOCK)) > 0.1 + 1e-6;
    n_dif = sum(abs(M(longe,2) - u_rec(longe)) > 1e-3);
    if n_dif > 0
        warning('valida_yaw:prbs', ...
            '%s: o PRBS regerado difere da tensao registrada em %d amostras fora das transicoes.', ...
            arq, n_dif);
    end

    % Entrada: apenas os instantes de transicao, com retencao de ordem zero.
    % Cada transicao ganha um ponto 1 us antes, para o degrau sair exato com
    % ou sem "Interpolate data" no From Workspace do modelo.
    u_t_ts = degraus_ts((0:(N_SEQ-1))'*T_CLOCK, amp*seq(:), t_p(end));
    u_m_ts = timeseries([0; 0], [0; t_p(end)]);   % rotor principal desligado

    % Condicao inicial coerente com o phi_0 usado nesta simulacao
    x0 = x0_base;
    x0(2) = cfg.phi_0;

    opc = struct();
    opc.T_fim   = t_p(end);
    opc.modo    = 0;                  % malhas abertas
    opc.mascara = ones(6,1);          % arfagem livre, como na bancada
    opc.x0      = x0;
    opc.u_m     = u_m_ts;
    opc.u_t     = u_t_ts;
    opc.par     = struct('C_c', cfg.C_c, 'phi_0', cfg.phi_0, 'f_vphi', cfg.f_vphi);
    if ~isempty(cfg.f_cphi)
        opc.par.f_cphi = cfg.f_cphi;
    end
    S = simula_trms(opc);

    % Saida do modelo referenciada ao instante inicial (phi - phi_0) e
    % reamostrada na grade da planta
    t_m     = S.t_phi;
    phi_m   = S.phi - S.phi(1);
    phi_sim = interp1(t_m, phi_m, t_p, 'linear', 'extrap');

    % Metricas. J normaliza pela variancia do sinal medido.
    e = phi_sim - phi_p;
    rmse_rel = mean(e.^2) / mean((phi_p - mean(phi_p)).^2) * 100;
    rmse_abs = sqrt(mean(e.^2));

    % Ganho e vies separam erro de escala de erro de offset
    A  = [phi_p, ones(size(phi_p))];
    ab = A \ phi_sim;

    fprintf('%-20s %6.2f %8.2f %10.5f %8.3f %9.4f\n', ...
            arq, amp, rmse_rel, rmse_abs, ab(1), ab(2));

    res(k).arquivo   = arq;
    res(k).amplitude = amp;
    res(k).rmse_rel  = rmse_rel;
    res(k).rmse_abs  = rmse_abs;
    res(k).ganho     = ab(1);
    res(k).vies      = ab(2);
    res(k).t         = t_p;
    res(k).phi_p     = phi_p;
    res(k).phi_sim   = phi_sim;

    subplot(ceil(n/2), 2, k);
    plot(t_p, phi_p, 'b', 'LineWidth', 1); hold on;
    plot(t_p, phi_sim, 'r--', 'LineWidth', 1);
    plot(t_p, e, 'k:', 'LineWidth', 0.8);
    grid on; xlabel('t [s]'); ylabel('\phi [rad]');
    title(sprintf('%s (%.2f V)   J = %.1f%%', strrep(arq, '_', '\_'), amp, rmse_rel));
    if k == 1, legend('planta', 'modelo', 'residuo', 'Location', 'Best'); end
end

fprintf('\n  J medio: %.2f%%\n', mean([res.rmse_rel]));
fprintf('  Ganho medio: %.3f\n', mean([res.ganho]));

% Piso experimental: J entre as duas realizacoes do PRBS de 0,3 V
i3 = find(abs([res.amplitude] - 0.30) < 1e-9);
if numel(i3) == 2
    a = res(i3(1));  c = res(i3(2));
    c_em_a = interp1(c.t, c.phi_p, a.t, 'linear', 'extrap');
    a_em_c = interp1(a.t, a.phi_p, c.t, 'linear', 'extrap');
    J_ca = 100*mean((c_em_a - a.phi_p).^2) / var(a.phi_p, 1);
    J_ac = 100*mean((a_em_c - c.phi_p).^2) / var(c.phi_p, 1);
    fprintf('  Piso experimental (J entre as duas realizacoes de 0,3 V): %.1f%% e %.1f%%\n', J_ca, J_ac);
    fprintf('  (diferenca de desvio-padrao entre elas: %.0f%%)\n', ...
            100*abs(std(c.phi_p, 1) - std(a.phi_p, 1))/std(a.phi_p, 1));
end

if cfg.salvar
    arq_res = fullfile(P.resultados, ...
        ternario(cfg.usar_nominal, 'valida_yaw_nominal.mat', 'valida_yaw_resultados.mat'));
    save(arq_res, 'res', 'cfg');
    fprintf('\n  Resultados salvos em %s\n', arq_res);
end

end

%% ------------------------------------------------------------------------------
function ts = degraus_ts(t_trans, v, T_fim)
%DEGRAUS_TS Sinal constante por partes como timeseries, com um ponto 1 us
%   antes de cada transicao (degrau exato com ou sem interpolacao).
t_trans = t_trans(:);  v = v(:);
t = t_trans(1);  y = v(1);
for k = 2:numel(t_trans)
    t = [t; t_trans(k) - 1e-6; t_trans(k)];   %#ok<AGROW>
    y = [y; v(k-1);            v(k)];          %#ok<AGROW>
end
if T_fim > t(end)
    t = [t; T_fim];  y = [y; v(end)];
end
ts = timeseries(y, t);
end

function s = ternario(c, a, b)
if c, s = a; else, s = b; end
end
