#!/usr/bin/env bash
#########################################################################################################
# Linux Networking Backup Script
# netbackup.sh
# (C) 2021 - Privex Inc. - https://www.privex.io - Private servers with affordable pricing (starts at $0.99/mo)
# Written by Chris (Someguy123) @ Privex
# Released under the X11 / MIT License
#
#
# Backs up the following networking configurations:
#
#   - Firewall configs on disk - listed in BK_FILES, by default:
#       - IPTables rules.v4
#       - IPTables rules.v6
#       - IPSet Persistent config (searches in 3 different locations)
#       - Pyrewall Rules file (rules.pyre)
#
#   - In memory firewall configurations:
#       - IPTables IPv4 rules (active in memory)
#       - IPTables IPv6 rules (active in memory)
#       - IPSet rules (active in memory)
#
#   - Network interface/routing configurations on disk (BK_FILES_IFACE)
#       - Main netplan configuration ($NETPLAN_FILE), default 50-cloud-init.yaml (in /etc/netplan)
#       - ifupdown /etc/network/interfaces file
#
#   - Network interface/routing configurations in memory
#       - 'ip addr' interface address config, both command output for v4/v6, and native binary dumps
#       - 'ip route' network routing config, both command output for v4/v6, and native binary dumps
#       - 'ip rule' routing rules config, both command output for v4/v6, and native binary dumps
#
# This results in a quite thorough backup, containing both configurations that have been persisted
# to disk as a config file, AND in-memory active configurations which would normally only be ephemeral
# and could be lost on reboot.
#
# You can customise some settings without editing this file, by creating either ~/.netbackup.env
# or /etc/netbackup.env
#
# Here is an example netbackup.env file:
#
#   BACKUP_DIR=/mnt/remote/net-backups
#   QUIET=1
#   # MEMORY_BACKUP=0
#   BK_FILES_IFACE+=("/etc/netplan/60-custom.yaml")
#   BK_FILES+=("/etc/ufw")
#   NETPLAN_FILE=10-default.yaml
#
#########################################################################################################

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:${PATH}"
export PATH="${HOME}/.local/bin:/snap/bin:${PATH}"

########
# User Adjustable + Internal variable definitions
########

BK_FILES=(
  /etc/iptables/rules.v4
  /etc/iptables/rules.v6
  /etc/iptables/ipset
  /etc/iptables/ipset.conf
  /etc/ipset.conf
  /etc/pyrewall/rules.pyre
)

NB_VERSION="0.5.0"

################################
# When >0 - enables quiet mode to keep progress messages to the bare minimum
: ${QUIET=0}


################################
# When >0 - enables backing up firewall (iptables + ipset) configurations that are currently in memory
: ${MEMORY_BACKUP=1}

################################
# When >0 - enables backing up firewall configs that are on disk
: ${DISK_BACKUP=1}

################################
# When >0 - enables backing up network interface configs (both on-disk and in-memory)
: ${IFACE_BACKUP=1}



################################
# The folder to store the timestamped backups within
: ${BACKUP_DIR="${HOME}/backups/"}

################################
# The name of your primary netplan configuration (if you use netplan)
: ${NETPLAN_FILE="50-cloud-init.yaml"}


################################
# The 'date' compatible date formatting string, used to generate
# the timestamped folder name for OUT_DIR
# See 'man strftime' for a list of available datetime format characters,
# such as %Y = 4 digit year, %m = 2 digit month, %d = 2 digit day etc.
: ${DATE_FMT="%Y-%m-%d_%H.%M.%S"}


################################
# The Linux/UNIX timezone code used as the timezone for the generated
# backup timestamp.
#
# For example:
#   - 'UTC' for universal co-ordinated time (+00:00)
#   - 'Europe/London' for UK time (GMT/BST +00:00 / +01:00 DST)
#   - 'America/New_York' for US Eastern Time (EST/EDT -05:00 / -04:00 DST)
#   - 'Asia/Tokyo' for Japan Standard Time (JST +09:00 / No DST)
#
# Use the command 'tzselect' on Linux to find out the correct timezone
# code for a certain region of the world.
: ${DATE_TZ="UTC"}

