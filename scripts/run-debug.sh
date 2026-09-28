#!/usr/bin/env bash
set -e

# ==============================================================================
# Script Runner Debug Mode untuk TossShare
# Menjalankan TossShare di foreground dengan streaming log ANSI berwarna realtime.
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🛑 Menghentikan instance TossShare lama..."
killall TossShare 2>/dev/null || true
sleep 1

echo "📦 Memperbarui bundle TossShare.app..."
"$PROJECT_DIR/scripts/package-app.sh"
cp -R "$PROJECT_DIR/TossShare.app" /Applications/

echo ""
echo "======================================================================"
echo "🚀 TossShare Live Debug Mode Siap!"
echo "======================================================================"
echo "👉 Jendela aplikasi TossShare akan segera terbuka."
echo "👉 Seluruh log koneksi, jabat tangan UKEY2, dan aliran transfer akan"
echo "   tercetak langsung di bawah ini secara realtime."
echo "👉 Tekan Ctrl+C di terminal ini untuk menghentikan aplikasi."
echo "======================================================================"
echo ""

exec /Applications/TossShare.app/Contents/MacOS/TossShare
