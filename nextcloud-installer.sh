#!/bin/bash

set -euo pipefail

# ============================================================================= #
#  								 Initialization  								#
# ============================================================================= #
init_constants() {
	readonly REPOS_NAME="nextcloud-releases/desktop"
	readonly FILE_NAME="nextcloud"
	readonly INSTALL_PATH="/usr/local/bin"
}

init_variables() {
	RELEASE_VERSION=""
	CURRENT_VERSION=""
	FORCE_DOWNLOAD=false
	USE_PRERELEASE=false
	PRERELEASE_VERSION=""
}

init_colors() {
	COLOR_RED=""
	COLOR_GREEN=""
	COLOR_YELLOW=""
	COLOR_BLUE=""
	COLOR_MAGENTA=""
	COLOR_CYAN=""
	COLOR_RESET=""
	BOLD=""

	if ! command -v tput >/dev/null 2>&1; then
		warning "'tput' is not installed. Terminal colors will be disabled."
		return
	fi

	if ! tput setaf 1 >/dev/null 2>&1; then
		warning "Terminal does not support colors. Colored output will be disabled."
		return
	fi

	local USER_THEME=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
	
	case "${USER_THEME}" in
		prefer-dark)
			COLOR_RED=$(tput setaf 9)
			COLOR_GREEN=$(tput setaf 10)
			COLOR_YELLOW=$(tput setaf 11)
			COLOR_BLUE=$(tput setaf 12)
			COLOR_MAGENTA=$(tput setaf 13)
			COLOR_CYAN=$(tput setaf 14)
		;;
		default | *)
			COLOR_RED=$(tput setaf 1)
			COLOR_GREEN=$(tput setaf 2)
			COLOR_YELLOW=$(tput setaf 3)
			COLOR_BLUE=$(tput setaf 4)
			COLOR_MAGENTA=$(tput setaf 5)
			COLOR_CYAN=$(tput setaf 6)
		;;
	esac

	COLOR_RESET=$(tput sgr0)
  	BOLD=$(tput bold)
}

# ============================================================================= #
# 										UI 										#
# ============================================================================= #
print() {
	echo -e "$@";
}

show_logo() {
	print "${COLOR_BLUE}"
	print " _   _           _       _                 _ "
	print "| \\ | | _____  _| |_ ___| | ___  _   _  __| |"
	print "|  \\| |/ _ \\ \\/ / __/ __| |/ _ \\| | | |/ _\` |"
	print "| |\\  |  __/>  <| || (__| | (_) | |_| | (_| |"
	print "|_| \\_|\\___/_/\\_\\__\\____|_|\\___/ \\__,_|\\__,_|"
	print ""
	print "Linux Installer and Updater"
	print "${COLOR_RESET}"
}

show_help() {
	bold "${COLOR_BLUE}Nextcloud Updater (Linux)${COLOR_RESET}"
	print ""
	info "This script installs or updates Nextcloud Desktop client."
	info "The latest release is downloaded from GitHub and saved to: ${BOLD}${INSTALL_PATH}${COLOR_RESET}."
	info "The script also sets the appropriate permissions for the file to be executable."
	print ""
	warning "Make sure installation directory ${BOLD}${INSTALL_PATH}${COLOR_RESET}${COLOR_YELLOW} is correct and exists before running the script."
	warning "This directory must be in the PATH variable to be able to launch the application from the terminal."
	print ""
	print "Usage:"
	print "    nextcloud-installer [options]"
	print ""
	print "Behavior:"
	print "    If no options are provided, the latest version will be installed."
	print ""
	print "Options:"
	print "    --help, -h"
	print "				Show this help message"
	print "    --release, -r <version>"
	print "				Install a specific stable version"
	print "    --prerelease, -p <version>"
	print "				Install latest or a specific prerelease version"
	print "    --force, -f"
	print "				Force re-download even if version is already installed"
	print "    --uninstall, -u"
	print "				Remove Nextcloud Desktop from the system"
	print ""
	print "Examples:"
	print "    nextcloud-installer -h"
	print "    nextcloud-installer"
	print "    nextcloud-installer -r 33.0.5"
	print "    nextcloud-installer -p 34.0.0-rc1"
	print "    nextcloud-installer --prerelease 34.0.0-rc1"
	print "    nextcloud-installer --force"
	print "    nextcloud-installer --uninstall"
	print ""
	exit 0
}

error() {
	print "${COLOR_RED}[ERROR] $1${COLOR_RESET}";
}

warning() {
	print "${COLOR_YELLOW}[WARN] $1${COLOR_RESET}"
}

info() {
	print "${COLOR_BLUE}[INFO] $1${COLOR_RESET}"
}

