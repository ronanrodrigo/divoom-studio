# Resultado das revisões

Dois subagents revisaram áreas independentes de sua própria implementação.

- P1 writeSync no MainActor: substituído por writeAsync, continuation, retenção de buffer e watchdog5s. Timeout total60s, geração de conexão e teardown cancelável.
- P2 interrupção do canal mantinha busy: guard fecha sessão, defer limpa busy somente na geração correspondente.
- P2 correlação ACK por opcode: limitação do protocolo explicitada na UI. Não se afirma confirmação por pacote; payloads só são classificados como resposta quando0x04 e marcador0x55 validados após framing/checksum.
- P3 logs truncados: agora completos, até500entradas/~2MB.
- P2 EXIF: thumbnail ImageIO com transform; teste com APP1Exif real passou.
- P2 GIF timing: duração inicial preservada; tempos variáveis sinalizados e normalizados explicitamente; dois testes passaram.
- P2 relógio12/24h: envio0x2D antes0x45; prévia com ciclo de hora explícito.
- P2 tamanho JSON: fileSize verificado antes da leitura, leitura mapeada e limite reafirmado antes do decode.

Riscos restantes documentados: variantes de firmware, respostas atrasadas sem transactionID, testes físicos de alarmes/animação/modos pendentes e backend iOS não implementado. Não são tratados como funções verificadas.
