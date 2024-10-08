#!/bin/bash

# Скрипт для миграции баз данных и пользователей между двумя кластерами Patroni.
# Скрипт выполняет следующие шаги:

# 1. Интерактивный ввод параметров:
#    - Ввод параметров для подключения к старому и новому кластерам Patroni (адреса, порты, имя пользователя, каталог для дампов).
#    - Если пользователь не введет параметры, будут использованы значения по умолчанию (порт 5432 и каталог ./dumps).
#
# 2. Проверка подключения к старому кластеру:
#    - Используется команда `pg_isready` для проверки доступности старого кластера.
#    - Если подключение не удалось, пользователю предлагается возможность изменить параметры и повторить попытку.
#    - При успешном подключении выводится сообщение об успешности.
#
# 3. Работа с каталогом для дампов:
#    - Проверяется наличие каталога для дампов.
#    - Если каталог существует, но не пуст, пользователю предлагается два варианта:
#      1) Удалить все файлы в каталоге (с подтверждением).
#      2) Заархивировать все файлы в архив с текущей датой и удалить их.
#    - Если каталог не существует, пользователю предлагается его создать.
#
# 4. Получение списка баз данных со старого кластера:
#    - Выполняется SQL-запрос для получения списка баз данных (исключая шаблонные базы).
#    - При успешном выполнении запроса выводится сообщение об успешности получения списка.
#
# 5. Выбор баз данных для миграции:
#    - Пользователю предлагается выбрать базы данных для экспорта с помощью меню выбора.
#    - Выбор осуществляется через цикл, где пользователь может добавлять базы по одной.
#    - Пользователь может завершить выбор в любой момент, выбрав опцию "Завершить выбор".
#
# 6. Экспорт пользователей и их прав доступа:
#    - Выполняется SQL-запрос для получения списка пользователей и их ролей на старом кластере.
#    - Права доступа и пользователи сохраняются в файл `users.sql` в каталоге для дампов.
#    - По завершении экспорта выводится сообщение об успешности.
#
# 7. Экспорт баз данных:
#    - Для каждой выбранной базы данных выполняется экспорт с помощью команды `pg_dump`.
#    - Каждая база данных сохраняется в виде дампа в указанном каталоге.
#    - Для каждой базы выводится сообщение об успешности или ошибке.
#
# 8. Импорт пользователей и прав на новый кластер:
#    - Выполняется импорт пользователей и их прав на новый кластер через SQL-скрипт `users.sql`.
#    - При успешном выполнении вывода сообщения об успешности.
#
# 9. Импорт баз данных на новый кластер:
#    - Для каждой базы данных выполняется восстановление из дампа с помощью команды `pg_restore`.
#    - Каждая база данных восстанавливается на новом кластере.
#    - Для каждой базы выводится сообщение об успешности или ошибке.
#
# 10. Завершение:
#    - По завершении миграции выводится сообщение об успешном завершении процесса миграции.

# Дополнительная информация:
# - Все операции логируются в консоль с сообщениями об успешности или ошибках.
# - В случае ошибки на любом шаге скрипт завершает выполнение с выводом соответствующего сообщения.
# - Скрипт использует код возврата `$?` для отслеживания состояния выполнения команд.

# Функция для получения ввода с проверкой на пустоту
get_input() {
    local prompt="$1"
    local input_var
    while true; do
        read -rp "$prompt" input_var
        if [ -n "$input_var" ]; then
            echo "$input_var"
            break
        else
            echo "Пожалуйста, введите значение."
        fi
    done
}

# Функция для запроса подтверждения (да/нет)
confirm_action() {
    local prompt="$1"
    local input_var
    while true; do
        read -rp "$prompt [y/n]: " input_var
        case "$input_var" in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        *) echo "Пожалуйста, введите y или n." ;;
        esac
    done
}

