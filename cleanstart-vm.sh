#!/usr/bin/env bash
#
# Bersihkan state VM VirtualBox setelah power loss / startup error.
# Membersihkan lock file, saved state, dan proses VirtualBox yang nyangkut,
# lalu mencoba start ulang VM.
#
# Usage: ./cleanup-vm.sh <nama-vm> [--no-start]

set -euo pipefail

# ─── Input & validasi ────────────────────────────────────────────────────────
VM_NAME="${1:-}"
NO_START="${2:-}"

if [[ -z "$VM_NAME" ]]; then
  echo "Usage: $0 <nama-vm> [--no-start]"
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