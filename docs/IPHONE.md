# Divoom Studio no iPhone

Target: DivoomStudioMobile, iOS17 ou superior. Painel e editor nativos SwiftUI no mesmo projetoXcode do Mac.

## Recursos

- Painel com data, hora, alarme configurado e clima; seleção de cidade e cache local.
- Transmissão das quatro telas pixeladas por Bluetooth quando o app está em primeiro plano.
- Editor16×16, paleta/borracha, quadros, reprodução local, imagens e animaçõesBLE.
- ImportaçãoPNG/JPEG/GIF/JSON e exportaçãoPNG/GIF/JSON; biblioteca no iPhone.
- Relógio, brilho, modos e primeiro alarme do aparelho; envio explícito.
- BuscaBLE, seleção do aparelho, perfil de compatibilidade e diagnóstico exportável.

O iPhone usa o canal Light/BLE. O canal de áudio nos Ajustes é separado. O perfil padrão do app é diagnóstico: selecione o controle DitooPlus conscientemente antes de enviar comandos. Um perfil GATT não reconhecido permanece bloqueado, sem tentativa em outra característica gravável.

## Executar no simulador

```sh
./Scripts/build-ios.sh
./Scripts/test-ios.sh
```

O simulador valida interface, mídia e codec. Não comprova o Bluetooth com o Ditoo.

## Instalar no iPhone

1. Use Xcode compatível com a versão iOS do telefone e configure sua conta Apple em Xcode → Settings → Accounts.
2. Conecte o iPhone, desbloqueie-o e confirme confiança/DeveloperMode no próprio aparelho, se solicitado.
3. Abra DivoomStudio.xcodeproj, selecione DivoomStudioMobile, escolha o iPhone e sua equipe em Signing & Capabilities, com assinatura automática; execute Run.

AlternativaCLI sem versionar IDs pessoais:

```sh
DIVOOM_DEVELOPMENT_TEAM='<sua equipe>' DIVOOM_DEVICE_ID='<seu iPhone>' ./Scripts/install-ios.sh
```

A conta precisa permitir criar um AppID/perfil para dev.ronanrodrigo.DivoomStudioMobile. Ter somente o certificado no Keychain não substitui esse perfil. Não reutilize o perfil de outro app nem mude o bundleID para se passar por ele.

## Conectar ao Ditoo

Feche a conexão de controle no Mac ou no app oficial antes de conectar a versão iPhone: o dispositivo aceita uma conexão de controle por vez.

Na aba Aparelho: Buscar, escolha o DitooLight, selecione o perfil DitooPlus e Conectar. Confira primeiro um controle curto e uma imagem. Confirme visualmente o resultado: ACK confirma o pacote, não sua aparência na tela. Logs podem conter identificadores pessoais; compartilhe-os apenas quando necessário e não os versione.

A transferência de animaçãoBLEusa0x8B com quadros paletizados. Ela não usa o conteúdo LCD/Zstandard do MiniToo. Sem solicitação de dados do Ditoo, não são enviados blocos da animação.

## Segundo plano

A saída do primeiro plano pausa a transmissão e a prévia. O app não retoma transmissões sozinho. A permissão bluetooth-central permite eventosBLEem segundo plano, mas não garante um relógio/timer de envio contínuo quando o iOS suspende o processo. A animação transferida pode ser reproduzida pelo firmware, porém quadros pré-renderizados não atualizam hora ou clima sozinhos.

## Assinatura e distribuição

O app iPhone exige assinatura de desenvolvimento para o aparelho ou distribuição via TestFlight/AppStore em um fluxo próprio. A assinatura ad-hoc usada no Mac não instala um app no iPhone. Esta etapa não afirma publicação na AppStore nem notarização.
