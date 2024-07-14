#!/bin/bash

BASE_URL="https://loteriascaixa-api.herokuapp.com/api/"

DOWNLOAD_ALL=false
DOWNLOAD_LATEST=false
SEARCH_CONTEST=false
SEARCH_CONTEST_NUMBER=""
SEARCH_TENS=false
SEARCH_TENS_ARRAY=()

show_usage() {
    echo "Uso: $0 -d {all|latest} | -s <contest> | -s [ten01,ten02,...]"
    exit 1
}

while getopts ":d:s:" opt; do
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
                SEARCH_TENS=true
                IFS=',' read -r -a SEARCH_TENS_ARRAY <<< "${OPTARG#[}"
                SEARCH_TENS_ARRAY=("${SEARCH_TENS_ARRAY[@]%]}")
            else
                SEARCH_CONTEST=true
                SEARCH_CONTEST_NUMBER="$OPTARG"
            fi
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

if [ "$DOWNLOAD_ALL" != true ] && [ "$DOWNLOAD_LATEST" != true ] && [ "$SEARCH_CONTEST" != true ] && [ "$SEARCH_TENS" != true ]; then
    show_usage
fi

if ! command -v jq &> /dev/null
then
    echo "jq não está instalado. Instale-o com 'sudo pacman -S jq'."
    exit 1
fi

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

json_file_name="$lottery_name.json"

lottery_core_vizualization() {
    local json_data=$1

    echo "$json_data" | jq '{
        loteria: .loteria,
        concurso: .concurso,
        data: .data,
        dezenasOrdemSorteio: .dezenasOrdemSorteio
    }'
}

download_all() {
    url_fatcher="${BASE_URL}${lottery_name}"

    if [ -e "$json_file_name" ]; then
        echo "O arquivo $json_file_name já existe no diretório atual."
        exit 0
    fi

    curl -o "$json_file_name" "$url_fatcher"
}

download_latest() {
    if [ ! -e "$json_file_name" ]; then
        echo "O arquivo $json_file_name não existe no diretório atual."
        exit 1
    fi

    url_fetcher="${BASE_URL}${lottery_name}/latest"

    echo "Baixando dados da loteria $lottery_name de $url_fetcher..."
    json_data=$(curl -s "$url_fetcher")

    if [ $? -eq 0 ]; then
        echo "Download concluído com sucesso."

        echo "Adicionando o novo objeto JSON ao arquivo $json_file_name..."
        new_data=$(jq --argjson new_data "$json_data" '. |= [$new_data] + .' "$json_file_name")
        echo "$new_data" > "$json_file_name"

        echo "Core content \"$lottery_name\":"
        lottery_core_vizualization "$json_data"
        echo
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
    result=$(jq --arg search_contest_number "$SEARCH_CONTEST_NUMBER" '.[] | select(.concurso == ($search_contest_number | tonumber))' "$json_file_name")

    if [ -n "$result" ]; then
        echo "Concurso encontrado:"
        echo "$result" | jq
    else
        echo "Concurso número $SEARCH_CONTEST_NUMBER não encontrado."
    fi
}

search_by_tens() {
    if [ ! -e "$json_file_name" ]; then
        echo "O arquivo $json_file_name não existe no diretório atual."
        exit 1
    fi

    echo "Pesquisando pelas dezenas sorteadas [${SEARCH_TENS_ARRAY[*]}] em $json_file_name..."
    search_tens_array_str=$(printf ",%s" "${SEARCH_TENS_ARRAY[@]}")
    search_tens_array_str="[${search_tens_array_str:1}]"
    
    result=$(jq --argjson search_tens_array "$search_tens_array_str" '
        .[] | select((.dezenasOrdemSorteio | map(tonumber)) as $d | ($d | inside($search_tens_array)))
    ' "$json_file_name")

    if [ -n "$result" ]; then
        echo "Concursos encontrados:"
        echo "$result" | jq
    else
        echo "Nenhum concurso encontrado com as dezenas [${SEARCH_TENS_ARRAY[*]}]."
    fi
}

if [ "$DOWNLOAD_ALL" == true ]; then
    download_all
fi

if [ "$DOWNLOAD_LATEST" == true ]; then
    download_latest
fi

if [ "$SEARCH_CONTEST" == true ]; then
    search_by_contest
fi

if [ "$SEARCH_TENS" == true ]; then
    search_by_tens
fi
