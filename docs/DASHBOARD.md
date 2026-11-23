# Painel: data, hora, alarme e clima

No Mac: quatro cartões simultâneos, mais prévia pixelada e configuração de cidade. O painel abre como tela inicial.

No Ditoo: alternância entre quatro imagens16×16, com ícone próprio e cores distintas. Data DD-MM, hora HH:MM, alarme HH:MM e clima com símbolo/temperatura em°C. Imagens usam o codec legado0x44 já validado fisicamente; não dependem do comando de animação não testado.

## Clima

Cidade editável por busca no Divoom Studio e seleção entre resultados; escolha é guardada neste Mac. Joinville é a cidade inicial solicitada. Dados atuais fornecidos pelo Open-Meteo via HTTPS, sem chave. Consulta automática a cada15min enquanto o painel estiver aberto, inclusive sem transmissão. Falhas não disparam consulta a cada troca de frame. Dados com mais de1h recebem sinalização no Mac e deixam de ser enviados como temperatura atual ao Ditoo.

## Horário e alarme

Data/hora usam fuso do Mac. Horário do alarme vem do formulário Alarmes do app, persiste entre execuções e é qualificado como configuração local. O app ainda não lê o alarme gravado no firmware. Sem horário configurado, a tela física mostra --:--. Alarme desativado com horário salvo usa ícone/cor distintos.

Exibir o painel não altera ou programa o alarme do Ditoo. Isso só acontece no botão específico da tela Alarmes.

## Transmissão

Conecte e clique Exibir no Ditoo. Intervalo configurável3–15s entre telas. O Mac continua atualizando os frames enquanto o painel estiver aberto e conectado. Parar ou navegar a outra seção encerra o agendamento; o último frame transmitido fica na tela. Sem repetição automática se houver erro de escrita ou desconexão. Resposta do protocolo não equivale a confirmação visual.
