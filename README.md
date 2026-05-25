# cleanstart-vm

A lightweight bash script to **start a VirtualBox VM cleanly** from the terminal — with optional systemd service integration to **auto-start your VM on every boot**.

---

## 📋 Requirements

- Linux (Ubuntu / Debian-based recommended)
- [VirtualBox](https://www.virtualbox.org/) installed
- `curl` installed
- `sudo` access

---

## ⚡ Quick Install

### Install script only

```bash
curl -sSL https://raw.githubusercontent.com/yunhasnawa/cleanstart-vm/main/install.sh | sudo bash
```

### Install + auto-start a VM on boot

```bash
curl -sSL https://raw.githubusercontent.com/yunhasnawa/cleanstart-vm/main/install.sh | sudo bash -s -- "nama-vm"
```

Replace `"nama-vm"` with the **exact name of your VirtualBox VM**.

> **Tip:** To find your VM names, run `VBoxManage list vms`

---

## 🚀 Usage

Once installed, the command is available globally from any directory:

```bash
cleanstart-vm "nama-vm"
```

### Examples

```bash
# Clean state and restart a VM
cleanstart-vm "hadoop-namenode"

# Clean state without restarting
cleanstart-vm "hadoop-namenode" --no-start

# Start multiple VMs one by one
cleanstart-vm "datanode-1"
cleanstart-vm "datanode-2"
cleanstart-vm "datanode-3"
```

---

## 🔧 Auto-start on Boot (Systemd Service)

There are two ways to set up a VM to auto-start on boot:

### Option 1 — During installation (via `install.sh`)

Pass the VM name when running the installer:

```bash
curl -sSL https://raw.githubusercontent.com/yunhasnawa/cleanstart-vm/main/install.sh | sudo bash -s -- "nama-vm"
```

### Option 2 — After installation (via `--create-service`)

Once the script is installed, you can create the service at any time using:

```bash
sudo cleanstart-vm --create-service "nama-vm"
```

Replace `"nama-vm"` with the **exact name of your VirtualBox VM**.

> **Tip:** To find your VM names, run `VBoxManage list vms`

Both options produce the same systemd service. If you already have a service set up and want to point it to a different VM, simply run `--create-service` again with the new VM name.

If you provided a VM name during installation, a systemd service is automatically created and enabled.

### Check service status

```bash
sudo systemctl status cleanstart-vm
```

### View service logs

```bash
sudo journalctl -u cleanstart-vm -f
```

### Manually enable / disable the service

```bash
# Enable (auto-start on boot)
sudo systemctl enable cleanstart-vm

# Disable (no auto-start)
sudo systemctl disable cleanstart-vm
```

### Manually start / stop the service

```bash
sudo systemctl start cleanstart-vm
sudo systemctl stop cleanstart-vm
```

---

## 🔄 Re-install or Update

To update the script to the latest version, simply re-run the installer:

```bash
# Update script only
curl -sSL https://raw.githubusercontent.com/yunhasnawa/cleanstart-vm/main/install.sh | sudo bash

# Update script + recreate service with a VM name
curl -sSL https://raw.githubusercontent.com/yunhasnawa/cleanstart-vm/main/install.sh | sudo bash -s -- "nama-vm"
```

---

## 🗑️ Uninstall

```bash
# Remove the command
sudo rm /usr/local/bin/cleanstart-vm

# Remove the systemd service (if created)
sudo systemctl disable cleanstart-vm
sudo systemctl stop cleanstart-vm
sudo rm /etc/systemd/system/cleanstart-vm.service
sudo systemctl daemon-reload
```

---

## 📁 Repository Structure

```
cleanstart-vm/
├── cleanstart-vm.sh   # Main script
└── install.sh         # Installer
```

---

## 📄 License

MIT License — feel free to use, modify, and distribute.

---

## 👤 Author

**Yoppy Yunhasnawa**
GitHub: [@yunhasnawa](https://github.com/yunhasnawa)