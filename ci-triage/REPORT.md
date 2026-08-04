# Relatório de Triagem de CI

Fonte: `./logs/*.txt` (11 logs de job de uma única execução de CI, branch `async-fixes`, run id
`30934401451`). Apenas análise — nenhum código foi modificado, nenhum build/teste foi executado.

## 1. Jobs que falharam

11 jobs no total. 7 falharam, 4 passaram.

| # | Job | Resultado | Sinal de saída |
|---|---|---|---|
| 1 | 🍎 iPadOS | **FALHOU** | `Fatal error` (trap) → exit 65 |
| 3 | 🍎 iOS | **FALHOU** | `Fatal error` (trap) → exit 65 |
| 4 | 🍎 macOS Catalyst | **FALHOU** | Falha de asserção em teste → exit 65 |
| 5 | 🍎 visionOS | **FALHOU** | `Fatal error` (trap) → exit 65 |
| 6 | 🍎 tvOS | **FALHOU** | `Fatal error` (trap) → exit 65 |
| 7 | 🍎 watchOS | **FALHOU** | `Fatal error` (trap) → exit 65 |
| 0 | 📤 Coverage Upload | **FALHOU** | script `exit 1` (`.profdata` ausente) |
| 8 | 🍎 macOS | passou | — |
| 9 | 🔧 Linux | passou (1011 testes / 158 suítes, 11,2s) | — |
| 2 | 🔗 Linkage Test (FoundationEssentials) | passou | — |
| 11 | 🎨 Format | passou | — |

As 6 plataformas contadas pelo usuário são os 6 jobs de teste Apple: **iPadOS, iOS, macOS
Catalyst, visionOS, tvOS, watchOS**. O Coverage Upload é um 7º job, separado e downstream — não é
uma das 6 plataformas, e sua falha é analisada isoladamente no cluster B abaixo, já que atribuí-la
à mesma causa seria incorreto (ver evidências).

## 2. Clusters de causa raiz

### Cluster A — defeito de leitura concorrente em `Internals.Buffer` (5 crashes + 1 falha explícita de teste)

**Plataformas:** iPadOS, iOS, tvOS, watchOS, visionOS (crash), macOS Catalyst (falha não fatal).
**Classificação: CODE_BUG** (padrão confirmado, não é ruído de ambiente).

Evidência, iPadOS (`logs/1_Swift CI _ 🍎 iPadOS.txt:1802-1804`):
```
##[error]Fatal error: 🐞 RequestDL bug: Buffer reported 851968 readable bytes but returned none
##[error]Fatal error: 🐞 RequestDL bug: Buffer reported 835584 readable bytes but returned none
##[error]Fatal error: 🐞 RequestDL bug: Buffer reported 851968 readable bytes but returned none
```
Mesmo formato de mensagem (só a contagem de bytes muda) em iOS (`3_*.txt:1824-1827`), visionOS
(`5_*.txt:1807-1809`), tvOS (`6_*.txt:1839-1840`), watchOS (`7_*.txt:1826-1827`).

O trap se origina em `Internals.assertionFailure` dentro de
`Sources/RequestDL/Internals/Sources/Body/Internals.BodySequence.swift:75-77`, disparado quando
`Internals.Buffer.readData(_:)` é solicitado a ler um intervalo que `readableBytes` reporta como
disponível, mas o armazenamento subjacente devolve `nil` para ele.

No macOS Catalyst, o mesmo tipo de defeito aparece como uma falha de teste normal (não fatal) em
vez de um trap de processo (`logs/4_Swift CI _ 🍎 macOS Catalyst.txt:1907-1909`):
```
##[error]Recorded an issue (Expectation failed: (Set(datas.compactMap { $0 }).count → 558) == (1_024 → 1024))
##[error]fileBuffer_whenRacingImmutable() (8.825 seconds) 1 issue(s)
##[error]Suite InternalsFileBufferTests failed after 8.912 seconds with 1 issue(s)
```
`fileBuffer_whenRacingImmutable`
(`Tests/RequestDLTests/Internals/Sources/Buffers/File/InternalsFileBufferTests.swift:788-809`)
dispara 1024 leituras concorrentes de `getData(at:length:)` contra um único `Internals.FileBuffer`
imutável e espera que todas as 1024 tenham sucesso com resultados distintos. Apenas 558 voltaram
não-nulas — cerca de 46% das leituras em um buffer que nada limpa ou modifica durante o teste
retornaram `nil` apesar de o intervalo solicitado ser válido.

**Por que isso é um único cluster, e não seis problemas não relacionados:** nas cinco plataformas
que travam, `Suite InternalsFileBufferTests started` é logado, mas **`InternalsFileBufferTests
passed` (ou `failed`) nunca aparece** — a suíte ainda estava em execução, quase certamente rodando
`fileBuffer_whenRacingImmutable` ou um caminho equivalente de leitura concorrente, no momento do
crash (confirmado no iPadOS: a suíte inicia às `17:45:26`, o crash ocorre às `17:45:56`, e a linha
de conclusão nunca é impressa; mesma ausência em iOS, tvOS, watchOS, visionOS). O
`InternalsBodySequenceTests`, cujos testes `bodySequence_*` rodam concorrentemente com ele sob a
execução paralela do Swift Testing, é quem efetivamente dispara a asserção fatal — mas ambas as
suítes exercitam o mesmo caminho de leitura de `Internals.Buffer`/`FileStreamBuffer` sob
concorrência. O Catalyst é o caso de controle que mostra exatamente o que está dando errado quando
o processo sobrevive à corrida em vez de travar.

