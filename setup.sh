#!/bin/sh -e

# Define color codes using tput for better compatibility
RC=$(tput sgr0 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)

# Where the repo lives when we have to fetch it ourselves (override with MYBASH_DIR=...)
MYBASH_DIR="${MYBASH_DIR:-$HOME/mybash}"
MYBASH_REPO="${MYBASH_REPO:-https://github.com/swedishstyle/mybash}"
PACKAGER=""
SUDO_CMD=""
SUGROUP=""
GITPATH=""

# Helper functions
print_colored() {
    printf "${1}%s${RC}\n" "$2"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

installDocker() {
    #Docker install script
    curl -sSL https://get.docker.com | bash

    #Docker compose + add user to group
    LATEST=$(curl -sL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            curl -sSL https://github.com/docker/compose/releases/download/$LATEST/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
            ;;
        i686 | i386)
            echo "32-bit architecture detected, wtf"
            ;;
        arm* | aarch64)
            curl -sSL https://github.com/docker/compose/releases/download/$LATEST/docker-compose-linux-aarch64 -o ~/.docker/cli-plugins/docker-compose
            ;;
        *)
            echo "Unknown architecture: $ARCH"
            # Add a fallback command or an error message here
            ;;
    esac

    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
    
    if [ $(getent group docker) ]; then
        echo "Docker group exists"
    else
        sudo groupadd docker
    fi
    
    sudo usermod -aG docker $USER
}

# Setup functions
detect_environment() {
    # Check for required commands
    REQUIREMENTS='curl groups sudo'
    for req in $REQUIREMENTS; do
        if ! command_exists "$req"; then
            print_colored "$RED" "To run me, you need: $REQUIREMENTS"
            exit 1
        fi
    done

    # Determine package manager
    PACKAGEMANAGER='nala apt dnf yum pacman zypper emerge xbps-install nix-env'
    for pgm in $PACKAGEMANAGER; do
        if command_exists "$pgm"; then
            PACKAGER="$pgm"
            printf "Using %s\n" "$pgm"
            break
        fi
    done

    if [ -z "$PACKAGER" ]; then
        print_colored "$RED" "Can't find a supported package manager"
        exit 1
    fi

    # Determine sudo command
    if command_exists sudo; then
        SUDO_CMD="sudo"
    elif command_exists doas && [ -f "/etc/doas.conf" ]; then
        SUDO_CMD="doas"
    else
        SUDO_CMD="su -c"
    fi
    printf "Using %s as privilege escalation software\n" "$SUDO_CMD"
}

install_git() {
    print_colored "$YELLOW" "Installing git..."
    case "$PACKAGER" in
        apt|nala) ${SUDO_CMD} ${PACKAGER} update && ${SUDO_CMD} ${PACKAGER} install -y git ;;
        pacman) ${SUDO_CMD} pacman -Sy --noconfirm git ;;
        xbps-install) ${SUDO_CMD} xbps-install -Sy git ;;
        emerge) ${SUDO_CMD} emerge -v dev-vcs/git ;;
        nix-env) ${SUDO_CMD} nix-env -iA nixos.git ;;
        zypper) ${SUDO_CMD} zypper install -n git ;;
        *) ${SUDO_CMD} ${PACKAGER} install -y git ;;
    esac
}

