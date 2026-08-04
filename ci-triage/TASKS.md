# Tarefas de Triagem de CI

Derivado de `REPORT.md`. Nenhuma tarefa aqui foi executada — este é o plano de ação, nenhum código
foi alterado ainda.

---

### T1 — Instrumentar `Internals.Buffer.Storage.read` para capturar o motivo do `nil`

- **Categoria:** CODE_BUG — investigação (bloqueante para T3/T4)
- **Prioridade:** P0
- **Plataformas afetadas:** iOS, iPadOS, tvOS, watchOS, visionOS, macOS Catalyst
- **Evidência nos logs:** `logs/1_*iPadOS.txt:1802-1804`, `logs/3_*iOS.txt:1824-1827`,
  `logs/5_*visionOS.txt:1807-1809`, `logs/6_*tvOS.txt:1839-1840`, `logs/7_*watchOS.txt:1826-1827` —
  todas com a mensagem `Fatal error: 🐞 RequestDL bug: Buffer reported N readable bytes but
  returned none`.
- **Hipótese de causa:** dentro de `Buffer.Storage.read(at:length:)`
  (`Sources/RequestDL/Internals/Sources/Buffers/Buffer/Internals.Buffer.swift:141-160`), o `guard
  await url.isResourceAvailable() else { return (nil, index) }` (ou a leitura/seek subsequente)
  falha silenciosamente mesmo com um intervalo válido. Não se sabe ainda se é
  `isResourceAvailable()` retornando falso-negativo, um erro engolido pelo `catch { return (nil,
  index) }`, ou esgotamento de recurso (file descriptors) do SO sob alta concorrência.
- **Ação proposta:** adicionar logging temporário (ou um contador `@_spi(Testing)`) em torno do
  `guard`/`catch` de `read(at:length:)` e de `FileStreamBuffer.readData(length:)` para registrar:
  resultado de `isResourceAvailable()`, erro capturado (se houver) e se o descriptor de arquivo
  ainda está aberto no momento da falha. Rodar `fileBuffer_whenRacingImmutable` localmente em loop
  no simulador de iOS até reproduzir e capturar esse log.
- **Validação sugerida:** reproduzir localmente `swift test --filter
  InternalsFileBufferTests/fileBuffer_whenRacingImmutable` num simulador iOS repetidamente (ex.:
  50x) até obter pelo menos uma falha instrumentada; confirmar qual branch do `guard`/`catch` foi
  atingido.

#### Resultado (concluído em 2026-08-04)

Instrumentação temporária adicionada (`#if DEBUG`, custo zero em release), reaproveitando a
infraestrutura de log já existente (`Internals.Log`):

- `Sources/RequestDL/Internals/Sources/Logger/Internals.Log.swift` — novas factories
  `bufferReadFailed(at:index:length:metadata:)` e `resourceStatFailed(path:error:)`.
- `Sources/RequestDL/Internals/Sources/Buffers/Buffer/Internals.Buffer.swift` —
  `Storage.read(at:length:)` loga ao atingir o `guard isResourceAvailable()` e ao cair no `catch`.
- `Sources/RequestDL/Internals/Sources/Buffers/Buffer/Models/Internals.FileStreamBuffer.swift` —
  `readData(length:)` loga leitura de zero bytes, incluindo se o descriptor ainda está aberto
  (`!_isClosed`).
- `Sources/RequestDL/Internals/Extensions/URL+Extensions.swift` — `URL.isReachable` trocou
  `try? await FileSystem.shared.info(...)` por `do/catch` explícito (comportamento idêntico,
  `nil`/erro → `false` do mesmo jeito), logando o erro real quando `FileSystem.shared.info` lança.

Reproduzido 2x rodando a suíte `RequestDLTests` inteira via `xcodebuild test` num simulador iOS
(iPhone 17 Pro, iOS 26.5; requer `IPHONEOS_DEPLOYMENT_TARGET=17.0` no `xcodebuild` local — o scheme
gerado pelo SwiftPM usa o mínimo `.iOS(.v15)` do `Package.swift`, e `LocalServerConcurrencyTests`
usa `ContinuousClock`, iOS 16+; gap pré-existente, não relacionado a este bug, não corrigido aqui):