**Por que macOS nativo e Linux não reproduzem isso:** `logs/8_*.txt` e `logs/9_*.txt` não têm
nenhum marcador de erro; o Linux completou 1011 testes em 11,2s. As 6 plataformas que falharam
rodam em simuladores (ou, no caso do Catalyst, em um runtime sandboxed similar ao iOS) com I/O de
arquivo mais lento/contencioso do que macOS nativo ou um container Linux, o que alarga a janela de
tempo para qualquer corrida presente em
`Internals.Buffer.Storage.read(at:length:)`
(`Sources/RequestDL/Internals/Sources/Buffers/Buffer/Internals.Buffer.swift:141-160`) e/ou em seu
backing `FileStreamBuffer`
(`Sources/RequestDL/Internals/Sources/Buffers/Buffer/Models/Internals.FileStreamBuffer.swift`).
Pela regra de triagem (mesma assinatura de falha em mais de uma plataforma ⇒ provável CODE_BUG na
ausência de evidência clara de ambiente), e havendo uma reprodução independente de plataforma no
próprio repositório (`fileBuffer_whenRacingImmutable`), isso é classificado como **CODE_BUG**, não
PLATFORM_BUG. Ainda não foi isolado até uma única linha — ver TASKS.md T1-T3 para a investigação
restrita (candidatos: a checagem `isResourceAvailable()` correndo contra um evento concorrente de
ciclo de vida do buffer, esgotamento de file descriptors sob 1024 aberturas concorrentes em um
`ulimit` mais apertado de simulador, ou um bug na composição dos dois `AsyncLock` independentes
usados por `Buffer.Storage` e por `FileStreamBuffer`).

### Cluster B — Coverage Upload: `find .xcbuild -name "*.profdata"` desatualizado (1 job)

**Plataforma:** Coverage Upload (runner macOS, downstream do job 🍎 macOS).
**Classificação: CODE_BUG** (script de CI, não código do pacote) — alta confiança, distinto do
cluster A.

Evidência (`logs/0_Swift CI _ 📤 Coverage Upload.txt:207-213`):
```
=== Processing: artifacts/apple-macOS/ ===
Nenhum .profdata em artifacts/apple-macOS/
##[error]Process completed with exit code 1.
```
O download do artefato `apple-macOS` teve sucesso (2/2 artefatos baixados, SHA256 correto), então
não se trata de artefato ausente ou falha de dependência. Rastreando até o job que o produziu
(`logs/8_Swift CI _ 🍎 macOS.txt:1950-1953`):
```
mkdir -p coverage-artifacts
find .xcbuild -name "*.profdata" -exec cp {} coverage-artifacts/ \; 2>/dev/null || true
find .xcbuild -name "*.xctest" -not -path "*/.dSYM/*" -exec cp -r {} coverage-artifacts/ \; 2>/dev/null || true
```
`-enableCodeCoverage YES` foi passado à execução dos testes (`8_*.txt:539`) e a execução completou
com sucesso, produzindo um bundle `.xcresult`
(`.xcbuild/Logs/Test/Test-request-dl-2026.08.04_17-38-05-+0000.xcresult`, `8_*.txt:1948`). Nesta
imagem (macOS 26.5.2 / Xcode 26.6, `0_*.txt:11-17`), os dados de cobertura ficam dentro desse
pacote `.xcresult`, não como um arquivo `.profdata` solto sob `.xcbuild` — então `find .xcbuild
-name "*.profdata"` legitimamente não encontra nada, o `|| true` engole essa falha, e os bundles
`.xctest` são enviados sem seus dados de cobertura. A etapa consumidora só descobre isso depois e
falha ruidosamente.

Isso não aconteceu porque os testes de macOS falharam (eles passaram) e não tem relação com o
cluster A; é uma quebra latente na etapa de shell que extrai a cobertura, provavelmente exposta
agora por uma atualização de imagem/Xcode que mudou onde os dados de cobertura são gravados.

## 3. Tabela-resumo

| Causa | Classificação | Plataformas | Confiança |
|---|---|---|---|
| Leitura concorrente em `Internals.Buffer` retorna `nil` apesar de `readableBytes > 0` | CODE_BUG | iOS, iPadOS, tvOS, watchOS, visionOS, macOS Catalyst | Alta (reproduzida no próprio repo por um teste dedicado; assinatura consistente em 6 jobs) |
| `find .xcbuild -name "*.profdata"` não bate mais com o layout de saída desta imagem do Xcode | CODE_BUG | Coverage Upload (macOS) | Alta (causa raiz totalmente rastreada nos logs) |

Nenhuma classificação PLATFORM_BUG, UNKNOWN ou FLAKY foi justificada nesta execução: toda falha se
traça a uma causa concreta e reproduzível no repositório, não a um problema pontual de ambiente.