# Network interface config files on disk
BK_FILES_IFACE=(
  /etc/network/interfaces
)

####
# The user might need to be able to call rfc-datetime from the .env script,
# so we make it available prior to sourcing .env
rfc-datetime() { TZ="$DATE_TZ" date +"$DATE_FMT"; }

########
# Load the user's env file if it exists. Try their homedir first, fallback to /etc
# if they don't have one in their homedir.
########
if [[ -f "${HOME}/.netbackup.env" ]]; then
  source "${HOME}/.netbackup.env"
elif [[ -f "/etc/netbackup.env" ]]; then
  source "/etc/netbackup.env"
fi

# We add the netplan config path to BK_FILES_IFACE only after we've loaded the env file, since the user
# could change NETPLAN_FILE within the .env
[[ -n "$NETPLAN_FILE" ]] && BK_FILES_IFACE+=("/etc/netplan/${NETPLAN_FILE}")
# Strip the slash from the end of BACKUP_DIR to avoid potential double slashing
BACKUP_DIR="${BACKUP_DIR%/}"


########
# Helper function definitions
########

err() { >&2 echo -e "$@"; }
qmsg() { (( QUIET )) || >&2 echo -e "$@"; }


automkdir() {
  local notfound nfcount=0
  notfound=()
  for p in "$@"; do
    if [[ ! -d "$p" ]]; then
      notfound+=("$p")
      nfcount=$(( nfcount + 1 ))
    fi
  done
  if (( nfcount == 0 )); then return 0; fi
  qmsg "    > Folder(s) ${notfound[*]} don't exist - creating them..."
  (( QUIET )) && >&2 mkdir -p "${notfound[@]}" || >&2 mkdir -vp "${notfound[@]}"
}





bkfile() {
  local fsrc="$1" fdst="$2"
  local dstdir="$(dirname "$fdst")"
  if [[ ! -f "$fsrc" && ! -d "$fsrc" ]]; then
    qmsg "     > Warning: File '${fsrc}' does not exist. Skipping..."
    return 42
  fi
  automkdir "$dstdir"

  [[ -f "$fsrc" ]] && [[ -d "$fdst" ]] && fdst="${fdst%/}/"
  [[ -d "$fsrc" ]] && [[ -d "$fdst" ]] && fsrc="${fsrc%/}/" fdst="${fdst%/}/"

  (( QUIET )) && rflags="-aqL" || rflags="-avhL"
  >&2 rsync "$rflags" "$fsrc" "$fdst"
}

########
# Basic initialisation - create the backup folder if needed, generate a timestamped folder to hold this
# backup round, and define some dynamic path variables based on the user specified backup folder.
########

NOTICE_OUTL="+=======================================================+"
NOTICE_PADL="#                                                       #"
VER_CPC="# Linux Net CFG Backup (netbackup.sh) VER v${NB_VERSION}        #"

VER_NOTICE="# Linux Network Config Backup Script                    #
# (aka netbackup.sh)                                    #
#                                                       #
# Version v${NB_VERSION}                                        #"

COPY_NOTICE="# (C) 2021 Privex Inc. - https://www.privex.io/         #
# BUY A SERVER TODAY - PRIVEX MAKES PRIVACY AFFORABLE!  #
# VPS's from \$0.99/mo - Dedi's from \$40/mo              #
# We take: BTC LTC BCH EOS DOGE XMR HIVE HBD + others   #"


LICENSE_NOTICE="# Official Repo: https://github.com/Privex/netbackup    #
# Released under X11 / MIT License                      #"

FULL_NOTICE="
$NOTICE_OUTL
$NOTICE_PADL
$VER_NOTICE
$NOTICE_PADL
$COPY_NOTICE
$NOTICE_PADL
$LICENSE_NOTICE
$NOTICE_PADL
$NOTICE_OUTL
"