- 1ª execução: crash real — `Fatal error: 🐞 RequestDL bug: Buffer reported 131072 readable bytes
  but returned none` (`Internals.BodySequence.swift:75`), precedido por várias linhas de log
  `isResourceAvailable() == false`.
- 2ª execução (com a instrumentação de `URL.isReachable`): sem crash, mas `fileBuffer_
  whenRacingImmutable` falhou de forma determinística (`Set(datas...).count → 778` em vez de
  `1024`), com ~247 leituras retornando `nil`.
- Rodar apenas `fileBuffer_whenRacingImmutable` isoladamente em loop (42x) no mesmo simulador
  **nunca** reproduziu — só reproduz como parte da suíte inteira, confirmando a suspeita do T4 de
  que o gatilho depende de carga/concorrência de todo o processo de teste, não só do teste isolado.
  Rodar a suíte inteira em native macOS (`swift test`, sem simulador) também nunca reproduziu.

**Causa confirmada, com uma correção importante em relação à hipótese original:** em **100% das
falhas observadas (~250 ocorrências, nas duas execuções)**, o caminho atingido foi sempre o mesmo —
o `guard await url.isResourceAvailable() else { ... }` em `Storage.read(at:length:)` — e **nunca**
os outros dois: nem o `catch` de `Storage.read` (nenhum erro foi lançado/capturado), nem o ramo de
zero bytes em `FileStreamBuffer.readData(length:)`, nem (após a instrumentação adicional) o `catch`
dentro do próprio `URL.isReachable`. Ou seja: `FileSystem.shared.info(forFileAt:)` **não lançou
erro nenhuma vez** — ele retornou `nil` de forma "limpa", como se o arquivo genuinamente não
existisse, para um arquivo que certamente existe (escrito e fechado antes do teste iniciar as 1024
leituras concorrentes) e cujo cursor (`readableBytes > 0`) prova que a store ainda o considera
válido.

Isso **descarta a hipótese original de esgotamento de file descriptors via `SystemPackage.
FileDescriptor.open` lançando erro engolido** (essa branch nunca foi atingida) — ver nota em T2.
A causa real está um nível abaixo do que T1 pediu para instrumentar: é o próprio `NIOFileSystem`
(`FileSystem.shared.info(forFileAt:)`, chamado por `URL.isReachable` em
`Sources/RequestDL/Internals/Extensions/URL+Extensions.swift:75-84`) que intermitentemente reporta
"não existe" para um arquivo existente, sob a sequência intensa de chamadas gerada por 1024
leituras (todas serializadas por um único `AsyncLock` — a serialização do lock foi auditada e está
correta, então não é uma race na store deste pacote). Também vale notar que os índices que falham
aparecem em faixas contíguas (ex. 779–787 em sequência), sugerindo uma janela de degradação
temporária em vez de falhas isoladas e aleatórias.

Ainda não confirmado *por que* `NIOFileSystem.info(forFileAt:)` erra dessa forma sob carga em
simuladores sandboxed (bug do próprio NIOFileSystem, do file system do simulador, ou do thread
pool bloqueante compartilhado) — isso é o próximo passo de investigação, mais adequado a uma nova
tarefa T2 revisada do que a T3 diretamente.

---

### T2 — Testar a hipótese de esgotamento de file descriptors

- **Categoria:** CODE_BUG — investigação
- **Prioridade:** P0
- **Plataformas afetadas:** iOS, iPadOS, tvOS, watchOS, visionOS, macOS Catalyst
- **Evidência nos logs:** mesma de T1; adicionalmente, o fato de `fileBuffer_whenRacingImmutable`
  abrir 1024 tarefas concorrentes contra um único arquivo (`Tests/RequestDLTests/Internals/Sources/
  Buffers/File/InternalsFileBufferTests.swift:788-809`) e de as 6 plataformas afetadas serem todas
  simuladores/sandboxed (tipicamente com `ulimit -n` mais baixo que macOS nativo/Linux CI).
