# Citra

Утилита из строки меню macOS: тащишь файл из Finder, во время перетаскивания зажимаешь модификатор — у курсора появляется круговое меню; отпускаешь кнопку над сектором, и выбранное действие выполняется над файлом. Окно приложения не открывается.

| Модификатор | Режим |
|---|---|
| ⌘ | Conversion |
| ⇧ | Tools |
| ⌃ | File Actions |

Если зажато несколько — приоритет ⌘ > ⇧ > ⌃. В меню попадают только действия, которые работают для перетаскиваемых файлов; больше 10 — первые 9 и **More** с наружной дугой.

## Что умеет

| Тип | ⌘ Conversion | ⇧ Tools |
|---|---|---|
| Изображения (всё, что читает ImageIO: PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP…) | JPEG, PNG, HEIC, TIFF (кроме собственного формата), PDF | Resize (пресеты), Rotate 90°, Compress (только JPEG/HEIC), Metadata (удалить EXIF/GPS/IPTC/XMP) |
| ZIP | TAR, TAR.GZ | Extract, Test |
| Видео, которое открывает AVFoundation (MP4, MOV, M4V) | MOV (passthrough), M4A | Snapshot (средний кадр → PNG), Mute |
| Любые файлы и папки | — | — |

M4A и Mute для видео без звука сообщают, что аудиодорожки нет, и ничего не создают: до drop Citra не читает файлы, чтобы macOS не запрашивала доступ к папкам.

⌃ File Actions для любых файлов и папок: AirDrop, Float (плавающая полка), Copy (⌘V в Finder вставляет сами файлы), Move (с вопросом при конфликте имён), Copy Path, Terminal.

Результат — рядом с оригиналом: `video.mp4` → `video.mov`, инструменты — `photo rotated.png`; занятое имя → `video 2.mov`. Оригинал не изменяется (кроме Move). Запись идёт во временный файл и переименовывается по готовности: отмена или ошибка не оставляют битых файлов. Ход задач и отмена — в меню строки меню.

## Настройки

Строка меню → Settings… (⌘,):
- **General** — включение, запуск при входе, уведомления, куда сохранять результат.
- **Shortcuts** — модификатор для каждого режима.
- **Appearance** — размер кольца, анимации, акцентный цвет.
- **Conversions** — качество JPEG/HEIC, режим для MOV, доступные конвертации.
- **File Actions** — Terminal или iTerm2, край полки.

## Сборка

Требуется Xcode 26+ и XcodeGen (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project Citra.xcodeproj -scheme Citra -destination 'platform=macOS' test
xcodebuild -project Citra.xcodeproj -scheme Citra -configuration Debug build
```

Собирать в стандартный DerivedData (без `-derivedDataPath` внутри проекта): если папка синхронизируется iCloud Drive, codesign отклоняет бандл из-за extended attributes.

## Разрешения и sandbox

- App Sandbox **выключен** — осознанно, для прямого распространения (Developer ID): нужны глобальный мониторинг мыши, запись результата рядом с оригиналом в любой папке и запуск системных инструментов (`/usr/bin/tar`, позже — внешний `ffmpeg`).
- Accessibility, Input Monitoring, Full Disk Access и Automation **не нужны**: начало drag ловится глобальным монитором мыши, модификаторы и Escape читаются опросом состояния, Terminal открывается через Launch Services без AppleScript.
- **Уведомления** — запрашиваются при первом готовом результате (не при запуске); без них результат всё равно появляется рядом с оригиналом.
