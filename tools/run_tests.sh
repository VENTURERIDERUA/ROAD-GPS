#!/bin/bash
# Тести на цьому комп'ютері: бібліотека PDF (pdfrx → pdfium) для тестів на Windows потребує компілятора
# Visual Studio, якого тут немає. Тому — копія проєкту в тимчасовій теці, з неї прибрано pdfrx, і тести там.
# Робочий pubspec.yaml не змінюється: перерваний запуск нічого не псує. Файли з pdfrx тести не імпортують.
# Запуск з теки проєкту: bash tools/run_tests.sh [файли тестів]   (без аргументів — усі тести)
set -e
cd "$(dirname "$0")/.."
export PATH="${FLUTTER_BIN:+$FLUTTER_BIN:}$PATH"
src="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r "$src/lib" "$src/test" "$src/pubspec.yaml" "$src/pubspec.lock" "$src/analysis_options.yaml" "$tmp/"
cd "$tmp"
sed -i '/^  pdfrx:/d' pubspec.yaml
flutter pub get >/dev/null
flutter test "$@"
