#!/bin/bash

set -euo pipefail

main() {
    parse_arguments "$@"
    header "Downloading fly executables"
    download_fly_executables
}

download_fly_executables() {
    wget -q "${FLY_DOWNLOAD_URL}" --output-document "${FLY_EXE_PATH}"
    chmod +x "${FLY_EXE_PATH}"
    wget -q "${FLY_NEXT_DOWNLOAD_URL}" --output-document "${FLY_NEXT_EXE_PATH}"
    chmod +x "${FLY_NEXT_EXE_PATH}"
}

header() {
    echo -e "=====> $@"
}

subheader() {
    echo -e "-----> $@"
}

indent() {
    sed 's/^/       /'
}

usage() {
    echo "Usage: $(basename $0) [options]"
    echo
    echo "Predeploy script to be ran during dokku deployment"
    echo
    echo -e "      --help\t\tShow this help message"
}

parse_arguments() {
    while [[ $# > 0 ]] ; do
        key="$1"

        case $key in
            --help)
                usage
                exit 0
                ;;

            *)
                echo "$(basename $0): unrecognized option ${key}"
                usage
                exit 1
                ;;
        esac
    done
}

main "$@"
