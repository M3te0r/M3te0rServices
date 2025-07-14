# Proxmox VE Helper Scripts

https://community-scripts.github.io/ProxmoxVE/scripts

# Add hardware monitoring display (CPU, disks, fan, etc) to Proxmox node UI

https://github.com/Meliox/PVE-mods

```shell
apt-get install lm-sensors
# lm-sensors must be configured, run below to configure your sensors, apply temperature offsets. Refer to lm-sensors manual for more information.
sensors-detect 
wget https://raw.githubusercontent.com/Meliox/PVE-mods/main/pve-mod-gui-sensors.sh
bash pve-mod-gui-sensors.sh install
# Then clear the browser cache to ensure all changes are visualized.
```

# Using clusters for migration (old to new node)

https://youtu.be/E60_FC967YE?si=T12vOoHJoMGbw7Se&t=721

# NFS Share to an LXC

## NAS 

On NAS or sharing system, in my case a Synology NAS

- Connect to Web UI
- Go to Settings panel
- Go to shared folders
- Click on the folder you want to share
- Click on Edit
- Click on NFS
- Add a permission
- Enter the proxmox IP address
- Read/Write
- Make sure to select map all users to admin on mapping

## Proxmox

### on proxmox host

Assuming that:

- NAS_IP=192.168.2.23
- NAS shared folder=/volume4/MEDIAS_HMS
- Mounting point under proxmox=/mnt/lxc_shares/nas_medias_test_rwx

make a directory for where the share will be mounted

`mkdir -p /mnt/lxc_shares/nas_medias_test_rwx`

edit fstab (/etc/fstab)

`nano /etc/fstab`

add line:

`192.168.2.23:/volume4/MEDIAS_HMS /mnt/lxc_shares/nas_medias_test_rwx nfs defaults 0 0`

Mount the share:

`systemctl daemon-reload`

`mount -a`

#### Add mounting point to the LXC


Edit config file of LXC 

`nano /etc/pve/lxc/222.conf`

Add line

`mp0: /mnt/lxc_shares/nas_medias_test_rwx,mp=/mnt/medias`


### on LXC container

Start LXC container


Open console

`groupadd -g 10000 lxc_shares`

`usermod -aG lxc_shares root`

Reboot LXC


Sources
- The one that truly worked => https://forum.proxmox.com/threads/tutorial-mounting-nfs-share-to-an-unprivileged-lxc.138506/
- https://www.youtube.com/watch?v=DMPetY4mX-c


