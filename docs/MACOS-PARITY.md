# macOS — paridade com o companion iPhone

Pedido de 23/11/2026: retomar o foco no macOS e atualizar o app existente para equivalência funcional com o companion iOS. A versão iPhone é preservada, sem novas funcionalidades nesta etapa.

## Comparação e decisão

O Mac já possui painel data/hora/alarme/clima, editor 16×16, quadros/prévia, importação PNG/JPEG/GIF/JSON, exportação PNG/GIF/JSON, biblioteca local, relógios, brilho, modos, alarme e diagnóstico. Seus controles adicionais de iluminação e variações visuais são preservados.

A atualização cobre as lacunas: reconexão automática ao último aparelho validado, canal salvo, desativação/esquecimento, snapshot meteorológico offline, dias/volume de alarme persistentes, envio de página única, intervalo de 2–30 segundos e proteção contra comandos concorrentes durante a rotação do painel.

A edição do alarme é um rascunho local até o usuário enviar. O app nunca declara leitura do agendamento do firmware. O painel continua entre seções, com indicador e botão Parar sempre disponíveis; para no sono do Mac e na perda da conexão, sem retomada automática de envios ao reconectar.

## Transporte e autorização

A automação se limita à abertura de RFCOMM do último endereço/canal cujo openComplete teve sucesso. A seleção antiga é preservada como seleção, sem ser promovida a conexão validada. Desconectar desativa a reconexão; Esquecer remove o alvo. Tentativas usam espera progressiva, são canceladas durante sono e retomadas ao despertar/abrir. Não há pareamento, ativação do rádio, desconexão de áudio ou reenvio de comandos automático.

Não copiar o envelope BLE/RCSP do iPhone ao RFCOMM do Mac. Imagens/animações continuam no codec Classic existente; esta atualização não introduz o formato MiniToo que travou o aparelho anteriormente.

## Verificação

Executar Scripts/test.sh e Scripts/build.sh em snapshot local para evitar travas do FileProvider ao abrir o projeto Xcode. Conferir assinatura ad-hoc e interface do app neste Mac. Testes de estado/persistência não conectam ao hardware. Nenhum alarme ou imagem será enviado para validar paridade.

A distribuição local será atualizada; publicação de release/Homebrew não integra esta etapa.

## Resultado

44 testes macOS passaram. Release universal Intel/Apple Silicon e assinatura ad-hoc foram verificados. Versão 0.3.0, build 3, instalada em /Applications/Divoom Studio.app após autorização para fechar a versão anterior; cópia da versão anterior preservada localmente. Interface final conferida: ações do painel completas, reconexão automática visível, alarme restaurado e animação desabilitada com um quadro. Não houve conexão ou envio ao Ditoo durante a verificação de interface. Nenhum arquivo iOS foi alterado.
