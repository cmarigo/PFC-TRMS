# Gêmeo digital do sistema didático rotor duplo (TRMS)

Projeto Final de Curso — Engenharia de Controle e Automação, Escola de Engenharia da UFMG
Autora: Clara Temponi Marigo · Orientador: Prof. Leonardo Amaral Mozelli

Códigos, dados experimentais e resultados da monografia *Desenvolvimento de Gêmeo Digital do Sistema Didático do Tipo Rotor Duplo*. O modelo de referência é o de Tastemirov et al. (2017), implementado em Simulink e reidentificado sobre a unidade do Laboratório de Controle e Automação I.

## Requisitos

- MATLAB e Simulink R2025b ou posterior (versão em que o modelo foi salvo).
- Nenhuma outra toolbox. As otimizações usam `fminsearch`, do próprio MATLAB.

## Estrutura

```
PFC-TRMS-CLARATEMPONI/
├── 01-Modelo/                 modelo Simulink e funções de apoio
├── 02-Dados/
│   ├── Coleta 1 - Pitch (Step, PRBS, CHIRP)/
│   ├── Coleta 2 - Yaw sem soltura completa/
│   ├── Coleta 3 - Yaw Solto e PID arfagem/
│   └── utils/                 localização dos dados
├── 03-Identificacao/          identificação de parâmetros
│   └── Analises-sensibilidade/
├── 04-Validacao/
│   ├── Malha-aberta/          validação da arfagem e da guinada
│   └── Malha-fechada/         comparação com a bancada sob o PID de arfagem
├── 05-Monografia/
│   └── resultados/            resultados (.mat) usados no texto
└── 3D/                        aplicativo do estudante e cena tridimensional
```

## Como executar

Com a pasta `PFC-TRMS-CLARATEMPONI` como pasta corrente do MATLAB:

```matlab
raiz = pwd;
addpath(genpath(fullfile(raiz, '01-Modelo')), ...
        genpath(fullfile(raiz, '02-Dados', 'utils')), ...
        genpath(fullfile(raiz, '03-Identificacao')), ...
        genpath(fullfile(raiz, '04-Validacao')));
addpath(fullfile(raiz, '3D'), '-end');
```

A pasta `3D` entra no fim do caminho porque contém cópias do `trms_params.m` e do modelo; assim, valem as de `01-Modelo`. Ela só é necessária para o `trms_anima_comparacao` e para o aplicativo.

Convenções comuns a todos os scripts:

- **Parâmetros.** O `InitFcn` do modelo é vazio. Cada script carrega o `trms_params` no workspace base e passa ao modelo, por `Simulink.SimulationInput`, os parâmetros que deseja alterar. Os scripts são funções, para que suas variáveis locais não se misturem com as do workspace base.
- **Simulação.** Toda simulação passa pelo `simula_trms`, que é o único lugar onde os nomes de entradas e saídas do `.slx` aparecem.
- **Ponto de operação.** Nos ensaios de arfagem, o ponto de operação é identificado pela tensão de polarização registrada nos primeiros 19 s, e não só pelo nome do arquivo. A condição inicial é o equilíbrio nesse ponto, calculado pelo `trms_equilibrium`.
- **Guinada travada.** Nos ensaios de arfagem, a guinada é travada no modelo pela máscara de estados `[1 0 1 1 1 0]`, como o parafuso a travava na bancada.
- **Custo.** O erro é calculado a partir de 20 s (`T_SETTLE`), com medido e simulado referenciados à média dos 2 s anteriores. Os índices relativos usam J = 100·MSE/var(medido).
- **Saídas.** Os resultados são gravados em `05-Monografia/resultados/`. Rodar um script de novo sobrescreve o arquivo correspondente. Os scripts também abrem figuras de conferência na tela.

A pasta `resultados` já contém os resultados que deram origem às tabelas e figuras da monografia.

---

## 01-Modelo

**`trms_model_pid_bancada.slx`** — Modelo Simulink do gêmeo. A dinâmica não linear de seis estados `[ψ φ ω_m ω_t ψ̇ φ̇]` está no bloco MATLAB Function `trms_dynamics`, integrada com passo fixo de 1 ms. O bloco `trms_sel_entrada` escolhe o modo de operação (0: malhas abertas; 1: arfagem em malha fechada). O controlador de arfagem replica o PID discreto da bancada, com saturação e quantização do encoder, e um bloco de viés converte a saída de arfagem para o referencial do encoder, que é zerado na posição de repouso.

