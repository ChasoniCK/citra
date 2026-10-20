# Citra — прогресс

Спецификация: `PROMPT.md`. План этапа 1: `docs/superpowers/plans/2026-10-20-stage1-poc.md`.
Результаты по реализуемости: `docs/feasibility.md`.

## Текущий этап: 1 — Proof of concept (ждёт ручной проверки)

### Сделано
- Проект XcodeGen (`project.yml`), menu bar приложение (`LSUIElement`), Swift 6, macOS 15+, без зависимостей.
- `DragMonitor` — начало и конец drag, режим по модификатору, URL из drag-пастборда; без Accessibility и Input Monitoring.
- `RadialMenuPanelController` — одно non-activating `NSPanel`, drop-цель, позиционирование внутри `visibleFrame`.
- `RadialLayout` — чистая геометрия и hit-test; `RadialMenuView` — простая отрисовка (стили — этап 2).
- Реальные действия в PoC: ⌘ PNG → JPEG (рядом, атомарно, без перезаписи), ⌃ Copy (file URL на general-пастборд), ⌃ Copy Path. Остальные секторы — тусклые заглушки (beep, ничего не делают).
- Диагностический лог `~/Library/Logs/Citra/poc.log` (пункт меню «Open PoC Log»).

### Проверено
| Что | Как |
|---|---|
| Сборка Debug, ad-hoc подпись | собрано (`xcodebuild`) |
| 26 unit-тестов: приоритет режимов, hit-test для 1/2/6/9 секторов (центр, край, зазоры), пути секторов, позиционирование у краёв и на втором экране, уникальные имена, выбор drag-операции, PNG → JPEG (валидный JPEG, оригинал не изменён, прозрачность на белом, `img 2.jpg`, нет временных файлов, битый файл) | покрыто тестом |
| Приложение стартует без Accessibility и Input Monitoring | запуск, строка `launch:` в логе |
| drag между приложениями, появление окна, drop, режимы, Escape | **не проверено** — ждёт ручного чек-листа |

### Дальше
1. Ручной прогон чек-листа → заполнить «Результаты» в `docs/feasibility.md` по логу.
2. Если механизм подтверждён — этап 2 (radial UI по референсам). Если нет — запасной вариант из `feasibility.md`.

### Открытые вопросы
- Маска операций Finder при ⌘ (если в ней нет `generic`, drop с ⌘ невозможен).
- Видно ли состояние Escape через `CGEventSource.keyState` без Input Monitoring.
- Мульти-монитор проверить нечем (один дисплей).

## Заметки по окружению
- Проект лежит в `~/Documents`, который синхронизирует iCloud Drive. Из-за этого: (1) сборка в папку проекта падает на codesign (xattr от File Provider) — собирать только в стандартный DerivedData; (2) iCloud уже создавал конфликтную копию `Citra 2.xcodeproj` после `xcodegen generate`. Рекомендация — перенести репозиторий за пределы iCloud.
- XcodeGen установлен через Homebrew (`brew install xcodegen`); после добавления или удаления файлов — `xcodegen generate`.
- Тестовый хост — само приложение: при прогоне тестов в `poc.log` появляется строка `launch:`.
