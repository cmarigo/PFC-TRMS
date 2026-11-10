function x0 = trms_equilibrium(u_offset)
%   Calcula o estado de equilibrio estatico do TRMS para um dado offset
%   de tensao no motor principal (canal de pitch, yaw travado).
%
%   Resolve sequencialmente tres equacoes de equilibrio estatico:
%   [1] Eq. (30) com dom_m=0, ddphi=0, dphi=0
%   [2] Eq. (28) com dpsi=0, dphi=0, ddpsi=0, om_t=0
%   [3] Eq. (29) com dpsi=0, dphi=0, dom_m=0, om_t=0

% 1. Leitura de parametros do workspace 
k_um     = evalin('base', 'k_um');
k_vm     = evalin('base', 'k_vm');
k_tm     = evalin('base', 'k_tm');
R        = evalin('base', 'R');
f_vm     = evalin('base', 'f_vm');
CR_m_pos = evalin('base', 'CR_m_pos');
CR_m_neg = evalin('base', 'CR_m_neg');
CT_m_pos = evalin('base', 'CT_m_pos');
CT_m_neg = evalin('base', 'CT_m_neg');
l_m      = evalin('base', 'l_m');
G_z      = evalin('base', 'G_z');
G_y      = evalin('base', 'G_y');
phi_0    = evalin('base', 'phi_0');
C_c      = evalin('base', 'C_c');

opts = optimset('Display', 'off', 'TolX', 1e-10);

% 2. Velocidade de regime do main rotor (eq. 30 em equilibrio)

f_rotor = @(om) rotor_residual(om, u_offset, k_um, k_vm, k_tm, R, ...
                                f_vm, CR_m_pos, CR_m_neg);

% Chute inicial: aprox. sem atrito (v = k_vm * om_m em regime)
om_guess = k_um * u_offset / k_vm;
om_m_eq  = fzero(f_rotor, om_guess, opts);

% 3. Coeficientes aerodinamicos para om_m_eq calculado

if om_m_eq >= 0
    CT_m = CT_m_pos;
    CR_m = CR_m_pos;
else
    CT_m = CT_m_neg;
    CR_m = CR_m_neg;
end

% 4. Angulo de pitch de equilibrio (eq. 28 em equilibrio)

f_pitch = @(psi) G_z*sin(psi) - G_y*cos(psi) ...
                 + CT_m * om_m_eq * abs(om_m_eq) * l_m;

% Chute inicial: psi_0 identificado por Tastemirov
psi_eq = fzero(f_pitch, -0.54, opts);

% 5. Angulo de yaw de equilibrio (eq. 29 em equilibrio, analitico)

phi_eq = phi_0 - CR_m * om_m_eq * abs(om_m_eq) * cos(psi_eq) / C_c;

% 6. Montagem do vetor de estado

x0 = [psi_eq; phi_eq; om_m_eq; 0; 0; 0];

fprintf('[trms_equilibrium]  u_offset = %+.4f V\n', u_offset);
fprintf('  om_m_eq = %8.2f rad/s\n',                om_m_eq);
fprintf('  psi_eq  = %+8.4f rad  (%+7.3f graus)\n', psi_eq, psi_eq*180/pi);
fprintf('  phi_eq  = %+8.4f rad\n',                 phi_eq);

end

%  Funcao auxiliar: residuo da equacao de equilibrio do main rotor

function res = rotor_residual(om_m, u_offset, k_um, k_vm, k_tm, R, ...
                               f_vm, CR_m_pos, CR_m_neg)
if om_m >= 0
    CR_m = CR_m_pos;
else
    CR_m = CR_m_neg;
end
i_m = (k_um * u_offset - k_vm * om_m) / R;
res = k_tm * i_m - f_vm * om_m - CR_m * om_m * abs(om_m);
end