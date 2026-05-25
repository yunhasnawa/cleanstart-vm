#!/bin/bash

# ============================================================
#  Installer for cleanstart-vm
#  GitHub: https://github.com/yunhasnawa/cleanstart-vm
#  Usage:
#    Install only:       ./install.sh
#    Install + Service:  ./install.sh "nama-vm"
# ============================================================

set -e  # Exit immediately on error

# --- Config ---
GITHUB_USER="yunhasnawa"
REPO_NAME="cleanstart-vm"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"
INSTALL_PATH="/usr/local/bin/cleanstart-vm"
SERVICE_NAME="cleanstart-vm"
VM_NAME="${1:-}"  # Optional: nama VM dari parameter pertama

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helpers ---
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Check root ---
if [ "$EUID" -ne 0 ]; then
    error "Script ini harus dijalankan dengan sudo.\nCoba: sudo bash install.sh"
fi

# ============================================================
# STEP 1: Download dan install cleanstart-vm
# ============================================================
echo ""
echo "========================================"
echo "  Installing cleanstart-vm"
echo "========================================"
echo ""

info "Mengunduh cleanstart-vm.sh dari GitHub..."
curl -fsSL "$RAW_BASE/cleanstart-vm.sh" -o "$INSTALL_PATH" \
    || error "Gagal mengunduh script. Periksa koneksi internet atau URL repository."

info "Mengatur permission..."
chmod 755 "$INSTALL_PATH"
chown root:root "$INSTALL_PATH"

success "cleanstart-vm berhasil diinstall di $INSTALL_PATH"
echo ""

# Verifikasi
if command -v cleanstart-vm &>/dev/null; then
    success "Command 'cleanstart-vm' siap digunakan dari mana saja."
else
    warn "Command tidak ditemukan di PATH. Pastikan /usr/local/bin ada di PATH Anda."
fi

# ============================================================
# STEP 2: (Opsional) Buat systemd service
# ============================================================
if [ -n "$VM_NAME" ]; then

    echo ""
    echo "========================================"
    echo "  Creating Systemd Service"
    echo "  VM: $VM_NAME"
    echo "========================================"
    echo ""

    # Dapatkan user yang menjalankan sudo (bukan root)
    REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo $USER)}"

    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    info "Membuat service file di $SERVICE_FILE..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto-start VM '$VM_NAME' on boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$REAL_USER
ExecStart=$INSTALL_PATH "$VM_NAME"
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    info "Mengaktifkan service..."
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"

    success "Service '${SERVICE_NAME}' berhasil dibuat dan diaktifkan."
    echo ""
    info "VM '$VM_NAME' akan otomatis menyala setiap kali komputer boot."

else
    echo ""
    warn "Tidak ada nama VM yang diberikan. Service tidak dibuat."
    info "Untuk membuat service, jalankan ulang installer dengan nama VM:"
    echo ""
    echo "  curl -sSL $RAW_BASE/install.sh | sudo bash -s -- \"nama-vm\""
    echo ""
fi

# ============================================================
# DONE
# ============================================================
echo ""
echo "========================================"
echo -e "  ${GREEN}Instalasi selesai!${NC}"
echo "========================================"
echo ""
info "Cara penggunaan:"
echo "  cleanstart-vm \"nama-vm\""
echo ""
if [ -n "$VM_NAME" ]; then
    info "Cek status service:"
    echo "  sudo systemctl status $SERVICE_NAME"
    echo "  sudo journalctl -u $SERVICE_NAME -f"
    echo ""
fi