# Validação Ditoo-Plus

Data: 2026-11-23. Dispositivo pareado: Ditoo Audio, [endereço Bluetooth omitido], canal RFCOMM 1. Probe temporário usa o codec Swift real de Sources/Protocol e fecha o canal após 4 segundos. Nenhum serviço TCP aberto pelo novo app.

## Consulta de canal — observada

TX: `01 03 00 46 49 00 02`

RX: `01 19 00 04 46 55 00 00 00 FF FF FF 5F 00 01 00 5F 01 FF FF FF 01 01 00 00 01 75 07 02`

Abertura RFCOMM e writeSync retornaram 0. A resposta referencia comando 0x46 e marcador0x55. O comprimento e a soma de verificação são verificáveis com decodeFrame.

## Retorno ao relógio — resposta observada, visual pendente

TX: `01 04 00 45 00 49 00 02`

RX: `01 06 00 04 45 55 00 A4 00 02`

RX adicional: `01 06 00 04 31 55 5F EF 00 02`

Abertura/escrita retornaram 0. Recebido ACK do comando0x45. Usuário respondeu: "Esta normal, rotacionando telas". Estabilidade confirmada; relógio fixo não confirmado. Não confundir ACK com aplicação visível.

## Ainda sem validação física

Relógios configurados, sincronização hora, brilho, luz, VJ/visualizer, alarmes, imagens e animação. Os vetores podem estar cobertos por testes do codec, mas isso não prova compatibilidade com este firmware. Não programar alarmes automaticamente durante QA.

## Histórico anterior

O formato MiniToo (0x8B + LCD/Zstandard) travou a tela. O usuário reiniciou e confirmou recuperação. Esse formato não faz parte do codec do novo app.

## App SwiftUI Release — validado pelo usuário

O .app Release com assinatura ad-hoc foi aberto neste Mac e operado pela interface nativa.

- Conectar: estado observado "Conectado por Bluetooth; aguardando ação".
- Aplicar relógio: TX0x2D para formato24h e TX0x45 com estilo0/cor ciano. Recebida resposta0x45. Não recebida resposta0x2D (fonte de referência usa skipRead nesse comando).
- Abrir projeto: Examples/Teste-Ditoo.json carregou e apareceu no editor.
- Enviar quadro: imagem de duas cores (preto/ciano), formato0x44 paletaAA; recebido resposta do comando0x44.
- Confirmação física do usuário: **"Sim, apareceu e está normal"**.

Isso valida conexão, escrita assíncrona, parser de resposta e envio visual de uma imagem curta pelo app final neste Ditoo-Plus. Não prova que todos os estilos, alarmes ou animações sejam compatíveis.

## Testes automatizados

Xcode27, Swift6, Debug e concorrência completa: 13 testes, zero falhas. Vetores de protocolo, checksum/reassembly, paletas1/2/256cores, limites de animação, alarmes/relógio; PNGRGB/orientação, recorte central, EXIF6, GIF timing e JSON inválido.

Separadamente, o codec foi comparado byte a byte com os métodos reais do hass-divoom para paletas1,2,3,5,16,256cores; correspondência integral.
