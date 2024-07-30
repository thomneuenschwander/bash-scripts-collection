#!/bin/bash

BASE_URL="https://loteriascaixa-api.herokuapp.com/api/"

DOWNLOAD_ALL=false
DOWNLOAD_LATEST=false
SEARCH_CONTEST=false
SEARCH_CONTEST_NUMBER=""
SEARCH_NUMBERS=false
SEARCH_NUMBERS_ARRAY=()
CORE_VISUALIZE_OUTPUT=true

show_usage() {
    echo "Uso: $0 -d {all|latest} | -s <contest> | -s [number01,number02,...] | -v"
    exit 1
}

while getopts ":d:s:v" opt; do
    case $opt in
        d)
            case $OPTARG in
                all)
                    DOWNLOAD_ALL=true
                    ;;
                latest)
                    DOWNLOAD_LATEST=true
                    ;;
                *)
                    echo "Opção inválida: -d $OPTARG" >&2
                    show_usage
                    ;;
            esac
            ;;
        s)
            if [[ $OPTARG == \[*\] ]]; then
                SEARCH_NUMBERS=true
                IFS=',' read -r -a SEARCH_NUMBERS_ARRAY <<< "${OPTARG#[}"
                SEARCH_NUMBERS_ARRAY=($(printf "%s\n" "${SEARCH_NUMBERS_ARRAY[@]%]}" | sort -n))
            else
                SEARCH_CONTEST=true
                SEARCH_CONTEST_NUMBER="$OPTARG"
            fi
            ;;
        v)
            CORE_VISUALIZE_OUTPUT=false
            ;;
        \?)
            echo "Opção inválida: -$OPTARG" >&2
            show_usage
            ;;
        :)
            echo "A opção -$OPTARG requer um argumento." >&2
            show_usage
            ;;
    esac
done

if [ "$DOWNLOAD_ALL" != true ] && [ "$DOWNLOAD_LATEST" != true ] && [ "$SEARCH_CONTEST" != true ] && [ "$SEARCH_NUMBERS" != true ]; then
    show_usage
fi

if ! command -v jq &> /dev/null
then
    echo "jq não está instalado."
    exit 1
fi

select_lottery() {
    PS3="Escolha a loteria para fazer download: "
    options=("maismilionaria" "megasena" "lotofacil" "quina" "lotomania" "timemania" "duplasena" "federal" "diadesorte" "supersete")
    select lottery_name in "${options[@]}"
    do
        if [[ " ${options[*]} " == *" $lottery_name "* ]]; then
            break
        else
            echo "Opção inválida. Tente novamente."
        fi
    done
}

lottery_core_visualization() {
    local json_data=$1
    echo "$json_data" | jq '{
        loteria: .loteria,
        concurso: .concurso,
        data: .data,
        dezenas: .dezenas
    }'
}

download_all() {
    local url_fetcher="${BASE_URL}${lottery_name}"
    if [ -e "$json_file_name" ]; then
        echo "O arquivo $json_file_name já existe no diretório atual."
        exit 0
    fi
    curl -o "$json_file_name" "$url_fetcher"
}

download_latest() {
    if [ ! -e "$json_file_name" ]; then
        echo "O arquivo $json_file_name não existe no diretório atual."
        exit 1
    fi
    local url_fetcher="${BASE_URL}${lottery_name}/latest"
    echo "Baixando dados da loteria $lottery_name de $url_fetcher..."
    local json_data=$(curl -s "$url_fetcher")
    if [ $? -eq 0 ]; then
        echo "Download concluído com sucesso."
        echo "Adicionando o novo objeto JSON ao arquivo $json_file_name..."
        local new_data=$(jq --argjson new_data "$json_data" '. |= [$new_data] + .' "$json_file_name")
        echo "$new_data" > "$json_file_name"
        if [ "$CORE_VISUALIZE_OUTPUT" == true ]; then
            echo "Core content \"$lottery_name\":"
            lottery_core_visualization "$json_data"
            echo
        fi
    else
        echo "Falha no download."
    fi
}

search_by_contest() {
    if [ ! -e "$json_file_name" ]; then
        echo "O arquivo $json_file_name não existe no diretório atual."
        exit 1
    fi
    echo "Pesquisando pelo concurso número $SEARCH_CONTEST_NUMBER em $json_file_name..."
    local result=$(jq --arg search_contest_number "$SEARCH_CONTEST_NUMBER" '.[] | select(.concurso == ($search_contest_number | tonumber))' "$json_file_name")
    if [ -n "$result" ]; then
        echo "Concurso encontrado:"
        if [ "$CORE_VISUALIZE_OUTPUT" == true ]; then
            lottery_core_visualization "$result"
        else
            echo "$result" | jq
        fi
    else
        echo "Concurso número $SEARCH_CONTEST_NUMBER não encontrado."
    fi
}

search_by_numbers() {
    if [ ! -e "$json_file_name" ];then
        echo "O arquivo $json_file_name não existe no diretório atual."
        exit 1
    fi
    echo "Pesquisando pelas dezenas sorteadas [${SEARCH_NUMBERS_ARRAY[*]}] em $json_file_name..."
    local search_numbers_array_str=$(printf ",%s" "${SEARCH_NUMBERS_ARRAY[@]}")
    search_numbers_array_str="[${search_numbers_array_str:1}]"
    local result=$(jq --argjson search_numbers_array "$search_numbers_array_str" '
        .[] | select((.dezenas | map(tonumber)) as $d | ($d | inside($search_numbers_array)))
    ' "$json_file_name")
    if [ -n "$result" ]; then
        echo "Concursos encontrados:"
        if [ "$CORE_VISUALIZE_OUTPUT" == true ]; then
            lottery_core_visualization "$result"
        else
            echo "$result" | jq
        fi
    else
        echo "Nenhum concurso encontrado com as dezenas [${SEARCH_NUMBERS_ARRAY[*]}]."
    fi
}

select_lottery
json_file_name="$lottery_name.json"

if [ "$DOWNLOAD_ALL" == true ]; then
    download_all
fi

if [ "$DOWNLOAD_LATEST" == true ]; then
    download_latest
fi

if [ "$SEARCH_CONTEST" == true ]; then
    search_by_contest
fi

if [ "$SEARCH_NUMBERS" == true ]; then
    search_by_numbers
fi
