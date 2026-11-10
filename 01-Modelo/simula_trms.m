function S = simula_trms(opc)
%SIMULA_TRMS Unico ponto de contato dos scripts com o modelo Simulink.
%
%   S = simula_trms(opc) simula o trms_model_pid_bancada e devolve as saidas em
%   formato padronizado. Todos os scripts de identificacao, validacao e
%   figuras chamam esta funcao, de modo que os nomes de variaveis e saidas
%   do .slx ficam declarados SO AQUI.
%
%   opc (struct):
%     T_fim    [s] duracao da simulacao (obrigatorio)
%     modo     0 = malhas abertas (padrao); 1 = arfagem em malha fechada
%     mascara  6x1, estados [psi phi om_m om_t dpsi dphi]; padrao ones(6,1).
%              [1 0 1 1 1 0]' trava a guinada (ensaios de arfagem).
%     x0       6x1; vazio ou ausente usa o x0 do trms_params no base
%     u_m, u_t entradas dos rotores (timeseries ou matriz [t u]); padrao 0
%     par      struct com parametros a sobrescrever (campo = nome da variavel)
%     pid      struct com kp, ki, kd, ref, t_degrau (obrigatorio no modo 1)
%
%   S (struct):
%     t_psi, psi     arfagem (como sai do modelo)
%     t_phi, phi     guinada (como sai do modelo)
%     t_u1,  u1      comando do PID antes da saturacao (vazio se nao logado)
%     t_up,  u_planta tensao do rotor de cauda na entrada da planta (vazio se
%                    nao logado)
%     out            Simulink.SimulationOutput
%
%   Pre-requisito: trms_params carregado no workspace base (o InitFcn do
%   modelo esta vazio). Os parametros de opc.par, opc.pid etc. vao por
%   setVariable e tem prioridade sobre o base.

%% Nomes do .slx -- AJUSTAR SO AQUI se algo nao bater -------------------------
MODELO = 'trms_model_pid_bancada';
VAR = struct( ...
    'modo', 'modo', 'mascara', 'mascara', 'x0', 'x0', ...
    'u_main', 'u_m_ts', 'u_tail', 'u_t_ts', ...
    'kp', 'Kp_pitch', 'ki', 'Ki_pitch', 'kd', 'Kd_pitch', ...
    'ref', 'ref_pitch', 'tdeg', 't_degrau');
% Saidas logadas: a primeira encontrada da lista e' usada
SAI.psi = {'pitch_sim', 'psi_sim'};
SAI.phi = {'yaw_sim', 'phi_sim'};
SAI.u1  = {'u1_pid', 'u_pitch_cmd'};   % confirmar que u_pitch_cmd e' o u1 antes da saturacao
SAI.up  = {'u_planta'};      % saida do trms_sel_entrada [u_m; u_t]
COL_UT  = 2;                 % canal do u_t em u_planta

%% Padroes ---------------------------------------------------------------------
if ~isfield(opc, 'T_fim'), error('simula_trms:T_fim', 'opc.T_fim e'' obrigatorio.'); end
T = opc.T_fim;
zero = timeseries([0; 0], [0; T]);
if ~isfield(opc, 'modo')    || isempty(opc.modo),    opc.modo    = 0;          end
if ~isfield(opc, 'mascara') || isempty(opc.mascara), opc.mascara = ones(6,1);  end
if ~isfield(opc, 'u_m')     || isempty(opc.u_m),     opc.u_m     = zero;       end
if ~isfield(opc, 'u_t')     || isempty(opc.u_t),     opc.u_t     = zero;       end
if ~isfield(opc, 'par'),                             opc.par     = struct();   end
if opc.modo == 1
    if ~isfield(opc, 'pid')
        error('simula_trms:pid', 'modo 1 exige opc.pid (kp, ki, kd, ref, t_degrau).');
    end
    pid = opc.pid;
else
    % Malha aberta: controlador inerte (as variaveis precisam existir para
    % o modelo compilar, mesmo fora da malha)
    pid = struct('kp', 0, 'ki', 0, 'kd', 0, 'ref', 0, 't_degrau', 2*T);
end

if ~bdIsLoaded(MODELO), load_system(MODELO); end

%% Simulacao -------------------------------------------------------------------
in = Simulink.SimulationInput(MODELO);
in = in.setModelParameter('StopTime', sprintf('%.10g', T));
in = in.setVariable(VAR.modo,    opc.modo);
in = in.setVariable(VAR.mascara, opc.mascara(:));
in = in.setVariable(VAR.u_main,  opc.u_m);
in = in.setVariable(VAR.u_tail,  opc.u_t);
in = in.setVariable(VAR.kp,      pid.kp);
in = in.setVariable(VAR.ki,      pid.ki);
in = in.setVariable(VAR.kd,      pid.kd);
in = in.setVariable(VAR.ref,     pid.ref);
in = in.setVariable(VAR.tdeg,    pid.t_degrau);
if isfield(opc, 'x0') && ~isempty(opc.x0)
    in = in.setVariable(VAR.x0, opc.x0(:));
end
campos = fieldnames(opc.par);
for i = 1:numel(campos)
    in = in.setVariable(campos{i}, opc.par.(campos{i}));
end

out = sim(in);
if ~isempty(out.ErrorMessage)
    error('simula_trms:sim', '%s', out.ErrorMessage);
end

%% Saidas ----------------------------------------------------------------------
[S.t_psi, S.psi]      = le_saida(out, SAI.psi, 1, true);
[S.t_phi, S.phi]      = le_saida(out, SAI.phi, 1, true);
[S.t_u1,  S.u1]       = le_saida(out, SAI.u1,  1, false);
[S.t_up,  S.u_planta] = le_saida(out, SAI.up,  COL_UT, false);
S.out = out;
end


% =========================================================================
function [t, y] = le_saida(out, candidatos, col, obrigatorio)
%LE_SAIDA Primeira saida da lista que existir no SimulationOutput.
lista = out.who;
k = find(ismember(candidatos, lista), 1);
if isempty(k)
    if obrigatorio
        error('simula_trms:saida', 'Nenhuma das saidas {%s} encontrada. Disponiveis: %s', ...
              strjoin(candidatos, ', '), strjoin(lista, ', '));
    end
    t = [];  y = [];
    return;
end
s = out.get(candidatos{k});
if isa(s, 'timeseries')
    t = s.Time;
    y = squeeze(s.Data);
elseif isstruct(s) && isfield(s, 'time')
    t = s.time;
    y = squeeze(s.signals.values);
elseif isnumeric(s) && size(s, 1) == numel(out.tout)
    t = out.tout;
    y = s;
else
    error('simula_trms:formato', ...
          'Saida "%s" em formato nao previsto (use Timeseries no To Workspace).', candidatos{k});
end
t = t(:);
% Linhas = tempo. Um sinal 2x1 sai como 2 x N depois do squeeze.
if size(y, 1) ~= numel(t) && size(y, 2) == numel(t)
    y = y.';
end
y = y(:, min(col, size(y, 2)));
end
