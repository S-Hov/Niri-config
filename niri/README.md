# Конфигурация Niri

Модульный конфиг Niri для Arch Linux и Noctalia v5. Требуется Niri **25.11 или новее**, потому что основной файл использует директиву `include`; рекомендуемая версия — 26.04+.

## Структура

| Файл | Что делает |
| --- | --- |
| `config.kdl` | Точка входа, подключает модули из `cfg/` |
| `cfg/autostart.kdl` | Запускает KDE Polkit agent и Noctalia v5 |
| `cfg/input.kdl` | Клавиатура, US/RU phonetic, мышь и touchpad |
| `cfg/display.kdl` | Выходы, режимы, масштаб и расположение мониторов |
| `cfg/layout.kdl` | Отступы и предустановленные ширины колонок |
| `cfg/rules.kdl` | Скругления окон, PiP, окно настроек и wallpaper Noctalia |
| `cfg/animation.kdl` | Скорость и кривые анимаций |
| `cfg/keybinds.kdl` | Запуск приложений и управление окнами/Noctalia |
| `cfg/misc.kdl` | Wayland-переменные, CSD, скриншоты и overlay |

## Зависимости

```bash
sudo pacman -S --needed niri polkit-kde-agent kitty firefox nautilus
paru -S noctalia-git
```

Noctalia v5 должна предоставлять исполняемый файл `noctalia`. Конфиг не предназначен для Quickshell-версии v4.

По умолчанию Noctalia v5 не регистрирует собственный Polkit agent, поэтому конфиг запускает `polkit-kde-agent`. Если в Noctalia включена настройка `shell.polkit_agent`, удалите строку KDE agent из `cfg/autostart.kdl`, чтобы два агента не конкурировали.

## Установка

```bash
mkdir -p ~/.config/niri
cp -a ./niri/. ~/.config/niri/
```

Перед копированием сохраните существующий `~/.config/niri`.

## Настройка мониторов

Шаблон рассчитан на два дисплея:

- `DP-1`: 2560×1440 @ 359.979 Hz, scale 1, основной;
- `DP-2`: 3840×2160, scale 1.25, расположен справа.

Получите реальные имена и режимы:

```bash
niri msg outputs
```

Затем отредактируйте `cfg/display.kdl`. При дробном scale координаты задаются в логических пикселях. Не копируйте частоту `359.979`, если монитор её не сообщает.

## Основные клавиши

| Клавиша | Действие |
| --- | --- |
| `Mod+Return` | Kitty |
| `Mod+D` | Launcher Noctalia |
| `Mod+B` / `Mod+E` | Firefox / Nautilus |
| `Mod+Alt+L` | Экран блокировки Noctalia |
| `Mod+стрелки` | Фокус окна |
| `Mod+Shift+стрелки` | Перемещение окна |
| `Mod+Ctrl+Up/Down` | Соседний workspace |
| `Mod+1…9` | Выбор workspace |
| `Mod+Shift+1…9` | Перенос колонки на workspace |
| `Mod+F` | Полноэкранный режим |
| `Mod+Space` | Floating/tiled |
| `Mod+O` | Overview Niri |
| `Print` | Скриншот области |

`Mod` соответствует клавише Super в обычной Niri-сессии.

## Noctalia v5

Конфиг запускает `noctalia` и использует IPC вида `noctalia msg ...` для launcher, lock screen и управления звуком. Проверить интеграцию можно из терминала:

```bash
noctalia msg --help
noctalia msg panel-toggle launcher
noctalia msg volume-osd
```

Wallpaper сопоставляется по namespace `^noctalia-wallpaper` и помещается в backdrop Niri. Если используется отдельный blurred backdrop Noctalia, замените namespace на `^noctalia-backdrop` согласно настройкам оболочки.

## Проверка и диагностика

После установки:

```bash
niri validate
```

Дополнительно:

```bash
niri msg outputs
niri msg layers
journalctl --user -b -u niri.service
```

`niri msg layers` помогает проверить настоящий namespace wallpaper. Если конфиг не загружается, временно запускайте `niri validate` после каждого изменения отдельного модуля.
