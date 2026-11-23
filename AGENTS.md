# Divoom Studio

App macOS nativo em SwiftUI / Swift 6 para Ditoo via Bluetooth Classic (RFCOMM). macOS mínimo: 14. `project.yml` é a fonte de verdade do projeto Xcode; gere com XcodeGen, sem editar o pbxproj manualmente.

## Comandos

Na raiz do repositório, antes de concluir alterações:

```sh
./Scripts/test.sh
./Scripts/build.sh
```

O primeiro comando executa os testes Xcode. O segundo gera Release e verifica a assinatura ad-hoc. Pré-requisitos: Xcode 27 selecionado por `xcode-select` e XcodeGen (`brew install xcodegen`). App gerado: `build/Build/Products/Release/Divoom Studio.app`.

## Organização e invariantes

- `Sources/App`: ciclo de vida, estado e navegação SwiftUI.
- `Sources/Bluetooth`: transporte e logs; estado isolado no MainActor.
- `Sources/Protocol`: codec e framing sem UI ou transporte.
- `Sources/Editor`: projetos, mídia e editor de pixels.
- `Sources/Dashboard`: painel, renderização 16×16 e consultas Open-Meteo.
- `Tests`: vetores de protocolo, mídia, painel e clima.

Preserve Swift 6 e concorrência estrita. Não envie comandos Bluetooth automaticamente ao iniciar o app. Não conecte nem altere configurações do aparelho para validar código sem pedido explícito. ACK não comprova resultado visual; registre separadamente testes automatizados e validação física. Nunca versione endereços Bluetooth pessoais, credenciais, logs privados ou artefatos de build. Preserve as atribuições em `docs/THIRD_PARTY.md`.

## Distribuição

Versão e build ficam em `Info.plist`. Rode os dois comandos acima antes de empacotar. Crie o ZIP com `ditto -c -k --sequesterRsrc --keepParent` sobre o bundle Release. Publique como `Divoom-Studio-VERSAO-universal.zip` em uma release `vVERSAO` no GitHub. Atualize versão, URL e SHA-256 de `Casks/divoom-studio.rb` em `ronanrodrigo/homebrew-tap` e valide com `brew style` e instalação por Cask. Não anuncie notarização sem verificá-la; a distribuição atual usa assinatura ad-hoc.
