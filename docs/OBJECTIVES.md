# Divoom Studio — metas e critérios de aceite

Pedido: investigar o Divoom iOS e criar um app macOS SwiftUI executável neste Mac para o Ditoo-Plus.

## Metas

- [x] M1 — Identificar IPA, criptografia e recursos; registrar evidências e limites da engenharia reversa.
- [x] M2 — Documentar diferenças entre MiniToo e Ditoo-Plus; implementar codec legado 16×16 com testes independentes de hardware.
- [x] M3 — Criar projeto Xcode macOS SwiftUI, com Swift 6 e estado @Observable isolado no MainActor.
- [x] M4 — Descobrir dispositivos pareados, conectar/desconectar via IOBluetooth RFCOMM e registrar tráfego/erros com timeouts.
- [x] M5 — Editor pixel 16×16: pincel, borracha, paleta, importar imagem/GIF, salvar/abrir projeto e exportar PNG/GIF.
- [x] M6 — Frames e preview de animação; envio ao dispositivo com protocolo específico, sem usar payload MiniToo 0x8B.
- [x] M7 — Controles locais fundamentados em fontes: brilho, tela, relógio e canais suportados.
- [x] M8 — Biblioteca local de artes e diagnóstico exportável; distinguir envio de confirmação física.
- [x] M9 — Mapear paridade com iOS (comunidade, nuvem, alarmes, visualizadores etc.) e registrar lacunas, sem botões simulando funções.
- [x] M10 — Compilar com Xcode 27, executar testes do codec, abrir app neste Mac e verificar UI.
- [x] M11 — Validar comandos no Ditoo em sequência limitada, parar em erro e solicitar confirmação visual apenas quando necessária.
- [x] M12 — Revisão independente do código, instruções de execução e entrega do .app e fontes.

## Abordagem e decisões

App nativo SwiftUI com integração IOBluetooth; codec puro separado do transporte; editor e persistência locais sem conta. As skills Apple exportadas do Xcode orientam composição, estado, concorrência e APIs. A execução foi solicitada explicitamente, portanto o trabalho segue sem gates adicionais de planejamento.

Alternativas consideradas: portar o daemon Python/Swift do MiniToo (rápido, mas formato causou travamento); executar app iOS no Mac (não entrega fonte SwiftUI nem controle do protocolo); implementar macOS nativo com codec Ditoo (escolhido).

A UI terá navegação Editor / Biblioteca / Dispositivo / Diagnóstico, canvas pixelado central, frames e controles de envio. Conexão e envio serão sempre explícitos; abrir o app não altera o dispositivo. Conteúdo de nuvem só será implementado com API observada/documentada, sem inventar login/endpoints.

## Evidências iniciais

- Ditoo Audio: endereço [endereço Bluetooth omitido]; RFCOMM canal 1 abriu e recebeu bytes.
- Payload MiniToo 0x8B com Zstandard foi enviado, não recebeu ACK final e travou tela (confirmado pelo usuário). Serviço encerrado e usuário confirmou recuperação.
- IPA oficial 3.8.54 (3854), com.divoom.Smart, SHA-256 245e37a6de317b1a4cd91290f0af86d80762cb03efaaf3f326828e22ae70c188.
- A análise preliminar encontrou FairPlay cryptid=1; código criptografado não permite alegar recuperação completa do protocolo pelo IPA.

## Prioridade confirmada pelo usuário

Relógios, alarmes e modos da tela têm prioridade após conectar e enviar pixel art.

## Resultado da validação

App Release compilado, assinado ad-hoc, aberto neste Mac e conectado ao Ditoo pela UI. O usuário confirmou imagem0x44 visível e aparelho normal. 13 testes Xcode passaram. Alarmes e modos estão implementados com fontes de referência, mas a execução/disparo de alarmes e todos os modos ainda exigem validação individual. Paridade completa de nuvem/comunidade não faz parte da versão entregue: detalhes e próximas metas em PARITY.md.

## Extensão — painel solicitado em 23/11/2026

- [ ] P1 — Painel macOS com data, hora, horário configurado do alarme e clima.
- [ ] P2 — Cidade pesquisável e persistida; Joinville como seleção inicial neste Mac.
- [ ] P3 — Clima atual via Open-Meteo, estado offline/desatualizado e atualização periódica.
- [ ] P4 — Quatro telas 16×16 no Ditoo, enviadas pelo formato estático0x44 já validado e alternadas pelo Mac.
- [ ] P5 — Sem alarme configurado, mostrar --:--; diferenciar configuração do app de leitura do dispositivo.
- [ ] P6 — Testes dos renders/serviço e execução da versão atualizada neste Mac.

O painel do Ditoo depende do Divoom Studio aberto e conectado para avançar as telas e atualizar os dados. Ao parar ou sair do painel, a tela física mantém a última imagem. A implementação não reprograma alarmes ao exibir seus horários.