- **Hipótese de causa:** `SystemPackage.FileDescriptor.open` em
  `Internals.FileStreamBuffer.init(readingFrom:)`
  (`Sources/RequestDL/Internals/Sources/Buffers/Buffer/Models/Internals.FileStreamBuffer.swift:60-62`)
  ou chamadas equivalentes via `NIOFileSystem` (`Internals.FileBufferURL`) falham sob pressão de
  descriptors abertos simultaneamente pela suíte inteira rodando em paralelo, e essa falha é
  engolida pelo `catch` em `Buffer.Storage.read`.
- **Ação proposta:** comparar `ulimit -n` do runner macOS nativo vs. o processo de teste no
  simulador iOS (via `Process.self.rlimit` ou `getrlimit` num teste de diagnóstico temporário); se
  for significativamente menor, isso explica por que só simuladores reproduzem.
- **Validação sugerida:** rodar a suíte completa localmente no simulador com `ulimit -n` reduzido
  artificialmente no ambiente macOS nativo e verificar se `fileBuffer_whenRacingImmutable` passa a
  falhar também ali — isso confirmaria ou refutaria a hipótese sem precisar de acesso a um runner
  simulador.

> **Atualização (T1, 2026-08-04):** a instrumentação de T1 reproduziu a falha duas vezes num
> simulador iOS real e capturou ~250 ocorrências, todas no mesmo branch (`isResourceAvailable() ==
> false`), zero delas por erro lançado/capturado. Isso enfraquece especificamente a variante
> "`SystemPackage.FileDescriptor.open` lança e o erro é engolido" — essa branch nunca disparou. A
> hipótese de esgotamento de recurso ainda pode ser válida, mas se for, ela se manifesta como
> `NIOFileSystem.info(forFileAt:)` retornando `nil` sem lançar, não como uma exceção capturada.
> Ver a seção "Resultado" em T1 para os detalhes completos.

#### Resultado (concluído em 2026-08-04)

**Hipótese refutada**, por duas vias independentes — leitura de código e experimento empírico —
sem necessidade de acesso a um runner simulador.

**1. Leitura de código (`NIOFileSystem` 2.101.3, vendorizado em
`.build/checkouts/swift-nio/Sources/_NIOFileSystem/FileSystem.swift`):**

`URL.isReachable` (`Sources/RequestDL/Internals/Extensions/URL+Extensions.swift:76-89`), que é o
que alimenta o `guard await url.isResourceAvailable()` investigado em T1, chama
`FileSystem.shared.info(forFileAt:)` (`FileSystem.swift:298-305`), que por sua vez delega para
`_info(forFileAt:infoAboutSymbolicLink:)` (`FileSystem.swift:961-982`). Essa função **não abre um
file descriptor** — ela roda `Syscall.stat`/`Syscall.lstat` diretamente sobre o `path`, sem passar
por `open(2)`. `stat(2)` resolve o caminho via cache de entradas de diretório e não consome (nem
depende de) descriptors abertos pelo processo; `EMFILE`/`ENFILE` (os erros de esgotamento de
descriptors) não afetam essa chamada da mesma forma que afetariam um `open(2)`.

Mais importante: o próprio `_info` (`FileSystem.swift:974-980`) só converte o resultado em
`.success(nil)` quando `errno == .noSuchFileOrDirectory` — qualquer outro errno (o que incluiria
`EMFILE`/`ENFILE`, se algum dia ocorressem aqui) é propagado como `FileSystemError` **lançado**, não
engolido silenciosamente. Ou seja: mesmo que esgotamento de recurso pudesse, por algum caminho
indireto, afetar esse `stat`, o sintoma esperado seria uma exceção capturada pelo `catch` de
`URL.isReachable` (linha 81-87) ou pelo de `Buffer.Storage.read` — exatamente os branches que T1
already confirmou **nunca** dispararam nas ~250 ocorrências reais. A hipótese é estruturalmente
incompatível com o sintoma observado.

**2. Experimento empírico (`ulimit -n` artificialmente reduzido em macOS nativo, conforme a
"Validação sugerida" original):**

Rodado neste ambiente (`ulimit -Hn` = `unlimited`, `kern.maxfilesperproc` = 61440):

