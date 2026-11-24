# Divoom Studio

App nativo SwiftUI / Swift 6 para Ditoo-Plus. O foco atual é macOS 14+, com companion iPhone iOS 17+ preservado no mesmo projeto. Oriente o escopo pelo pedido do usuário; paridade funcional não significa copiar a UI ou o transporte entre plataformas.

`project.yml` é a fonte de verdade do projeto Xcode. Gere com XcodeGen; não edite `project.pbxproj` manualmente. Preserve Swift 6, concorrência estrita e as atribuições em `docs/THIRD_PARTY.md`.

## Contexto e organização

Leia as instruções locais e os documentos pertinentes antes de alterar comportamento:

- `docs/MACOS-PARITY.md`: recursos e decisões atuais do Mac.
- `docs/AUTOMATIC-CONNECTION.md` e `docs/IPHONE.md`: companion iPhone e seus limites.
- `docs/HARDWARE-VALIDATION.md`: evidência física, separada dos testes automatizados.
- `docs/adr/`: decisões arquiteturais. Documentos históricos podem descrever comportamentos substituídos; confira o código e as decisões posteriores.

Limites dos módulos:

- `Sources/App`: estado, ciclo de vida e navegação SwiftUI do Mac.
- `Sources/Bluetooth`: transporte Classic RFCOMM, reconexão, preferências e logs do Mac; estado no MainActor.
- `Sources/Protocol`: codec/framing puros, sem UI ou transporte.
- `Sources/Editor`: projetos, mídia e editor de pixels. Preserve a compatibilidade dos arquivos entre plataformas.
- `Sources/Dashboard`: painel, renders 16×16, cidade, clima Open-Meteo e cache.
- `Sources/iOS`: apresentação e transporte CoreBluetooth do companion. Não importe IOBluetooth/AppKit para o target iOS.
- `Tests`: vetores, mídia, painel, clima e persistência. Testes exclusivos do Mac devem usar `#if os(macOS)` ou exclusão no XcodeGen, pois o target iOS também inclui testes compartilhados.

## Engenharia reversa e artefatos de pesquisa

Antes de investigar ou alterar o protocolo, consulte `docs/IOS-COMPATIBILITY.md`, `docs/PARITY.md`, `docs/THIRD_PARTY.md` e `docs/HARDWARE-VALIDATION.md`. Esses documentos estão versionados e distinguem fontes, implementação e validação física.

Os artefatos originais estão fora do repositório, neste Mac:

- Base de entregáveis: `/Users/ronan/Documents/Codex/2026-11-23/cone/outputs/divoom/`.
- Nessa base: `research-ipa.md` (investigação do app), `research-protocol.md` (protocolo), `research-xcode.md` (ambiente), `metadata.json` e `Divoom.ipa`.
- Saídas brutas REA: `/Users/ronan/Documents/Codex/2026-11-23/cone/work/ipa-investigation/`, incluindo `rea-artifact-summary.json`, `rea-artifact-evidence.json`, `rea-doctor.json`, `artifact-evidence.json`, `english-features.json` e `strings.txt`.
- Pesquisa posterior local: `work/offline-protocol-research.md`, `work/firmware-ipa/` e `work/ios-compat-divoom-ble-web/`. `work/` é temporário e não deve ser a única fonte de uma decisão durável.

Esses caminhos são locais e podem não existir em outro checkout; não confunda sua ausência com ausência de evidência. O IPA analisado tem FairPlay `cryptid=1`: os recursos/metadados foram inspecionados, mas não houve recuperação completa do código cifrado. O protocolo também se fundamenta em implementações públicas identificadas nos documentos acima. Não versione o IPA, extrações, logs privados ou dumps sem revisão; registre conclusões sanitizadas em `docs/`.

## Bluetooth e reconexão

O Mac usa Bluetooth Classic/RFCOMM; o iPhone usa GATT/BLE com envelope RCSP próprio. Não envie frames RFCOMM diretamente a uma characteristic BLE nem porte o envelope BLE para o canal Classic.

Reconexão automática está autorizada como comportamento do produto, limitada ao último aparelho validado e à preferência persistida:

- No Mac, grave endereço/canal como alvo somente após abertura RFCOMM confirmada. Uma seleção ou tentativa antiga não prova sucesso.
- No iPhone, valide serviço, características e notificações antes de concluir a conexão automática e lembrar o alvo.
- Desconectar desativa a reconexão; Esquecer remove o alvo. Respeite cancelamento, suspensão e espera progressiva após erros.
- Reconectar abre o transporte; nunca repete comandos, imagens, horário, alarmes ou uma transmissão anterior.
- Preserve os guards de geração/epoch, identidade do canal e token de escrita. Callbacks antigos não podem concluir operações da sessão nova; buffers assíncronos precisam permanecer vivos até conclusão/cancelamento.
- Não pareie, ligue o rádio, derrube áudio ou altere configurações do aparelho automaticamente.

