# ADR0001 — Versão iPhone no mesmo projeto

Status: implementado; validação Bluetooth física pendente, 23/11/2026.

## Objetivo

Levar o painel, editor de pixels, biblioteca, relógio e alarmes ao iPhone para permitir conexão Bluetooth próxima ao Ditoo. A investigação de firmware customizado foi pausada por decisão do usuário em favor da versão iPhone.

## Decisão

Adicionar target DivoomStudioMobile(iOS17+) em project.yml, preservando o target macOS14+ existente. Compartilhar codec puro, renderização16×16, modelo/conversão de mídia e cliente meteorológico. UI/apresentação iOS vive em Sources/iOS, transporte CoreBluetooth em Sources/iOS/Bluetooth. IOBluetooth continua exclusivo do Mac. O formato BLE é distinto do envelope RFCOMM; não enviar framesRFCOMM diretamente a uma characteristicGATT.

As skills Apple swiftui-specialist e device-interaction orientam UI e validação. A skill ios-swiftui foi consultada e declara explicitamente que não se aplica retroativamente a repositório existente; por isso não se impõe nova arquitetura SwiftPM/Bitrise ao repo macOS existente. AGENTS.md e XcodeGen seguem como fonte das invariantes.

## Ciclo de vida e limites

Nenhum scan/conexão/envio automático ao abrir o app. Descoberta, conexão e envio exigem intenção do usuário. Transmissão do painel para quando o app deixa o estado ativo; não prometer execução contínua de timer sob suspensão do iOS. bluetooth-central permite eventos de CoreBluetooth em segundo plano, não execução irrestrita.

Simulador valida build, estado local, navegação e mídia; não comprova comunicação física BLE com o Ditoo. A compatibilidade final precisa de um iPhone real conectado ao aparelho. O app é assinado com configuração de desenvolvimento local, sem chaves/profiles versionados. Distribuição TestFlight/AppStore exige fluxo próprio; assinatura ad-hoc macOS não instala um app iOS.

## Verificação

Gates existentes obrigatórios: Scripts/test.sh e Scripts/build.sh. Gates novos: Scripts/test-ios.sh e Scripts/build-ios.sh. Os testes puros compartilhados compilam/executam em ambos os targets. Teste físico e ACK do protocolo são registrados separadamente da confirmação visual.
