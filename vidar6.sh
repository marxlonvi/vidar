#!/bin/bash

# ================= KONFIGURASI AUTO-UPDATE =================
SCRIPT_URL="https://raw.githubusercontent.com/marxlonvi/vidar/refs/heads/main/vidar6.sh"
SCRIPT_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"

check_update() {
    if [ "$SKIP_UPDATE" == "1" ]; then
        return
    fi

    TMP_SCRIPT="/tmp/roblox_autojoin_latest.sh"
    if command -v curl &> /dev/null; then
        curl -sL "$SCRIPT_URL" -o "$TMP_SCRIPT" 2>/dev/null
    else
        return
    fi

    if [ ! -s "$TMP_SCRIPT" ]; then
        rm -f "$TMP_SCRIPT"
        return
    fi

    if ! cmp -s "$TMP_SCRIPT" "$SCRIPT_PATH" 2>/dev/null; then
        echo "[*] Versi baru terdeteksi! Memperbarui script..."
        cp "$TMP_SCRIPT" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        rm -f "$TMP_SCRIPT"
        echo "[+] Update selesai. Menjalankan ulang script..."
        sleep 1
        SKIP_UPDATE=1 exec bash "$SCRIPT_PATH" "$@"
        exit 0
    fi

    rm -f "$TMP_SCRIPT"
}

# Auto-update aktif secara default.
# SCRIPT_URL di atas sudah pakai format TANPA commit-hash
# (.../<gistid>/raw/<filename>) sehingga otomatis selalu mengambil
# revisi TERBARU dari gist tanpa perlu diedit ulang tiap kali kamu
# update gist-nya. Kalau suatu saat mau matikan sementara:
#   SKIP_UPDATE=1 bash vidar2.sh
check_update "$@"
# =============================================================

# Variabel Global & File Konfigurasi
BG_PID=""
ROBLOX_PS_LINK=""
DELAY_TIME=60
ACTIVE_PACKAGES=()
AUTO_GRID=true

CONFIG_FILE="$HOME/.vidar_config"
PID_FILE="$HOME/.vidar_pid"
CACHE_PID_FILE="$HOME/.vidar_cache_pid"
AUTO_CLEAR_CACHE=false
CACHE_INTERVAL=300
CACHE_PID=""

# Simpan Konfigurasi
save_config() {
    {
        echo "ROBLOX_PS_LINK=\"$ROBLOX_PS_LINK\""
        echo "DELAY_TIME=\"$DELAY_TIME\""
        echo "AUTO_GRID=\"$AUTO_GRID\""
        echo "ACTIVE_PACKAGES=(${ACTIVE_PACKAGES[*]@Q})"
        echo "AUTO_CLEAR_CACHE=\"$AUTO_CLEAR_CACHE\""
        echo "CACHE_INTERVAL=\"$CACHE_INTERVAL\""
    } > "$CONFIG_FILE"
}

# Muat Konfigurasi
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" 2>/dev/null
    fi
    if [ -f "$PID_FILE" ]; then
        SAVED_PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$SAVED_PID" ] && kill -0 "$SAVED_PID" 2>/dev/null; then
            BG_PID="$SAVED_PID"
        else
            rm -f "$PID_FILE"
        fi
    fi
    if [ -f "$CACHE_PID_FILE" ]; then
        SAVED_CACHE_PID=$(cat "$CACHE_PID_FILE" 2>/dev/null)
        if [ -n "$SAVED_CACHE_PID" ] && kill -0 "$SAVED_CACHE_PID" 2>/dev/null; then
            CACHE_PID="$SAVED_CACHE_PID"
        else
            rm -f "$CACHE_PID_FILE"
        fi
    fi
}

