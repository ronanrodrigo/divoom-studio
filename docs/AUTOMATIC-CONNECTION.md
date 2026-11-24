# Reconexão automática no iPhone

Solicitada em 2026-11-23 após o usuário confirmar a conexão do build 5.

O app guarda localmente o identificador CoreBluetooth, nome e protocolo do último aparelho cuja conexão e perfil foram validados. Ao abrir ou retornar ao primeiro plano, reconecta somente a esse alvo. O CoreBluetooth pode manter uma conexão pendente até o aparelho voltar ao alcance; falhas explícitas usam espera progressiva para evitar tentativas em sequência. Nenhum comando de tela, hora, imagem ou alarme é disparado pela reconexão.

A opção de reconectar fica em Aparelho. Desconectar manualmente desativa a reconexão; o usuário pode reativá-la. Esquecer apaga o alvo e encerra a conexão. Sem alvo salvo, é necessária uma primeira conexão pelo usuário; não se escolhe automaticamente outro aparelho próximo. O identificador fica em UserDefaults, nunca no repositório.

A restauração de estado deve recuperar apenas o alvo salvo e respeitar a preferência. O painel continua pausado fora do primeiro plano. O iOS controla eventos de segundo plano; encerramento forçado não equivale a suspensão. Abrir o app novamente retoma as tentativas. Fonte: [Apple TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules).

Alternativas: exigir conexão manual em cada abertura não atende ao pedido; procurar e conectar qualquer Divoom próximo poderia escolher outro aparelho. Por isso a automação se limita ao último alvo validado.