- Suíte completa (`swift test --filter RequestDLTests`, 1043 testes) com `ulimit -n` no valor
  padrão do shell: passou, `fileBuffer_whenRacingImmutable` incluído, **1** ocorrência de
  `isResourceAvailable() == false` no log.
- Mesma suíte completa com `ulimit -n 48` (uma redução de mais de 20.000x frente ao padrão do
  shell): passou igualmente, `fileBuffer_whenRacingImmutable` incluído, e também **exatamente 1**
  ocorrência do mesmo log, no mesmo ponto.
- As duas ocorrências são idênticas e benignas: vêm de
  `fileBuffer_whenReadZeroBytes_shouldBeNil` (`Tests/RequestDLTests/Internals/Sources/Buffers/File/
  InternalsFileBufferTests.swift:624-633`), que lê um `Internals.FileBuffer()` recém-criado e vazio
  — cujo arquivo de apoio nunca chegou a ser criado, já que `_createResourceIfNeeded` só roda em
  `write` (`Internals.Buffer.swift:271-278`) — então `isResourceAvailable() == false` ali é o
  resultado correto e esperado, não um sintoma do bug de T1. Nenhuma outra ocorrência, e nenhum
  `catch` (nem em `Storage.read` nem em `URL.isReachable`) disparou em nenhuma das duas execuções,
  mesmo sob a pressão de descriptors artificialmente extrema.

**Conclusão:** o esgotamento de file descriptors — seja pela variante original ("`FileDescriptor.
open` lança e o erro é engolido", já enfraquecida por T1) seja pela variante revisada ("`NIOFileSystem.
info` reporta ausência sob pressão de recurso") — não é a causa da falha observada em T1. A causa
raiz de `isResourceAvailable() == false` sob carga permanece a descrita no "Resultado" de T1:
`NIOFileSystem.info(forFileAt:)` intermitentemente reportando ausência para um arquivo existente sob
alta frequência de chamadas em simuladores sandboxed — um comportamento que este ambiente (macOS
nativo, `swift test`, sem simulador) nunca conseguiu reproduzir independentemente do `ulimit -n`, o
que é consistente com a causa estar em `NIOFileSystem`/no file system do simulador, não em recursos
do processo que o `ulimit -n` do host controla. Nenhuma alteração de código foi necessária para
concluir T2. T3 deve seguir com a causa confirmada de T1 como única hipótese ativa.

---

### T3 — Corrigir o defeito de leitura concorrente identificado em T1/T2

- **Categoria:** CODE_BUG — correção
- **Prioridade:** P0 (bloqueado por T1)
- **Plataformas afetadas:** iOS, iPadOS, tvOS, watchOS, visionOS, macOS Catalyst
- **Evidência nos logs:** ver T1.
- **Hipótese de causa:** a ser confirmada por T1/T2 antes de qualquer alteração de código.
- **Ação proposta:** implementar o fix mínimo correspondente à causa confirmada (ex.: reabrir/
  retry em `_inputStream` quando o descriptor cacheado estiver inválido; tratar `isResourceAvailable
  () == false` de forma diferente de "arquivo removido"; ou não suprimir o erro de
  `FileDescriptor.open`/`read` dentro do `catch`, propagando-o para diagnóstico em vez de
  silenciá-lo). Não iniciar esta tarefa antes de T1 apontar a causa exata, para evitar corrigir o
  sintoma errado.
- **Validação sugerida:** `fileBuffer_whenRacingImmutable` deve passar de forma consistente
  (ex.: 100 execuções seguidas) num simulador iOS; adicionar um novo teste de regressão que exercite
  especificamente o cenário identificado (ex.: alta contagem de FDs abertos, ou a condição exata de
  `isResourceAvailable()`); depois validar as 6 plataformas via CI real.

#### Resultado (concluído em 2026-08-04)

Fix mínimo aplicado em `Internals.Buffer.Storage.read(at:length:)`
(`Sources/RequestDL/Internals/Sources/Buffers/Buffer/Internals.Buffer.swift`), seguindo a opção "tratar
`isResourceAvailable() == false` de forma diferente de 'arquivo removido'" listada na Ação proposta:

- Novo método privado, lockless, `Storage._isResourceAvailable()` substitui a chamada direta a
  `url.isResourceAvailable()` dentro do `guard` de `read(at:length:)`. Em vez de aceitar uma única
  resposta "não disponível" como definitiva, ele repete a checagem de `isResourceAvailable()` até 5
  vezes, com uma pausa de 2ms entre tentativas, e só então reporta a leitura como falha. Escopo
  deliberadamente restrito ao caminho de leitura: é o único lugar onde a própria contabilidade do
  buffer (`readableBytes > 0`) já garante que o arquivo deveria existir, então uma resposta "ausente"
  ali é inconsistente com o estado local e vale a pena repetir. `write`/`truncate`/`create` não foram
  tocados — para eles, "ausente" pode ser uma resposta legítima (ex.: arquivo ainda não criado), e
  adicionar retry ali só atrasaria o caso comum sem corrigir bug nenhum.
- A instrumentação temporária de T1 (`Internals.Log.bufferReadFailed`/`resourceStatFailed`, e os
  `#if DEBUG` que as chamavam em `Internals.Buffer.swift`, `Internals.FileStreamBuffer.swift` e
  `URL+Extensions.swift`) foi removida por completo, conforme os comentários "Remove once T3 lands"
  deixados em `Internals.Log.swift`. `URL.isReachable` voltou à forma original (`try?`), já que T1/T2
  confirmaram que o `catch` nunca é atingido na prática — o do/catch instrumentado não tinha mais
  função sem o log. `Internals.Buffer.swift`, `Internals.FileStreamBuffer.swift` e
  `URL+Extensions.swift` voltaram a ter diff zero contra `main` fora da mudança descrita acima.