# Hentikan Bot Background
stop_rejoin() {
    if [ -f "$PID_FILE" ]; then
        SAVED_PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$SAVED_PID" ] && kill -0 "$SAVED_PID" 2>/dev/null; then
            kill "$SAVED_PID" 2>/dev/null
            echo ""
            echo "[i] Auto-rejoin di background telah dihentikan (PID: $SAVED_PID)."
        fi
        rm -f "$PID_FILE"
    elif [ -n "$BG_PID" ] && kill -0 "$BG_PID" 2>/dev/null; then
        kill "$BG_PID" 2>/dev/null
        echo ""
        echo "[i] Auto-rejoin di background telah dihentikan (PID: $BG_PID)."
    fi
    BG_PID=""
}

# Hentikan Auto-Clear Cache Background
stop_cache_clear() {
    if [ -f "$CACHE_PID_FILE" ]; then
        SAVED_CACHE_PID=$(cat "$CACHE_PID_FILE" 2>/dev/null)
        if [ -n "$SAVED_CACHE_PID" ] && kill -0 "$SAVED_CACHE_PID" 2>/dev/null; then
            kill "$SAVED_CACHE_PID" 2>/dev/null
            echo ""
            echo "[i] Auto-clear cache di background telah dihentikan (PID: $SAVED_CACHE_PID)."
        fi
        rm -f "$CACHE_PID_FILE"
    elif [ -n "$CACHE_PID" ] && kill -0 "$CACHE_PID" 2>/dev/null; then
        kill "$CACHE_PID" 2>/dev/null
        echo ""
        echo "[i] Auto-clear cache di background telah dihentikan (PID: $CACHE_PID)."
    fi
    CACHE_PID=""
}

