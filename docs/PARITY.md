# Paridade com Divoom iOS

O app iOS atende uma família ampla de produtos. Esta implementação se concentra no Ditoo-Plus LED16×16, com UI nativa macOS SwiftUI. Não é uma cópia binária ou uma alegação de paridade integral.

| Recurso | Implementação macOS | Validação / limite |
|---|---|---|
| Bluetooth | Dispositivos pareados, endereço manual, canal RFCOMM, conectar/desconectar, logs | Canal1 abriu; consulta0x46 e retorno0x45 responderam no aparelho |
| Relógio | 6 estilos, cor,12/24h, sincronizar Mac | Codec fundamentado; estilos específicos ainda precisam confirmação visual |
| Modos | Relógio, iluminação, canal nuvem do aparelho, VJ, música, personalizado | Seleciona canal do firmware; não baixa conteúdos da comunidade |
| Iluminação | RGB, efeito, brilho, apagar tela e voltar relógio | Comandos de referência; dependem firmware |
| Alarmes | Primeiro alarme(slot0), ativar/desativar, horário, repetição semanal, volume | Protocolo de referência; disparo e persistência ainda não verificados no aparelho |
| Pixel art | Canvas16×16, pincel, borracha, paleta, teclado | UI local |
| Animação | Até60 frames, adicionar/duplicar/excluir, preview e envio legado0x49 | Limites de transferência impostos; hardware ainda em validação |
| Importar | PNG/JPEG/GIF, EXIF, crop central, limite de decode, tempoGIF | GIFs com tempos variáveis são normalizados para primeiro tempo e aviso |
| Exportar | PNG/GIF e projeto JSON | Testes roundtrip, metadados, cores |
| Biblioteca | Projetos locais em ApplicationSupport/DivoomStudio/Library | Sem conta ou sincronização de nuvem |
| Diagnóstico | RX/TX completos limitados500 entradas/~2MB, exportar texto | Respostas por opcode não garantem aplicação física ou confirmação por pacote |
| Comunidade/login/perfil/postagens/curtidas | Não implementado | API autenticada oficial não foi observada nem documentada nesta investigação |
| Galeria online/pesquisa de artes | Não implementado | Importar arquivos locais disponível; nenhum endpoint adivinhado |
| Clima/notificações/integrações do celular | Não implementado | Dependem dados externos e recursos do app móvel |
| Jogos, sleep, rádio, placar, cronômetro | Não implementado nesta versão | Recursos aparecem no IPA, suporte exato por modelo varia |
| Atualizar firmware / gravar slots persistentes | Não implementado | Não executar comandos de flash sem fluxo específico documentado |

## O que o IPA revelou

O pacote oficial3.8.54 contém recursos e traduções que confirmam os módulos do produto. O Mach-O está cifrado(FairPlay cryptid1), incluindo código e metadados Objective-C relevantes. Portanto o protocolo implementado foi obtido de implementações públicas específicas para Ditoo e verificado com vetores; não foi decompilado do IPA cifrado.

Ver relatórios em `../../divoom/research-ipa.md` e `../../divoom/research-protocol.md`, além de `HARDWARE-VALIDATION.md`.
