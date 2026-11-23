# iPhone: compatibilidade Bluetooth e execução em segundo plano

Investigação somente leitura em 2026-11-23. Nenhuma conexão, descoberta Bluetooth, transmissão ao Ditoo, instalação no iPhone ou alteração de assinatura foi feita por esta investigação.

## Evidência específica do Ditoo Plus

Foi encontrada uma implementação pública que declara testes físicos com Ditoo Plus e Pixoo SlingBag, incluindo fotografia do aparelho. Isso é evidência primária de viabilidade do transporte BLE para o modelo; ainda não é validação do aparelho deste usuário. Fonte fixada: [alikendir0/divoom-ble-web, commit 03b2d4096a7650e9ccfd2e560d0e5df5f9f23085](https://github.com/alikendir0/divoom-ble-web/tree/03b2d4096a7650e9ccfd2e560d0e5df5f9f23085). Cópia local de pesquisa em `work/ios-compat-divoom-ble-web`.

O [documento de protocolo](https://github.com/alikendir0/divoom-ble-web/blob/03b2d4096a7650e9ccfd2e560d0e5df5f9f23085/docs/protocol.md) e [device.py](https://github.com/alikendir0/divoom-ble-web/blob/03b2d4096a7650e9ccfd2e560d0e5df5f9f23085/divoom_ble/device.py) estabelecem:

| Elemento | Valor |
|---|---|
| Serviço GATT | `49535343-FE7D-4AE5-8FA9-9FAFD205E455` |
| Escrita | `49535343-8841-43F4-A8D4-ECBE34729BB3` |
| Notificações | `49535343-1E4D-4BD9-BA61-23C647249616` |
| Envelope BLE | `FE EF AA 55 LEN_LE16 01 PACKET_LE32 COMMAND BODY SUM_LE16` |
| ACK correlacionável | Resposta clássica opcode `0x33` com número de pacote LE32 |
| Fluxo | Fragmentar conforme limite GATT, aguardar ACK, uma conexão controladora |

O [vetor de teste capturado](https://github.com/alikendir0/divoom-ble-web/blob/03b2d4096a7650e9ccfd2e560d0e5df5f9f23085/tests/test_protocol.py) para consultar volume (`09`), pacote1, é `feefaa5508000101000000091300`. Frames RFCOMM `01…02` não devem ser enviados diretamente como envelope GATT. As notificações de resposta mantêm o framing clássico e precisam de reassembly por tamanho/checksum.

A mesma referência relata controles e imagens estáticas, mais animação nativa `0x8B` mediante capabilities/handshake. O conteúdo de animação é paleta LED, diferente do payload RGB888/Zstandard MiniToo que travou o aparelho anteriormente. Não inferir equivalência pelo opcode.

## Fontes relacionadas e separação de perfis

[TheMarco/timebox-studio, ca1403d14e44d58ca9076fad6a4440237f278cf6](https://github.com/TheMarco/timebox-studio/tree/ca1403d14e44d58ca9076fad6a4440237f278cf6) possui implementação Swift CoreBluetooth e declara testes iOS no Timebox Evo. Seu `CoreBluetoothRCSPTransport.swift` usa os mesmos UUIDs e envelope. A nota DEVELOPMENT_NOTES antiga chama BLE de caminho sem resultado, enquanto código/README mais novos explicam o wrapper que o torna funcional; privilegiar código atual e evidência de teste, sem transferir automaticamente a garantia ao Plus.

[orionparrott/divoom-protocol, f9b661f8e06a6d40be91c800fed656c7402bd2ac](https://github.com/orionparrott/divoom-protocol/tree/f9b661f8e06a6d40be91c800fed656c7402bd2ac) trata geração moderna Backpack M/TimeBox-Evo-audio, com inicialização e estado distintos. Compartilhar UUID não basta para escolher esse handshake. A referência específica Plus acima evita aplicar a inicialização moderna indiscriminadamente.

PyPixoo (`endymion/PyPixoo`) é cliente HTTP para Pixoo64, sem evidência útil para o GATT Plus. Buscas limitadas por FFE1/FFF1 e pelo nome divoom-gatt não produziram fonte específica melhor; isso não prova ausência de outros perfis.

## O que iOS permite

CoreBluetooth oferece GATT em BLE e também em BR/EDR desde iOS13. O suporte Classic descrito pela Apple não expõe um socket RFCOMM/SPP arbitrário equivalente ao IOBluetooth do Mac. A implementação iPhone deve usar descoberta de serviços/características e fragmentação/flow control de GATT. [Apple: WWDC19 CoreBluetooth](https://developer.apple.com/videos/play/wwdc2019/901/), [sample Classic](https://developer.apple.com/documentation/corebluetooth/using-core-bluetooth-classic).

ExternalAccessory é outra rota, destinada a acessórios MFi e protocolos autorizados pelo fabricante. Não é substituto genérico para a conexão Classic deste app. [Apple: ExternalAccessory](https://developer.apple.com/documentation/externalaccessory).

O IPA oficial Divoom 3.8.54 (`com.divoom.Smart`, SHA256 `245e37a6de317b1a4cd91290f0af86d80762cb03efaaf3f326828e22ae70c188`) declara `NSBluetoothAlwaysUsageDescription`, modos `bluetooth-central` e `bluetooth-peripheral`. Não declara `UISupportedExternalAccessoryProtocols` ou modo `external-accessory`. Isso é consistente com CoreBluetooth, mas não recupera protocolo: o código e strings Objective-C estão cifrados por FairPlay.

## Segundo plano: promessas que podem ser feitas

`bluetooth-central` permite despertar para eventos Bluetooth e interagir com periféricos; não fornece execução ilimitada para um relógio próprio ou polling HTTP. State restoration recupera sessões elegíveis e deve ser implementada explicitamente. Ao suspender, o sistema pode coalescer scans e aumentar intervalos; eventos devem ser tratados rapidamente. [Apple: CoreBluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).

Scanning normal em background exige filtro explícito de serviços. Isso torna importante persistir o UUID do periférico e serviço confirmado, em vez de depender continuamente de busca por nome. [Apple: scanForPeripherals](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:)).

A documentação atual acrescenta que iOS26 permite privilégios Bluetooth equivalentes ao foreground durante uma Live Activity iniciada com CBManager instanciado. Isso não deve ser anunciado como garantia de execução permanente do painel: requer adoção/teste desse ciclo e respeito ao término da atividade e desconexão. [Apple: CoreBluetooth](https://developer.apple.com/documentation/corebluetooth).

Um frame/loop já armazenado no Ditoo pode continuar sem iPhone quando o firmware suporta isso. Um relógio totalmente desenhado com hora atual, clima e atualizações contínuas precisa de emissor ativo ou lógica no firmware; uma animação pré-calculada tem prazo finito e não consulta clima sozinha. Inference de arquitetura, não comportamento físico validado nesta sessão.

## Ambiente local e validação pendente

Inspeção read-only encontrou Xcode27 selecionado e duas identidades de assinatura válidas (Development e Distribution). Nomes, hashes de certificados e identificadores pessoais não estão registrados aqui. A disponibilidade dessas identidades não prova provisionamento de um novo bundle iOS.

`devicectl list devices` informou um iPhone físico cadastrado como indisponível no instante da consulta, além de um simulador desligado. Nenhuma ação de controle foi executada. Simulador serve para UI/tests, não prova a conexão Bluetooth física.

Critérios para confirmar funcionamento: build assinado no iPhone real; permissão Bluetooth concedida; descobrir serviço e propriedades das características; subscribe notifications; enviar uma consulta de baixo impacto e correlacionar ACK por pacote; enviar uma alteração visível e obter confirmação do usuário; depois validar imagem16×16 e comportamento foreground/background. Até esses resultados, registrar suporte implementado por referência e validação física pendente separadamente.


## Correção de descoberta: conexão existente no iOS

A busca inicial usava apenas anúncios próximos e filtro de nome. Isso podia omitir um aparelho já conectado ao iOS pelo aplicativo oficial, ou um anúncio sem nome/renomeado com o serviço correto. A implementação agora consulta `retrieveConnectedPeripherals(withServices:)` pelo serviço UART ISSC conhecido antes de iniciar a busca. Um resultado recuperado ainda exige seleção e `connect` local explícito; não habilita escrita por si só. A busca aceita anúncio com esse serviço exato independentemente do nome e verifica os dois nomes disponíveis quando o serviço não está anunciado. Anúncios alheios são descartados antes de armazenar ou registrar informações.

A API [Apple retrieveConnectedPeripherals](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:)) inclui conexões estabelecidas por outros apps. O guia [Apple de reconexão](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/BestPracticesForInteractingWithARemotePeripheralDevice/BestPracticesForInteractingWithARemotePeripheralDevice.html) distingue recuperar conexão do sistema de conectar localmente ao próprio app. Isso fundamenta a correção, mas ainda não comprova a causa da falha observada neste iPhone/Ditoo.

O UUID ISSC é um serviço genérico: um resultado é candidato, não prova de fabricante/modelo. A verificação exata das características e a escolha do protocolo continuam necessárias antes de enviar comandos. Logs de busca registram início, origem dos candidatos compatíveis e contagem final; o valor RSSI127 de um aparelho recuperado não é apresentado como medição válida. Sem nova conexão, comandos ou testes físicos automáticos.

## Reconexão automática — build 6

Após a confirmação física da conexão pelo usuário, foi implementada a reconexão ao último aparelho validado. A conexão manual inicial salva UUID CoreBluetooth, nome e protocolo localmente. Com a preferência ativa, o manager é reconstruído em App.init, inclusive em relançamento por Bluetooth, com identificador de restauração estável; somente o UUID salvo é adotado. Conexões automáticas ficam pendentes no sistema até o aparelho estar disponível. Depois de didConnect, há limite de 15 segundos para serviços e assinatura de notificações; erros explícitos aplicam espera progressiva no primeiro plano. Desconectar desativa a preferência e Esquecer remove o alvo.

Isso substitui a exigência anterior de seleção manual a cada abertura, sem enviar comandos de aplicação ao conectar. Sem alvo persistido, ainda é necessária a primeira seleção manual. A transmissão do painel continua limitada ao primeiro plano. Restauração não garante retomada após encerramento forçado; as regras atuais estão na [Apple TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules). Testes físicos de reconexão são registrados separadamente em HARDWARE-VALIDATION.md.