Não use o conteúdo LCD/Zstandard do MiniToo no Ditoo-Plus: esse formato já travou o aparelho. O opcode isolado não identifica o formato; mantenha as variantes específicas de cada transporte.

## Painel, alarme e persistência

- O painel do Mac pode continuar entre seções, com indicação e botão Parar acessíveis. Fechar a janela, suspender ou perder/trocar a sessão Bluetooth interrompe os envios. Reconectar exige nova ação para transmitir.
- Enquanto o painel transmite, bloqueie comandos concorrentes. Preserve o envio de página única e o intervalo de 2–30 segundos.
- Hora e clima renderizados dependem do app em execução; não prometa autonomia no firmware nem execução irrestrita em segundo plano no iPhone.
- Cache meteorológico deve corresponder à cidade selecionada e preservar data da consulta/observação. Dados com mais de uma hora não entram no render como clima atual.
- Horário, dias e volume do alarme são estado local persistido. Edição vira rascunho até encaminhamento explícito; isso não comprova leitura, programação ou disparo no firmware.
- Ao restaurar propriedades `@Observable` com `didSet`, evite gravar preferências parciais durante a inicialização. Use defaults isolados e verifique restauração nos testes.

## Validação e comandos

Na raiz do repositório, antes de concluir alterações:

```sh
./Scripts/test.sh
./Scripts/build.sh
```

O primeiro executa os testes macOS. O segundo gera Release e verifica assinatura ad-hoc. Pré-requisitos: Xcode 27 compatível com o SDK/aparelho e XcodeGen (`brew install xcodegen`). Se necessário, selecione o Xcode por `DEVELOPER_DIR` no comando; evite mudar a seleção global sem necessidade.

App gerado: `build/Build/Products/Release/Divoom Studio.app`. Confira `lipo -archs` antes de afirmar que o binário é universal.

Quando alterar o target iOS ou código compartilhado que o afete, execute também:

```sh
./Scripts/test-ios.sh
./Scripts/build-ios.sh
```

`DIVOOM_IOS_DESTINATION` permite escolher o simulador. Instalação física usa `Scripts/install-ios.sh`, com `DIVOOM_DEVELOPMENT_TEAM` e `DIVOOM_DEVICE_ID` fornecidos localmente, nunca versionados. Conta Apple, perfil válido, confiança, Developer Mode e iPhone desbloqueado são pré-requisitos.

Se o projeto em diretório sincronizado/FileProvider travar em coordenação de arquivos, hidrate os arquivos e use um snapshot local em `/private/tmp`, regenerando com XcodeGen. Edite primeiro o repositório e sincronize as mudanças ao snapshot; não entregue um build de fontes desatualizados. Não remova projetos duplicados ou arquivos do usuário sem investigar sua origem.

Testes automatizados devem usar UserDefaults isolados e não conectar ao hardware. Preserve o bloqueio de reconexão automática nos hosts XCTest. Testes físicos opt-in exigem pedido explícito; não conecte nem altere o Ditoo apenas para validar código sem essa autorização. Simulador, abertura do canal, escrita, ACK e confirmação visual são evidências distintas. Registre limitações e resultados separadamente, sem afirmar resultado visual pelo ACK.

Para mudanças visuais, confira a interface em execução. Cópias de QA devem ter identidade/preferências isoladas e não enviar comandos. Nunca versione endereços Bluetooth pessoais, credenciais, IDs de assinatura/aparelho, logs privados ou artefatos de build.

## Instalação e distribuição

Versão/build macOS ficam em `Info.plist`; iOS em `Mobile-Info.plist`. Atualização local não equivale a publicação de release.

Antes de substituir `/Applications/Divoom Studio.app`, verifique se está aberto e preserve trabalho não salvo. Mantenha uma cópia da versão anterior, instale o bundle Release validado e confira a assinatura no destino. Não trate uma cópia de QA como a instalação definitiva.

Para publicar uma versão macOS, rode os gates acima, crie o ZIP com `ditto -c -k --sequesterRsrc --keepParent` sobre o bundle Release e publique `Divoom-Studio-VERSAO-universal.zip` na release `vVERSAO`. Atualize versão, URL e SHA-256 de `Casks/divoom-studio.rb` em `ronanrodrigo/homebrew-tap`; valide com `brew style` e instalação por Cask. Publique apenas dentro do escopo solicitado.

A distribuição atual usa assinatura ad-hoc. Não anuncie notarização sem verificá-la. App Store/TestFlight e assinatura de desenvolvimento iOS têm fluxos próprios.
