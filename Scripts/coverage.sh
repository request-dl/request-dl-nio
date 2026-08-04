#!/bin/bash
set -euo pipefail

echo "▶ Rodando testes com coverage..."
swift test --enable-code-coverage

echo "▶ Localizando artefatos..."
BIN_DIR="$(swift build --build-tests --show-bin-path)"
PROFDATA="$BIN_DIR/codecov/default.profdata"

TEST_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -name '*.xctest' | head -n 1)"
BUNDLE_NAME="$(basename "$TEST_BUNDLE" .xctest)"
BINARY="$TEST_BUNDLE/Contents/MacOS/$BUNDLE_NAME"

echo "▶ Gerando relatório resumido por arquivo..."
xcrun llvm-cov report "$BINARY" -instr-profile "$PROFDATA" \
  -ignore-filename-regex='Tests/.*' > coverage-report.txt

echo "▶ Gerando detalhes linha a linha (arquivos com 0% ou baixa cobertura)..."
xcrun llvm-cov show "$BINARY" -instr-profile "$PROFDATA" \
  -ignore-filename-regex='Tests/.*' \
  --format=text > coverage-lines.txt || true

echo "✅ Pronto:"
echo "   - coverage-report.txt  (resumo por arquivo)"
echo "   - coverage-lines.txt   (linha a linha)"