# The configs are symlinked out of the directory this script lives in, so the
# script has to run from a checkout. If it was piped in (curl | bash) there is
# no checkout yet: fetch one and hand over to its copy of this script.
bootstrap() {
    # When the script is piped in, $0 is the shell ("bash"), not a path -- and
    # dirname of that is ".", which would wrongly make the current directory the
    # checkout. Only trust $0 when it names a file that actually exists.
    SCRIPT_DIR=""
    if [ -f "$0" ]; then
        SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || SCRIPT_DIR=""
    fi

    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/.bashrc" ] && [ -f "$SCRIPT_DIR/starship.toml" ]; then
        GITPATH="$SCRIPT_DIR"
        return 0
    fi

    if [ -n "$MYBASH_BOOTSTRAPPED" ]; then
        print_colored "$RED" "$MYBASH_DIR doesn't look like a mybash checkout"
        exit 1
    fi

    command_exists git || install_git

    if [ -d "$MYBASH_DIR/.git" ]; then
        print_colored "$YELLOW" "Updating existing checkout: $MYBASH_DIR"
        git -C "$MYBASH_DIR" pull --ff-only || print_colored "$YELLOW" "Couldn't fast-forward, using the checkout as-is"
    else
        print_colored "$YELLOW" "Cloning mybash into: $MYBASH_DIR"
        if ! git clone "$MYBASH_REPO" "$MYBASH_DIR"; then
            print_colored "$RED" "Failed to clone mybash repository"
            exit 1
        fi
    fi

    chmod +x "$MYBASH_DIR/setup.sh"
    print_colored "$GREEN" "Running $MYBASH_DIR/setup.sh"
    MYBASH_BOOTSTRAPPED=1
    export MYBASH_BOOTSTRAPPED
    exec "$MYBASH_DIR/setup.sh"
}

check_environment() {
    # Check write permissions
    if [ ! -w "$GITPATH" ]; then
        print_colored "$RED" "Can't write to $GITPATH"
        exit 1
    fi

    # Check superuser group
    SUPERUSERGROUP='wheel sudo root'
    for sug in $SUPERUSERGROUP; do
        if groups | grep -q "$sug"; then
            SUGROUP="$sug"
            printf "Super user group %s\n" "$SUGROUP"
            break
        fi
    done

    if ! groups | grep -q "$SUGROUP"; then
        print_colored "$RED" "You need to be a member of the sudo group to run me!"
        exit 1
    fi
}

install_dependencies() {
    DEPENDENCIES='bash bash-completion tar bat tree multitail fastfetch wget unzip fontconfig trash-cli'
    if ! command_exists nvim; then
        DEPENDENCIES="${DEPENDENCIES} neovim"
    fi

    print_colored "$YELLOW" "Installing dependencies..."
    case "$PACKAGER" in
        pacman)
            install_pacman_dependencies
            ;;
        nala)
            ${SUDO_CMD} ${PACKAGER} install -y ${DEPENDENCIES}
            ;;
        emerge)
            ${SUDO_CMD} ${PACKAGER} -v app-shells/bash app-shells/bash-completion app-arch/tar app-editors/neovim sys-apps/bat app-text/tree app-text/multitail app-misc/fastfetch app-misc/trash-cli
            ;;
        xbps-install)
            ${SUDO_CMD} ${PACKAGER} -v ${DEPENDENCIES}
            ;;
        nix-env)
            ${SUDO_CMD} ${PACKAGER} -iA nixos.bash nixos.bash-completion nixos.gnutar nixos.neovim nixos.bat nixos.tree nixos.multitail nixos.fastfetch nixos.pkgs.starship nixos.trash-cli
            ;;
        dnf)
            ${SUDO_CMD} ${PACKAGER} install -y ${DEPENDENCIES}
            ;;
        zypper)
            ${SUDO_CMD} ${PACKAGER} install -n ${DEPENDENCIES}
            ;;
        *)
            #Fix for Ubuntu - fastfetch not in default repos before 24.10, need PPA
            if [ -r /etc/os-release ]; then
                . /etc/os-release
                if [ "$ID" = "ubuntu" ]; then
                    # If the PPA can't be added, fall back to the upstream .deb and
                    # drop fastfetch from the apt package list so the rest still installs.
                    if ! setup_fastfetch_source; then
                        DEPENDENCIES=$(echo "${DEPENDENCIES}" | sed 's/ fastfetch//')
                    fi
                fi
            fi
            ${SUDO_CMD} ${PACKAGER} install -yq ${DEPENDENCIES}
            ;;
    esac

    install_font
}

