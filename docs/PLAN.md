# Plano de execução

## Onda 1 — pesquisa (concluída)

Três subagents independentes examinaram IPA, protocolo e ambiente Xcode. A investigação REA estabeleceu o inventário do IPA; FairPlay impede recuperar o código do protocolo pelo pacote. Fontes primárias com implementação Ditoo forneceram um codec legado independente. Xcode 27, SDK 27, Swift 6.4 e XcodeGen já estão disponíveis.

## Onda 2 — implementação em paralelo

- **Protocol**: encoder/decoder puro, relógio, sincronização, brilho, imagem paletizada, animação e alarme; testes de vetores e limites.
- **Bluetooth**: transporte IOBluetooth RFCOMM, conexão assíncrona, timeouts, logs, fila cancelável, validação de respostas e desconexão explícita.
- **SwiftUI**: navegação nativa e estado @Observable; prioridade relógios/alarmes/modos, editor e biblioteca local.
- **Integração**: projeto XcodeGen, build/settings, documentação e execução neste Mac.

## Onda 3 — validação

1. Compilar com concorrência Swift 6 completa e corrigir diagnósticos.
2. Executar testes independentes do dispositivo; conferir vetores contra fontes.
3. Abrir .app e verificar controles e estados na UI.
4. Uma conexão; consulta de canal somente leitura. Conferir checksum e resposta.
5. Um controle de relógio/brightness, sem alterar alarmes automaticamente; pedir confirmação visual quando necessário.
6. Frame curto legado somente após consulta/control responder; sem reenvio automático em timeout. Não repetir formato MiniToo.
7. Revisão independente e correções; documentar funções implementadas versus validadas em hardware.

## Regras de evidência

Escrita RFCOMM, ACK de firmware e confirmação visual são níveis diferentes. O app não deve afirmar que relógio/alarme/imagem foi aplicado só pelo sucesso da escrita. Recursos de nuvem não serão substituídos por endpoints inventados ou uma interface sem implementação.