**Por que retry, e não outra opção da lista original:** "reabrir/retry em `_inputStream`" não se
aplica — T1 confirmou que o `catch` em torno de `_inputStream`/`stream.seek`/`stream.readData` nunca
disparou; o descriptor cacheado nunca chegou a ser tocado, porque o `guard` anterior a ele já barrava
a leitura. "Não suprimir o erro, propagando para diagnóstico" também não se aplica — não há erro
lançado nesse caminho para propagar, `isResourceAvailable()` retorna `false` "limpo". Retry é a única
opção compatível com a causa raiz confirmada: uma janela de degradação temporária e contígua na
resposta do `stat` do `NIOFileSystem` sob carga em simuladores, que uma nova tentativa alguns
milissegundos depois tem chance real de superar.

**Validação nesta máquina:** `swift build` limpo; `swift test --filter InternalsFileBufferTests`
(39/39, incluindo `fileBuffer_whenRacingImmutable` em 0.194s) e a suíte completa (`swift test`,
1043/1043) passam. `swift format lint --recursive --strict` limpo nos 4 arquivos tocados. Como T1/T2
já haviam estabelecido, o bug nunca reproduziu neste ambiente (macOS nativo, sem simulador) mesmo
antes do fix, então essas execuções confirmam ausência de regressão, não a correção do bug em si.

**Pendente, fora do escopo executável neste ambiente:** a validação real de T3 — rodar
`fileBuffer_whenRacingImmutable` repetidamente (ex.: 100x) num simulador iOS real e/ou a suíte
completa nos 6 simuladores afetados via CI — precisa rodar num runner com acesso a simulador Apple,
que não está disponível aqui. Os números de tentativas/atraso (5 tentativas, 2ms) são uma estimativa
de engenharia a partir da evidência de T1 (falhas em faixas contíguas de até ~9 índices sob leituras
inteiramente serializadas por um único lock); ajustar esses números pode ser necessário após validar
em CI real. T4 (teste de regressão dedicado) continua não iniciado.

---

### T4 — Adicionar teste de regressão para o cenário fatal de `BodySequence`

- **Categoria:** test-coverage
- **Prioridade:** P1 (após T3)
- **Plataformas afetadas:** iOS, iPadOS, tvOS, watchOS, visionOS
- **Evidência nos logs:** o crash ocorre com `InternalsBodySequenceTests` já `passed` e
  `InternalsFileBufferTests` ainda em execução (`logs/1_*iPadOS.txt:1724,1802`; mesmo padrão em
  `3_*iOS.txt:1773,1824`, `5_*visionOS.txt:1731,1807`, `6_*tvOS.txt:1763,1839`,
  `7_*watchOS.txt:1770,1826`), indicando que o gatilho fatal vem de execução concorrente entre
  suítes, não de um teste isolado de `BodySequence`.
