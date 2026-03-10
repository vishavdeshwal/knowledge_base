# Linux / Ubuntu — System Administrator Reference Guide

> **Scope:** Ubuntu 20.04 / 22.04 / 24.04 LTS (most commands apply to any Debian-based distro)
> **Convention:** `#` = run as root or with `sudo` | `$` = run as regular user

---

## Table of Contents

1. [User & Group Management](#1-user--group-management)
2. [File & Directory Permissions](#2-file--directory-permissions)
3. [SSH & Remote Access](#3-ssh--remote-access)
4. [Package Management (APT)](#4-package-management-apt)
5. [Process & Service Management (systemd)](#5-process--service-management-systemd)
6. [Disk, Filesystem & Storage](#6-disk-filesystem--storage)
7. [Networking](#7-networking)
8. [Firewall (UFW / iptables)](#8-firewall-ufw--iptables)
9. [System Monitoring & Performance](#9-system-monitoring--performance)
10. [Logs & Journald](#10-logs--journald)
11. [Cron & Scheduled Tasks](#11-cron--scheduled-tasks)
12. [Backup & Restore](#12-backup--restore)
13. [Security Hardening](#13-security-hardening)
14. [Environment Variables & Shell Config](#14-environment-variables--shell-config)
15. [Nginx Web Server](#15-nginx-web-server)
16. [Apache Web Server](#16-apache-web-server)
17. [MySQL / MariaDB](#17-mysql--mariadb)
18. [SSL / TLS Certificates (Let's Encrypt)](#18-ssl--tls-certificates-lets-encrypt)
19. [Docker](#19-docker)
20. [System Updates & Upgrades](#20-system-updates--upgrades)
21. [Troubleshooting Cheatsheet](#21-troubleshooting-cheatsheet)

---

## 1. User & Group Management

### Create a User

```bash
# Create user with home directory and bash shell
sudo useradd -m -s /bin/bash <username>

# Set password
sudo passwd <username>

# Create user and add to a specific group in one step
sudo useradd -m -s /bin/bash -G <groupname> <username>
```

### Modify a User

```bash
# Change <username>
sudo usermod -l <new_name> <old_name>

# Change home directory
sudo usermod -d /new/home -m <username>

# Lock / unlock account
sudo usermod -L <username>     # lock
sudo usermod -U <username>     # unlock

# Set account expiry
sudo usermod --expiredate 2025-12-31 <username>

# Add user to supplementary group
sudo usermod -aG <groupname> <username>   # -a = append (never omit this!)

# Change default shell
sudo chsh -s /bin/zsh <username>
```

### Delete a User

```bash
# Delete user (keep home directory)
sudo userdel <username>

# Delete user AND home directory
sudo userdel -r <username>
```

### Create & Manage Groups

```bash
# Create a group
sudo groupadd <groupname>

# Delete a group
sudo groupdel <groupname>

# List all groups a user belongs to
groups <username>
id <username>

# Remove user from a group
sudo gpasswd -d <username> <groupname>
```

### Grant sudo Access

```bash
# Add to sudo group
sudo usermod -aG sudo <username>

# Grant specific command without password (edit sudoers safely)
sudo visudo
# Add line:  <username> ALL=(ALL) NOPASSWD: /usr/bin/systemctl
```

### Useful Inspection Commands

```bash
cat /etc/passwd          # all users
cat /etc/group           # all groups
getent passwd <username>   # single user record
lastlog                  # last login per user
last <username>            # login history
who                      # currently logged-in users
w                        # who + what they're doing
```

---

## 2. File & Directory Permissions

### Permission Basics

```
Owner  Group  Others
 rwx    rwx    rwx
 421    421    421
```

| Symbol | Octal | Meaning |
|--------|-------|---------|
| r | 4 | Read |
| w | 2 | Write |
| x | 1 | Execute |

### chmod — Change Permissions

```bash
# Symbolic
chmod u+x <file>          # add execute for owner
chmod g-w <file>          # remove write for group
chmod o=r <file>          # set others to read-only
chmod a+x <file>          # all (u+g+o) get execute

# Octal
chmod 755 <file>          # rwxr-xr-x  (owner full, group/others read+exec)
chmod 644 <file>          # rw-r--r--  (owner rw, group/others read)
chmod 700 /home/user    # rwx------  (owner only)
chmod 750 /home/shared  # rwxr-x---  (owner full, group read+exec)

# Recursive
chmod -R 755 /var/www/html
```

### chown — Change Ownership

```bash
sudo chown <user> <file>
sudo chown <user>:<group> <file>
sudo chown -R <user>:<group> /path/to/dir    # recursive

# Change group only
sudo chgrp <groupname> <file>
```

### ACL — Fine-Grained Access Control

```bash
sudo apt install acl

# Grant specific user rwx on a directory
sudo setfacl -m u:<username>:rwx /home/nutrabay

# Grant specific group read+exec
sudo setfacl -m g:<group_name>:rx /var/www/site

# Apply default ACL (inherited by new files inside dir)
sudo setfacl -d -m u:<username>:rwx /home/nutrabay

# View ACLs
getfacl /home/nutrabay

# Remove ACL entry
sudo setfacl -x u:<username> /home/nutrabay

# Remove all ACLs
sudo setfacl -b /home/nutrabay
```

### Special Permission Bits

```bash
chmod u+s <file>      # setuid  — runs as file owner
chmod g+s <dir>       # setgid  — new files inherit group
chmod +t <dir>        # sticky bit — only owner can delete (e.g., /tmp)

# Octal notation
chmod 4755 <file>     # setuid + 755
chmod 2755 <dir>      # setgid + 755
chmod 1777 /tmp     # sticky + rwxrwxrwx
```

---

## 3. SSH & Remote Access

### Connect

```bash
ssh <username>@<host>
ssh -p 2222 <username>@<host>          # custom port
ssh -i ~/.ssh/id_rsa <username>@<host> # specify key
ssh -L 8080:localhost:80 <user>@<host> # local port forward
ssh -R 9090:localhost:3000 <user>@<host> # remote port forward
```

### Key-Based Authentication

```bash
# Generate key pair (on client)
ssh-keygen -t ed25519 -C "your@email.com"

# Copy public key to server
ssh-copy-id <username>@<host>
# or manually
cat ~/.ssh/id_ed25519.pub | ssh <user>@<host> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# Correct permissions on server
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### SSH Server Configuration (`/etc/ssh/sshd_config`)

```
Port 2222                        # change default port
PermitRootLogin no               # disable root login
PasswordAuthentication no        # force key-based auth
PubkeyAuthentication yes
AllowUsers vikas_kumar deploy    # whitelist users
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

```bash
# Apply changes
sudo systemctl restart sshd

# Test config before restarting
sudo sshd -t
```

### SSH Config File (Client `~/.ssh/config`)

```
Host myserver
    HostName 192.168.1.100
    User vikas_kumar
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

```bash
# Now simply:
ssh myserver
```

---

## 4. Package Management (APT)

```bash
# Update package index
sudo apt update

# Upgrade all packages
sudo apt upgrade -y

# Full upgrade (handles dependency changes)
sudo apt full-upgrade -y

# Install a package
sudo apt install nginx -y

# Remove package (keep config)
sudo apt remove nginx

# Remove package + config
sudo apt purge nginx

# Remove unused dependencies
sudo apt autoremove -y

# Search for a package
apt search nginx

# Show package info
apt show nginx

# List installed packages
dpkg -l
dpkg -l | grep nginx

# Check which package owns a file
dpkg -S /usr/bin/nginx

# Install a .deb file
sudo dpkg -i package.deb
sudo apt install -f   # fix broken dependencies after dpkg

# Hold a package at current version
sudo apt-mark hold nginx
sudo apt-mark unhold nginx
```

---

## 5. Process & Service Management (systemd)

### systemctl — Service Control

```bash
# Start / stop / restart
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx
sudo systemctl reload nginx      # reload config without downtime

# Enable / disable at boot
sudo systemctl enable nginx
sudo systemctl disable nginx
sudo systemctl enable --now nginx  # enable AND start immediately

# Status
sudo systemctl status nginx

# List all services
systemctl list-units --type=service
systemctl list-units --type=service --state=failed
```

### Process Management

```bash
# View running processes
ps aux
ps aux | grep nginx
pgrep -a nginx

# Real-time process viewer
top
htop           # install: sudo apt install htop

# Kill a process
kill <PID>
kill -9 <PID>            # force kill (SIGKILL)
sudo pkill nginx       # kill by name
sudo killall nginx

# Background / foreground
<command> &              # run in background
jobs                   # list background jobs
fg %1                  # bring job 1 to foreground
bg %1                  # resume job 1 in background
nohup <command> &        # keep running after logout

# Priority (nice value: -20 highest to 19 lowest)
nice -n 10 command
renice -n 5 -p <PID>
```

### Create a Custom systemd Service

```bash
sudo nano /etc/systemd/system/<app_name>.service
```

```ini
[Unit]
Description=My Application
After=network.target

[Service]
Type=simple
User=<app_user>
WorkingDirectory=/opt/<app_name>
ExecStart=/usr/bin/node /opt/<app_name>/index.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now <app_name>
```

---

## 6. Disk, Filesystem & Storage

### Disk Usage & Space

```bash
df -h                    # disk space per filesystem
df -hT                   # include filesystem type
du -sh /var/log          # size of a directory
du -sh /* 2>/dev/null | sort -rh | head -20   # top disk users
lsblk                    # block devices tree
lsblk -f                 # with filesystem info
fdisk -l                 # partition table
blkid                    # UUIDs and types
```

### Partition Management

```bash
# Interactive partition editor
sudo fdisk /dev/sdb      # MBR
sudo gdisk /dev/sdb      # GPT (recommended)
sudo parted /dev/sdb     # supports both

# Format a partition
sudo mkfs.ext4 /dev/sdb1
sudo mkfs.xfs /dev/sdb1

# Label filesystem
sudo e2label /dev/sdb1 "data-vol"
```

### Mount & Unmount

```bash
# Mount
sudo mount /dev/sdb1 /mnt/data
sudo mount -t ext4 /dev/sdb1 /mnt/data

# Unmount
sudo umount /mnt/data

# Persistent mount via /etc/fstab
# UUID=xxxx-xxxx  /mnt/data  ext4  defaults,nofail  0  2
# Get UUID:
blkid /dev/sdb1
```

### LVM — Logical Volume Manager

```bash
# Physical volume
sudo pvcreate /dev/sdb
pvdisplay

# Volume group
sudo vgcreate vg_data /dev/sdb
vgdisplay

# Logical volume
sudo lvcreate -L 50G -n lv_app vg_data
lvdisplay

# Extend volume group
sudo vgextend vg_data /dev/sdc

# Extend logical volume + filesystem
sudo lvextend -L +20G /dev/vg_data/lv_app
sudo resize2fs /dev/vg_data/lv_app      # ext4
sudo xfs_growfs /dev/vg_data/lv_app     # xfs
```

### Swap

```bash
# Create a swapfile
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make persistent — add to /etc/fstab:
# /swapfile  none  swap  sw  0  0

# View swap usage
swapon --show
free -h
```

---

## 7. Networking

### Network Interfaces

```bash
ip addr                     # show all interfaces
ip addr show eth0           # specific interface
ip link set eth0 up/down    # bring up/down

# Legacy (still works)
ifconfig -a
```

### IP Routing

```bash
ip route show               # routing table
ip route add default via 192.168.1.1
ip route add 10.0.0.0/8 via 192.168.1.1 dev eth0
ip route del 10.0.0.0/8
```

### DNS & Hostname

```bash
hostname                    # current hostname
sudo hostnamectl set-hostname <new-hostname>

cat /etc/hosts              # local DNS overrides
cat /etc/resolv.conf        # DNS servers

# Test DNS resolution
nslookup google.com
dig google.com
dig @8.8.8.8 google.com
```

### Network Diagnostics

```bash
ping -c 4 google.com
traceroute google.com          # sudo apt install traceroute
mtr google.com                 # interactive traceroute
curl -I https://example.com    # HTTP headers
wget -q --spider https://example.com  # check URL reachability

# Open ports and sockets
ss -tlnp                    # listening TCP ports + process
ss -ulnp                    # listening UDP ports
netstat -tlnp               # legacy (install: net-tools)

# Bandwidth test
iperf3 -s                   # server mode
iperf3 -c <server_ip>         # client test

# Interface traffic stats
vnstat                      # install: sudo apt install vnstat
```

### Netplan (Ubuntu 18.04+)

```bash
# Config file
sudo nano /etc/netplan/00-installer-config.yaml
```

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [192.168.1.50/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

```bash
sudo netplan apply
sudo netplan try    # test with auto-rollback
```

---

## 8. Firewall (UFW / iptables)

### UFW — Uncomplicated Firewall

```bash
# Enable / disable
sudo ufw enable
sudo ufw disable
sudo ufw status verbose

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow / deny by port
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw deny 3306/tcp

# Allow by service name
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'

# Allow from specific IP
sudo ufw allow from 203.0.113.10
sudo ufw allow from 203.0.113.10 to any port 22

# Allow subnet
sudo ufw allow from 10.0.0.0/8

# Delete a rule
sudo ufw delete allow 80/tcp
sudo ufw delete 3            # by rule number (from ufw status numbered)

# Logging
sudo ufw logging on
```

### iptables (Advanced)

```bash
# List rules
sudo iptables -L -n -v
sudo iptables -L INPUT -n --line-numbers

# Allow established connections
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Block IP
sudo iptables -A INPUT -s 203.0.113.99 -j DROP

# Save rules persistently
sudo apt install iptables-persistent
sudo netfilter-persistent save
sudo netfilter-persistent reload
```

---

## 9. System Monitoring & Performance

### CPU & Memory

```bash
top                         # interactive process monitor
htop                        # better top (sudo apt install htop)
vmstat 1 10                 # virtual memory stats every 1s, 10 times
mpstat -P ALL 1             # per-CPU usage (install: sysstat)
sar -u 1 5                  # CPU usage (install: sysstat)
free -h                     # memory usage
cat /proc/meminfo           # detailed memory info
```

### Disk I/O

```bash
iostat -xz 1                # disk I/O stats (install: sysstat)
iotop                       # per-process I/O (sudo apt install iotop)
dstat                       # combined stats (sudo apt install dstat)
```

### System Info

```bash
uname -a                    # kernel + arch
lsb_release -a              # Ubuntu version
cat /etc/os-release
hostnamectl                 # hostname, OS, kernel
uptime                      # uptime + load average
lscpu                       # CPU details
lsmem                       # memory layout
dmidecode -t memory         # RAM slots / installed DIMMs
lshw -short                 # hardware summary
lspci                       # PCI devices
lsusb                       # USB devices
```

### Load Average

```
load average: 0.45, 0.60, 0.70
              1min  5min  15min
```

> Rule of thumb: Load ≤ number of CPU cores = healthy

---

## 10. Logs & Journald

### systemd Journal

```bash
# View all logs (newest first)
journalctl -r

# Follow live
journalctl -f

# By service
journalctl -u nginx
journalctl -u nginx -f         # follow
journalctl -u nginx --since today
journalctl -u nginx --since "2024-01-01" --until "2024-01-31"

# By boot
journalctl -b                  # current boot
journalctl -b -1               # previous boot
journalctl --list-boots

# By priority (emerg/alert/crit/err/warning/notice/info/debug)
journalctl -p err

# Kernel messages
journalctl -k
dmesg | tail -50
dmesg -T | grep -i error

# Disk usage of journal
journalctl --disk-usage

# Vacuum old logs
sudo journalctl --vacuum-time=30d
sudo journalctl --vacuum-size=1G
```

### Traditional Log Files

| File | Content |
|------|---------|
| `/var/log/syslog` | General system messages |
| `/var/log/auth.log` | Authentication (SSH, sudo) |
| `/var/log/kern.log` | Kernel messages |
| `/var/log/apt/history.log` | APT install/remove history |
| `/var/log/nginx/access.log` | Nginx access log |
| `/var/log/nginx/error.log` | Nginx error log |
| `/var/log/mysql/error.log` | MySQL errors |

```bash
tail -f /var/log/syslog
grep "Failed password" /var/log/auth.log
grep "ERROR" /var/log/nginx/error.log | tail -100
```

### logrotate

```bash
# Force rotation now
sudo logrotate -f /etc/logrotate.conf

# Test config
sudo logrotate -d /etc/logrotate.conf

# Custom app config
sudo nano /etc/logrotate.d/<app_name>
```

```
/var/log/<app_name>/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    sharedscripts
    postrotate
        systemctl reload <app_name>
    endscript
}
```

---

## 11. Cron & Scheduled Tasks

### crontab Syntax

```
┌───────── minute (0-59)
│ ┌───────── hour (0-23)
│ │ ┌───────── day of month (1-31)
│ │ │ ┌───────── month (1-12)
│ │ │ │ ┌───────── day of week (0=Sun … 6=Sat)
│ │ │ │ │
* * * * *  command
```

### Common Examples

```bash
# Edit crontab for current user
crontab -e

# Edit another user's crontab
sudo crontab -u <username> -e

# List crontab
crontab -l
sudo crontab -u <username> -l

# Every 5 minutes
*/5 * * * * /opt/scripts/check.sh

# Every day at 2:30 AM
30 2 * * * /opt/scripts/backup.sh

# Every Monday at 9 AM
0 9 * * 1 /opt/scripts/weekly_report.sh

# First day of every month
0 0 1 * * /opt/scripts/monthly.sh

# Every hour, log output
0 * * * * /opt/scripts/task.sh >> /var/log/task.log 2>&1
```

### System-wide Cron Directories

```
/etc/cron.hourly/
/etc/cron.daily/
/etc/cron.weekly/
/etc/cron.monthly/
/etc/cron.d/              ← custom cron files (include <username> field)
```

---

## 12. Backup & Restore

### rsync — Efficient File Sync/Backup

```bash
# Basic sync
rsync -avz /source/ /destination/

# Remote sync over SSH
rsync -avz -e ssh /local/path/ <user>@<host>:/remote/path/

# Dry run (preview)
rsync -avzn /source/ /destination/

# Delete files at destination not in source
rsync -avz --delete /source/ /destination/

# Exclude patterns
rsync -avz --exclude='*.log' --exclude='.git/' /source/ /dest/

# Bandwidth limit (KB/s)
rsync -avz --bwlimit=1000 /source/ <user>@<host>:/dest/
```

### tar — Archive & Compress

```bash
# Create archive
tar -czvf backup.tar.gz /path/to/dir

# Create archive with date
tar -czvf "backup-$(date +%Y%m%d).tar.gz" /path/to/dir

# Extract archive
tar -xzvf backup.tar.gz
tar -xzvf backup.tar.gz -C /target/dir

# List contents
tar -tzvf backup.tar.gz

# tar with xz compression (higher ratio)
tar -cJvf backup.tar.xz /path/to/dir
```

### Database Backups

```bash
# MySQL / MariaDB — single DB
mysqldump -u root -p <db_name> > dbname_backup.sql

# All databases
mysqldump -u root -p --all-databases > all_dbs.sql

# Compressed
mysqldump -u root -p <db_name> | gzip > dbname_$(date +%Y%m%d).sql.gz

# Restore
mysql -u root -p <db_name> < dbname_backup.sql
gunzip < dbname_backup.sql.gz | mysql -u root -p <db_name>

# PostgreSQL
pg_dump <db_name> > <db_name>.sql
pg_dumpall > all_dbs.sql
psql <db_name> < <db_name>.sql
```

### Automated Backup Script Example

```bash
#!/bin/bash
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

# Files
tar -czvf "$BACKUP_DIR/files_$DATE.tar.gz" /var/www/html

# Database
mysqldump -u root -p"${DB_PASS}" <db_name> | gzip > "$BACKUP_DIR/db_$DATE.sql.gz"

# Cleanup old backups
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $DATE"
```

```bash
chmod +x /opt/scripts/backup.sh
# Schedule daily at 2 AM
echo "0 2 * * * root /opt/scripts/backup.sh >> /var/log/backup.log 2>&1" \
  | sudo tee /etc/cron.d/daily-backup
```

---

## 13. Security Hardening

### User Account Policies

```bash
# Password aging policy
sudo chage -l <username>              # view current policy
sudo chage -M 90 <username>           # max 90 days
sudo chage -m 7 <username>            # min 7 days before change
sudo chage -W 14 <username>           # warn 14 days before expiry
sudo chage -E 2025-12-31 <username>   # account expires

# Enforce password complexity (/etc/pam.d/common-password)
sudo apt install libpam-pwquality
# Add to /etc/pam.d/common-password:
# password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1
```

### Fail2ban — Brute-Force Protection

```bash
sudo apt install fail2ban -y

# Create local config (never edit .conf directly)
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

```ini
[DEFAULT]
bantime  = 3600       ; 1 hour
maxretry = 5
findtime = 600

[sshd]
enabled = true
port    = 22
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
```

```bash
sudo systemctl enable --now fail2ban

# Monitor
sudo fail2ban-client status
sudo fail2ban-client status sshd

# Unban IP
sudo fail2ban-client set sshd unbanip 203.0.113.99
```

### Audit & Intrusion Detection

```bash
# Check for failed SSH logins
grep "Failed password" /var/log/auth.log | awk '{print $11}' | sort | uniq -c | sort -rn

# Check who has sudo access
grep -Po '^sudo.+:\K.*$' /etc/group

# Audit file changes (auditd)
sudo apt install auditd
sudo auditctl -w /etc/passwd -p wa -k passwd_changes
sudo aureport --summary
sudo ausearch -k passwd_changes
```

### Automatic Security Updates

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Config: /etc/apt/apt.conf.d/50unattended-upgrades
```

---

## 14. Environment Variables & Shell Config

```bash
# View environment
env
printenv
printenv PATH

# Set variable (current session)
export MY_VAR="value"

# Permanent for a user (~/.bashrc or ~/.profile)
echo 'export MY_VAR="value"' >> ~/.bashrc
source ~/.bashrc

# System-wide (/etc/environment or /etc/profile.d/)
echo 'MY_VAR="value"' | sudo tee -a /etc/environment
sudo nano /etc/profile.d/myvars.sh   # add export statements here

# Add to PATH
export PATH="$PATH:/opt/<app_name>/bin"
```

---

## 15. Nginx Web Server

### Installation & Basic Control

```bash
sudo apt install nginx -y
sudo systemctl enable --now nginx
sudo nginx -t          # test config
sudo nginx -s reload   # reload without downtime
```

### Config Structure

```
/etc/nginx/
├── nginx.conf              ← main config
├── sites-available/        ← virtual host definitions
├── sites-enabled/          ← symlinks to active sites
├── conf.d/                 ← drop-in configs
└── snippets/               ← reusable config fragments
```

### Virtual Host Example

```nginx
# /etc/nginx/sites-available/example.com
server {
    listen 80;
    server_name example.com www.example.com;

    root /var/www/example.com;
    index index.html index.php;

    access_log /var/log/nginx/example.access.log;
    error_log  /var/log/nginx/example.error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/example.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### Reverse Proxy

```nginx
server {
    listen 80;
    server_name app.example.com;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
    }
}
```

---

## 16. Apache Web Server

```bash
sudo apt install apache2 -y
sudo systemctl enable --now apache2

# Enable / disable modules
sudo a2enmod rewrite ssl headers
sudo a2dismod status

# Enable / disable sites
sudo a2ensite example.com.conf
sudo a2dissite 000-default.conf

sudo apache2ctl configtest
sudo systemctl reload apache2
```

### Virtual Host Example

```apache
# /etc/apache2/sites-available/example.com.conf
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/example.com

    ErrorLog  ${APACHE_LOG_DIR}/example_error.log
    CustomLog ${APACHE_LOG_DIR}/example_access.log combined

    <Directory /var/www/example.com>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

---

## 17. MySQL / MariaDB

```bash
# Install
sudo apt install mysql-server -y
sudo mysql_secure_installation

# Connect
sudo mysql -u root -p
mysql -u <username> -p -h 127.0.0.1 <db_name>
```

### Common SQL Admin Commands

```sql
-- Create DB and user
CREATE DATABASE <db_name> CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '<db_user>'@'localhost' IDENTIFIED BY 'StrongPass123!';
GRANT ALL PRIVILEGES ON <db_name>.* TO '<db_user>'@'localhost';
FLUSH PRIVILEGES;

-- Show
SHOW DATABASES;
SHOW TABLES;
SHOW PROCESSLIST;
SHOW GRANTS FOR '<db_user>'@'localhost';

-- Drop
DROP DATABASE <db_name>;
DROP USER '<db_user>'@'localhost';

-- Change password
ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewPass123!';
```

### MySQL Config

```bash
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

# Key settings:
# bind-address = 127.0.0.1    # restrict to localhost
# max_connections = 200
# slow_query_log = 1
# slow_query_log_file = /var/log/mysql/slow.log
# long_query_time = 2

sudo systemctl restart mysql
```

---

## 18. SSL / TLS Certificates (Let's Encrypt)

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Obtain certificate (Nginx)
sudo certbot --nginx -d example.com -d www.example.com

# Obtain certificate (standalone — stops web server briefly)
sudo certbot certonly --standalone -d example.com

# Test auto-renewal
sudo certbot renew --dry-run

# List certificates
sudo certbot certificates

# Renew manually
sudo certbot renew

# Auto-renewal is set up via a systemd timer or cron automatically.
# Verify:
systemctl status certbot.timer
```

### Certificates Location

```
/etc/letsencrypt/live/example.com/
├── fullchain.pem   ← certificate + chain (use this for nginx ssl_certificate)
├── privkey.pem     ← private key
├── cert.pem        ← certificate only
└── chain.pem       ← chain only
```

---

## 19. Docker

```bash
# Install
sudo apt install docker.io -y
sudo systemctl enable --now docker

# Add user to docker group (avoid sudo for docker)
sudo usermod -aG docker <username>
newgrp docker  # apply without logout

# Basic commands
docker ps                        # running containers
docker ps -a                     # all containers
docker images                    # local images
docker pull nginx                # pull image
docker run -d -p 80:80 nginx     # run container
docker stop <container_id>
docker rm <container_id>
docker rmi <image_id>

# Exec into running container
docker exec -it <container_id> bash

# View logs
docker logs <container_id>
docker logs -f <container_id>      # follow

# Volumes
docker volume ls
docker volume create <volume_name>
docker volume inspect <volume_name>
```

### Docker Compose

```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# View logs
docker compose logs -f

# Rebuild images
docker compose up -d --build

# Scale
docker compose up -d --scale web=3
```

### Cleanup

```bash
docker system prune -af            # remove all unused images, containers, networks
docker volume prune                # remove unused volumes
```

---

## 20. System Updates & Upgrades

```bash
# Routine update
sudo apt update && sudo apt upgrade -y

# Check for available upgrades without installing
apt list --upgradable

# Upgrade to new Ubuntu LTS
sudo do-release-upgrade

# Simulate upgrade (no changes)
sudo do-release-upgrade -s

# Check current kernel
uname -r

# List installed kernels
dpkg -l | grep linux-image

# Remove old kernels
sudo apt autoremove --purge
```

---

## 21. Troubleshooting Cheatsheet

### Service Won't Start

```bash
sudo systemctl status <service_name>
journalctl -u <service_name> -n 50 --no-pager
sudo journalctl -xe             # full context around last errors
```

### Port Already in Use

```bash
sudo ss -tlnp | grep :80
sudo lsof -i :80
sudo kill -9 $(lsof -t -i:80)
```

### Disk Full

```bash
df -h                                         # find full filesystem
du -sh /* 2>/dev/null | sort -rh | head -20  # find biggest dirs
sudo journalctl --vacuum-size=500M            # clear old logs
sudo apt clean                                # clear apt cache
find /var/log -name "*.gz" -delete            # remove compressed logs
```

### Out of Memory / OOM Kill

```bash
dmesg | grep -i "killed process"
journalctl -k | grep -i oom
free -h
vmstat 1 5
```

### High CPU

```bash
top -o %CPU             # sort by CPU
ps aux --sort=-%cpu | head -10
strace -p <PID>           # trace system calls of a process
```

### Cannot SSH into Server

```bash
# From another session or console:
sudo systemctl status sshd
sudo ss -tlnp | grep :22
sudo ufw status
sudo grep "sshd" /var/log/auth.log | tail -20
sudo sshd -t            # check sshd config syntax
```

### Network Unreachable

```bash
ip addr                 # check IPs assigned
ip route show           # check default gateway
ping 8.8.8.8            # test internet (no DNS)
ping google.com         # test DNS
cat /etc/resolv.conf    # check DNS servers
sudo systemctl restart systemd-networkd
sudo netplan apply
```

---

*Last updated: March 2026 | Maintained for Ubuntu 20.04 / 22.04 / 24.04 LTS*