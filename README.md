# Citra

Утилита из строки меню macOS: тащишь файл из Finder, во время перетаскивания зажимаешь модификатор — у курсора появляется круговое меню; отпускаешь кнопку над сектором, и выбранное действие выполняется над файлом.

| Модификатор | Режим |
|---|---|
| ⌘ | Conversion |
| ⇧ | Tools |
| ⌃ | File Actions |

Если зажато несколько — приоритет ⌘ > ⇧ > ⌃.

Статус: этап 1 (proof of concept), см. `PROGRESS.md` и `docs/feasibility.md`.

## Сборка

Требуется Xcode 26+ и XcodeGen (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project Citra.xcodeproj -scheme Citra -destination 'platform=macOS' test
xcodebuild -project Citra.xcodeproj -scheme Citra -configuration Debug build
```

Собирать в стандартный DerivedData (без `-derivedDataPath` внутри проекта): если папка синхронизируется iCloud Drive, codesign отклоняет бандл из-за extended attributes.

## Разрешения и sandbox

- App Sandbox **выключен** — осознанно, для прямого распространения (Developer ID): нужны глобальный мониторинг мыши, запись результата рядом с оригиналом в произвольной папке и, позже, запуск внешнего `ffmpeg`.
- Accessibility, Input Monitoring и Full Disk Access не нужны: начало drag ловится глобальным монитором мыши, модификаторы читаются через `NSEvent.modifierFlags`, файлы — через drag-пастборд.