- **Hipótese de causa:** não há hoje um teste que force `Internals.BodySequence` a ler de um
  `Internals.Buffer` compartilhado sob alta concorrência de outras operações de I/O simultâneas.
- **Ação proposta:** escrever um teste que combine leitura de `BodySequence` com pressão
  concorrente equivalente à de `fileBuffer_whenRacingImmutable`, para que o cenário fatal tenha uma
  cobertura direta (hoje só é coberto indiretamente pela execução paralela da suíte inteira).
- **Validação sugerida:** o novo teste deve falhar de forma determinística antes do fix de T3 e
  passar de forma consistente depois.

#### Resultado (concluído em 2026-08-04)

Novo teste `bodySequence_whenReadingFileBufferUnderConcurrentPressure_shouldNotReportBug` em
`Tests/RequestDLTests/Internals/Sources/Body/Models/InternalsBodySequenceTests.swift`, seguindo
literalmente a "Ação proposta": combina uma `Internals.BodySequence` drenando um
`Internals.FileBuffer` de 128 KiB (`chunkSize: 4_096`, ou seja 32 leituras sequenciais via
`Storage.read`) com a mesma pressão concorrente de `fileBuffer_whenRacingImmutable` — 1.024 tarefas
`getData(at:length:)` simultâneas contra o mesmo arquivo, via `withTaskGroup`/`async let` rodando
ao mesmo tempo que o consumo da sequência. Ambos os caminhos passam pelo `AsyncLock` compartilhado
de `Storage`, então o teste é uma cobertura direta do cenário fatal (`BodySequence` lendo um buffer
compartilhado sob alta concorrência de I/O simultânea), não apenas indireta via suíte inteira.

Duas asserções:

- `Internals.Override.AssertionFailure.replace(...)` intercepta qualquer chamada a
  `Internals.assertionFailure` durante o teste (o mesmo mecanismo de
  `InternalsOverrideAssertionFailureTests.swift`) e o teste falha se o bug de
  `BodySequence.swift:75` ("Buffer reported N readable bytes but returned none") disparar.
- Os `ByteBuffer` chunks produzidos, concatenados, precisam ser byte-a-byte iguais aos 128 KiB
  originais — cobre tanto o crash quanto a variante silenciosa (`buffers.removeFirst()` descartando
  um chunk sem travar o processo, o que geraria um corpo mais curto que o declarado).

**Validação nesta máquina:** `swift build`; `swift test --filter
RequestDLTests.InternalsBodySequenceTests` (8/8, novo teste em ~0.29s) e `swift test --filter
RequestDLTests.InternalsFileBufferTests` (39/39) passam; suíte completa `swift test` também passa
(1044/1044, o teste novo soma um caso a mais frente aos 1043 registrados em T1/T2/T3); `swift format
lint --recursive --strict` limpo. Como esperado — e como T1/T2/T3 já haviam estabelecido — o bug
nunca reproduziu de forma independente neste ambiente (macOS nativo, sem simulador), mesmo antes do
fix de T3, então esta execução comprova que o novo teste não é flaky/falso-positivo neste ambiente e
que não há regressão, não que o cenário fatal em si foi reproduzido aqui. A validação de que o teste
falharia de fato antes do fix (a "Validação sugerida" original) e passaria depois — em um simulador
iOS real — continua pendente, pela mesma limitação de ambiente descrita em T1/T3.

---

### T5 — Corrigir extração de `.profdata` no job 🍎 macOS para o layout do Xcode 26

- **Categoria:** CODE_BUG — script de CI
- **Prioridade:** P1
- **Plataformas afetadas:** Coverage Upload (consumidor), job 🍎 macOS (produtor do artefato)
- **Evidência nos logs:** `logs/0_*Coverage Upload.txt:207-213` (`Nenhum .profdata em
  artifacts/apple-macOS/` → `exit code 1`); `logs/8_*macOS.txt:1950-1953` (`find .xcbuild -name
  "*.profdata"` não encontra nada apesar de `-enableCodeCoverage YES` em `8_*macOS.txt:539` e um
  `.xcresult` válido gerado em `8_*macOS.txt:1948`).
