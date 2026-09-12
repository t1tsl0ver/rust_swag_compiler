# Rust SWAG Compiler

Учебный компилятор Rust-подобного языка. Проект реализуется на C++ и собирается с помощью CMake.

Наш проект и исходный код разрабатываемого компилятора находятся в каталоге `_compiler/`.

Для проверки реализации используется официальный компилятор Rust той же зафиксированной версии: один и тот же `.rs`-файл передаётся оригинальному `rustc` и нашему компилятору, после чего сравниваются результат, сообщения об ошибках и поведение программы.

## Эталонная версия Rust

- Rust: `1.98.1`
- Edition: `2024`
- Commit компилятора: `48a229ceaefd4985c50990b14116b6d856af0985`
- Commit Rust Reference: `86635e30bf861a038dc197d7e16fd09e7e514e7a`

Версию следует указывать явно при каждом запуске, чтобы будущие обновления Rust не изменили результаты тестов.

## Установка оригинального компилятора

Команды ниже предназначены для Windows PowerShell.

1. Установить официальный [rustup](https://www.rust-lang.org/tools/install).
2. Перезапустить терминал, чтобы команда `rustup` появилась в `PATH`.
3. Установить минимальный GNU-toolchain и локальный HTML-мануал:

```powershell
rustup toolchain install 1.98.1-x86_64-pc-windows-gnu --profile minimal --component rust-docs
```

Проверить установленную версию:

```powershell
rustc +1.98.1-x86_64-pc-windows-gnu --version --verbose
```

В выводе должны присутствовать версия `1.98.1` и commit `48a229ceaefd4985c50990b14116b6d856af0985`.

## Проверка `.rs`-теста оригинальным компилятором

Тест может находиться в любом каталоге. Например, чтобы проверить файл `tests\example.rs`:

```powershell
New-Item -ItemType Directory -Force .\build\reference
rustc +1.98.1-x86_64-pc-windows-gnu --edition 2024 .\tests\example.rs -o .\build\reference\example.exe
```

Если компиляция успешна, запустить получившуюся программу:

```powershell
.\build\reference\example.exe
```

Если тест должен содержать ошибку, достаточно передать его `rustc` и изучить диагностику:

```powershell
rustc +1.98.1-x86_64-pc-windows-gnu --edition 2024 .\tests\invalid.rs
$LASTEXITCODE
```

Код завершения `0` означает успешную компиляцию, ненулевой код — отказ компилятора. В дальнейшем эти же тестовые файлы нужно передавать нашему компилятору и сравнивать результаты. Команда запуска нашего компилятора будет добавлена после появления его CLI.

Исходники оригинального `rustc` используются только как справочный материал. Локально они находятся в `reference/realRustCompiler/compiler/`; ту же версию можно [посмотреть на GitHub](https://github.com/rust-lang/rust/tree/1.98.1/compiler). Собирать оригинальный компилятор из этих исходников для проверки тестов не требуется.

## Rust Reference

Открыть установленный локальный HTML-мануал в браузере:

```powershell
rustup doc --toolchain 1.98.1-x86_64-pc-windows-gnu --reference
```

Узнать точный путь к его `index.html`, не открывая браузер:

```powershell
rustup doc --toolchain 1.98.1-x86_64-pc-windows-gnu --reference --path
```

Также доступны:

- [Rust Reference 1.98.1 онлайн](https://doc.rust-lang.org/1.98.1/reference/);
- исходные Markdown-файлы локального снимка в `manual/src/`.