# Функция для проверки подключения к старому кластеру
check_connection() {
    echo "Проверка подключения к старому кластеру $OLD_HOST:$OLD_PORT..."
    pg_isready -h "$OLD_HOST" -p "$OLD_PORT" -U "$USER"
    local connection_status=$?
    if [ $connection_status -ne 0 ]; then
        echo "Ошибка: Не удалось подключиться к старому кластеру $OLD_HOST:$OLD_PORT. Код ошибки: $connection_status"
        if confirm_action "Желаете ли вы изменить параметры подключения и попробовать снова?"; then
            OLD_HOST=$(get_input "Введите адрес старого кластера Patroni: ")
            OLD_PORT=$(get_input "Введите порт старого кластера (по умолчанию 5432): ")
            USER=$(get_input "Введите имя пользователя с правами на базы данных: ")
            check_connection
        else
            echo "Скрипт завершен."
            exit 1
        fi
    else
        echo "Подключение к старому кластеру успешно!"
    fi
}

# Ввод параметров через интерактивный режим
OLD_HOST=$(get_input "Введите адрес старого кластера Patroni: ")
NEW_HOST=$(get_input "Введите адрес нового кластера Patroni: ")
OLD_PORT=$(get_input "Введите порт старого кластера (по умолчанию 5432): ")
NEW_PORT=$(get_input "Введите порт нового кластера (по умолчанию 5432): ")
USER=$(get_input "Введите имя пользователя с правами на базы данных: ")
DUMP_DIR=$(get_input "Введите каталог для дампов (по умолчанию ./dumps): ")

# Если порты или каталог не заданы, устанавливаем значения по умолчанию
OLD_PORT=${OLD_PORT:-5432}
NEW_PORT=${NEW_PORT:-5432}
DUMP_DIR=${DUMP_DIR:-./dumps}

# Проверка подключения к старому кластеру
check_connection

