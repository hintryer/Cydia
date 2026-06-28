#!/usr/bin/env bash

set -euo pipefail

CONFIG_DIR="./assets/repo"
CONFIG_FILE="$CONFIG_DIR/repo.conf"
GPG_KEY_FILE=""
key_id=""

initialize_variables() {
    local origin="" label="" codename="" description=""
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        origin=$(awk -F\" '/Origin/ {print $2}' "$CONFIG_FILE")
        label=$(awk -F\" '/Label/ {print $2}' "$CONFIG_FILE")
        codename=$(awk -F\" '/Codename/ {print $2}' "$CONFIG_FILE")
        description=$(awk -F\" '/Description/ {print $2}' "$CONFIG_FILE")
    else
        echo "Configuration file not found. Creating a new one."
        mkdir -p "$CONFIG_DIR"
        touch "$CONFIG_FILE"
        origin="${REPO_ORIGIN:-}"
        label="${REPO_LABEL:-$origin}"
        codename="${REPO_CODENAME:-}"
        description="${REPO_DESCRIPTION:-$origin}"
        if [[ -n "$origin" && -n "$codename" ]]; then
            save_config
        else
            edit_repo_conf
        fi
    fi

    if [[ -n "${REPO_ORIGIN:-}" ]]; then
        origin="${REPO_ORIGIN}"
    fi
    if [[ -n "${REPO_LABEL:-}" ]]; then
        label="${REPO_LABEL}"
    fi
    if [[ -n "${REPO_CODENAME:-}" ]]; then
        codename="${REPO_CODENAME}"
    fi
    if [[ -n "${REPO_DESCRIPTION:-}" ]]; then
        description="${REPO_DESCRIPTION}"
    fi

    GPG_KEY_FILE="${origin}-repo.gpg"

    if [[ -n "${REPO_ORIGIN:-}" || -n "${REPO_LABEL:-}" || -n "${REPO_CODENAME:-}" || -n "${REPO_DESCRIPTION:-}" ]]; then
        save_config
    fi
}

save_config() {
    GPG_KEY_FILE="${origin}-repo.gpg"
    cat > "$CONFIG_FILE" <<EOL
APT {
    FTPArchive {
        Release {
            Origin "$origin";
            Label "$label";
            Suite stable;
            Version 1.0;
            Codename "$codename";
            Architectures "iphoneos-arm" "iphoneos-arm64";
            Components main;
            Description "$description";
        };
    };
};
EOL
    echo "repo.conf file updated."
}

generate_gpg_key() {
    local realname="$1"
    local email="$2"
    local gen_key_script

    gen_key_script=$(mktemp)
    cat > "$gen_key_script" <<EOL
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $realname
Name-Email: $email
Expire-Date: 0
%commit
EOL

    gpg --batch --yes --pinentry-mode loopback --gen-key "$gen_key_script"
    rm -f "$gen_key_script"

    key_id=$(gpg --list-secret-keys --with-colons --keyid-format LONG | awk -F: '/^sec:/ {print $5; exit}')
    if [[ -z "$key_id" ]]; then
        echo "Error: failed to retrieve a newly generated GPG key ID."
        exit 1
    fi
}

get_secret_key_id() {
    gpg --with-colons --list-secret-keys --keyid-format LONG 2> /dev/null | awk -F: '/^sec:/ {print $5; exit}'
}

import_private_key() {
    if [[ -n "${REPO_GPG_PRIVATE_KEY:-}" ]]; then
        echo "Importing GPG private key from REPO_GPG_PRIVATE_KEY."
        printf '%s' "$REPO_GPG_PRIVATE_KEY" | gpg --batch --import
        return 0
    fi
    return 1
}

generate_or_input_key() {
    key_id=$(get_secret_key_id)
    if [[ -n "$key_id" ]]; then
        echo "Secret GPG key already available: $key_id"
        return
    fi

    if import_private_key; then
        key_id=$(get_secret_key_id)
        if [[ -z "$key_id" ]]; then
            echo "Error: private key import failed."
            exit 1
        fi
        gpg --export "$key_id" > "$GPG_KEY_FILE"
        echo "GPG key exported to $GPG_KEY_FILE"
        return
    fi

    if [[ -f "$GPG_KEY_FILE" ]]; then
        echo "GPG key file $GPG_KEY_FILE already exists. Checking key type..."
        key_id=$(gpg --with-colons --import-options show-only --import "$GPG_KEY_FILE" 2> /dev/null | awk -F: '/^pub:/ { print $5; exit }')
        if [[ -n "$key_id" ]]; then
            echo "Public key file detected, but no secret key is available."
            if [[ -n "${REPO_GPG_NAME:-}" && -n "${REPO_GPG_EMAIL:-}" ]]; then
                echo "Generating a new GPG key because the secret key is missing."
                generate_gpg_key "$REPO_GPG_NAME" "$REPO_GPG_EMAIL"
                echo "Exporting the public key..."
                gpg --export "$key_id" > "$GPG_KEY_FILE"
                echo "GPG key exported to $GPG_KEY_FILE"
                return
            fi
            echo "Error: $GPG_KEY_FILE contains only a public key and no secret key is available."
            echo "Set REPO_GPG_PRIVATE_KEY or remove $GPG_KEY_FILE to generate a new key."
            exit 1
        fi
    fi

    if [[ -n "${REPO_GPG_NAME:-}" && -n "${REPO_GPG_EMAIL:-}" ]]; then
        echo "Generating a new GPG key from REPO_GPG_NAME and REPO_GPG_EMAIL."
        generate_gpg_key "$REPO_GPG_NAME" "$REPO_GPG_EMAIL"
        echo "Exporting the public key..."
        gpg --export "$key_id" > "$GPG_KEY_FILE"
        echo "GPG key exported to $GPG_KEY_FILE"
        return
    fi

    while true; do
        read -rp "Do you want to generate a new GPG key or use an existing one? (gen/use): " action
        case "$action" in
            gen)
                read -rp "Enter your name: " realname
                read -rp "Enter your email: " email
                generate_gpg_key "$realname" "$email"
                echo "Exporting the public key..."
                gpg --export "$key_id" > "$GPG_KEY_FILE"
                echo "GPG key exported to $GPG_KEY_FILE"
                break
                ;;
            use)
                echo "List of available keys:"
                gpg --list-secret-keys --keyid-format=long
                read -rp "Enter the key ID (the value after 'sec' in the list above): " key_id
                echo "Exporting the public key..."
                gpg --export "$key_id" > "$GPG_KEY_FILE"
                echo "GPG key exported to $GPG_KEY_FILE"
                break
                ;;
            *)
                echo "Invalid option. Please enter 'gen' or 'use'."
                ;;
        esac
    done
}

edit_repo_conf() {
    read -rp "Enter the Repository Name: " origin
    label="$origin"
    read -rp "Enter the Repository Codename: " codename
    read -rp "Enter the Repository Description: " description

    save_config
}

update_repo() {
    local apt_ftparchive

    if command -v apt-ftparchive &> /dev/null; then
        apt_ftparchive="apt-ftparchive"
    elif [[ -f "./apt-ftparchive" ]]; then
        apt_ftparchive="./apt-ftparchive"
    else
        echo "Error: apt-ftparchive not found."
        exit 1
    fi

    cd "$(dirname "$0")" || exit
    rm -f Packages* Contents-iphoneos-arm* Release* 2> /dev/null

    $apt_ftparchive packages ./debians > Packages
    gzip -c9 Packages > Packages.gz
    xz -c9 Packages > Packages.xz
    zstd -c19 Packages > Packages.zst
    bzip2 -c9 Packages > Packages.bz2

    $apt_ftparchive contents ./debians > Contents-iphoneos-arm
    bzip2 -c9 Contents-iphoneos-arm > Contents-iphoneos-arm.bz2
    xz -c9 Contents-iphoneos-arm > Contents-iphoneos-arm.xz
    xz -5fkev --format=lzma Contents-iphoneos-arm > Contents-iphoneos-arm.lzma
    lz4 -c9 Contents-iphoneos-arm > Contents-iphoneos-arm.lz4
    gzip -c9 Contents-iphoneos-arm > Contents-iphoneos-arm.gz
    zstd -c19 Contents-iphoneos-arm > Contents-iphoneos-arm.zst

    $apt_ftparchive release -c "$CONFIG_FILE" . > Release

    gpg -abs -u "$key_id" -o Release.gpg Release

    echo "Repository Updated and Signed, thanks for using repo.me!"
}

install_packages() {
    echo "Checking for required packages..."
    packages="apt-utils gnupg xz-utils zstd bzip2 lz4 gzip gawk"

    for package in $packages; do
        if ! dpkg -s "$package" &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y "$package"
        fi
    done
}

install_brew_packages() {
    echo "Checking for Homebrew and required packages..."
    if ! command -v brew &> /dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    fi

    brew_packages="wget gnupg xz zstd bzip2 lz4 gzip gawk"

    for package in $brew_packages; do
        if ! brew list --verbose "$package" &> /dev/null; then
            brew install "$package"
        fi
    done
}

prepare_apt_ftparchive() {
    if ! command -v apt-ftparchive &> /dev/null; then
        wget -q -nc https://apt.procurs.us/apt-ftparchive
        sudo chmod 755 ./apt-ftparchive
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        mkdir -p /usr/local/etc/apt/apt.conf.d/
    fi
}

main() {
    initialize_variables

    case "$OSTYPE" in
        linux*) 
            ## Linux & WSL
            install_packages
            ;;
        darwin*)
            if [[ "$(uname -m)" == "x86_64" || "$(uname -m)" == "arm64" ]]; then
            ## macOS
                install_brew_packages
                echo "apt-ftparchive compiled by @Diatrus" # credits to Hayden!
                prepare_apt_ftparchive
            else 
            ## iOS / iPadOS
                install_packages
            fi
            ;;
        *)
            echo "Error: Running an unsupported operating system. Email me: hi@air.rip"
            exit 1
            ;;
    esac

    load_config
    generate_or_input_key
    update_repo
}

main "$@"