MIN_NOTICE="$NOTICE_OUTL
$NOTICE_PADL
$VER_CPC
$NOTICE_PADL
$COPY_NOTICE
$LICENSE_NOTICE
$NOTICE_PADL
$NOTICE_OUTL
"

err "$FULL_NOTICE"

# Auto-create the backup folder if it doesn't yet exist, then enter it.
automkdir "$BACKUP_DIR"
cd "$BACKUP_DIR"

# Get the current UTC date + time in a filename safe format, create a folder with that datetime as it's name,
# store the path, and enter the folder.
: ${BK_NAME="$(rfc-datetime)"}
mkdir "$BK_NAME"
cd "$BK_NAME"

: ${OUT_DIR="$(pwd)"}
if [[ "$(pwd)" != "$OUT_DIR" ]]; then cd "$OUT_DIR"; fi

qmsg " >>> Backing up to timestamped folder: $OUT_DIR"

# We create aliases to ipt/memory, ipt/disk, and ifaces for easy and stable referencing, and then
# create their folder structures if needed.
xdir_mem="${PWD}/ipt/memory" xdir_disk="${PWD}/ipt/disk" xdir_ifaces="${PWD}/ifaces"
automkdir "$xdir_mem" "$xdir_disk" "$xdir_ifaces"

########
# Backup in-memory firewall rules (ipset + iptables) if MEMORY_BACKUP > 0
########
if (( MEMORY_BACKUP )); then
  qmsg "    >>> Backing up iptables / ipset currently in memory to $xdir_mem"
  qmsg "        --> Backing up iptables v4"
  iptables-save > "${xdir_mem}/rules.v4"
  qmsg "        --> Backing up iptables v6"
  ip6tables-save > "${xdir_mem}/rules.v6"
  qmsg "        --> Backing up ipset"
  ipset save > "${xdir_mem}/ipset.conf"
  qmsg "\n [+++] Finished backing up in-memory iptables + ipset :)\n"
fi
qmsg "\n"

########
# Backup on-disk firewall rules (ipset + iptables) if DISK_BACKUP > 0
########
if (( DISK_BACKUP )); then
  qmsg "    >>> Backing up config files already on disk:\n"
  for f in "${BK_FILES[@]}"; do
    qmsg "      * $f"
  done
  qmsg "\n"
  for f in "${BK_FILES[@]}"; do
    fdname="$(basename "$f")"
    qmsg "      > Backing up: $f    to: ${xdir_disk%/}/${fdname}"
    bkfile "$f" "${xdir_disk}/${fdname}"
  done
  qmsg "\n [+++] Finished backing up config files already on disk :)\n"
fi

########
# Backup both in-memory and on-disk network configurations if IFACE_BACKUP > 0
########
if (( IFACE_BACKUP )); then
  ######## Create the folders we plan to use to store the various types of network configs ########
  qmsg "    >>> Backing up general network configs (netplan/ifupdown) on disk + in memory to $xdir_ifaces"
  qmsg "      > Entering folder: $xdir_ifaces"
  cd "${xdir_ifaces}"

  automkdir "dump" "log" "disk"
  cd log
  automkdir "all" "v4" "v6"