# Install fastfetch straight from the upstream GitHub release.
# Used when Launchpad is unavailable (it regularly 500s with GPGKeyTemporarilyNotFoundError).
install_fastfetch_deb() {
    case "$(dpkg --print-architecture)" in
        amd64) ff_arch="amd64" ;;
        arm64) ff_arch="aarch64" ;;
        armhf) ff_arch="armv7l" ;;
        *)
            print_colored "$RED" "No fastfetch .deb for $(dpkg --print-architecture), skipping fastfetch"
            return 0
            ;;
    esac

    ff_url=$(curl -sL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
        | grep -o "https://[^\"]*fastfetch-linux-${ff_arch}\.deb" | head -n1)
    if [ -z "$ff_url" ]; then
        print_colored "$RED" "Couldn't find a fastfetch release asset, skipping fastfetch"
        return 0
    fi

    ff_deb=$(mktemp -d)/fastfetch.deb
    if curl -sSL -o "$ff_deb" "$ff_url" && ${SUDO_CMD} apt install -y "$ff_deb"; then
        print_colored "$GREEN" "Installed fastfetch from $ff_url"
    else
        print_colored "$RED" "fastfetch install failed, continuing without it"
    fi
    rm -rf "$(dirname "$ff_deb")"
}

# Make sure apt has a fastfetch candidate. Returns 0 if apt can install it,
# 1 if it was installed some other way (caller should drop it from the apt list).
setup_fastfetch_source() {
    if apt-cache policy fastfetch 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        return 0
    fi

    if ! grep -qs "zhangsongcui3371.*fastfetch" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        ppa_attempt=1
        while [ "$ppa_attempt" -le 3 ]; do
            if ${SUDO_CMD} add-apt-repository -y ppa:zhangsongcui3371/fastfetch; then
                break
            fi
            print_colored "$YELLOW" "add-apt-repository failed (attempt ${ppa_attempt}/3)"
            # A failed add can leave a keyless source behind that breaks apt update
            ${SUDO_CMD} rm -f /etc/apt/sources.list.d/zhangsongcui3371-ubuntu-fastfetch-*.sources
            ppa_attempt=$((ppa_attempt + 1))
            if [ "$ppa_attempt" -le 3 ]; then
                print_colored "$YELLOW" "Retrying in 10s..."
                sleep 10
            fi
        done
    fi

    ${SUDO_CMD} apt update || true

    if apt-cache policy fastfetch 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        return 0
    fi

    print_colored "$YELLOW" "fastfetch PPA unavailable, falling back to the upstream .deb"
    ${SUDO_CMD} rm -f /etc/apt/sources.list.d/zhangsongcui3371-ubuntu-fastfetch-*.sources
    ${SUDO_CMD} apt update || true
    install_fastfetch_deb
    return 1
}

install_pacman_dependencies() {
    if ! command_exists yay && ! command_exists paru; then
        printf "Installing yay as AUR helper...\n"
        ${SUDO_CMD} ${PACKAGER} --noconfirm -S base-devel
        cd /opt && ${SUDO_CMD} git clone https://aur.archlinux.org/yay-git.git && ${SUDO_CMD} chown -R "${USER}:${USER}" ./yay-git
        cd yay-git && makepkg --noconfirm -si
    else
        printf "AUR helper already installed\n"
    fi
    if command_exists yay; then
        AUR_HELPER="yay"
    elif command_exists paru; then
        AUR_HELPER="paru"
    else
        printf "No AUR helper found. Please install yay or paru.\n"
        exit 1
    fi
    ${AUR_HELPER} --noconfirm -S ${DEPENDENCIES}
}