# Jalankan Auto-Clear Cache Background
start_cache_clear() {
    stop_cache_clear

    (
        FIRST_CACHE_RUN=true
        while true; do
            if [ "$FIRST_CACHE_RUN" = true ]; then
                # Pengecualian: pembersihan cache pertama kali cukup jeda 3 detik saja
                sleep 3
                FIRST_CACHE_RUN=false
            else
                sleep "$CACHE_INTERVAL"
            fi

            if [ ${#ACTIVE_PACKAGES[@]} -gt 0 ]; then
                # ROOT: hapus isi folder cache tiap package aktif saja.
                # Hanya folder /cache & /code_cache yang disentuh -> data/login TIDAK terhapus.
                for pkg in "${ACTIVE_PACKAGES[@]}"; do
                    su -c "rm -rf /data/data/$pkg/cache/* /data/data/$pkg/code_cache/*" >/dev/null 2>&1
                done
            else
                # Fallback: pangkas cache sistem jika belum ada package terpilih
                su -c "pm trim-caches 999999999999" >/dev/null 2>&1
            fi
        done
    ) &

    CACHE_PID=$!
    echo "$CACHE_PID" > "$CACHE_PID_FILE"
}

# Muat Config & Wake-Lock
load_config
if command -v termux-wake-lock &> /dev/null; then
    termux-wake-lock
fi

# Jika sebelumnya AUTO_CLEAR_CACHE aktif tapi proses background belum jalan, nyalakan ulang
if [ "$AUTO_CLEAR_CACHE" = true ] && [ -z "$CACHE_PID" ]; then
    start_cache_clear
fi

# Menu 1: Link Private Server
setup_link() {
    clear
    echo "================================================="
    echo "       PENGATURAN LINK PRIVATE SERVER (PS)"
    echo "================================================="
    echo "Link saat ini: ${ROBLOX_PS_LINK:-Belum diatur}"
    echo "-------------------------------------------------"
    read -p "Masukkan Link Private Server (PS) Roblox baru: " input_link
    
    if [ -n "$input_link" ]; then
        ROBLOX_PS_LINK="$input_link"
        save_config
        echo ""
        echo "[+] Link PS berhasil disimpan!"
    else
        echo ""
        echo "[x] Error: Link tidak boleh kosong!"
    fi
    sleep 2
}

# Menu 2: Package & Delay
setup_package() {
    clear
    echo "================================================="
    echo "       PENGATURAN PACKAGE  "
    echo "================================================="
    echo "[*] Mendeteksi Roblox & Clone..."

    ACTIVE_PACKAGES=()
    
    # Murni hanya 1 cara deteksi
    DETECTED_PACKAGES=($(pm list packages -3 2>/dev/null | grep -i "roblox" | sed 's/package://g' | sort -u))

    # Jika benar-benar kosong di sistem
    if [ ${#DETECTED_PACKAGES[@]} -eq 0 ]; then
        echo ""
        echo "[!] Tidak ada aplikasi dengan nama 'roblox' yang terdeteksi."
        read -p "Tekan Enter untuk kembali ke menu..."
        return
    fi

    echo ""
    echo "-------------------------------------------------"
    echo " DAFTAR PACKAGE ROBLOX:"
    echo "-------------------------------------------------"
    for i in "${!DETECTED_PACKAGES[@]}"; do
        echo " [$((i + 1))] ${DETECTED_PACKAGES[$i]}"
    done
    echo "-------------------------------------------------"
    read -p " Pilihan kamu: " SELECT_INPUT

    if [ -z "$SELECT_INPUT" ] || [ "${SELECT_INPUT,,}" == "all" ]; then
        ACTIVE_PACKAGES=("${DETECTED_PACKAGES[@]}")
    else
        for NUM in $SELECT_INPUT; do
            if [[ "$NUM" =~ ^[0-9]+$ ]]; then
                IDX=$((NUM - 1))
                if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#DETECTED_PACKAGES[@]}" ]; then
                    ACTIVE_PACKAGES+=("${DETECTED_PACKAGES[$IDX]}")
                fi
            fi
        done
    fi

    echo ""
    echo "-------------------------------------------------"
    echo " STATUS AKHIR PACKAGE SELEKSI:"
    echo "-------------------------------------------------"
    for pkg in "${DETECTED_PACKAGES[@]}"; do
        IS_ACTIVE=false
        for active in "${ACTIVE_PACKAGES[@]}"; do
            if [ "$active" == "$pkg" ]; then
                IS_ACTIVE=true
                break
            fi
        done

        if [ "$IS_ACTIVE" = true ]; then
            echo " [ ON  ]  $pkg"
        else
            echo " [ OFF ]  $pkg"
        fi
    done
    echo "-------------------------------------------------"

    if [ ${#ACTIVE_PACKAGES[@]} -eq 0 ]; then
        echo ""
        echo "[x] Error: Tidak ada package yang diaktifkan!"
        sleep 2
        return
    fi

    echo ""
    read -p "Masukkan jeda waktu antar-app (detik, default 30): " input_delay
    DELAY_TIME=${input_delay:-30}

    echo ""
    echo "[+] Konfigurasi berhasil disimpan!"
    save_config
    sleep 2
}

# Menu 3: Toggle Auto Grid
setup_autogrid() {
    clear
    echo "================================================="
    echo "       PENGATURAN AUTO-GRID LAYOUT"
    echo "================================================="
    echo "Status saat ini: $( [ "$AUTO_GRID" = true ] && echo "[AKTIF]" || echo "[MATI]" )"
    echo "-------------------------------------------------"
    read -p "Aktifkan Auto-Grid Layout? (y/n): " grid_choice
    
    if [[ "$grid_choice" =~ ^[Yy]$ ]]; then
        AUTO_GRID=true
        echo ""
        echo "[+] Auto-Grid Layout berhasil DIAKTIFKAN!"
    else
        AUTO_GRID=false
        echo ""
        echo "[+] Auto-Grid Layout dimatikan."
    fi
    save_config
    sleep 2
}

# Menu: Toggle Auto-Clear Cache Background
setup_autoclear_cache() {
    clear
    echo "================================================="
    echo "       PENGATURAN AUTO-CLEAR CACHE (BACKGROUND)"
    echo "================================================="
    echo "Status saat ini : $( [ "$AUTO_CLEAR_CACHE" = true ] && echo "[AKTIF]" || echo "[MATI]" )"
    echo "Interval saat ini: $CACHE_INTERVAL detik"
    echo "-------------------------------------------------"
    echo "Mode: ROOT — cache tiap package aktif (Menu 2)"
    echo "dibersihkan langsung via 'su' setiap interval."
    echo "Hanya folder cache/code_cache yang dihapus,"
    echo "data login TIDAK ikut terhapus."
    echo "-------------------------------------------------"
    read -p "Aktifkan Auto-Clear Cache di background? (y/n): " cc_choice

    if [[ "$cc_choice" =~ ^[Yy]$ ]]; then
        read -p "Interval pembersihan cache (detik, default 300): " input_interval
        CACHE_INTERVAL=${input_interval:-300}
        AUTO_CLEAR_CACHE=true
        start_cache_clear
        echo ""
        echo "[+] Auto-Clear Cache berhasil DIAKTIFKAN!"
        echo "    Pembersihan pertama: 3 detik lagi. Selanjutnya tiap $CACHE_INTERVAL detik."
    else
        AUTO_CLEAR_CACHE=false
        stop_cache_clear
        echo ""
        echo "[+] Auto-Clear Cache dimatikan."
    fi
    save_config
    sleep 2
}

# Menu 4: Jalankan Rejoin Background (DELAY PER-APP)
start_rejoin() {
    if [ -z "$ROBLOX_PS_LINK" ] || [ ${#ACTIVE_PACKAGES[@]} -eq 0 ]; then
        echo ""
        echo "[!] Harap atur Link PS (Menu 1) dan Package (Menu 2) terlebih dahulu!"
        sleep 2
        return
    fi

    stop_rejoin

    echo ""
    echo "[*] Auto-Rejoin mulai berjalan di background..."
    echo "[*] Clone pertama dibuka setelah jeda 3 detik (start cepat)."
    echo "[*] Clone berikutnya & siklus selanjutnya pakai jeda $DELAY_TIME detik."

    (
        FIRST_RUN=true
        while true; do
            for pkg in "${ACTIVE_PACKAGES[@]}"; do
                if [ "$FIRST_RUN" = true ]; then
                    # Pengecualian: clone pertama kali dibuka cukup jeda 3 detik saja
                    sleep 3
                    FIRST_RUN=false
                else
                    sleep "$DELAY_TIME"
                fi

                am start -a android.intent.action.VIEW -n "$pkg/com.roblox.client.ActivityProtocolRedirector" -d "$ROBLOX_PS_LINK" >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                    am start -a android.intent.action.VIEW -p "$pkg" -d "$ROBLOX_PS_LINK" >/dev/null 2>&1
                fi
                
                if [ "$AUTO_GRID" = true ]; then
                    sleep 1
                    am task stack resize 2>/dev/null || true
                fi
            done
        done
    ) &

    BG_PID=$!
    echo "$BG_PID" > "$PID_FILE"
    echo "[+] Auto-rejoin Berhasil Dijadwalkan! (Background PID: $BG_PID)"
    sleep 2
}

# Cek Status Aplikasi Running (BATCH - 1x panggilan su untuk semua package)
# Mengisi associative array global PKG_STATUS[pkg]="online"/"offline"
declare -A PKG_STATUS

refresh_pkg_status() {
    local cmd=""
    for pkg in "${ACTIVE_PACKAGES[@]}"; do
        cmd+="pidof $pkg >/dev/null 2>&1 && echo O:$pkg || echo X:$pkg; "
    done

    local RESULT
    RESULT=$(su -c "$cmd" 2>/dev/null)

    if [ -z "$RESULT" ]; then
        # fallback non-root jika su gagal/tidak tersedia
        for pkg in "${ACTIVE_PACKAGES[@]}"; do
            if pidof "$pkg" &>/dev/null || ps -A 2>/dev/null | grep -q "$pkg"; then
                PKG_STATUS[$pkg]="online"
            else
                PKG_STATUS[$pkg]="offline"
            fi
        done
        return
    fi

    while IFS=: read -r flag pkg; do
        [ -z "$pkg" ] && continue
        if [ "$flag" == "O" ]; then
            PKG_STATUS[$pkg]="online"
        else
            PKG_STATUS[$pkg]="offline"
        fi
    done <<< "$RESULT"
}

# Menu 6: Monitoring Status Live (Tanpa Username, Sesuai UI HP)
monitor_services() {
    if [ ${#ACTIVE_PACKAGES[@]} -eq 0 ]; then
        echo -e "\e[31m[!] Belum ada package yang diatur. Atur dulu lewat Menu 2.\e[0m"
        sleep 2
        return
    fi

    # Definisi Warna ANSI
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    ORANGE='\033[38;5;208m'
    WHITE='\033[1;37m'
    NC='\033[0m' # No Color

    read -p "Interval refresh monitor (detik, default 5, makin besar makin ringan): " MON_INTERVAL_INPUT
    MON_INTERVAL=${MON_INTERVAL_INPUT:-5}
    [[ "$MON_INTERVAL" =~ ^[0-9]+$ ]] || MON_INTERVAL=5
    [ "$MON_INTERVAL" -lt 1 ] && MON_INTERVAL=1

    while true; do
        refresh_pkg_status
        clear

        # 1. Hitung Sisa Memory (RAM) murni (MemFree) agar sesuai UI HP
        if [ -f /proc/meminfo ]; then
            MEM_FREE_KB=$(grep -w MemFree /proc/meminfo | awk '{print $2}')
            MEM_TOTAL_KB=$(grep -w MemTotal /proc/meminfo | awk '{print $2}')
            
            MEM_FREE_MB=$((MEM_FREE_KB / 1024))
            MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
            
            if [ "$MEM_TOTAL_MB" -gt 0 ]; then
                MEM_PCT=$(( 100 * MEM_FREE_KB / MEM_TOTAL_KB ))
            else
                MEM_PCT=0
            fi
            MEM_INFO="${MEM_PCT}% (${MEM_FREE_MB}M)"
        else
            MEM_INFO="Free: Unknown"
        fi

        # 2. Hitung jumlah package yang sedang Online (dari hasil batch refresh_pkg_status)
        TOTAL_PKG=${#ACTIVE_PACKAGES[@]}
        AKTIF_COUNT=0
        for pkg in "${ACTIVE_PACKAGES[@]}"; do
            if [ "${PKG_STATUS[$pkg]}" == "online" ]; then
                AKTIF_COUNT=$((AKTIF_COUNT + 1))
            fi
        done

        # 3. Info System & Memory (format list mini, fixed width kecil)
        echo "------------------------"
        echo " Online: ${AKTIF_COUNT}/${TOTAL_PKG}  RAM: ${MEM_INFO}"
        echo "------------------------"

        # 4. Daftar Package (format list mini)
        for pkg in "${ACTIVE_PACKAGES[@]}"; do
            if [ "${PKG_STATUS[$pkg]}" == "online" ]; then
                echo -e "${GREEN}ON  $pkg${NC}"
            else
                echo "OFF $pkg"
            fi
        done

        echo "------------------------"
        echo "Refresh ${MON_INTERVAL}d, 'q' keluar"
        
        # Auto-refresh sesuai interval yang dipilih. Tekan 'q' untuk keluar.
        read -t "$MON_INTERVAL" -n 1 KEY
        if [[ "$KEY" == "q" || "$KEY" == "Q" ]]; then
            break
        fi
    done
}

# Menu 7: Force Close Semua Clone Aktif
force_close_clones() {
    if [ ${#ACTIVE_PACKAGES[@]} -eq 0 ]; then
        echo -e "\e[31m[!] Belum ada package yang diatur. Atur dulu lewat Menu 2.\e[0m"
        sleep 2
        return
    fi
    
    echo ""
    echo "[*] Menutup paksa (Force Close) semua clone Roblox..."
    for pkg in "${ACTIVE_PACKAGES[@]}"; do
        echo " -> Mematikan: $pkg"
        su -c "am force-stop $pkg" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            # fallback tanpa root (kemungkinan besar tetap gagal tanpa izin sistem)
            am force-stop "$pkg" >/dev/null 2>&1
        fi
    done
    echo "[+] Semua clone berhasil ditutup!"
    sleep 2
}

# --- MENU UTAMA ---
while true; do
    clear
    echo "================================================="
    echo "   ROBLOX AUTO-JOIN / REJOIN PS (MULTI-CLONE)"
    echo "================================================="
    
    if [ -n "$BG_PID" ] && kill -0 "$BG_PID" 2>/dev/null; then
        echo " Status Bot : [ RUNNING ] (PID: $BG_PID)"
    else
        echo " Status Bot : [ STOPPED ]"
    fi
    echo " Link PS    : ${ROBLOX_PS_LINK:-Belum diatur}"
    echo " Pkg Aktif  : ${ACTIVE_PACKAGES[*]:-Belum diatur}"
    echo " Jeda Waktu : $DELAY_TIME detik per-app"
    echo " Auto-Grid  : $( [ "$AUTO_GRID" = true ] && echo "AKTIF" || echo "MATI" )"
    if [ -n "$CACHE_PID" ] && kill -0 "$CACHE_PID" 2>/dev/null; then
        echo " Auto-Clear Cache : [ RUNNING ] tiap ${CACHE_INTERVAL}s (PID: $CACHE_PID)"
    else
        echo " Auto-Clear Cache : $( [ "$AUTO_CLEAR_CACHE" = true ] && echo "[AKTIF tapi belum jalan]" || echo "[MATI]" )"
    fi
    if [ -f "$CONFIG_FILE" ]; then
        echo " Config     : Dimuat dari $CONFIG_FILE"
    fi
    echo "================================================="
    echo "1. Setting Link Private Server (PS)"
    echo "2. Setting Package & Delay"
    echo "3. Atur Fitur Auto-Grid Layout"
    echo "4. Mulai Auto-Rejoin"
    echo "5. Stop Auto-Rejoin"
    echo "6. Monitoring Layanan (Tabel Live)"
    echo "7. Force Close Semua Clone"
    echo "8. Reset Config Tersimpan"
    echo "9. Keluar (Exit)"
    echo "10. Toggle Auto-Clear Cache (Background)"
    echo "================================================="
    read -p "Pilih menu (1-10): " MENU_CHOICE

    case "$MENU_CHOICE" in
        1) setup_link ;;
        2) setup_package ;;
        3) setup_autogrid ;;
        4) start_rejoin ;;
        5) 
            stop_rejoin
            sleep 1
            ;;
        6) monitor_services ;;
        7) force_close_clones ;;
        8)
            read -p "Yakin hapus config tersimpan? (y/n): " CONFIRM_RESET
            if [[ "$CONFIRM_RESET" =~ ^[Yy]$ ]]; then
                stop_rejoin
                stop_cache_clear
                rm -f "$CONFIG_FILE" "$PID_FILE" "$CACHE_PID_FILE"
                ROBLOX_PS_LINK=""
                DELAY_TIME=30
                ACTIVE_PACKAGES=()
                AUTO_GRID=false
                AUTO_CLEAR_CACHE=false
                CACHE_INTERVAL=300
                echo ""
                echo "[+] Config berhasil direset."
            else
                echo ""
                echo "[i] Dibatalkan."
            fi
            sleep 1
            ;;
        9)
            stop_rejoin
            stop_cache_clear
            echo ""
            echo "[*] Keluar dari program. Terima kasih!"
            exit 0
            ;;
        10) setup_autoclear_cache ;;
        *)
            echo ""
            echo "[x] Pilihan tidak valid!"
            sleep 1
            ;;
    esac
done
