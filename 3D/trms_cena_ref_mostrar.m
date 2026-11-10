function trms_cena_ref_mostrar(R, linhas, fantasma)
%TRMS_CENA_REF_MOSTRAR Liga ou desliga as linhas de referencia e o fantasma.
%
%   TRMS_CENA_REF_MOSTRAR(R, linhas, fantasma) com valores logicos. Passe
%   [] para deixar uma das partes como esta. Partes que nao foram criadas
%   (opcoes.linhas ou opcoes.fantasma falsos no TRMS_CENA_REF_CRIAR) sao
%   ignoradas.
%
%   Ao ligar as linhas, chame TRMS_CENA_REF_ATUALIZAR em seguida: os arcos
%   nao sao recalculados enquanto estao escondidos.
%
%   O fantasma ligado so aparece quando ha referencia (psi_ref nao NaN).
%
%   Ver tambem TRMS_CENA_REF_CRIAR, TRMS_CENA_REF_ATUALIZAR.

if nargin >= 2 && ~isempty(linhas)
    h = [R.mesa R.viga];
    h = h(isgraphics(h));
    set(h, 'Visible', onoff(linhas));
end
if nargin >= 3 && ~isempty(fantasma) && ~isempty(R.fant_on) && isgraphics(R.fant_on)
    R.fant_on.Visible = onoff(fantasma);
end
end

function s = onoff(v)
if v
    s = 'on';
else
    s = 'off';
end
end
