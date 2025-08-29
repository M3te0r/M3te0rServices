#! /bin/bash

VMID=9299
STORAGE=local
IMAGE_URL=https://cloud-images.ubuntu.com/plucky/current/plucky-server-cloudimg-amd64.img
USERNAME=m3te0r
IMAGE_NAME=pluck-server-cloudimg-amd64.img

set -x

function setUSER() {
    # Set Cloid-init user
#    ciu=$(whiptail --backtitle "$backTEXT" --title "Create CI User" --inputbox \
#      "\nCreate with CI user" \
#      10 48 $initUSER 3>&1 1>&2 2>&3)
#      echo "     -  Cloud-init user: $ciu"

    # Create a long and complicated password 6 is a joke 8 is something 12 is semi ok 16 is ok 20 is good
    while [[ "$cip" != "$cip_repeat" || ${#cip} -lt $passLENGHT ]]; do
      cip=$(whiptail --backtitle "$backTEXT" --title "Create CI User" --passwordbox \
        "\nPlease enter a password ($passLENGHT chars min.): " 10 48 $initPASSWD 3>&1 1>&2 2>&3)
      cip_repeat=$(whiptail  --backtitle "$backTEXT" --title "Create CI User" --passwordbox \
        "\nPlease repeat the password: " 10 48 $initPASSWD 3>&1 1>&2 2>&3)
      cip_invalid="WARNING Password too short, or not matching! "
    done

    # Set Key name and address
#    myKEY=$(whiptail --backtitle "$backTEXT" --title "Create CI User" --inputbox \
#      "\nSet users SSH Public Key:" \
#      10 48 $initKEY 3>&1 1>&2 2>&3)

#      echo "     -  My key: $myKEY"

}


# Install the needed libguestfs-tools if it'smissing
if dpkg -s libguestfs-tools &>/dev/null; then
    echo -e "The libguestfs-tools was found"
else
  echo -e "\b   Missing libguestfs-tools"
  echo -e "\b   downloading and installing libguestfs-tools ..."
  apt-get update && apt-get install -y libguestfs-tools
fi
rm -f $IMAGE_NAME
wget -q $IMAGE_URL -O $IMAGE_NAME
qemu-img resize $IMAGE_NAME 32G
qm destroy $VMID
qm create $VMID --name "ubuntu-plucky-template" --ostype l26 \
    --memory 2048 --balloon 0 \
    --agent 1,fstrim_cloned_disks=1 \
    --bios ovmf --machine q35 --efidisk0 $STORAGE:0,pre-enrolled-keys=0 \
    --cpu host --socket 1 --cores 2 \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0
qm importdisk $VMID $IMAGE_NAME $STORAGE
qm set $VMID --scsihw virtio-scsi-pci --virtio0 $STORAGE:vm-$VMID-disk-1,discard=on
qm set $VMID --boot order=virtio0
qm set $VMID --scsi1 $STORAGE:cloudinit
mkdir -p /var/lib/vz/snippets
cat << EOF | tee /var/lib/vz/snippets/ubuntu-vendor-basic.yaml
#cloud-config

system_info:
  default_user:
    name: m3te0r
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups:
      - wheel
      - sudo
      - docker
chpasswd: { expire: False }
ssh_pwauth: True
package_update: true
package_upgrade: true

apt:
  sources:
    docker.list:
      source: deb [arch=amd64] https://download.docker.com/linux/ubuntu plucky stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

# create the docker group
groups:
  - docker

packages:
  - qemu-guest-agent
  - nano
  - ncurses-term
  - git
  - bat
  - curl
  - htop
  - apt-transport-https
  - ca-certificates
  - gnupg
  - software-properties-common
  - lsb-release
  - unattended-upgrades
  - bashtop
  - zsh
  - fastfetch
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin

timezone: Europe/Paris

# Enable ipv4 forwarding, required on CIS hardened machines
write_files:
  - path: /etc/sysctl.d/enabled_ipv4_forwarding.conf
    content: |
      net.ipv4.conf.all.forwarding=1

runcmd:
    - cp /etc/zsh/newuser.zshrc.recommended /home/m3te0r/.zshrc
    - chsh -s /usr/bin/zsh m3te0r
    - runuser -l m3te0r -c 'sh -c "\$(curl -fsSL https://raw.githubusercontent.com/coreycole/oh-my-zsh/master/tools/install.sh)"'
    - runuser -l m3te0r -c 'sh -c "\$(curl -fsSL https://raw.githubusercontent.com/M3te0r/dotfiles/main/install.sh)"'
    - systemctl enable ssh
    - systemctl start ssh
    - systemctl enable qemu-guest-agent
    - systemctl start qemu-guest-agent
    - systemctl restart systemd-sysctl
    - reboot

final_message: "The system is finally up"

EOF

qm set $VMID --cicustom "vendor=local:snippets/ubuntu-vendor-basic.yaml"
qm set $VMID --tags ubuntu-template,pluck,cloudinit
#setUSER
qm set $VMID --cipassword
qm set $VMID --ipconfig0 ip=dhcp
qm template $VMID
