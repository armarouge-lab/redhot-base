#!/bin/sh
# ensure-base.sh — idempotent XDG directory bootstrap (Handoff.md §4.1).
#
# Creates /etc/redhot and ~/.local/state/redhot with strict permissions,
# then seeds redhot.conf and theme.conf if they do not exist.

set -eu

systemConfigDirectory="/etc/redhot"
systemLibraryDirectory="/usr/local/lib/redhot"
systemDataDirectory="/usr/local/share/redhot"
systemHelpDirectory="/usr/local/share/redhot/help"
systemInstalledDirectory="/usr/local/share/redhot/installed"

userConfigDirectory="$HOME/.config/redhot"
userStateDirectory="$HOME/.local/state/redhot"
userDataDirectory="$HOME/.local/share/redhot"

create_system_directory() {
    directoryPath="$1"
    if [ ! -d "$directoryPath" ]; then
        mkdir -p "$directoryPath"
        chmod 0755 "$directoryPath"
        printf '[ OK ] created %s\n' "$directoryPath"
    fi
}

create_user_directory() {
    directoryPath="$1"
    if [ ! -d "$directoryPath" ]; then
        mkdir -p "$directoryPath"
        chmod 0700 "$directoryPath"
        printf '[ OK ] created %s\n' "$directoryPath"
    fi
}

create_system_directory "$systemConfigDirectory"
create_system_directory "$systemConfigDirectory/themes"
create_system_directory "$systemLibraryDirectory"
create_system_directory "$systemDataDirectory"
create_system_directory "$systemHelpDirectory"
create_system_directory "$systemInstalledDirectory"

create_user_directory "$userConfigDirectory"
create_user_directory "$userConfigDirectory/themes"
create_user_directory "$userStateDirectory"
create_user_directory "$userDataDirectory"

printf '[info] ensure-base.sh completed\n'