# Проверка на существование каталога для дампов
if [ -d "$DUMP_DIR" ]; then
    echo "Каталог $DUMP_DIR уже существует."

    # Если каталог не пустой
    if [ "$(ls -A $DUMP_DIR)" ]; then
        echo "Каталог $DUMP_DIR не пустой. Вот список файлов:"
        ls -lh "$DUMP_DIR"

        # Предложить 2 варианта действий
        echo "Выберите действие:"
        echo "1. Удалить все файлы дампов в каталоге"
        echo "2. Заархивировать все файлы в архив с названием dump_дата_создания"

        # Получаем выбор пользователя
        read -rp "Ваш выбор (1/2): " choice
        case $choice in
        1)
            # Подтверждение перед удалением всех файлов
            FILE_COUNT=$(ls -1 "$DUMP_DIR" | wc -l)
            echo "В каталоге $DUMP_DIR находится $FILE_COUNT файл(ов)."
            if ! confirm_action "Вы действительно хотите удалить все файлы?"; then
                echo "Удаление файлов отменено."
                exit 1
            fi
            echo "Удаление всех файлов в каталоге $DUMP_DIR..."
            rm -f "$DUMP_DIR"/*
            if [ $? -eq 0 ]; then
                echo "Файлы успешно удалены."
            else
                echo "Ошибка при удалении файлов."
                exit 1
            fi
            ;;
        2)
            TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
            ARCHIVE_NAME="dump_$TIMESTAMP.tar.gz"
            echo "Архивирование файлов в архив $ARCHIVE_NAME..."
            tar -czf "$DUMP_DIR/$ARCHIVE_NAME" -C "$DUMP_DIR" .
            if [ $? -eq 0 ]; then
                echo "Файлы успешно заархивированы."
                rm -f "$DUMP_DIR"/*
                echo "Файлы удалены после архивирования."
            else
                echo "Ошибка при архивировании файлов."
                exit 1
            fi
            ;;
        *)
            echo "Неверный выбор."
            exit 1
            ;;
        esac
    else
        echo "Каталог $DUMP_DIR пустой. Продолжаем..."
    fi
else
    # Если каталог не существует, предложить его создать
    echo "Каталог $DUMP_DIR не существует."
    if confirm_action "Хотите создать каталог $DUMP_DIR?"; then
        mkdir -p "$DUMP_DIR"
        if [ $? -eq 0 ]; then
            echo "Каталог $DUMP_DIR успешно создан."
        else
            echo "Ошибка при создании каталога $DUMP_DIR."
            exit 1
        fi
    else
        echo "Каталог $DUMP_DIR не был создан. Завершение скрипта."
        exit 1
    fi
fi

# Получение списка баз данных
echo "Получение списка баз данных со старого кластера"
DATABASES=$(psql -h "$OLD_HOST" -p "$OLD_PORT" -U "$USER" -d postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;")
if [ $? -eq 0 ]; then
    echo "Список баз данных успешно получен."
else
    echo "Ошибка при получении списка баз данных."
    exit 1
fi

# Преобразуем список баз данных в массив
DATABASES_ARRAY=($DATABASES)

# Массив для хранения выбранных баз данных
SELECTED_DATABASES=()

# Цикл для выбора баз данных
while true; do
    echo "Выберите базы данных для миграции (введите номер):"
    for i in "${!DATABASES_ARRAY[@]}"; do
        echo "$((i + 1))) ${DATABASES_ARRAY[$i]}"
    done
    echo "0) Завершить выбор"

    # Получаем выбор пользователя
    read -rp "Введите номер базы данных: " CHOICE

    if [[ "$CHOICE" == "0" ]]; then
        echo "Выбор завершен."
        break
    elif [[ "$CHOICE" -gt 0 && "$CHOICE" -le "${#DATABASES_ARRAY[@]}" ]]; then
        SELECTED_DATABASES+=("${DATABASES_ARRAY[$((CHOICE - 1))]}")
        echo "База данных ${DATABASES_ARRAY[$((CHOICE - 1))]} добавлена."
    else
        echo "Неверный выбор, попробуйте снова."
    fi

    # Спросим, продолжить ли выбор
    read -rp "Продолжить выбор баз данных? [y/n]: " CONTINUE_CHOICE
    if [[ "$CONTINUE_CHOICE" =~ ^[Nn]$ ]]; then
        echo "Выбор завершен."
        break
    fi
done

# Экспорт пользователей и прав
echo "Экспорт пользователей и ролей"
psql -h "$OLD_HOST" -p "$OLD_PORT" -U "$USER" -d postgres -c "\du" -t -A | awk '{print $1}' | while read -r role; do
    if [[ "$role" != "postgres" && "$role" != "pg_monitor" && "$role" != "pg_signal_backend" ]]; then
        echo "CREATE ROLE $role WITH LOGIN;" >>"$DUMP_DIR/users.sql"
    fi
done
if [ $? -eq 0 ]; then
    echo "Пользователи и права успешно экспортированы."
else
    echo "Ошибка при экспорте пользователей."
    exit 1
fi

# Экспорт каждой выбранной базы данных
for DB in "${SELECTED_DATABASES[@]}"; do
    echo "Экспорт базы данных $DB"
    pg_dump -h "$OLD_HOST" -p "$OLD_PORT" -U "$USER" -d "$DB" -F c -f "$DUMP_DIR/$DB.dump"
    if [ $? -eq 0 ]; then
        echo "База данных $DB успешно экспортирована."
    else
        echo "Ошибка при экспорте базы данных $DB."
        exit 1
    fi
done

# Импорт пользователей и прав на новом кластере
echo "Импорт пользователей на новый кластер"
psql -h "$NEW_HOST" -p "$NEW_PORT" -U "$USER" -f "$DUMP_DIR/users.sql"
if [ $? -eq 0 ]; then
    echo "Пользователи успешно импортированы."
else
    echo "Ошибка при импорте пользователей."
    exit 1
fi

# Импорт каждой базы данных на новый кластер
for DB in "${SELECTED_DATABASES[@]}"; do
    echo "Импорт базы данных $DB"
    pg_restore -h "$NEW_HOST" -p "$NEW_PORT" -U "$USER" -d "$DB" -F c "$DUMP_DIR/$DB.dump"
    if [ $? -eq 0 ]; then
        echo "База данных $DB успешно импортирована."
    else
        echo "Ошибка при импорте базы данных $DB."
        exit 1
    fi
done

echo "Миграция успешно завершена!"