**`trms_params.m`** — Todos os parâmetros do modelo: geometria, motores, aerodinâmica, atrito e cabo. Contém os valores identificados neste trabalho (f_s = 3,48·f_cψ e v_s = 0,05 rad/s na arfagem; C_c, f_vφ e φ₀ na guinada), o repouso de arfagem ψ₀, derivado de G_y e G_z, e a condição inicial `x0`.

**`simula_trms.m`** — Interface única dos scripts com o modelo. Recebe uma estrutura com duração, modo, máscara de estados, condição inicial, entradas dos rotores, parâmetros a sobrescrever e ganhos do PID, e devolve as saídas com nomes padronizados (`psi`, `phi`, `u1` e a tensão do rotor de cauda).

**`trms_equilibrium.m`** — Estado de equilíbrio estático para uma tensão no rotor principal, com a guinada travada. Resolve em sequência as equações de equilíbrio do motor, da arfagem e da guinada do modelo de Tastemirov. É usado como condição inicial dos ensaios de arfagem.

**`confere_params.m`** — Confere os parâmetros carregados no workspace base contra o conjunto identificado (ou o nominal) e aponta o que diverge, incluindo a coerência de `x0` com ψ₀ e φ₀. Não altera nada. É chamado pelos scripts de malha fechada antes de simular.

## 02-Dados

Todos os registros foram feitos a 10 Hz na bancada do Laboratório de Controle e Automação I.

- **Coleta 1 — arfagem, guinada travada.** Degrau, PRBS e varredura em frequência (`chirp`) em sete pontos de operação, de −10° a +20°. Os nomes seguem `out_[sinal]_op[p/n][ângulo]_amp03`. Nos arquivos de varredura, a variável `pitch` guarda a tensão aplicada e o ângulo de arfagem está em `yaw`; os scripts detectam e corrigem a troca. O arquivo `out_prbs_opn10deg_amp03` foi coletado com a polarização de −5° e é tratado como repetição desse ponto.
- **Coleta 2 — guinada.** Patamares de 80 s da curva estática (`out_025`, `out_n05` etc.; o sufixo `_v2` indica a coleta de controle, feita em outra sessão), oscilação livre com os motores desligados (`out_solto`, `out_livre`), degrau longo de validação do protocolo (`out_media`) e PRBS de 0,15 a 0,40 V (`out_prbs_*`).
- **Coleta 3 — parafuso da guinada solto e malha fechada.** Soma de senoides no rotor de cauda (`out_yaw_sen_*`), degraus de guinada e ensaios com o PID de arfagem da bancada (`out_pitch_pid_*`), incluindo o Teste 6, com degrau de u₂ durante o controle.

**`utils/caminhos_dados.m`** — Declara num só lugar as pastas das três coletas e a pasta de resultados, que é criada se não existir.

**`utils/acha_dados.m`** — Procura um arquivo pelo nome dentro de uma pasta de coleta e de todas as suas subpastas. Exige um único resultado, para não usar sem aviso um arquivo homônimo de outra subpasta.

## 03-Identificacao — eixo de arfagem

**`identifica_fs_multiexperimento.m`** — Identifica o nível de atrito estático f_s. Varre f_s/f_cψ numa grade de 21 pontos entre 1 e 16, simulando seis ensaios (degrau e PRBS em 0°, +5° e −5°) em cada ponto, num total de 126 simulações. Com a grade completa, calcula o ótimo isolado de cada ensaio e o ótimo do custo agregado (média do J relativo) para diferentes subconjuntos. O valor adotado vem do conjunto sem o PRBS de 0°, cuja excursão de ±3° está na escala da quantização do encoder; o mínimo é refinado por interpolação entre os pontos vizinhos da grade.
*Saída:* `fs_multiexperimento.mat` (Tabelas `fs_isolado` e `fs_agregado`; Figura `custo_fs`).

**`reidentifica_fcpsi_com_fs.m`** — Testa se o excesso de atrito de Coulomb identificado nos degraus era, na verdade, atrito estático ausente do modelo. Em cada um dos seis ensaios, otimiza f_cψ em dois cenários: (A) sem atrito estático e (B) com f_s fixo no ótimo isolado daquele ensaio, lido do `fs_multiexperimento.mat`. Roda duas vezes, com o coeficiente de empuxo C_Tm⁺ nominal e com 0,91 vez o nominal (valor da curva de equilíbrio), para avaliar o efeito dessa escala no ajuste dinâmico.
*Saídas:* `fcpsi_com_fs_ct100.mat` e `fcpsi_com_fs_ct091.mat`, com as séries da janela de custo (Tabelas `fc_reident` e `ct_m_custo`; Figura `ct_m_degrau`).

### Análises de sensibilidade

