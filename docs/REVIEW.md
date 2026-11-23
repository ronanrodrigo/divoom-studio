# Revisão independente — codec, UI e editor

2026-11-23. Escopo somente leitura dos fontes Protocol, App e Editor. Transporte excluído desta revisão. Referências Apple lidas: swiftui-specialist/dataflow, foreach, structure e soft-deprecation. Nenhum comando foi enviado ao dispositivo.

## Achados

1. **P2 — Importação não aplica orientação EXIF.** `Sources/Editor/PixelProject.swift:37` cria o raster bruto e `:42` o desenha sem ler/aplicar `kCGImagePropertyOrientation`. Fotografias JPEG com orientação 6/8/3 serão importadas giradas. Reproduzido com JPEG 16×16 criado em ImageIO com Orientation=6: pixel vermelho permaneceu no canto superior esquerdo em vez de superior direito. Fixture/script em `work/ipa-investigation/OrientationReview.swift`. Aplicar transformação na thumbnail de ImageIO antes do raster 16×16.

2. **P2 — GIF importado perde temporização.** `Sources/Editor/PixelProject.swift:35` percorre imagens, mas não lê `kCGImagePropertyGIFDelayTime`/UnclampedDelayTime; `Sources/App/AppModel.swift:74` troca apenas frames/nome. Um GIF de 50 ms por quadro é reproduzido/enviado com a duração anterior do projeto (inicialmente 200 ms), e durações diferentes por quadro são achatadas silenciosamente. Preservar delays por frame, ou ao menos escolher um FPS explícito e avisar sobre uniformização/truncamento.

3. **P2 — Aplicar relógio não transmite o comando separado de formato de hora da referência.** `Sources/App/AppModel.swift:61` envia somente `DivoomProtocol.clock` (0x45). A referência fixada hass-divoom `devices/divoom.py:732-734` envia primeiro `set time type` (0x2D) e depois `set view`. O codec tem `timeFormat` em `Sources/Protocol/DivoomProtocol.swift:58`, mas a UI não o chama. Resultado em hardware ainda não observado: o checkbox 12/24h pode deixar o formato anterior do aparelho, especialmente no retorno de um canal. Enviar os dois payloads como a referência e validar no Ditoo.

4. **P2 — Limite de arquivo JSON é verificado depois da alocação integral.** `Sources/App/AppModel.swift:90` faz `Data(contentsOf:)` antes de conferir 2 MB. Um arquivo JSON grande escolhido pelo usuário/biblioteca pode bloquear a main thread e consumir memória arbitrária antes de ser recusado. Consultar tamanho do arquivo e impor leitura limitada antes de decodificar. Esse achado trata disponibilidade local, não execução de código.

## Verificações sem achados

- `PixelProject.validated()` recusa frames vazios, mais de60, RGB fora de768, IDs duplicados e duração inválida antes de atribuir ao modelo. Não foi encontrado caminho de arquivo JSON vazio até os índices `[0]`/módulo por zero.
- PNG roundtrip de padrão assimétrico 16×16 preservou exatamente RGB e orientação. Script `work/ipa-investigation/MediaReview.swift`.
- Importação usa alpha premultiplicado sobre buffer zerado e remove alpha: equivale a achatar em preto, coerente com tela LED sem transparência; não detectado bug nessa escolha.
- ForEach de frames usa UUID persistido e validado; biblioteca usa URL; logs UUID. Sem loops de atualização observados estaticamente. A paleta/int packing respeita 256 cores e oito bits, e buffers inválidos são rejeitados pelo codec.
- Valores de hora/minuto/volume/dias são limitados antes do payload do alarme. A semântica real de disparo/slot0 permanece sem teste no aparelho; não afirmar que o alarme foi agendado.

## Limites de paridade

A versão local ainda não replica comunidade online/login/nuvem, áudio/radio/mixer, sleep, texto LED, jogos, notificações e todos os estilos do aplicativo iOS. Recursos do IPA provam conceitos de produto, não suporte do Ditoo nem bytes de protocolo. Relógio, alarmes, imagem e animação continuam dependentes de confirmação física. Não é correto declarar paridade completa com iOS.
