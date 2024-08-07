#!/bin/bash

RC='\e[0m'
RED='\e[31m'
YELLOW='\e[33m'
GREEN='\e[32m'

# Check if the home directory and linuxtoolbox folder exist, create them if they don't
LINUXTOOLBOXDIR="$HOME/linuxtoolbox"

if [[ ! -d "$LINUXTOOLBOXDIR" ]]; then
    echo -e "${YELLOW}Creating linuxtoolbox directory: $LINUXTOOLBOXDIR${RC}"
    mkdir -p "$LINUXTOOLBOXDIR"
    echo -e "${GREEN}linuxtoolbox directory created: $LINUXTOOLBOXDIR${RC}"
fi

if [[ ! -d "$LINUXTOOLBOXDIR/mybash" ]]; then
    echo -e "${YELLOW}Cloning mybash repository into: $LINUXTOOLBOXDIR/mybash${RC}"
    git clone https://github.com/swedishstyle/mybash "$LINUXTOOLBOXDIR/mybash"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Successfully cloned mybash repository${RC}"
    else
        echo -e "${RED}Failed to clone mybash repository${RC}"
        exit 1
    fi
fi

cd "$LINUXTOOLBOXDIR/mybash"

command_exists() {
    command -v $1 >/dev/null 2>&1
}

installDocker() {
    #Docker install script
    sh <(curl -sSL https://get.docker.com)

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

checkEnv() {
    ## Check for requirements.
    REQUIREMENTS='curl groups sudo'
    if ! command_exists ${REQUIREMENTS}; then
        echo -e "${RED}To run me, you need: ${REQUIREMENTS}${RC}"
        exit 1
    fi

    ## Check Package Handeler
    PACKAGEMANAGER='apt yum dnf pacman zypper'
    for pgm in ${PACKAGEMANAGER}; do
        if command_exists ${pgm}; then
            PACKAGER=${pgm}
            echo -e "Using ${pgm}"
        fi
    done

    if [ -z "${PACKAGER}" ]; then
        echo -e "${RED}Can't find a supported package manager"
        exit 1
    fi

    ## Check if the current directory is writable.
    GITPATH="$(dirname "$(realpath "$0")")"
    if [[ ! -w ${GITPATH} ]]; then
        echo -e "${RED}Can't write to ${GITPATH}${RC}"
        exit 1
    fi

    ## Check SuperUser Group
    SUPERUSERGROUP='wheel sudo root'
    for sug in ${SUPERUSERGROUP}; do
        if groups | grep ${sug}; then
            SUGROUP=${sug}
            echo -e "Super user group ${SUGROUP}"
        fi
    done

    ## Check if member of the sudo group.
    if ! groups | grep ${SUGROUP} >/dev/null; then
        echo -e "${RED}You need to be a member of the sudo group to run me!"
        exit 1
    fi
}

installDepend() {
	local dtype="unknown"  # Default to unknown
    ARCH=$(uname -m)

	# Use /etc/os-release for modern distro identification
	if [ -r /etc/os-release ]; then
		source /etc/os-release
		case $ID in
			fedora|rhel|centos)
				dtype="redhat"
				;;
			sles|opensuse*)
				dtype="suse"
				;;
			debian)
				dtype="debian"
				;;
            ubuntu)
				dtype="ubuntu"
                
                case "$ARCH" in
                    x86_64)
                        fastfetch_ppa="ppa:zhangsongcui3371/fastfetch"
                        if ! grep -q "^deb .*$fastfetch_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
                            sudo add-apt-repository ppa:zhangsongcui3371/fastfetch
                            sudo ${PACKAGER} update
                        fi
                        ;;
                    arm* | aarch64)
                        FASTFETCH_URL=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep "browser_download_url.*linux-armvhf.deb" | cut -d '"' -f 4)
			
                        # Download the latest fastfetch deb file
                        curl -sL $FASTFETCH_URL -o /tmp/fastfetch_latest_armvhf.deb
                        
                        # Install the downloaded deb file using apt-get
                        sudo apt-get install /tmp/fastfetch_latest_armvhf.deb
                        ;;
                    *)
                        echo "Unknown architecture: $ARCH"
                        # Add a fallback command or an error message here
                        ;;
                esac
				;;
			gentoo)
				dtype="gentoo"
				;;
			arch)
				dtype="arch"
				;;
			slackware)
				dtype="slackware"
				;;
			*)
				# If ID is not recognized, keep dtype as unknown
				;;
		esac
	fi

    ## Check for dependencies.
    DEPENDENCIES='bash bash-completion tar tree multitail fastfetch tldr trash-cli'
    echo -e "${YELLOW}Installing dependencies...${RC}"
    if [[ $PACKAGER == "pacman" ]]; then
        if ! command_exists yay && ! command_exists paru; then
            echo "Installing yay as AUR helper..."
            sudo ${PACKAGER} --noconfirm -S base-devel
            cd /opt && sudo git clone https://aur.archlinux.org/yay-git.git && sudo chown -R ${USER}:${USER} ./yay-git
            cd yay-git && makepkg --noconfirm -si
        else
            echo "Aur helper already installed"
        fi
        if command_exists yay; then
            AUR_HELPER="yay"
        elif command_exists paru; then
            AUR_HELPER="paru"
        else
            echo "No AUR helper found. Please install yay or paru."
            exit 1
        fi
        ${AUR_HELPER} --noconfirm -S ${DEPENDENCIES}
    else
        sudo ${PACKAGER} install -yq ${DEPENDENCIES}
    fi
}

installStarship() {
    if command_exists starship; then
        echo "Starship already installed"
        return
    fi

    if ! curl -sS https://starship.rs/install.sh | sh; then
        echo -e "${RED}Something went wrong during starship install!${RC}"
        exit 1
    fi
    if command_exists fzf; then
        echo "Fzf already installed"
    else
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        ~/.fzf/install
    fi
}

installZoxide() {
    if command_exists zoxide; then
        echo "Zoxide already installed"
        return
    fi

    if ! curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
        echo -e "${RED}Something went wrong during zoxide install!${RC}"
        exit 1
    fi
}

linkConfig() {
    ## Get the correct user home directory.
    USER_HOME=$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)
    ## Check if a bashrc file is already there.
    OLD_BASHRC="${USER_HOME}/.bashrc"
    if [[ -e ${OLD_BASHRC} ]]; then
        echo -e "${YELLOW}Moving old bash config file to ${USER_HOME}/.bashrc.bak${RC}"
        if ! mv ${OLD_BASHRC} ${USER_HOME}/.bashrc.bak; then
            echo -e "${RED}Can't move the old bash config file!${RC}"
            exit 1
        fi
    fi

    echo -e "${YELLOW}Linking new bash config file...${RC}"
    ## Make symbolic link.
    ln -svf ${GITPATH}/.bashrc ${USER_HOME}/.bashrc

    #Create .config folder if it does not exist
    mkdir -p ${USER_HOME}/.config

    ln -svf ${GITPATH}/starship.toml ${USER_HOME}/.config/starship.toml
}

checkEnv

if command -v docker &> /dev/null; then
    echo "Docker installation found"
else
    installDocker
fi

installDepend
installStarship
installZoxide

if linkConfig; then
    echo -e "${GREEN}Done!\nrestart your shell to see the changes.${RC}"
else
    echo -e "${RED}Something went wrong!${RC}"
fi