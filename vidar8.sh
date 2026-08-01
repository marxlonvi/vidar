#!/bin/bash

# ================= KONFIGURASI AUTO-UPDATE =================
SCRIPT_VERSION="vidar8"
SCRIPT_URL="https://raw.githubusercontent.com/marxlonvi/vidar/refs/heads/main/vidar8.sh"
SCRIPT_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"

check_update() {
    if [ "$SKIP_UPDATE" = "1" ]; then
        return
    fi

    TMP_SCRIPT="/tmp/vidar8_latest.sh"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT" 2>/dev/null || return
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP_SCRIPT" "$SCRIPT_URL" || return
    else
        return
    fi

    [ ! -s "$TMP_SCRIPT" ] && {
        rm -f "$TMP_SCRIPT"
        return
    }

    if ! cmp -s "$TMP_SCRIPT" "$SCRIPT_PATH"; then
        echo ""
        echo "[*] Update baru ditemukan ($SCRIPT_VERSION)"
        cp "$TMP_SCRIPT" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        rm -f "$TMP_SCRIPT"
        echo "[+] Update selesai."
        sleep 1
        SKIP_UPDATE=1 exec bash "$SCRIPT_PATH" "$@"
        exit
    fi

    rm -f "$TMP_SCRIPT"
}

check_update "$@"
# ===========================================================

# Variabel Global & File Konfigurasi
BG_PID=""
ROBLOX_PS_LINK=""
DELAY_TIME=60
ACTIVE_PACKAGES=()
PACKAGE_CACHE="$HOME/.vidar8_packages"
DETECTED_PACKAGES=()
AUTO_GRID=true