success() {
	print "${COLOR_GREEN}[SUCCESS] $1${COLOR_RESET}"
}

check() {
	print "${COLOR_CYAN}[CHECK] $1${COLOR_RESET}"
}

action() {
	print "${COLOR_MAGENTA}[ACTION] $1${COLOR_RESET}"
}

question() {
	print -ne "$1[QUESTION] $2${COLOR_RESET}"
}

bold() {
	print "${BOLD}$1${COLOR_RESET}"
}

fail() {
	print "${COLOR_RED}[FAIL] $1${COLOR_RESET}"
}

# ============================================================================= #
# 									System check 								#
# ============================================================================= #
check_required_commands() {
	local MISSING_COMMANDS=()

	for cmd in "$@"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			MISSING_COMMANDS+=("${cmd}")
		fi
	done

	if [ ${#MISSING_COMMANDS[@]} -ne 0 ]; then
		error "Missing required command(s): ${MISSING_COMMANDS[*]}"
		exit 1
	fi
}

check_dependencies() {
	check_required_commands sudo jq grep sed awk sha256sum pkill sleep gsettings stat
}

check_install_path() {
	if [ ! -d "${INSTALL_PATH}" ]; then
		error "${INSTALL_PATH} does not exist. Please create it and run the script again."
		print ""
		info "nextcloud-installer -h for more information."
		print  ""
		exit 1
	fi
}

determine_download_command() {
	if command -v wget2 >/dev/null; then
		DOWNLOAD_CMD="wget2 -q -O"
		HEAD_CMD="wget2 --spider -q"
		info "Using wget2 for download."
		print""
		return
	fi

	if command -v wget >/dev/null; then
		DOWNLOAD_CMD="wget -q -O"
		HEAD_CMD="wget --spider -q -I -O"
		info "Using wget for download."
		print""
		return
	fi

	if command -v curl >/dev/null; then
		DOWNLOAD_CMD="curl -L -s"
		HEAD_CMD="curl -fsI"
		info "Using curl for download."
		print""
		return
	fi

	error "No supported download tool found."
	info "Please install one of the following:"
	print "${COLOR_BLUE} - wget2"
	print " - wget"
	print " - curl"
	print "${COLOR_RESET}"
	exit 1
}

# ============================================================================= #
# 								Version control 								#
# ============================================================================= #
get_installed_version() {
	action "Checking installed Nextcloud Desktop version..."
	if [ -f ${INSTALL_PATH}/${FILE_NAME} ]; then
		CURRENT_VERSION=$(nextcloud --version 2>/dev/null | grep -oP '(?<=version )[^ ]+' || true)
		if [[ -z "${CURRENT_VERSION}" ]]; then
			current_version=$(stat -c %y "${INSTALL_PATH}/${FILE_NAME}" | cut -d ' ' -f1 | tr -d '-')
			info "Installed version could not be determined. Using file modification date as version: ${current_version}"
		fi
	fi
	if [ -z "${CURRENT_VERSION}" ]; then
		info "No installed version detected."
	else
		info "Installed version detected: v${CURRENT_VERSION}"
	fi
	print ""
}

get_latest_version() {
	local LATEST_VERSION=$(
			$DOWNLOAD_CMD - "https://api.github.com/repos/${REPOS_NAME}/releases/latest" | \
			jq -r '.tag_name'
		)
	
	if [ -z "${LATEST_VERSION}" ]; then
		fail "Failed to fetch latest version."
		exit 1
	fi
	echo "${LATEST_VERSION}"
}

get_latest_prerelease_version() {
	local LATEST_PRERELEASE_VERSION=$(
			$DOWNLOAD_CMD - "https://api.github.com/repos/${REPOS_NAME}/releases" | \
			jq -r '[.[] | select(.prerelease == true)] | sort_by(.published_at) | reverse | .[0].tag_name' | \
			tr -d '[:space:]'
		)

	if [[ -z "$LATEST_PRERELEASE_VERSION" ]]; then
		print ""
		fail "Failed to fetch latest prerelease version." 
		fail "Check your internet connection or GitHub API status." 
		fail "Try specifying a version with --release." 
		fail "Ensure prereleases exist for this repo."
	fi
	echo "${LATEST_PRERELEASE_VERSION}"
}

get_target_version() {
	if [ -n "${RELEASE_VERSION}" ]; then
		info "Using requested version: ${RELEASE_VERSION}"
		return
	fi

	if [ "${USE_PRERELEASE}" == true ]; then
		if [ -n "${PRERELEASE_VERSION}" ]; then
			RELEASE_VERSION="${PRERELEASE_VERSION}"
			info "Using requested prerelease version: ${RELEASE_VERSION}"
		else
			action "Fetching latest prerelease from Github..."
			RELEASE_VERSION=$(get_latest_prerelease_version)
		fi
	else
		action "Fetching latest version from Github..."
		RELEASE_VERSION=$(get_latest_version)
	fi
	info "Target version: ${RELEASE_VERSION}"
	print ""
}

handle_already_up_to_date() {
	if [ "${RELEASE_VERSION}" != "v${CURRENT_VERSION}" ]; then
		return
	fi

	if [ "${FORCE_DOWNLOAD}" == true ]; then
		return
	fi

	info "Nextcloud Desktop is already up to date."
	question "${COLOR_YELLOW}" "Do you want to reinstall it ? (Y/[N]):"
	read -r REP
	if [ "$REP" == "y" ] || [ "$REP" == "Y" ]; then
		info "Reinstalling Nextcloud Desktop..."
		print ""
		return
	fi
	info "Exiting without changes."
	exit 0
}

# ============================================================================= #
# 								URL / Files management 							#
# ============================================================================= #
build_download_url() {
	GITHUB_URL="https://github.com/${REPOS_NAME}/releases/download/${RELEASE_VERSION}/Nextcloud-${RELEASE_VERSION#v}-x86_64.AppImage"
}

build_appimage_name() {
	APP_IMAGE="${FILE_NAME}-${RELEASE_VERSION#v}-x86_64.AppImage"
}

download_release() {
	action "Downloading Nextcloud file at: ${GITHUB_URL}"
	if ! $HEAD_CMD "${GITHUB_URL}" > /dev/null; then
		error "Version ${RELEASE_VERSION} not found. Please check the version number and try again."
		exit 1
	fi
	$DOWNLOAD_CMD "${APP_IMAGE}" -q --show-progress "${GITHUB_URL}"
}

# ============================================================================= #
# 									Check sum 									#
# ============================================================================= #
fetch_expected_checksum() {
	local EXPECTED_CHECKSUM=$(
		$DOWNLOAD_CMD - "https://api.github.com/repos/${REPOS_NAME}/releases/tags/${RELEASE_VERSION}" | \
		jq -r --arg name "Nextcloud-${RELEASE_VERSION#v}-x86_64.AppImage" \
		'.assets[] | select(.name==$name) | .digest' |
		sed 's/sha256://'
	)
	echo "${EXPECTED_CHECKSUM}"
}

calculate_actual_checksum() {
	local ACTUAL_CHECKSUM=$(sha256sum "${APP_IMAGE}" | awk '{print $1}')
	echo "${ACTUAL_CHECKSUM}"
}

verify_checksum() {
	info "Starting checksum verification..."
	action "Fetching expected checksum from Github..."
	local EXPECTED_CHECKSUM=""
	EXPECTED_CHECKSUM=$(fetch_expected_checksum)
	action "Calculating actual checksum of the downloaded file..."
	local ACTUAL_CHECKSUM=""
	ACTUAL_CHECKSUM=$(calculate_actual_checksum)

	if [ -z "${EXPECTED_CHECKSUM}" ]; then
		warning "Expected checksum not found. Skipping verification."
	elif [ "${ACTUAL_CHECKSUM}" = "${EXPECTED_CHECKSUM}" ]; then
		success "Checksum verification passed."
	else
		error "Checksum verification failed!"
		error "Expected: ${EXPECTED_CHECKSUM}"
		error "Actual:   ${ACTUAL_CHECKSUM}"
		error "Please try again"
		print ""
		exit 1
	fi
	success "Download completed"
	print""
}

# ============================================================================= #
# 								Nextcloud management 							#
# ============================================================================= #
stop_nextcloud() {
	action "Stopping Nextcloud..."
	local current_pid=$$

	for pid in $(pgrep -x ${FILE_NAME}); do
		kill "$pid" >/dev/null
		sleep 1
	done

	for pid in $(pgrep -x AppRun); do
		kill "${pid}" >/dev/null
		sleep 1
	done
}

start_nextcloud() {
	action "Starting Nextcloud..."
	"${INSTALL_PATH}/${FILE_NAME}" &
	sleep 2
}

restart_nextcloud() {
	local TO_DO
	if [ -z "${CURRENT_VERSION}" ]; then
		TO_DO="Start"
	else
		TO_DO="Restart"
	fi
	print ""
	question "${COLOR_YELLOW}" "${TO_DO} Nextcloud now ? ([Y]/N):"
	read -r REP
	if [ -z "$REP" ] || [ "$REP" == "y" ] || [ "$REP" == "Y" ]; then
		if [ ! -z "${CURRENT_VERSION}" ]; then
			stop_nextcloud
		fi
		start_nextcloud
	fi
}

uninstall_nextcloud() {
	if [ ! -f "${INSTALL_PATH}/${FILE_NAME}" ]; then
		error "Nextcloud Desktop is not installed at ${INSTALL_PATH}/${FILE_NAME}."
		exit 1
	fi
	warning "This action will completely remove Nextcloud Desktop from your system."

	question "${COLOR_RED}" "Do you really want to continue ? (Y/[N]):"
	read -r REP
	if [ "$REP" == "y" ] || [ "$REP" == "Y" ]; then
		info "Uninstalling Nextcloud Desktop..."
		stop_nextcloud
		sudo rm -f "${INSTALL_PATH}/${FILE_NAME}"
		if command -v "$FILE_NAME" >/dev/null 2>&1; then
			error "An error occured while uninstalling Nexcloud Dektop."
			exit 1
		fi
		success "Nextcloud Desktop uninstalled successfully."
		exit 0
	else
		info "Exiting without changes."
		exit 0
	fi
}

# ============================================================================= #
# 								Installation 									#
# ============================================================================= #
move_binary() {
	info "Installing Nextcloud at: ${INSTALL_PATH}/${APP_IMAGE}"
	sudo mv "${APP_IMAGE}" "${INSTALL_PATH}/${FILE_NAME}"
	success "File moved successfully"
	print ""
}

set_permissions() {
	action "Change owner and set execute permissions..."
	PS4="${COLOR_MAGENTA}+"
	set -x
	sudo chown root:root "${INSTALL_PATH}/${FILE_NAME}"
	sudo chmod +x "${INSTALL_PATH}/${FILE_NAME}"
	set +x
	success "Permissions updated"
	print ""
}

verify_installation() {
	action "Checking installation file..."

	if [ ! -f "${INSTALL_PATH}/${FILE_NAME}" ]; then
		fail "File not found at: ${INSTALL_PATH}/${FILE_NAME}"
		exit 1
	fi
	check "File ${FILE_NAME} exists at ${INSTALL_PATH}"

	if [ ! -x "${INSTALL_PATH}/${FILE_NAME}" ]; then
		fail "File is not executable"
		exit 1
	fi
	check "File ${FILE_NAME} is executable"


	local UID_FILE=$(stat --format="%U" "${INSTALL_PATH}/${FILE_NAME}" | tr -d '[:space:]')
	if [ "${UID_FILE}" != "root" ]; then
		fail "Incorrect owner. Expected 'root', fond ${UID_FILE}"
		exit 1
	fi
	check "Correct owner: ${UID_FILE}"

	local GID_FILE=$(stat --format="%G" "${INSTALL_PATH}/${FILE_NAME}" | tr -d '[:space:]')
	if [ "${GID_FILE}" != "root" ]; then
		fail "Incorrect group. Expected 'root', found ${GID_FILE}"
		exit 1
	fi
	check "Correct group: ${GID_FILE}"

	success "Installation verified"
	print ""
}

# ============================================================================= #
# 								Parse arguments 								#
# ============================================================================= #
parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
			-h | --help) show_help;;
			-r | --release)
				if [[ -z "${2:-}" ]]; then
					error "Option $1 requires a version argument."
					exit 1
				fi
				RELEASE_VERSION="v$2"
				shift 2
				continue
				;;
			--release=*)
				RELEASE_VERSION="v${1#*=}"
				shift
				continue
				;;
			--prerelease | -p)
				USE_PRERELEASE=true
				if [[ -z "${2:-}" ]]; then
					break
				fi
				PRERELEASE_VERSION="v$2"
				shift 2
				continue
				;;
			--prerelease=*)
				PRERELEASE_VERSION="${1#*=}"
				if [[ -z "${PRERELEASE_VERSION}" ]]; then
					error "Missing version argument for --prerelease."
					info "Use -h or --help for usage."
					exit 1
				fi
				PRERELEASE_VERSION="v${PRERELEASE_VERSION#v}"
				USE_PRERELEASE=true
				shift
				continue
				;;
			-f | --force)
				FORCE_DOWNLOAD=true
				shift
				continue
				;;
			-u | --uninstall) uninstall_nextcloud;;
			--)
				shift
				break
				;;
			*)
				error "Unknow option: $1"
				info "Use -h or --help for usage."
				print""
				exit 1
				;;

		esac
		shift
	done
}

# ============================================================================= #
# 									Main 										#
# ============================================================================= #
main() {
	init_constants
	init_variables
	init_colors

	show_logo

	parse_arguments "$@"
	check_dependencies
	check_install_path
	determine_download_command

	get_installed_version
	get_target_version
	handle_already_up_to_date

	build_download_url
	build_appimage_name

	download_release
	verify_checksum

	move_binary
	set_permissions
	verify_installation

	restart_nextcloud

	success "Done..."
	print ""	
}

main "$@"