**`otimiza_fvpsi_fcpsi.m`** — Primeira tentativa de identificação do atrito de arfagem: otimização conjunta de f_vψ e f_cψ, com atrito de Coulomb puro, em três ensaios (PRBS em 0° e +5°, degrau em 0°). Antes de cada otimização, varre cada coeficiente sozinho de 0,1 a 10 vezes o nominal. Os resultados mostram que os dois coeficientes não são identificáveis em conjunto.
*Saída:* `otimiza_fvpsi_fcpsi.mat` (Tabela `otim_conjunta`; Seção `nao_identificabilidade`).

**`sensibilidade_fvpsi_com_fs.m`** — Varre f_vψ de 0,1 a 31,6 vezes o nominal no degrau de 0°, sem e com atrito estático (f_s no ótimo isolado desse ensaio). Mostra que o vale de f_vψ em valores altos, presente sem f_s, desaparece quando o atrito estático é incluído.
*Saída:* `sensibilidade_fvpsi_com_fs.mat` (Tabela `fv_com_fs`).

**`sensibilidade_fs_vs.m`** — Varre separadamente f_s (de 1 a 3 vezes f_cψ) e a velocidade de Stribeck v_s (de 0,01 a 1 rad/s) no degrau de 0°, para verificar se os dados determinam esses parâmetros. Justifica a escolha de v_s = 0,05 rad/s.
*Saída:* `sensibilidade_fs_vs.mat` (Seção `atrito_estatico`; Tabela `param_final`).

**`sensibilidade_i_psi.m`** — Varre a inércia de arfagem I_ψ de 0,3 a 3 vezes o nominal no degrau de 0°, medindo o erro no ensaio completo e separadamente antes e depois de 50 s. Testa se a defasagem que aparece no fim desse ensaio vem da inércia; o mínimo fica no valor nominal nas três janelas.
*Saída:* `sensibilidade_i_psi.mat` (Seção `inercia_pitch`).

## 03-Identificacao — eixo de guinada

**`Analises-sensibilidade/ajusta_curva_yaw.m`** — Ajusta a equação de equilíbrio estático da guinada aos patamares de 80 s. A curva estática sozinha só determina a razão entre empuxo e rigidez do cabo; a oscilação livre com os motores desligados mede a rigidez C_c⁺ sem envolver o rotor e fornece a escala que falta. Calcula C_c⁺ pelos meios períodos da oscilação livre (com a inércia efetiva I_φ + I_c·cos²ψ), φ₀ e o atrito de ruptura pela assimetria das tensões de ruptura, a lei de potência do ramo positivo e a rigidez relativa do ramo negativo. Os resultados são impressos na tela.
*Seções:* `res_yaw_curva`, `res_cc` e `res_phi0`.

**`identifica_dinamica_yaw.m`** — Identifica a dinâmica da guinada pelos transitórios dos degraus da coleta de controle. Cada transitório é ajustado por `fminsearch` a três componentes: o equilíbrio, um modo lento de primeira ordem e uma oscilação amortecida. Separar o modo lento antes de extrair o amortecimento evita que a deriva lenta seja absorvida como amortecimento. Da oscilação saem ω_n, ζ, C_c e f_vφ; faz o mesmo cálculo na oscilação livre, para comparar o amortecimento com e sem o rotor de cauda.
*Saída:* `dinamica_yaw_resultados.mat` (Tabela `yaw_amortecimento`; Figura `yaw_ajuste_degrau`).

## 04-Validacao — malha aberta

**`Malha-aberta/valida_pitch_completo.m`** — Validação da arfagem com o conjunto de parâmetros congelado, sem nenhuma otimização. Simula todos os ensaios da Coleta 1 com o modelo nominal e com o identificado, e calcula J, RMSE, a melhora relativa e o pior erro numa janela de 1 s. Separa os ensaios usados na estimação dos de validação e, nas varreduras em frequência, calcula também o erro até o instante em que a frequência deixa a banda da arfagem.
*Saídas:* `validacao_pitch.mat` e `validacao_pitch.csv` (Tabelas `validacao` e `validacao_chirp`; Figuras `val_nominal`, `val_step`, `val_prbs` e `val_chirp`).

```matlab
valida_pitch_completo                                         % configuração da monografia
valida_pitch_completo('mascara', ones(6,1), 'salvar', false)  % com a guinada livre no modelo
```

