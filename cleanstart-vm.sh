#!/usr/bin/env bash
#
# Bersihkan state VM VirtualBox setelah power loss / startup error.
# Membersihkan lock file, saved state, dan proses VirtualBox yang nyangkut,
# lalu mencoba start ulang VM.
#
# Usage:
#   ./cleanstart-vm.sh <nama-vm> [--no-start]
#   ./cleanstart-vm.sh --create-service <nama-vm>

set -euo pipefail

SERVICE_NAME="cleanstart-vm"
INSTALL_PATH="/usr/local/bin/cleanstart-vm"

# ─── Fungsi: buat systemd service ────────────────────────────────────────────
cmd_create_service() {
  local vm="$1"

  if [[ "$EUID" -ne 0 ]]; then
    echo "Error: --create-service harus dijalankan dengan sudo."
    echo "  Coba: sudo $0 --create-service \"$vm\""
    exit 1
  fi

  # Tentukan user nyata di balik sudo — harus dilakukan sebelum memanggil
  # VBoxManage, karena registry VM bersifat per-user dan tidak terlihat oleh root
  local real_user="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"

  # Pastikan VM-nya ada (jalankan sebagai real_user, bukan root)
  if ! sudo -u "$real_user" VBoxManage list vms | grep -q "\"$vm\""; then
    echo "Error: VM '$vm' tidak ditemukan untuk user '$real_user'."
    echo ""
    echo "VM yang tersedia:"
    sudo -u "$real_user" VBoxManage list vms | sed 's/^/  /'
    exit 1
  fi
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

  # Tentukan path binary yang akan dipanggil service
  local exec_path
  if command -v cleanstart-vm &>/dev/null; then
    exec_path="$(command -v cleanstart-vm)"
  else
    exec_path="$INSTALL_PATH"
  fi

  echo "═══════════════════════════════════════════════════════════════"
  echo "  Membuat systemd service untuk VM: $vm"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  cat > "$service_file" <<EOF
[Unit]
Description=Auto-start VM '$vm' on boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$real_user
ExecStart=$exec_path "$vm"
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"

  echo "✓ Service '$SERVICE_NAME' berhasil dibuat dan diaktifkan."
  echo ""
  echo "  VM '$vm' akan otomatis menyala setiap kali komputer boot."
  echo ""
  echo "  Perintah berguna:"
  echo "    sudo systemctl status $SERVICE_NAME"
  echo "    sudo systemctl start  $SERVICE_NAME"
  echo "    sudo systemctl stop   $SERVICE_NAME"
  echo "    sudo systemctl disable $SERVICE_NAME"
  echo "    sudo journalctl -u $SERVICE_NAME -f"
  exit 0
}

# ─── Input & validasi ────────────────────────────────────────────────────────
ARG1="${1:-}"
ARG2="${2:-}"

if [[ "$ARG1" == "--create-service" ]]; then
  if [[ -z "$ARG2" ]]; then
    echo "Usage: $0 --create-service <nama-vm>"
    echo ""
    echo "VM yang tersedia:"
    VBoxManage list vms | sed 's/^/  /'
    exit 1
  fi
  cmd_create_service "$ARG2"
fi

VM_NAME="$ARG1"
NO_START="$ARG2"

if [[ -z "$VM_NAME" ]]; then
  echo "Usage:"
  echo "  $0 <nama-vm> [--no-start]"
  echo "  $0 --create-service <nama-vm>"
  echo ""
  echo "VM yang tersedia:"
  VBoxManage list vms | sed 's/^/  /'
  exit 1
fi

# Pastikan VM-nya ada
if ! VBoxManage list vms | grep -q "\"$VM_NAME\""; then
  echo "Error: VM '$VM_NAME' tidak ditemukan."
  echo ""
  echo "VM yang tersedia:"
  VBoxManage list vms | sed 's/^/  /'
  exit 1
fi

VM_DIR="$HOME/VirtualBox VMs/$VM_NAME"
[[ -d "$VM_DIR" ]] || { echo "Error: folder VM tidak ditemukan: $VM_DIR"; exit 1; }

