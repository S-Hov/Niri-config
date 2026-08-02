if status is-interactive
    # Интерактивные настройки Fish
end


# Упрощённый интерфейс для pacman / paru / yay
#
# Примеры:
#   pac install firefox
#   pac remove firefox
#   pac purge firefox
#   pac search browser
#   pac list
#   pac list firefox
#   pac info firefox
#   pac update
#   pac clean
#   pac orphan
#   pac help

function pac --description "Упрощённый интерфейс для pacman, paru и yay"
    # Автоматически выбираем пакетный менеджер.
    # Приоритет: paru -> yay -> pacman.
    set -l helper pacman

    if command -q paru
        set helper paru
    else if command -q yay
        set helper yay
    end

    # Показываем справку, если команда не передана.
    if test (count $argv) -eq 0
        __pac_help $helper
        return 0
    end

    set -l action $argv[1]
    set -e argv[1]

    switch $action
        case install add i
            if test (count $argv) -eq 0
                echo "Использование: pac install <пакет...>"
                return 1
            end

            if test $helper = pacman
                sudo command pacman -S --needed $argv
            else
                command $helper -S --needed $argv
            end

        case remove rm delete
            if test (count $argv) -eq 0
                echo "Использование: pac remove <пакет...>"
                return 1
            end

            # Удаляет пакет, но не удаляет автоматически
            # все его зависимости и конфигурацию.
            if test $helper = pacman
                sudo command pacman -R $argv
            else
                command $helper -R $argv
            end

        case purge uninstall
            if test (count $argv) -eq 0
                echo "Использование: pac purge <пакет...>"
                return 1
            end

            # Удаляет пакет, неиспользуемые зависимости
            # и системные конфигурационные файлы.
            if test $helper = pacman
                sudo command pacman -Rns $argv
            else
                command $helper -Rns $argv
            end

        case search find s
            if test (count $argv) -eq 0
                echo "Использование: pac search <запрос>"
                return 1
            end

            command $helper -Ss $argv

        case list ls installed
            # Без аргументов выводит все установленные пакеты.
            # С аргументами ищет среди установленных пакетов.
            if test (count $argv) -eq 0
                command pacman -Q
            else
                command pacman -Qs $argv
            end

        case info show
            if test (count $argv) -eq 0
                echo "Использование: pac info <пакет...>"
                return 1
            end

            command $helper -Si $argv

        case local-info installed-info
            if test (count $argv) -eq 0
                echo "Использование: pac local-info <пакет...>"
                return 1
            end

            command pacman -Qi $argv

        case update upgrade up
            # В Arch update и upgrade фактически являются
            # одной операцией полного обновления системы.
            if test $helper = pacman
                sudo command pacman -Syu
            else
                command $helper -Syu
            end

        case refresh
            # Принудительно обновляет базы пакетов и систему.
            # Обычно достаточно обычного pac update.
            if test $helper = pacman
                sudo command pacman -Syyu
            else
                command $helper -Syyu
            end

        case orphan orphans
            # Показывает зависимости, которые больше
            # не требуются ни одному установленному пакету.
            command pacman -Qdtq

        case remove-orphans autoremove
            set -l orphans (command pacman -Qdtq)

            if test (count $orphans) -eq 0
                echo "Неиспользуемые зависимости не найдены."
                return 0
            end

            echo "Будут удалены неиспользуемые зависимости:"
            printf "  %s\n" $orphans

            read --prompt-str="Продолжить? [y/N] " -l confirmation

            switch (string lower -- $confirmation)
                case y yes д да
                    sudo command pacman -Rns $orphans
                case '*'
                    echo "Отменено."
            end

        case clean
            # Безопасная очистка старых пакетов.
            # Не используется -Scc, чтобы не удалять весь кэш.
            if test $helper = pacman
                sudo command pacman -Sc
            else
                command $helper -Sc
            end

        case download
            if test (count $argv) -eq 0
                echo "Использование: pac download <пакет...>"
                return 1
            end

            if test $helper = pacman
                sudo command pacman -Sw $argv
            else
                command $helper -Sw $argv
            end

        case help h --help -h
            __pac_help $helper

        case raw
            # Позволяет передать оригинальные аргументы напрямую:
            # pac raw -Syu
            if test $helper = pacman
                sudo command pacman $argv
            else
                command $helper $argv
            end

        case '*'
            echo "Неизвестная команда: $action"
            echo
            __pac_help $helper
            return 1
    end
end


function __pac_help --argument-names helper
    echo "Используемый пакетный менеджер: $helper"
    echo
    echo "Использование:"
    echo "  pac <команда> [пакеты]"
    echo
    echo "Команды:"
    echo "  install <пакеты>       Установить пакеты"
    echo "  remove <пакеты>        Удалить пакеты"
    echo "  purge <пакеты>         Удалить пакеты и зависимости"
    echo "  search <запрос>        Найти пакет в репозиториях/AUR"
    echo "  list [запрос]          Показать или найти установленные пакеты"
    echo "  info <пакеты>          Информация о доступных пакетах"
    echo "  local-info <пакеты>    Информация об установленных пакетах"
    echo "  update                 Полностью обновить систему"
    echo "  refresh                Обновить базы принудительно и обновить систему"
    echo "  orphan                 Показать неиспользуемые зависимости"
    echo "  remove-orphans         Удалить неиспользуемые зависимости"
    echo "  clean                  Очистить старые пакеты из кэша"
    echo "  download <пакеты>      Скачать пакеты без установки"
    echo "  raw <аргументы>        Передать аргументы напрямую менеджеру"
    echo "  help                   Показать эту справку"
    echo
    echo "Примеры:"
    echo "  pac install firefox"
    echo "  pac search visual-studio-code"
    echo "  pac purge firefox"
    echo "  pac update"
end


# micro вместо nano
function nano
    if command -q micro
        command micro $argv
    else
        command nano $argv
    end
end

alias yz="yazi"