**`Malha-aberta/valida_yaw.m`** — Validação da guinada nos PRBS da Coleta 2, que não participaram da identificação. A entrada do modelo é a sequência PRBS regerada (registrador de 6 bits, período de 1,5 s), conferida contra a tensão registrada. Calcula J, o ganho e o viés da regressão entre simulado e medido e, como referência, o J entre as duas realizações do PRBS de 0,30 V, que é o piso de repetibilidade da bancada. Como φ₀ só aparece como (φ − φ₀), a comparação é feita em relação ao instante inicial e não depende do seu valor.
*Saídas:* `valida_yaw_resultados.mat` e, com os parâmetros nominais, `valida_yaw_nominal.mat` (Tabela `yaw_validacao`; Figuras `yaw_validacao_prbs` e `yaw_nominal`).

```matlab
valida_yaw                                                        % parâmetros identificados
valida_yaw('nominal', true)                                       % parâmetros de Tastemirov
valida_yaw('ensaios', {'out_prbs_015.mat', 0.15}, 'salvar', false) % ensaio de 0,15 V, fora da média
valida_yaw('C_c', 3.05e-2, 'salvar', false)                       % rigidez estimada pelos degraus
```

## 04-Validacao — malha fechada

**`Malha-fechada/compara_pid_c3.m`** — Compara o gêmeo com a bancada nos ensaios de PID de arfagem da Coleta 3 (ganhos 4/6/8 e 5/8/10, e o Teste 6). Simula o gêmeo com os mesmos ganhos, referência e perturbação, amostra e quantiza a saída como o encoder e calcula sobressinal, instante de pico, tempos de subida e de acomodação, u₁ de regime, contagens de ψ em regime e o erro relativo de ψ. Imprime também o piso de repetibilidade da bancada (4/6/8 contra o início do Teste 6), o sentido da mudança entre as duas sintonias e a deflexão da guinada provocada pelo degrau de u₂.
*Saída:* `compara_pid_c3_resultados.mat` (Tabela `validacao_mf`; Figura `validacao_mf`). O resultado salvo é o do modelo identificado; a coluna "Nominal" corresponde ao gêmeo com f_s = f_cψ no `trms_params`.

**`Malha-fechada/valida_senoides_c3.m`** — Valida a guinada com a soma de senoides no rotor de cauda, com o parafuso solto e o rotor principal desligado, em dois ganhos de saída: 0,19 (dentro da faixa dos PRBS de identificação) e 0,5 (extrapolação). Calcula J, ganho e viés e, para cada frequência da soma, o ganho e a fase de φ em relação a u₂ na bancada e no gêmeo.
*Saída:* `valida_senoides_c3_resultados.mat` (Tabelas `yaw_senoides` e `yaw_senoides_freq`).

**`Malha-fechada/metricas_integrais_c3.m`** — Calcula o IAE e o ISE da arfagem na bancada e no gêmeo, a partir dos sinais já alinhados pelo `compara_pid_c3`, com a mesma janela nas duas sintonias. Separa a parcela de regime, que vem da alternância de contagens do encoder, e compara a mudança entre sintonias com o piso de repetibilidade da bancada.
*Saída:* `metricas_integrais_c3.mat`.

**`Malha-fechada/trms_anima_comparacao.m`** — Anima a bancada e o gêmeo lado a lado, no mesmo relógio, a partir de um ensaio do `compara_pid_c3`, com os gráficos de ψ e φ abaixo das cenas. Permite travar a guinada no desenho, escolher o repouso desenhado e gravar vídeo.

```matlab
P = caminhos_dados();
S = load(fullfile(P.resultados, 'compara_pid_c3_resultados.mat'));
trms_anima_comparacao(S.R(1), struct('velocidade', 4, 'titulo', false, 'travar_yaw', true))
```

## 3D — aplicativo do estudante

**`trms_app.m`** — Interface do estudante. O aluno informa os ganhos do PID de arfagem, a referência e uma perturbação em u₂; o aplicativo simula o `trms_model_pid_bancada` e mostra os gráficos e a animação 3D lado a lado, com métricas de desempenho (sobressinal, tempo de pico, acomodação a 2%, erro de regime, IAE, ISE e esforço de controle).

**`trms_cena_geometria.m`, `trms_cena_criar.m`, `trms_cena_atualizar.m`, `trms_angulo_pa.m`** — Cena tridimensional cinemática do TRMS, construída com `hgtransform`: dimensões, criação dos objetos, atualização da pose a cada quadro e rotação aparente das pás.

**`trms_cena_ref_criar.m`, `trms_cena_ref_atualizar.m`, `trms_cena_ref_mostrar.m`** — Linhas de referência angular e fantasma do rotor na posição de referência, com opção de ligar e desligar.

Para usar o aplicativo sem o restante do projeto, instale a toolbox:

```matlab
matlab.addons.install('3D/release/TRMS-rotor-duplo.mltbx')
trms_app
```
