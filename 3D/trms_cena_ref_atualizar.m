function trms_cena_ref_atualizar(R, psi, phi, psi_ref, texto)
%TRMS_CENA_REF_ATUALIZAR Posiciona os arcos de angulo e o fantasma da referencia.
%
%   TRMS_CENA_REF_ATUALIZAR(R, psi, phi, psi_ref) para a pose (psi, phi) que
%   foi entregue a TRMS_CENA_ATUALIZAR no mesmo quadro.
%     psi, phi  angulos da viga [rad], convencao do modelo (psi = 0 na
%               horizontal), os mesmos da TRMS_CENA_ATUALIZAR.
%     psi_ref   referencia de arfagem na mesma convencao [rad]. NaN esconde
%               o fantasma (por exemplo, antes do degrau, quando a
%               referencia e o proprio repouso).
%   TRMS_CENA_REF_ATUALIZAR(..., texto) com texto = false pula os rotulos
%   dos arcos, que custam mais que as linhas.
%
%   O fantasma so muda de pose quando psi_ref muda; os arcos so sao
%   recalculados quando as linhas estao visiveis.
%
%   Ver tambem TRMS_CENA_REF_CRIAR, TRMS_CENA_REF_MOSTRAR.

if nargin < 5 || isempty(texto)
    texto = true;
end
g = R.g;

% --- Arcos -------------------------------------------------------------------
if ~isempty(R.mesa) && isgraphics(R.mesa) && logical(R.mesa.Visible)
    % psi: no plano da viga, da horizontal ate a viga (mesmo angulo que a
    % cena usa para girar a viga).
    th = -g.sinal_pitch * (psi + g.offset_pitch);
    a  = linspace(0, th, 24);
    set(R.arco_psi, 'XData', R.r_psi*cos(a), 'YData', 0*a, ...
                    'ZData', g.h + R.r_psi*sin(a));

    % phi: no plano horizontal do pivo, de phi = 0 ate a viga.
    b0 = g.sinal_yaw * g.offset_yaw;
    b1 = g.sinal_yaw * (phi + g.offset_yaw);
    b  = linspace(b0, b1, 32);
    set(R.arco_phi, 'XData', R.r_phi*cos(b), 'YData', R.r_phi*sin(b), ...
                    'ZData', g.h + 0*b);

    if texto && ~isempty(R.txt_psi)
        rp = R.r_psi + 0.035;
        rf = R.r_phi + 0.035;
        set(R.txt_psi, 'Position', [rp*cos(th/2), 0, g.h + rp*sin(th/2)]);
        set(R.txt_phi, 'Position', [rf*cos((b0 + b1)/2), rf*sin((b0 + b1)/2), g.h]);
    end
end

% --- Fantasma -------------------------------------------------------------------
if ~isempty(R.fant_pose) && isgraphics(R.fant_pose)
    if ~isequaln(R.fant_pose.UserData, psi_ref)
        R.fant_pose.UserData = psi_ref;
        if isnan(psi_ref)
            R.fant_pose.Visible = 'off';
        else
            % Mesma transformacao do t_pitch da cena.
            a_ref = g.sinal_pitch * (psi_ref + g.offset_pitch);
            R.fant_pose.Matrix = makehgtform('translate', [0 0 g.h]) * ...
                                 makehgtform('yrotate', a_ref);
            R.fant_pose.Visible = 'on';
        end
    end
end
end
