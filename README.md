# Privex Linux/UNIX Network Configuration Backup Script ( netbackup.sh )

(C) 2021 - Privex Inc. - https://www.privex.io - Private servers with affordable pricing (starts at $0.99/mo)

Written by Chris (Someguy123) @ Privex

Released under the X11 / MIT License

## What is this script, what does it do, and why?

This is a self-contained BASH script which is designed to thoroughly backup your network configurations
on Linux, which are generally spread out between various configuration files across your filesystem,
and several different tools used to manage your active configuration in memory.

It backs up both network + firewall configurations stored on your filesystem, AND it also backs up
the configurations currently active in your kernel's memory, which may not be safely persisted to disk.

Currently it supports backing up:

- **IPTables** - the native firewall system for Linux
- **IPSet** - often used alongside IPTables to manage lists of IPs / ports for whitelisting/blacklisting
- **iproute2** - the network toolkit that provides the versatile `ip` command
- **netplan** - the default network manager for Ubuntu 18.04, 20.04 and newer
- **ifupdown** - the default network manager for older versions of Ubuntu, as well as all versions of Debian, and many other Linux distros.
- [Pyrewall](https://github.com/Privex/pyrewall) - The firewall management system (overlay for iptables) developed by us - Privex Inc. :)
- Anything else not listed above which uses normal config files on disk, as you can simply add any extra
  network / firewall configs to the `BK_FILES` / `BK_FILES_IFACE` array via an ENV file, and they'll
  be backed up alongside the systems supported out of the box.

## Quickstart / Install / Use

Clone the repo and enter the folder:

```sh
git clone https://github.com/Privex/netbackup.git
cd netbackup
```

(Optional) Create an ENV file to change the backup folder from the default of `$HOME/backups` if you want.

```sh
echo 'BACKUP_DIR="/mnt/my-backups"' >> ~/.netbackup.env
```

Simply run the `netbackup.sh` script as root, either by running it while logged in as root,
or using an elevation tool such as `sudo` / `su`:

```sh
# NOTE! By default, 'sudo' will carry over your user's HOME env var, which means
# it will read your user's ~/.netbackup.env config, AND if your BACKUP_DIR relies on $HOME
# (e.g. the default $HOME/backups), then it will also backup with the home dir of the user
# that you're running 'sudo' as.
sudo ./netbackup.sh

# If you need/want to run the script under a normal user with root elevation via sudo,
# but you want the script to use root's HOME instead of your user's, you can use the '-H' flag,
# which disables HOME passthru:
sudo -H ./netbackup.sh
```

## Regular Backups (cron timed backups)

For regular backups of your network configuration, we recommend using `crontab` as root:

```sh
sudo su -
crontab -e
```

Here's an example crontab which runs netbackup.sh every hour at the 30 minute mark (xx:30):


```sh
#  m   h    dom mon dow    command
   30  *    *   *   *      /root/netbackup/netbackup.sh
```

## Installing the script globally

If you want to be able to run `netbackup` from anywhere on your system, e.g. to immediately make a full
backup of your network configurations before/after making changes to your networking setup, as the script
is self contained, it's very easy to do so.

On most systems, you should be able to simply use the `install` command, which will copy the script,
and ensure it has appropriate permissions to be read and executed by all users.

```sh
cd ~/netbackup
sudo install netbackup.sh /usr/local/bin/netbackup
```

Alternatively, if you don't have `install` (or it otherwise malfunctions), you can install it by hand:

```sh
sudo cp -v netbackup.sh /usr/local/bin/netbackup
sudo chmod 755 /usr/local/bin/netbackup
```

You should now be able to run `netbackup` from any user, in any folder of your system - and it will
run netbackup.

**NOTE:** Since almost all of netbackup's calls require root, to be able to run `netbackup` from normal users,
you'll need to use `sudo`. To avoid the issue of `$HOME` resolving to the local user, you should use
`/etc/netbackup.env` for your env file, instead of one in your home folder(s), and use an absolute
path for `BACKUP_DIR`, ensuring that all users can run `sudo netbackup` with no risk of it reading
the wrong netbackup config, or backing up to the wrong home folder.


## Backup Structure / Space Usage

The following space usage example, and file structure example, is based off of netbackup 0.5.0,
which was released on 10 / APRIL / 2021.

On one of our production servers, which has a handful of network interfaces, IP addresses,
and a moderate iptables setup - with only the default files being backed up, the backup
consumes ~136K (kibibytes) according to `du`

```
root@host ~ # du -sh /root/backups/2021-04-09_19.14.27
136K    /root/backups/2021-04-09_19.14.27
```

On this same system, the file structure of the timestamped backup folder looks like this:


```sh
root@host ~ # tree /root/backups/2021-04-09_19.14.27
/root/backups/2021-04-09_19.14.27
├── ifaces
│   ├── disk
│   │   ├── 50-cloud-init.yaml
│   │   └── interfaces
│   ├── dump
│   │   ├── addrs_v4.bin
│   │   ├── addrs_v6.bin
│   │   ├── routes_v4.bin
│   │   ├── routes_v6.bin
│   │   ├── rules_v4.bin
│   │   └── rules_v6.bin
│   └── log
│       ├── all
│       │   └── ip_route_all.txt
│       ├── ip_addr.txt
│       ├── ip_route.txt
│       ├── v4
│       │   ├── ip_route_all.txt
│       │   └── ip_route.txt
│       └── v6
│           ├── ip_route_all.txt
│           └── ip_route.txt
└── ipt
    ├── disk
    │   ├── rules.v4
    │   └── rules.v6
    └── memory
        ├── ipset.conf
        ├── rules.v4
        └── rules.v6

10 directories, 20 files
```



## What does it backup by default?

Backs up the following networking configurations:

- **Firewall configs on disk** - listed in `BK_FILES`, by default:
  - IPTables `rules.v4`
  - IPTables `rules.v6`
  - IPSet Persistent config (searches in 3 different locations)
  - [Pyrewall](https://github.com/Privex/pyrewall) Rules file (`rules.pyre`)

- **In memory firewall configurations**:
  - IPTables IPv4 rules (active in memory)
  - IPTables IPv6 rules (active in memory)
  - IPSet rules (active in memory)

- **Network interface/routing configurations on disk** (`BK_FILES_IFACE`)
  - Main netplan configuration (`NETPLAN_FILE`), default `50-cloud-init.yaml` (in `/etc/netplan`)
  - ifupdown `/etc/network/interfaces` file

- **Network interface/routing configurations in memory**
  - `ip addr` interface address config, both command output for v4/v6, and native binary dumps
  - `ip route` network routing config, both command output for v4/v6, and native binary dumps
  - `ip rule` routing rules config, both command output for v4/v6, and native binary dumps

This results in a quite thorough backup, containing both configurations that have been persisted
to disk as a config file, AND in-memory active configurations which would normally only be ephemeral
and could be lost on reboot.


## Customizing settings by using a `.env` environment variables file

You can customise some settings without editing the netbackup.sh file, by creating either `~/.netbackup.env`
or `/etc/netbackup.env`

An example ENV file is included in this repository as `example.env` - though it's a thorough example
which covers practically all possible ENV vars that you can customise.

Most people may only want to change the backup output folder, and/or the date/time format used
for timestamping the backup folders, which can both be done like so, either in `~/.netbackup.env`,
`/etc/netbackup.env`, or passed directly to the script through the environment:

```sh
# By default, BACKUP_DIR is set to ${HOME}/backups ( ~/backups )
BACKUP_DIR=/mnt/mybackups

# By default, DATE_FMT is set to a full "year-month-day_hour.minute.second" timestamp,
# i.e. "%Y-%m-%d_%H.%M.%S". The below example shortens it to just year-month-day,
# which would be more appropriate for folder names if you only do daily backups.
DATE_FMT="%Y-%m-%d"

# By default, the timezone is set to 'UTC' (universal co-ordinated time, +00:00).
# If you'd prefer your backups to be timestamped with your local regional timezone,
# or the timezone of the server etc. - run 'tzselect' to navigate through the available
# Linux timezones to find the correct code for your (or your server's) region.
# The below example is the correct timezone code for the United Kingdom (England/Scotland/Wales/NI):
DATE_TZ="Europe/London"
```



## License

This project is licensed under the **X11 / MIT** license. See the file **LICENSE** for full details.

Here's the important bits:

 - You must include/display the license & copyright notice (`LICENSE`) if you modify/distribute/copy
   some or all of this project.
 - You can't use our name to promote / endorse your product without asking us for permission.
   You can however, state that your product uses some/all of this project.



# Thanks for reading!

**If this project has helped you, consider [grabbing a VPS or Dedicated Server from Privex](https://www.privex.io)** -
**prices start at as little as US$0.99/mo (we take cryptocurrency!)**

