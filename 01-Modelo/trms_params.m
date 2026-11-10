% Geometria física (Tabela 1) 

l_m   = 0.254;   % [m]   comprimento da viga principal (pivô ao main rotor)
l_t   = 0.275;   % [m]   comprimento da viga de cauda (pivô ao tail rotor)
l_b   = 0.250;   % [m]   comprimento da viga do contrapeso
l_cb  = 0.240;   % [m]   distância do contrapeso ao pivô
h     = 0.06;    % [m]   comprimento da viga pivotada (deslocamento vertical)

% Parâmetros elétricos do motor CC (Tabela 1) 
R   = 8.0;        % [Ω]        resistência de armadura (igual para main e tail)
k_vm  = 0.0202;   % [V·s/rad]    constante de força contra-eletromotriz, main motor
k_vt  = 0.0202;   % [V·s/rad]    constante de força contra-eletromotriz, tail motor
k_tm  = 0.0202;   % [N·m/A]  constante de torque, main motor
k_tt  = 0.0202;   % [N·m/A]  constante de torque, tail motor
k_um  = 8.5;      % [-]        ganho de entrada, main
k_ut  = 6.5;      % [-]        ganho de entrada, tail

% Parâmetros de inércia (Tabela 2 - valores identificados)

I_m1  = 1.7249e-4;  % [kg·m²]  momento de inércia do main rotor em torno do eixo de rotação
I_t1  = 3.2170e-5;  % [kg·m²]  momento de inércia do tail rotor em torno do eixo de rotação
I_psi = 6.1644e-2;  % [kg·m²]  inércia de pitch (elevação) do conjunto do corpo
I_phi = 2.1117e-2;  % [kg·m²]  inércia de yaw (azimute) do conjunto do corpo
I_c   = 8.3286e-2;  % [kg·m²]  inércia da viga transversal em torno do eixo vertical

% Termos de gravidade / massa-geometria (Tabela 2 - valores identificados)

G_z   = -0.25254;    % [N·m]    coeficiente de torque gravitacional (componente z)
G_y   =  0.15032;    % [N·m]    coeficiente de torque gravitacional (componente y) - Valor calculado
H_z   = -1.5446e-3;  % [kg·m²]  termo de acoplamento da distribuição de massa (componente z)
H_y   =  6.6120e-3;  % [kg·m²]  termo de acoplamento da distribuição de massa (componente y) - Valor calculado

% Coeficientes de atrito (Tabela 2 - valores identificados) 

f_vpsi = 4.2150e-4;   % [N·m·s/rad]  atrito viscoso, eixo de pitch
f_cpsi = 4.0548e-4;   % [N·m]        atrito de Coulomb, eixo de pitch
f_vphi = 2.60e-2;   % [N.m.s/rad]  atrito viscoso, eixo de yaw (ajuste analitico dos degraus)
f_cphi = 1.1758e-5;   % [N·m]        atrito de Coulomb, eixo de yaw
f_vm   = 4.1993e-6;   % [N·m·s/rad]  atrito viscoso, main rotor
f_vt   = 3.2498e-6;   % [N·m·s/rad]  atrito viscoso, tail rotor
f_s = 3.48*f_cpsi;   % [N·m]  atrito estatico, eixo de pitch (identificacao multiexperimento)
v_s = 0.05;

%  Coeficientes aerodinâmicos (Tabela 2 - valores identificados, por sinal)

CT_m_pos = 1.4971e-5;  % [N·s²/rad²]    coef. de empuxo, main rotor, om_m >= 0
CT_m_neg = 8.9974e-6;  % [N·s²/rad²]    coef. de empuxo, main rotor, om_m <  0
CT_t_pos = 3.7755e-6;  % [N·s²/rad²]    coef. de empuxo, tail rotor, om_t >= 0
CT_t_neg = 2.3046e-6;  % [N·s²/rad²]    coef. de empuxo, tail rotor, om_t <  0
CR_m_pos = 5.0582e-7;  % [N·m·s²/rad²]  coef. de torque de reação, main rotor, om_m >= 0
CR_m_neg = 4.5047e-7;  % [N·m·s²/rad²]  coef. de torque de reação, main rotor, om_m <  0
CR_t_pos = 9.7031e-8;  % [N·m·s²/rad²]  coef. de torque de reação, tail rotor, om_t >= 0
CR_t_neg = 9.9176e-8;  % [N·m·s²/rad²]  coef. de torque de reação, tail rotor, om_t <  0

% Torque dos cabos e ângulos de repouso (Tabela 2 - valores identificados) 

C_c   = 2.10e-2;    % [N.m/rad]  rigidez do cabo (oscilacao livre, com I_eff)
phi_0 = 0.03011;    % [rad]      neutro do cabo (assimetria das tensoes de ruptura)
psi_0 = -atan(G_y/abs(G_z));   % [rad] repouso de pitch, derivado de G_y e G_z
% Condições iniciais para o bloco integrador do Simulink

x0 = [psi_0; phi_0; 0; 0; 0; 0];

% --- Controlador PID de arfagem (valores da pratica; o trms_app sobrescreve)
Kp_pitch = 4;        % [V/rad]
Ki_pitch = 6;        % [V/(rad.s)]
Kd_pitch = 8;        % [V.s/rad]
N_pitch  = 100;      % filtro derivativo (nao usado no trms_model_pid_bancada)
Ts_pid   = 0.001;    % [s]
ref_pitch = 0.4;     % [rad] referencial do ENCODER (nao somar psi_0)
t_degrau  = 10;      % [s]
mascara = ones(6,1); % [psi phi om_m om_t dpsi dphi], nada travado
modo    = 1;         % 0 abertos | 1 arfagem fechada | 2 guinada | 3 ambos

disp('[trms_params] Parâmetros carregados com sucesso.')