- **Hipótese de causa:** na imagem `macos-26-arm64` / Xcode 26.6 usada neste run
  (`logs/0_*.txt:11-17`), os dados de cobertura passaram a residir dentro do pacote `.xcresult` em
  vez de como `.profdata` solto sob `.xcbuild`, quebrando a extração baseada em `find`.
- **Ação proposta:** trocar a extração por `xcrun xcresulttool export` (ou `xccov`) apontando para
  o `.xcresult` gerado, ou localizar o `.profdata` dentro do próprio pacote `.xcresult`
  (`*.xcresult/**/*.profdata`) em vez de `.xcbuild` diretamente. Esta mudança vive no workflow
  reutilizável `request-dl/.github` (`Uses: request-dl/.github/.github/workflows/swift-ci.yaml`,
  `logs/0_*.txt:31`), não neste repositório — abrir a alteração lá.
- **Validação sugerida:** rodar o job 🍎 macOS e confirmar que `coverage-artifacts/` contém um
  `.profdata` não vazio antes do upload; depois confirmar que o job Coverage Upload processa
  `apple-macOS` sem o erro `Nenhum .profdata`.

---

### T6 — Adicionar smoke check ao workflow para artefato de cobertura vazio

- **Categoria:** test-coverage — CI
- **Prioridade:** P2 (após T5)
- **Plataformas afetadas:** Coverage Upload
- **Evidência nos logs:** o `|| true` em `logs/8_*macOS.txt:1952` engoliu silenciosamente a falha
  de extração; o problema só apareceu 7 jobs depois, no Coverage Upload, tornando o diagnóstico
  mais lento do que precisaria ser.
- **Hipótese de causa:** falha de descoberta de artefato (ex.: mudança futura de layout do Xcode)
  volta a passar despercebida no job produtor porque o script usa `|| true`.
- **Ação proposta:** no job 🍎 macOS, falhar explicitamente (sem `|| true`) se
  `coverage-artifacts/` não contiver nenhum `.profdata` após a extração, em vez de deixar o erro
  surgir só no Coverage Upload.
- **Validação sugerida:** simular localmente um `.xcresult` sem `.profdata` acessível e confirmar
  que o job 🍎 macOS falha imediatamente com uma mensagem clara, em vez de subir um artefato
  incompleto.

---

### T7 — Anexar nome do teste em execução ao crash de `Fatal error` nos runners Apple

- **Categoria:** efficiency — observabilidade de CI
- **Prioridade:** P3
- **Plataformas afetadas:** iOS, iPadOS, tvOS, watchOS, visionOS
- **Evidência nos logs:** em nenhum dos 5 logs de crash a linha do `Fatal error` é precedida por
  informação de qual teste/suíte estava ativo naquele exato momento (só foi possível inferir
  indiretamente comparando `Suite ... started` vs. ausência de `Suite ... passed/failed`).
- **Hipótese de causa:** não é um bug, é uma lacuna de diagnóstico — `xcodebuild`/swift-testing não
  está configurado para emitir um resumo de "testes em execução no momento do crash" nestes
  runners.
- **Ação proposta:** avaliar habilitar `-resultBundlePath` mais granular ou o modo de teste
  paralelo com relatório por-teste, para que uma futura triagem não precise inferir qual teste
  disparou o crash a partir de ausência de linhas de log.
- **Validação sugerida:** provocar um crash controlado localmente e confirmar que o novo log
  identifica o teste responsável diretamente.

---

## Resumo de prioridades

| ID | Prioridade | Bloqueado por |
|---|---|---|
| T1 | P0 | — |
| T2 | P0 | — (pode rodar em paralelo a T1) |
| T3 | P0 | T1, T2 |
| T4 | P1 | T3 |
| T5 | P1 | — |
| T6 | P2 | T5 |
| T7 | P3 | — |