#  cd ../log
#  automkdir "all" "v4" "v6"
  cd ..

  ######## Copy the files listed in BK_FILES_IFACE into the disk folder of the interfaces backup dir ########
  qmsg "      > Backing up config files listed in BK_FILES_IFACE into ${xdir_ifaces}/disk/"
  qmsg "\n"
  for f in "${BK_FILES_IFACE[@]}"; do
    fdname="$(basename "$f")"
    qmsg "        --> Backing up: $f    to: disk/${fdname}"
    bkfile "$f" "disk/${fdname}"
  done
  qmsg "\n [+++] Finished backing up interface configs on disk :)\n"

  qmsg "\n"

  ######## Create and output binary dumps of in-memory network configurations (addresses/routes/rules) ########
  qmsg "      > Generating binary network configuration dumps into ${xdir_ifaces}/dump/"
  qmsg "        These can be viewed with 'ip route|rule|addr showdump < dump.bin' respectively, and"
  qmsg "        restored using 'ip route|rule|addr restore < dump.bin' \n"

  cd "${xdir_ifaces}/dump/"
  qmsg "          --> Dumping IPv4 routes in binary dump format using 'ip -4 route save'    to: ${xdir_ifaces}/dump/routes_v4.bin"
  ip -4 route save > routes_v4.bin
  qmsg "          --> Dumping IPv6 routes in binary dump format using 'ip -6 route save'    to: ${xdir_ifaces}/dump/routes_v6.bin"
  ip -6 route save > routes_v6.bin
  qmsg "          --> Dumping IPv4 rules in binary dump format using 'ip -4 rule save'    to: ${xdir_ifaces}/dump/rules_v4.bin"
  ip -4 rule save > rules_v4.bin
  qmsg "          --> Dumping IPv6 rules in binary dump format using 'ip -6 rule save'    to: ${xdir_ifaces}/dump/rules_v6.bin"
  ip -6 rule save > rules_v6.bin
  qmsg "          --> Dumping IPv4 address config in binary dump format using 'ip -4 addr save'    to: ${xdir_ifaces}/dump/addrs_v4.bin"
  ip -4 addr save > addrs_v4.bin
  qmsg "          --> Dumping IPv6 address config in binary dump format using 'ip -6 addr save'    to: ${xdir_ifaces}/dump/addrs_v6.bin"
  ip -6 addr save > addrs_v6.bin

  ######## Create and output command output logs of in-memory network configurations (addresses/routes/rules) ########

  qmsg "\n      > Generating command output based network configuration logs into ${xdir_ifaces}/log/"
  qmsg "        Unlike the binary dumps, these generally can't be 'restored' directly, they're more like"
  qmsg "        a 'photo' of your configuration, to help you reproduce individual pieces of the config"
  qmsg "        or simply understand how it was setup in the past.\n"

  cd "${xdir_ifaces}/log/"
  qmsg "      > Dumping 'ip addr'    to: ${PWD}/ip_addr.txt"
  ip addr > "ip_addr.txt"
  qmsg "      > Dumping 'ip route'    to: ${PWD}/ip_route.txt"
  ip route > "ip_route.txt"

  cd "${xdir_ifaces}/log/v4"
  qmsg "      > Dumping 'ip -4 route'    to: ${PWD}/ip_route.txt"
  ip -4 route > "ip_route.txt"

  cd ../v6
  qmsg "      > Dumping 'ip -6 route'    to: ${PWD}/ip_route.txt"
  ip -6 route > "ip_route.txt"

  cd ../all
  qmsg "      > Dumping 'ip route show all'    to: ${PWD}/ip_route_all.txt"
  ip route show all > "ip_route_all.txt"

  cd ../v4
  qmsg "      > Dumping 'ip -4 route show all'    to: ${PWD}/ip_route_all.txt"
  ip -4 route show all > "ip_route_all.txt"

  cd ../v6
  qmsg "      > Dumping 'ip -6 route show all'    to: ${PWD}/ip_route_all.txt"
  ip -6 route show all > "ip_route_all.txt"

  qmsg "\n [+++] Finished backing up in-memory network configurations as both binary dumps and huamn readable command output logs :)\n"

fi

########
# All done :) - now we just print the output folder for the user's reference, and exit cleanly.
########

err "$MIN_NOTICE"

qmsg "\n ====================================================================================== \n"
qmsg "\n [+++] FULLY FINISHED - Everything requested should now have been backed up :)\n"
qmsg "\n ====================================================================================== \n"

echo -e "Output folder:"
echo -e "$OUT_DIR"

