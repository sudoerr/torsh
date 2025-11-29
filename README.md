# Torsh 🍋, Transparent Tor proxy for full system TCP traffic

Ever wondered how you can tunnel whole system traffic through Tor? The answer is iptables, Torsh is a simple bash script to handle this behavior. It tries to be simple yet useful, best philosofy for best tools in the world.

`[ Torsh, Sour For Spies, Sweet For You ]`



## Features

- Simple, standalone bash script
- Uses iptables to tunnel traffic through Tor
- Handles DNS over Tor (UDP and TCP)
- No Data Leakage
- Disables IPv6
- Checks final IP Address and Location to make sure of connectivity and geo filters for exit nodes
- Auto-cleanup on termination (SIGTERM) `ctrl+c`
- Never touching Tor process, so script remains simple
- Drops UDP connections to protect against WEBRTC or other UDP leaks (keeps DNS available through Tor)




## Prerequisites

- tor
- iptables (available by default)
- curl
- jq

### arch-base distro
```bash
sudo pacman -S tor curl jq
```

### debian-base distro
```bash
sudo apt install tor curl jq
```




## Installation And Usage

### Install
```bash
git clone https://github.com/sudoerr/torsh.git
cd torsh
sudo cp ./torsh.sh /usr/bin/torsh
# make sure to reset your terminal
```

### Configure torrc
```bash
sudo nano /etc/tor/torrc
```
and add necessary configs in it :
```text
User tor
SOCKSPort 9050
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsOnResolve 1
TransPort 9040
DNSPort 5353
```
The `User` value (`tor`) depends on your distro, in case you installed tor with a package manager like pacman or apt.  

> - Avoid duplicates in torrc  
> - In case of changes make sure to change config part of torsh script  


### Usage
```bash
# start or restart tor
sudo systemctl restart tor
# you can also run it directly, but
# better use systemd for compatibility
sudo torsh config
# if you need change config in your editor and finally close it
sudo torsh connect
```

### Config File
```bash
nano /etc/torsh/torsh.conf
```

### Some Considerations
- Disable firewall if you have one (like ufw), Torsh is not capable of handling under/beside any firewall (for now)  
- Be carefull everytime you use Tor...  


## ToDo :

- Nothing For now...



## All Contributions Are Welcome

In order to take a big step for safe internet, tor is a necessary tool. In some regions it's really big problem to not use tor! Your contributions are welcome as always, and **as I'm a noob in bash scripting**, I rather a professional help improving Torsh.  

***Thanks For Making Internet A Safer Place, Tor***