install_font() {
    FONT_NAME="MesloLGS Nerd Font Mono"
    if fc-list :family | grep -iq "$FONT_NAME"; then
        printf "Font '%s' is installed.\n" "$FONT_NAME"
    else
        printf "Installing font '%s'\n" "$FONT_NAME"
        FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"
        FONT_DIR="$HOME/.local/share/fonts"
        if wget -q --spider "$FONT_URL"; then
            TEMP_DIR=$(mktemp -d)
            wget -q $FONT_URL -O "$TEMP_DIR"/"${FONT_NAME}".zip
            unzip "$TEMP_DIR"/"${FONT_NAME}".zip -d "$TEMP_DIR"
            mkdir -p "$FONT_DIR"/"$FONT_NAME"
            mv "${TEMP_DIR}"/*.ttf "$FONT_DIR"/"$FONT_NAME"
            # Update the font cache
            fc-cache -fv
            rm -rf "${TEMP_DIR}"
            printf "'%s' installed successfully.\n" "$FONT_NAME"
        else
            printf "Font '%s' not installed. Font URL is not accessible.\n" "$FONT_NAME"
        fi
    fi
}

install_starship_and_fzf() {
    if ! command_exists starship; then
        if ! curl -sS https://starship.rs/install.sh | sh; then
            print_colored "$RED" "Something went wrong during starship install!"
            exit 1
        fi
    else
        printf "Starship already installed\n"
    fi

    if ! command_exists fzf; then
        if [ -d "$HOME/.fzf" ]; then
            print_colored "$YELLOW" "FZF directory already exists. Skipping installation."
        else
            git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
            ~/.fzf/install
        fi
    else
        printf "Fzf already installed\n"
    fi
}

install_zoxide() {
    if ! command_exists zoxide; then
        if ! curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
            print_colored "$RED" "Something went wrong during zoxide install!"
            exit 1
        fi
    else
        printf "Zoxide already installed\n"
    fi
}

create_fastfetch_config() {
    USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    CONFIG_DIR="$USER_HOME/.config/fastfetch"
    CONFIG_FILE="$CONFIG_DIR/config.jsonc"
    
    mkdir -p "$CONFIG_DIR"
    # -e is false for a dangling symlink, so test -L as well
    if [ -e "$CONFIG_FILE" ] || [ -L "$CONFIG_FILE" ]; then rm -f "$CONFIG_FILE"; fi

    # This repo doesn't ship a config.jsonc; don't leave a symlink to nothing behind
    if [ ! -f "$GITPATH/config.jsonc" ]; then
        printf "No config.jsonc in %s, leaving fastfetch on its defaults\n" "$GITPATH"
        return 0
    fi

    if ! ln -svf "$GITPATH/config.jsonc" "$CONFIG_FILE"; then
        print_colored "$RED" "Failed to create symbolic link for fastfetch config"
        exit 1
    fi
}

link_config() {
    USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    OLD_BASHRC="$USER_HOME/.bashrc"
    BASH_PROFILE="$USER_HOME/.bash_profile"
    
    if [ -e "$OLD_BASHRC" ]; then
        print_colored "$YELLOW" "Moving old bash config file to $USER_HOME/.bashrc.bak"
        if ! mv "$OLD_BASHRC" "$USER_HOME/.bashrc.bak"; then
            print_colored "$RED" "Can't move the old bash config file!"
            exit 1
        fi
    fi

    print_colored "$YELLOW" "Linking new bash config file..."
    if ! ln -svf "$GITPATH/.bashrc" "$USER_HOME/.bashrc" || ! ln -svf "$GITPATH/starship.toml" "$USER_HOME/.config/starship.toml"; then
        print_colored "$RED" "Failed to create symbolic links"
        exit 1
    fi

    # Create .bash_profile if it doesn't exist
    if [ ! -f "$BASH_PROFILE" ]; then
        print_colored "$YELLOW" "Creating .bash_profile..."
        echo "[ -f ~/.bashrc ] && . ~/.bashrc" > "$BASH_PROFILE"
        print_colored "$GREEN" ".bash_profile created and configured to source .bashrc"
    else
        print_colored "$YELLOW" ".bash_profile already exists. Please ensure it sources .bashrc if needed."
    fi
}

# Main execution
if command_exists docker || grep -qi "proxmox" /etc/os-release 2>/dev/null; then
    echo "Docker installation found or this is a proxmox server"
else
    installDocker
fi

detect_environment
bootstrap
check_environment
install_dependencies
install_starship_and_fzf
install_zoxide
create_fastfetch_config

if link_config; then
    print_colored "$GREEN" "Done!\nrestart your shell to see the changes."
else
    print_colored "$RED" "Something went wrong!"
fi