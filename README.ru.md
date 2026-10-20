[English](README.md) | **Русский**

# Citra

Утилита из строки меню macOS: тащишь файл из Finder, во время перетаскивания зажимаешь модификатор — у курсора появляется круговое меню; отпускаешь кнопку над сектором, и выбранное действие выполняется над файлом. Окно приложения не открывается.

| Модификатор | Режим |
|---|---|
| ⌘ | Conversion |
| ⇧ | Tools |
| ⌃ | File Actions |

Если зажато несколько — приоритет ⌘ > ⇧ > ⌃. В меню попадают только действия, которые работают для перетаскиваемых файлов; больше 10 — первые 9 и **More** с наружной дугой.

## Установка

1. Скачайте `Citra-<версия>.zip` со страницы [Releases](../../releases) и распакуйте.
2. Перетащите `Citra.app` в «Программы».
3. Первый запуск. Citra не подписана сертификатом Apple Developer, поэтому macOS сразу её не откроет:
   - откройте Citra — появится предупреждение, закройте его;
   - Системные настройки → Конфиденциальность и безопасность → внизу строка про Citra → **Всё равно открыть** → подтвердите.

   Или одной командой в Терминале (она же помогает, если macOS пишет, что приложение «повреждено»):

   ```bash
   xattr -dr com.apple.quarantine /Applications/Citra.app
   ```
4. В строке меню появится значок ◎. Окна у приложения нет: начните перетаскивать файл из Finder и только потом зажмите ⌘, ⇧ или ⌃.

Требования: macOS 26 или новее, Apple Silicon или Intel (на Intel не проверялось).

Без сертификата Apple Developer:
- после обновления шаг 3 может понадобиться снова — для macOS это новое приложение;
- macOS может отклонить запрос на уведомления без диалога. Тогда включите их вручную: Системные настройки → Уведомления → Citra. Результаты появляются рядом с файлами в любом случае.

## Что умеет

| Тип | ⌘ Conversion | ⇧ Tools |
|---|---|---|
| Изображения (всё, что читает ImageIO: PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP, AVIF…; SVG только на вход) | JPEG, PNG, HEIC, TIFF, AVIF, BMP, WebP (с cwebp) — кроме собственного формата, PDF | Resize (пресеты), Rotate 90°, Compress (только JPEG/HEIC), Metadata (убрать EXIF/GPS/IPTC/XMP); для SVG — нет |
| ZIP, TAR, TAR.GZ / TGZ | друг в друга (ZIP, TAR, TAR.GZ) | Extract; Test — только ZIP |
| GZ (одиночный файл) | — | Extract |
| Видео, которое открывает AVFoundation (MP4, MOV, M4V) | MOV ⇄ MP4 (без перекодирования), M4A, GIF; с ffmpeg — MKV, WebM, AVI, WMV, MP3 | Compress (720p), Mute, Trim, Crop, Speed, Snapshot |
| Видео, которое AVFoundation не открывает (MKV, WebM, AVI, WMV…) — только с ffmpeg | MP4, MOV, MKV, WebM, AVI, WMV, GIF, MP3 (кроме собственного формата) | — |
| Аудио (MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA…) — только с ffmpeg | MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA (кроме собственного формата) | — |
| Субтитры SRT, VTT | SRT ⇄ VTT, TXT (текст без тегов и повторов) | — |
| PDF | — | Merge (2 и больше), Split (по странице в файл) |

⌃ File Actions для любых файлов и папок: AirDrop, Float (плавающая полка), Copy (⌘V в Finder вставляет сами файлы), Move (с вопросом при конфликте имён), Copy Path, Terminal.

**От чего зависит доступность:**
- **HEIC** — от кодировщика ImageIO (на Apple Silicon есть).
- **TAR, TAR.GZ и конвертация архивов** — от `/usr/bin/tar`; одиночный GZ — от `/usr/bin/gzip`. Архив с путями через `..` не распаковывается и не конвертируется.
- **WebP** — от `cwebp` в тех же папках, что и ffmpeg (`brew install webp`): ImageIO WebP только читает.
- **SVG** растеризуется: длинная сторона не меньше 1024 px.
- **OGG** — встроенным экспериментальным кодером Vorbis из ffmpeg (в Homebrew-сборке нет libvorbis): всегда стерео, качество ниже, чем у libvorbis. Обложка альбома при конвертации аудио не переносится; WAV и AIFF — 16 бит.
- **Форматы через ffmpeg** — от `ffmpeg` в `/opt/homebrew/bin` или `/usr/local/bin` и нужных кодировщиков в нём. ffmpeg не встраивается в приложение; статус и подсказка — в Settings → Conversions.
- **Terminal / iTerm2** — от того, что выбрано в настройках и установлено на Mac.
- **M4A и Mute для видео без звука, Split для одностраничного PDF** — до drop Citra файлы не читает, чтобы macOS не запрашивала доступ к папкам. Поэтому эти действия показываются всегда, а при drop сообщают, почему не сработали, и ничего не создают.

Результат — рядом с оригиналом или в выбранной папке: `video.mp4` → `video.mov`, инструменты — `photo rotated.png`, занятое имя → `video 2.mov`. Оригинал не изменяется (кроме Move). Запись идёт во временный файл и переименовывается по готовности: отмена или ошибка не оставляют битых файлов. Ход задач и отмена — в меню строки меню.

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

По умолчанию сборка подписывается ad-hoc, поэтому собрать проект может кто угодно. Чтобы подписывать свои сборки сертификатом Apple Development (стабильная подпись сохраняет разрешение на уведомления между пересборками), создайте `Config/Signing.local.xcconfig` — git его игнорирует:

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <ваш Team ID>
```

## Релиз

```bash
scripts/release.sh
```

Скрипт собирает универсальную (Apple Silicon + Intel) Release-сборку с ad-hoc подписью, проверяет подпись и упаковывает её через `ditto` в `dist/Citra-<версия>.zip`. Личный сертификат в релиз не попадает, даже если есть `Signing.local.xcconfig`. Версия задаётся в `project.yml` (`CFBundleShortVersionString`). Публикация:

```bash
gh release create v1.0.0 dist/Citra-1.0.0.zip --title "Citra 1.0.0" --notes "…"
```

## Разрешения и sandbox

- App Sandbox **выключен** — осознанно, для прямого распространения (Developer ID): нужны глобальный мониторинг мыши, запись результата рядом с оригиналом в любой папке и запуск системных инструментов (`/usr/bin/tar`, позже — внешний `ffmpeg`).
- Accessibility, Input Monitoring, Full Disk Access и Automation **не нужны**: начало drag ловится глобальным монитором мыши, модификаторы и Escape читаются опросом состояния, Terminal открывается через Launch Services без AppleScript.
- **Уведомления** — запрашиваются при первом готовом результате (не при запуске); без них результат всё равно появляется рядом с оригиналом.