CONFIG_FILE="$HOME/.vidar8_config"
PID_FILE="$HOME/.vidar8_pid"
CACHE_PID_FILE="$HOME/.vidar8_cache_pid"
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
scan_packages() {

    DETECTED_PACKAGES=()

    if [ -f "$PACKAGE_CACHE" ]; then
        mapfile -t DETECTED_PACKAGES < "$PACKAGE_CACHE"

        if [ ${#DETECTED_PACKAGES[@]} -gt 0 ]; then
            return
        fi
    fi

    echo "[*] Mencari clone Roblox..."

    while IFS= read -r pkg
    do
        FOUND=false

        # Metode 1: resolve-activity (kadang exit code 0 walau "No activity found")
        RESOLVE_OUT="$(cmd package resolve-activity --brief \
            "$pkg/com.roblox.client.ActivityProtocolRedirector" 2>/dev/null)"
        if [ -n "$RESOLVE_OUT" ] && ! echo "$RESOLVE_OUT" | grep -qi "no activity found"; then
            FOUND=true
        fi

        # Metode 2: cek langsung ke dumpsys package (lebih toleran, tak perlu resolve-activity)
        if [ "$FOUND" = false ] && dumpsys package "$pkg" 2>/dev/null | grep -q "ActivityProtocolRedirector"; then
            FOUND=true
        fi

        # Metode 3: fallback nama package yang mengandung "roblox"
        if [ "$FOUND" = false ] && echo "$pkg" | grep -qi "roblox"; then
            FOUND=true
        fi

        if [ "$FOUND" = true ]; then
            DETECTED_PACKAGES+=("$pkg")
        fi

    done < <(
        pm list packages | sed 's/package://'
    )

    printf "%s\n" "${DETECTED_PACKAGES[@]}" > "$PACKAGE_CACHE"

}
clean_packages(){

    NEW_LIST=()

    for pkg in "${ACTIVE_PACKAGES[@]}"
    do
        if pm list packages | grep -q "^package:$pkg$"
        then
            NEW_LIST+=("$pkg")
        fi
    done

    ACTIVE_PACKAGES=("${NEW_LIST[@]}")

    save_config

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
scan_packages >/dev/null 2>&1

# Muat Config & Wake-Lock
load_config
clean_packages
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
    echo "          PENGATURAN PACKAGE VIDAR8"
    echo "================================================="
    scan_packages

    if [ ${#DETECTED_PACKAGES[@]} -eq 0 ]; then
        echo ""
        echo "[!] Tidak ditemukan clone Roblox."
        echo ""
        echo "Kemungkinan:"
        echo " - Clone belum pernah dijalankan."
        echo " - Delta Lite belum membuat Activity Roblox."
        echo " - Clone rusak."
        echo ""
        read -p "Tekan Enter..."
        return
    fi

    ACTIVE_PACKAGES=()

    echo ""
    echo "Clone yang ditemukan:"
    echo "-------------------------------------------------"

    i=1
    for pkg in "${DETECTED_PACKAGES[@]}"; do
        echo "[$i] $pkg"
        i=$((i+1))
    done

    echo "-------------------------------------------------"
    echo "Ketik:"
    echo " all     = semua clone"
    echo " 1 2 3   = pilih beberapa"
    echo "-------------------------------------------------"

    read -p "Pilihan : " SELECT_INPUT

    if [ -z "$SELECT_INPUT" ] || \
       [ "$SELECT_INPUT" = "all" ]; then

        ACTIVE_PACKAGES=("${DETECTED_PACKAGES[@]}")

    else

        for NUM in $SELECT_INPUT
        do
            if [[ "$NUM" =~ ^[0-9]+$ ]]; then

                IDX=$((NUM-1))

                if [ "$IDX" -ge 0 ] &&
                   [ "$IDX" -lt "${#DETECTED_PACKAGES[@]}" ]; then

                    ACTIVE_PACKAGES+=(
                        "${DETECTED_PACKAGES[$IDX]}"
                    )

                fi
            fi
        done
    fi

    if [ ${#ACTIVE_PACKAGES[@]} -eq 0 ]; then
        echo ""
        echo "[!] Tidak ada package dipilih."
        sleep 2
        return
    fi

    echo ""

    read -p "Delay antar clone (default 30): " input_delay

    DELAY_TIME=${input_delay:-30}

    save_config

    echo ""
    echo "[+] Package aktif:"
    echo ""

    for pkg in "${ACTIVE_PACKAGES[@]}"
    do
        echo "  ✓ $pkg"
    done

    sleep 2
}

launch_clone(){

    local pkg="$1"

    echo "[OPEN] $pkg"

    am force-stop "$pkg" >/dev/null 2>&1

    sleep 1

    monkey \
        -p "$pkg" \
        -c android.intent.category.LAUNCHER \
        1 >/dev/null 2>&1

    sleep 4

    am start \
        -n "$pkg/com.roblox.client.ActivityProtocolRedirector" \
        -a android.intent.action.VIEW \
        -d "$ROBLOX_PS_LINK" \
        >/dev/null 2>&1

    sleep 2

}
wait_clone(){

    local pkg="$1"

    local i

    for ((i=0;i<10;i++))
    do

        if ps -A | grep -q "$pkg"
        then
            return
        fi

        sleep 1

    done

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
            if [ ${#ACTIVE_PACKAGES[@]} -eq 0 ]; then
    echo ""
    echo "[!] Belum memilih clone."
    sleep 2
    return
fi
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
                    sleep 3
                    FIRST_RUN=false
                else
                    sleep "$DELAY_TIME"
                fi

                if ! ps -A | grep -q "$pkg"; then
                    launch_clone "$pkg"
                    wait_clone "$pkg"
                    if ! ps -A | grep -q "$pkg"; then
                        echo "[Retry] $pkg"
                        launch_clone "$pkg"
                    fi
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

refresh_pkg_status(){

    declare -gA PKG_STATUS

    local PROC

    PROC="$(ps -A 2>/dev/null)"

    [ -z "$PROC" ] && PROC="$(ps 2>/dev/null)"

    for pkg in "${ACTIVE_PACKAGES[@]}"
    do
        if echo "$PROC" | grep -Fq "$pkg"
        then
            PKG_STATUS["$pkg"]="online"
        else
            PKG_STATUS["$pkg"]="offline"
        fi
    done
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

        # 3. Tampilan polos tanpa garis/warna sama sekali
        echo "Online: ${AKTIF_COUNT}/${TOTAL_PKG} | RAM: ${MEM_INFO}"
        echo ""

        for pkg in "${ACTIVE_PACKAGES[@]}"; do
            if [ "${PKG_STATUS[$pkg]}" == "online" ]; then
                echo "ON  $pkg"
            else
                echo "OFF $pkg"
            fi
        done

        echo ""
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
    echo " Clone Terdeteksi : ${#DETECTED_PACKAGES[@]}"
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
    echo "11. Refresh Daftar Clone"
    echo "================================================="
    read -p "Pilih menu (1-11): " MENU_CHOICE

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
                rm -f \
"$CONFIG_FILE" \
"$PID_FILE" \
"$CACHE_PID_FILE" \
"$PACKAGE_CACHE"
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
        11)
            rm -f "$PACKAGE_CACHE"
            scan_packages
            echo ""
            echo "[+] Scan selesai."
            echo "Clone ditemukan : ${#DETECTED_PACKAGES[@]}"
            sleep 2
            ;;
        *)
            echo ""
            echo "[x] Pilihan tidak valid!"
            sleep 1
            ;;
    esac
done