echo "═══════════════════════════════════════════════════════════════"
echo "  Cleanup VM: $VM_NAME"
echo "  Folder    : $VM_DIR"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ─── Cek state awal ──────────────────────────────────────────────────────────
INITIAL_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null \
                | grep -oP '^VMState="\K[^"]+' || echo "unknown")
echo "→ State awal: $INITIAL_STATE"

# Kalau VM sudah jalan dengan state sehat, tidak perlu cleanup
if [[ "$INITIAL_STATE" == "running" ]]; then
  echo "✓ VM sudah jalan. Tidak ada yang perlu dibersihkan."
  exit 0
fi

# ─── Step 1: Kill proses VirtualBox yang nyangkut ────────────────────────────
echo ""
echo "→ [1/4] Cek proses VirtualBox yang nyangkut..."
STUCK_PROCS=$(pgrep -af "VBoxHeadless.*$VM_NAME" 2>/dev/null || true)
if [[ -n "$STUCK_PROCS" ]]; then
  echo "   Ditemukan proses nyangkut:"
  echo "$STUCK_PROCS" | sed 's/^/     /'
  pkill -9 -f "VBoxHeadless.*$VM_NAME" 2>/dev/null || true
  sleep 2
  echo "   ✓ Proses dimatikan."
else
  echo "   ✓ Tidak ada proses VBoxHeadless yang nyangkut."
fi

# ─── Step 2: Discard saved state kalau ada ───────────────────────────────────
echo ""
echo "→ [2/4] Discard saved state..."
if [[ "$INITIAL_STATE" == "saved" || "$INITIAL_STATE" == "aborted-saved" ]]; then
  VBoxManage discardstate "$VM_NAME" && echo "   ✓ Saved state dibuang." \
    || echo "   ⚠ Gagal discard state (mungkin sudah tidak ada)."
else
  echo "   ✓ Tidak ada saved state untuk dibuang (state: $INITIAL_STATE)."
fi

# ─── Step 3: Hapus lock files dan file temporary ─────────────────────────────
echo ""
echo "→ [3/4] Bersihkan lock files & file temporary..."
LOCK_COUNT=$(find "$VM_DIR" -type f \( -name "*.lock" -o -name "*.tmp" \) 2>/dev/null | wc -l)
if [[ $LOCK_COUNT -gt 0 ]]; then
  echo "   Ditemukan $LOCK_COUNT file lock/tmp:"
  find "$VM_DIR" -type f \( -name "*.lock" -o -name "*.tmp" \) -print | sed 's/^/     /'
  find "$VM_DIR" -type f \( -name "*.lock" -o -name "*.tmp" \) -delete
  echo "   ✓ File dihapus."
else
  echo "   ✓ Tidak ada lock/tmp file yang perlu dibersihkan."
fi

# ─── Step 4: Verifikasi state akhir sebelum start ────────────────────────────
echo ""
echo "→ [4/4] Verifikasi state setelah cleanup..."
FINAL_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null \
              | grep -oP '^VMState="\K[^"]+' || echo "unknown")
echo "   State sekarang: $FINAL_STATE"

if [[ "$FINAL_STATE" != "poweroff" && "$FINAL_STATE" != "aborted" ]]; then
  echo ""
  echo "⚠ State VM bukan 'poweroff' atau 'aborted' (sekarang: $FINAL_STATE)."
  echo "  Mungkin perlu intervensi manual. Cek log:"
  echo "    tail -50 \"$VM_DIR/Logs/VBox.log\""
  exit 1
fi

# ─── Start VM (kecuali --no-start) ───────────────────────────────────────────
echo ""
if [[ "$NO_START" == "--no-start" ]]; then
  echo "✓ Cleanup selesai. VM tidak di-start (--no-start)."
  echo "  Untuk start manual: VBoxManage startvm \"$VM_NAME\" --type headless"
  exit 0
fi

echo "═══════════════════════════════════════════════════════════════"
echo "  Starting VM headless..."
echo "═══════════════════════════════════════════════════════════════"
VBoxManage startvm "$VM_NAME" --type headless

echo ""
echo "✓ Selesai. VM '$VM_NAME' sudah jalan."
echo "  Cek status: VBoxManage list runningvms"
echo "  SSH       : ssh -p 2200 <user>@127.0.0.1"