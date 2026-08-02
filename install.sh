#!/bin/bash
#
# Copyright (c) 2026 KYZ Applications. Todos los derechos reservados.
# Uso permitido según LICENSE. Prohibida la copia, modificación o
# redistribución de este script sin autorización previa y por escrito
# de KYZ Applications.
#
set -o pipefail
clear

export DEBIAN_FRONTEND=noninteractive
source /etc/os-release

SUPPORT_LEVEL="unsupported"
case "$ID:$VERSION_ID" in
  ubuntu:20.04) SUPPORT_LEVEL="legacy" ;;
  ubuntu:22.04) SUPPORT_LEVEL="recommended" ;;
  ubuntu:24.04) SUPPORT_LEVEL="supported" ;;
  debian:11) SUPPORT_LEVEL="legacy" ;;
  debian:12) SUPPORT_LEVEL="supported" ;;
  *) SUPPORT_LEVEL="unsupported" ;;
esac

apt-get install figlet -y > /dev/null 2>&1
apt install lolcat -y > /dev/null 2>&1

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

step() {
    local msg="$1"; shift
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    tput civis 2>/dev/null
    ( "$@" ) > /dev/null 2>&1 &
    local pid=$!

    printf "  ${YELLOW}• %s${NC}" "$msg"
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % ${#spin} ))
        printf "\r  ${YELLOW}• %s ${CYAN}%s${NC}" "$msg" "${spin:$i:1}"
        sleep 0.1
    done
    wait "$pid"
    local status=$?
    tput cnorm 2>/dev/null

    if [ $status -eq 0 ]; then
        printf "\r  ${GREEN}✔ %s${NC}\n" "$msg"
    else
        printf "\r  ${RED}✘ %s${NC}\n" "$msg"
    fi
    return $status
}

mostrar_banner_instalador() {
    clear
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}       >>>>>  🐉  ${YELLOW}${BOLD}Installer KyzAuto${NC}${BLUE}  ✸  ${YELLOW}${BOLD}Por NokasVip${NC}${BLUE}  🐉  <<<<<${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}Dominio:${NC} ${CYAN}${DOMAIN:-N/A}${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}              Instalador de Script SSH Kyz Auto${NC}"
echo -e "${CYAN}        (AutoScript: SSH/Xray/Hysteria/ZiVPN/UDP Custom)${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}Sistemas Operativos Soportados:${NC}"
echo -e "${GREEN}  ✔ Debian 12              (Recomendado)${NC}"
echo -e "${GREEN}  ✔ Debian 11              (Soporte Legado)${NC}"
echo -e "${GREEN}  ✔ Ubuntu 24.04           (Soportado)${NC}"
echo -e "${GREEN}  ✔ Ubuntu 22.04           (Recomendado)${NC}"
echo -e "${GREEN}  ✔ Ubuntu 20.04           (Soporte Legado)${NC}"
echo -e "${CYAN}============================================================${NC}"
sleep 5

if [ "$SUPPORT_LEVEL" = "unsupported" ]; then
  echo -e "${GREEN}Este instalador solo soporta Ubuntu 20.04/22.04/24.04 y Debian 11/12.${NC}"
  echo -e "${CYAN}Detectado: ${ID} ${VERSION_ID}${NC}"
  exit 1
fi

clear

echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}                 Configuración de Dominio${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "$(echo -e "  ${YELLOW}🌐 Dominio/Subdominio para Xray${NC} ${WHITE}(enter = usar la IP):${NC} ")" -e -i "$(curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')" DOMAIN
export DOMAIN
echo ""

preparar_dns_certbot() {
    apt-get update -y > /dev/null 2>&1
    command -v dig >/dev/null 2>&1 || apt-get install -y dnsutils > /dev/null 2>&1
    command -v certbot >/dev/null 2>&1 || apt-get install -y certbot > /dev/null 2>&1
}
step "Preparando herramientas de DNS/SSL..." preparar_dns_certbot

mkdir -p /etc/xray > /dev/null 2>&1
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    USE_LETSENCRYPT=false
    echo -e "  ${CYAN}ℹ Se usará un certificado autofirmado para la IP ${WHITE}$DOMAIN${NC}"
    echo -e "  ${YELLOW}⚠ Los clientes deberán activar 'allowInsecure' para el TLS en el puerto 443.${NC}"
else
    USE_LETSENCRYPT=true
    echo -e "  ${CYAN}ℹ Verificando que ${WHITE}$DOMAIN${NC}${CYAN} resuelva a la IP del servidor...${NC}"
    SERVER_IP=$(curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 2>/dev/null | tail -1)
    if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
        echo -e "  ${RED}✘ ERROR: El dominio $DOMAIN no apunta a la IP $SERVER_IP.${NC}"
        echo -e "  ${RED}  Crea un registro A en tu DNS y vuelve a ejecutar el script.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✔ Dominio verificado.${NC}"
    systemctl stop xray 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    solicitar_certificado_le() {
        certbot certonly --standalone --non-interactive --agree-tos --email "admin@$DOMAIN" -d "$DOMAIN" > /dev/null 2>&1
    }
    if ! step "Solicitando certificado SSL (Let's Encrypt)..." solicitar_certificado_le; then
        echo -e "  ${RED}✘ No se pudo emitir el certificado Let's Encrypt para $DOMAIN.${NC}"
        exit 1
    fi
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "letsencrypt" > /etc/xray/cert_type
fi

if [ "$USE_LETSENCRYPT" = false ]; then
    generar_cert_autofirmado() {
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
          -keyout /etc/xray/xray.key \
          -out /etc/xray/xray.crt \
          -subj "/CN=${DOMAIN}/O=HexTunnel/C=US" > /dev/null 2>&1
    }
    step "Generando certificado autofirmado..." generar_cert_autofirmado
    echo "selfsigned" > /etc/xray/cert_type
else
    cp "$CERT_PATH" /etc/xray/xray.crt > /dev/null 2>&1
    cp "$KEY_PATH" /etc/xray/xray.key > /dev/null 2>&1
fi
chmod 644 /etc/xray/xray.crt > /dev/null 2>&1
chmod 600 /etc/xray/xray.key > /dev/null 2>&1
mkdir -p /etc/stunnel > /dev/null 2>&1
cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem 2>/dev/null
chmod 600 /etc/stunnel/stunnel.pem > /dev/null 2>&1
chown root:root /etc/stunnel/stunnel.pem > /dev/null 2>&1

SSH_Port1='22'
SSH_Port2='299'

Stunnel_Port='127.0.0.1:4443'
Stunnel_Port_Num='4443' 

Squid_Port1='3128'
Squid_Port2='8000'

WsPorts=('10080' '25' '2082' '2086')  
WsPort='10080'  

MainPort='666' 

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}                 Configuración de SlowDNS${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "$(echo -e "  ${YELLOW}🌐 Nameserver de SlowDNS${NC} ${WHITE}(enter = predeterminado):${NC} ")" -e -i "ns-name.kyzapps.app" Nameserver
echo ""
Serverkey='819d82813183e4be3ca1ad74387e47c0c993b81c601b2d1473a3f47731c404ae'
Serverpub='7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59'

UDP_PORT=":36712"
HYST2_PORT="36713"
UDP_CUSTOM_PORT="36717"
ZIVPN_PORT="5667"
_default_obfs='KyzTunnel'
_default_password='KyzTunnel'

echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}                 Configuración de UDP / Hysteria${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
if [ -t 0 ]; then
  read -e -p "$(echo -e "  ${YELLOW}🛡  Obfuscation (obfs)${NC} ${WHITE}[${_default_obfs}]:${NC} ")" -i "${_default_obfs}" _input_obfs
  OBFS="${_input_obfs:-${_default_obfs}}"
  read -e -p "$(echo -e "  ${YELLOW}🔒 Contraseña de UDP${NC} ${WHITE}[${_default_password}]:${NC} ")" -i "${_default_password}" _input_pass
  PASSWORD="${_input_pass:-${_default_password}}"
else
  OBFS="${OBFS:-${_default_obfs}}"
  PASSWORD="${PASSWORD:-${_default_password}}"
fi
echo ""

export OBFS PASSWORD

clear
sleep 1.5
Nginx_Port='85' 
Dns_1='1.1.1.1' 
Dns_2='1.0.0.1'

MyVPS_Time='Africa/Accra'

My_Chat_ID='6857779956'
My_Bot_Key='8710991931:AAEk7mdyVamfxX7mTvO3HE_stV_zwEjVxnY'
# ==========================================
# BOT DE ADMINISTRACIÓN POR TELEGRAM
# ==========================================
#!/bin/bash
set -o pipefail
umask 077

# ==============================
#  CONFIGURACIÓN (se reemplazan al final)
# ==============================
BOT_TOKEN="MYBOTID"
ADMIN_CHAT_ID="MYCHATID"
OFFSET_FILE="/tmp/bot_offset.txt"
ADMIN_LIST="/etc/telegram-admins.txt"
SESSION_DIR="/tmp/bot_sessions"
mkdir -p "$SESSION_DIR"

# ==============================
#  FUNCIONES DE ENVÍO
# ==============================
send_msg_to() {
    local chat="$1"
    local msg="$2"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat}&text=${msg}&parse_mode=markdown&disable_web_page_preview=true" > /dev/null 2>&1
}

send_msg() {
    send_msg_to "$ADMIN_CHAT_ID" "$1"
}

# ==============================
#  OBTENER ACTUALIZACIONES
# ==============================
get_updates() {
    local offset=0
    [ -f "$OFFSET_FILE" ] && offset=$(cat "$OFFSET_FILE")
    curl -s -X GET "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${offset}&timeout=30" | jq -r '.result[] | "\(.update_id)|\(.message.chat.id)|\(.message.text)"' 2>/dev/null
}

# ==============================
#  AUTORIZACIÓN
# ==============================
is_authorized() {
    local chat="$1"
    [ "$chat" = "$ADMIN_CHAT_ID" ] && return 0
    [ -f "$ADMIN_LIST" ] && grep -qx "$chat" "$ADMIN_LIST" && return 0
    return 1
}

# ==============================
#  FUNCIONES DE GESTIÓN DE SESIONES (para diálogos)
# ==============================
get_session() {
    local chat="$1"
    local file="$SESSION_DIR/$chat"
    if [ -f "$file" ]; then
        cat "$file"
    else
        echo ""
    fi
}

set_session() {
    local chat="$1"
    local data="$2"
    echo "$data" > "$SESSION_DIR/$chat"
}

clear_session() {
    local chat="$1"
    rm -f "$SESSION_DIR/$chat"
}

# ==============================
#  COMANDOS DE ADMIN (solo dueño)
# ==============================
process_admin_command() {
    local cmd="$1"
    local chat="$2"
    [ "$chat" != "$ADMIN_CHAT_ID" ] && return 1

    local action=$(echo "$cmd" | awk '{print $1}')
    local args=($(echo "$cmd" | cut -d' ' -f2-))

    case "$action" in
        /addadmin)
            if [ ${#args[@]} -lt 1 ]; then
                send_msg "❌ Uso: /addadmin <chat_id>"
                return 0
            fi
            local new_id="${args[0]}"
            if [[ ! "$new_id" =~ ^[0-9]+$ ]]; then
                send_msg "❌ El ID debe ser numérico."
                return 0
            fi
            if [ "$new_id" = "$ADMIN_CHAT_ID" ]; then
                send_msg "⚠️ Ese es el dueño, ya tiene acceso."
                return 0
            fi
            if grep -qx "$new_id" "$ADMIN_LIST" 2>/dev/null; then
                send_msg "⚠️ El ID $new_id ya está en la lista."
                return 0
            fi
            echo "$new_id" >> "$ADMIN_LIST"
            send_msg "✅ Administrador $new_id añadido correctamente."
            return 0
            ;;
        /deladmin)
            if [ ${#args[@]} -lt 1 ]; then
                send_msg "❌ Uso: /deladmin <chat_id>"
                return 0
            fi
            local del_id="${args[0]}"
            if [[ ! "$del_id" =~ ^[0-9]+$ ]]; then
                send_msg "❌ El ID debe ser numérico."
                return 0
            fi
            if [ "$del_id" = "$ADMIN_CHAT_ID" ]; then
                send_msg "❌ No puedes eliminar al dueño."
                return 0
            fi
            if ! grep -qx "$del_id" "$ADMIN_LIST" 2>/dev/null; then
                send_msg "⚠️ El ID $del_id no está en la lista."
                return 0
            fi
            sed -i "/^$del_id$/d" "$ADMIN_LIST"
            send_msg "✅ Administrador $del_id eliminado."
            return 0
            ;;
        /listadmins)
            local list
            if [ -f "$ADMIN_LIST" ]; then
                list=$(cat "$ADMIN_LIST" | paste -sd ', ')
            else
                list="(vacía)"
            fi
            send_msg "📋 *Lista de administradores:*\nDueño: $ADMIN_CHAT_ID\nAdicionales: $list"
            return 0
            ;;
    esac
    return 1
}

# ==============================
#  FUNCIONES DE INFORMACIÓN
# ==============================
get_domain() {
    cat /etc/deekayvpn/domain.txt 2>/dev/null || curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'
}

get_server_ip() {
    curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'
}

get_obfs_hysteria() {
    jq -r '.inbounds[0].obfs' /etc/hysteria/config.json 2>/dev/null || echo "HexTunnel"
}

# Muestra la información completa de una cuenta recién creada
show_account_info() {
    local type="$1"   # ssh, vless, vmess, trojan, all
    local user="$2"
    local pass="$3"
    local days="$4"
    local conn_limit="${5:-0}"
    local ip=$(get_server_ip)
    local domain=$(get_domain)
    local obfs=$(get_obfs_hysteria)

    local msg=""
    msg+="✅ *Cuenta creada exitosamente!*\n\n"
    msg+="🌐 *Dominio:* $domain\n"
    msg+="🖥️ *IP:* $ip\n"
    msg+="👤 *Usuario:* $user\n"
    msg+="🔑 *Contraseña:* $pass\n"
    msg+="📅 *Expira:* $(date -d "+$days days" +"%Y-%m-%d")\n"
    if [ "$conn_limit" -gt 0 ]; then
        msg+="🔗 *Límite de conexiones:* $conn_limit\n"
    else
        msg+="🔗 *Límite de conexiones:* Sin límite\n"
    fi
    msg+="\n📌 *Puertos disponibles:*\n"
    msg+="• SSH: 22, 299\n"
    msg+="• SSL/TLS: 443\n"
    msg+="• WebSocket: 80, 8080, 8880, 2082, 2086, 25\n"
    msg+="• SlowDNS: 53\n"
    msg+="• BadVPN: 7300\n"
    msg+="• UDP Custom: 1-65535\n"
    msg+="• Hysteria 1: 20000-50000 (obfs: $obfs)\n"
    msg+="• Hysteria 2: 36713 (obfs: $obfs)\n"
    msg+="• ZiVPN: 6000-19999\n"
    msg+="\n📝 *Payload HTTP:*\n"
    msg+="\`GET / HTTP/1.1[crlf]Host: ${domain}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]\`\n"
    msg+="\n📝 *Payload mejorado:*\n"
    msg+="\`GET / HTTP/1.1[crlf]Host: bug.com[crlf][crlf]PATCH / HTTP/1.1[crlf]Host: ${domain}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]\`\n"
    msg+="\n🐌 *SlowDNS NS:* $(grep 'ExecStart=' /etc/systemd/system/server-sldns.service 2>/dev/null | sed 's/.*server\.key \([^ ]*\) .*/\1/')"
    send_msg_to "$chat" "$msg"
}

# ==============================
#  PROCESADOR DE COMANDOS CON DIÁLOGOS
# ==============================
process_command() {
    local cmd="$1"
    local chat="$2"

    # 1. Autorización
    if ! is_authorized "$chat"; then
        send_msg_to "$chat" "⛔ No autorizado. Contacta al dueño del bot para obtener acceso."
        return
    fi

    # 2. Intentar comandos de administración (solo dueño)
    if process_admin_command "$cmd" "$chat"; then
        return
    fi

    # 3. Manejo de sesiones activas (diálogos en curso)
    local session=$(get_session "$chat")
    if [ -n "$session" ]; then
        # Si hay una sesión, procesamos el mensaje como respuesta a la pregunta actual
        handle_session "$chat" "$cmd" "$session"
        return
    fi

    # 4. Comandos normales (sin diálogo)
    local action=$(echo "$cmd" | awk '{print $1}')
    local args=($(echo "$cmd" | cut -d' ' -f2-))

    case "$action" in
        /help)
            send_msg_to "$chat" "📌 *Comandos disponibles:*\n/addssh user pass días [limite] (o sin args para modo interactivo)\n/delssh user\n/extendssh user días\n/listssh\n/addxray user proto días [uuid] (o sin args para interactivo; proto: vless, vmess, trojan, all)\n/delxray user\n/listxray\n/addadmin <chat_id> (solo dueño)\n/deladmin <chat_id> (solo dueño)\n/listadmins (solo dueño)\n/help"
            ;;
        /start)
            send_msg_to "$chat" "👋 Bienvenido al bot de administración de *HexAuto*.\nUsa /help para ver los comandos disponibles."
            ;;
        /addssh)
            if [ ${#args[@]} -ge 3 ]; then
                # Modo rápido
                add_ssh "$chat" "${args[0]}" "${args[1]}" "${args[2]}" "${args[3]:-0}"
            else
                # Iniciar diálogo
                set_session "$chat" "addssh|user"
                send_msg_to "$chat" "👤 Ingresa el *nombre de usuario* (sin espacios, solo letras/números/guiones):"
            fi
            ;;
        /delssh)
            if [ ${#args[@]} -lt 1 ]; then
                send_msg_to "$chat" "❌ Uso: /delssh usuario"
                return
            fi
            delete_ssh "$chat" "${args[0]}"
            ;;
        /extendssh)
            if [ ${#args[@]} -lt 2 ]; then
                send_msg_to "$chat" "❌ Uso: /extendssh usuario días"
                return
            fi
            extend_ssh "$chat" "${args[0]}" "${args[1]}"
            ;;
        /listssh)
            list_ssh "$chat"
            ;;
        /addxray)
            if [ ${#args[@]} -ge 3 ]; then
                # Modo rápido
                local proto="${args[1]}"
                local days="${args[2]}"
                local uuid="${args[3]:-}"
                add_xray "$chat" "${args[0]}" "$proto" "$days" "$uuid"
            else
                # Iniciar diálogo
                set_session "$chat" "addxray|user"
                send_msg_to "$chat" "👤 Ingresa el *nombre de usuario* para Xray:"
            fi
            ;;
        /delxray)
            if [ ${#args[@]} -lt 1 ]; then
                send_msg_to "$chat" "❌ Uso: /delxray usuario"
                return
            fi
            delete_xray "$chat" "${args[0]}"
            ;;
        /listxray)
            list_xray "$chat"
            ;;
        *)
            send_msg_to "$chat" "❌ Comando desconocido. Usa /help"
            ;;
    esac
}

# ==============================
#  FUNCIONES DE ACCIÓN (con sus diálogos)
# ==============================

# --- Manejo de sesiones (diálogos) ---
handle_session() {
    local chat="$1"
    local input="$2"
    local session="$3"

    # El formato de sesión es: "comando|paso|datos_acumulados"
    IFS='|' read -r command step accumulated <<< "$session"
    accumulated="${accumulated:-}"

    case "$command" in
        addssh)
            case "$step" in
                user)
                    if [[ "$input" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
                        if id "$input" &>/dev/null; then
                            send_msg_to "$chat" "❌ El usuario *$input* ya existe. Elige otro nombre:"
                            return
                        fi
                        accumulated="$input"
                        set_session "$chat" "addssh|pass|$accumulated"
                        send_msg_to "$chat" "🔑 Ingresa la *contraseña* para el usuario *$input*:"
                    else
                        send_msg_to "$chat" "❌ Nombre inválido. Usa solo letras, números, guiones bajos, sin espacios."
                    fi
                    ;;
                pass)
                    if [ -n "$input" ] && [[ ! "$input" =~ [[:space:]] ]]; then
                        local user="$accumulated"
                        accumulated="${accumulated}|$input"
                        set_session "$chat" "addssh|days|$accumulated"
                        send_msg_to "$chat" "📅 Ingresa la *validez en días*:"
                    else
                        send_msg_to "$chat" "❌ Contraseña inválida (no puede estar vacía ni contener espacios)."
                    fi
                    ;;
                days)
                    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -gt 0 ]; then
                        local user=$(echo "$accumulated" | cut -d'|' -f1)
                        local pass=$(echo "$accumulated" | cut -d'|' -f2)
                        accumulated="${accumulated}|$input"
                        set_session "$chat" "addssh|limit|$accumulated"
                        send_msg_to "$chat" "🔗 Ingresa el *límite de conexiones simultáneas* (0 = sin límite):"
                    else
                        send_msg_to "$chat" "❌ Debes ingresar un número de días mayor que 0."
                    fi
                    ;;
                limit)
                    if [[ "$input" =~ ^[0-9]+$ ]]; then
                        local user=$(echo "$accumulated" | cut -d'|' -f1)
                        local pass=$(echo "$accumulated" | cut -d'|' -f2)
                        local days=$(echo "$accumulated" | cut -d'|' -f3)
                        local limit="$input"
                        # Crear usuario
                        if ! useradd -e "$(date -d "+$days days" +%Y-%m-%d)" -s /bin/false -M "$user" 2>/dev/null; then
                            send_msg_to "$chat" "❌ Falló la creación del usuario $user. Quizás ya existe o hay un error."
                            clear_session "$chat"
                            return
                        fi
                        echo "$user:$pass" | chpasswd
                        if [ "$limit" -gt 0 ]; then
                            sed -i "/^$user /d" /etc/deekayvpn/ssh_limits.txt
                            echo "$user $limit" >> /etc/deekayvpn/ssh_limits.txt
                        fi
                        clear_session "$chat"
                        # Mostrar info completa
                        show_account_info "ssh" "$user" "$pass" "$days" "$limit"
                    else
                        send_msg_to "$chat" "❌ Ingresa un número válido (0 o mayor)."
                    fi
                    ;;
            esac
            ;;
        addxray)
            case "$step" in
                user)
                    if [[ "$input" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
                        if grep -qw "^$input" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then
                            send_msg_to "$chat" "❌ El usuario *$input* ya tiene cuenta Xray. Elige otro:"
                            return
                        fi
                        accumulated="$input"
                        set_session "$chat" "addxray|proto|$accumulated"
                        send_msg_to "$chat" "📡 Elige el *protocolo* (vless, vmess, trojan, all):"
                    else
                        send_msg_to "$chat" "❌ Nombre inválido. Usa solo letras, números, guiones bajos."
                    fi
                    ;;
                proto)
                    local proto="$input"
                    if [[ "$proto" =~ ^(vless|vmess|trojan|all)$ ]]; then
                        accumulated="${accumulated}|$proto"
                        set_session "$chat" "addxray|days|$accumulated"
                        send_msg_to "$chat" "📅 Ingresa la *validez en días*:"
                    else
                        send_msg_to "$chat" "❌ Protocolo no válido. Usa: vless, vmess, trojan, all"
                    fi
                    ;;
                days)
                    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -gt 0 ]; then
                        accumulated="${accumulated}|$input"
                        set_session "$chat" "addxray|uuid|$accumulated"
                        send_msg_to "$chat" "🔑 ¿Quieres usar un *UUID personalizado*? Si no, escribe *no* para generar uno automático:"
                    else
                        send_msg_to "$chat" "❌ Debes ingresar un número de días mayor que 0."
                    fi
                    ;;
                uuid)
                    local user=$(echo "$accumulated" | cut -d'|' -f1)
                    local proto=$(echo "$accumulated" | cut -d'|' -f2)
                    local days=$(echo "$accumulated" | cut -d'|' -f3)
                    local uuid=""
                    if [ "$input" = "no" ] || [ -z "$input" ]; then
                        uuid=$(cat /proc/sys/kernel/random/uuid)
                    else
                        uuid="$input"
                    fi
                    clear_session "$chat"
                    # Crear cuenta Xray
                    create_xray_account "$chat" "$user" "$proto" "$days" "$uuid"
                    ;;
            esac
            ;;
    esac
}

# --- Funciones de creación SSH (modo rápido) ---
add_ssh() {
    local chat="$1"
    local user="$2"
    local pass="$3"
    local days="$4"
    local limit="${5:-0}"

    if id "$user" &>/dev/null; then
        send_msg_to "$chat" "❌ El usuario $user ya existe."
        return
    fi
    if ! useradd -e "$(date -d "+$days days" +%Y-%m-%d)" -s /bin/false -M "$user" 2>/dev/null; then
        send_msg_to "$chat" "❌ Falló la creación del usuario $user."
        return
    fi
    echo "$user:$pass" | chpasswd
    if [ "$limit" -gt 0 ]; then
        sed -i "/^$user /d" /etc/deekayvpn/ssh_limits.txt
        echo "$user $limit" >> /etc/deekayvpn/ssh_limits.txt
    fi
    show_account_info "ssh" "$user" "$pass" "$days" "$limit"
}

delete_ssh() {
    local chat="$1"
    local user="$2"
    if ! id "$user" &>/dev/null; then
        send_msg_to "$chat" "❌ El usuario $user no existe."
        return
    fi
    pkill -u "$user" 2>/dev/null
    userdel -f "$user" 2>/dev/null
    sed -i "/^$user /d" /etc/deekayvpn/ssh_limits.txt
    send_msg_to "$chat" "✅ Usuario SSH *$user* eliminado."
}

extend_ssh() {
    local chat="$1"
    local user="$2"
    local days="$3"
    if ! id "$user" &>/dev/null; then
        send_msg_to "$chat" "❌ El usuario $user no existe."
        return
    fi
    current=$(chage -l "$user" | awk -F": " '/Account expires/ {print $2}')
    if [ "$current" = "never" ] || [ -z "$current" ]; then
        new_exp=$(date -d "+$days days" +%Y-%m-%d)
    else
        new_exp=$(date -d "$current +$days days" +%Y-%m-%d)
    fi
    chage -E "$new_exp" "$user"
    send_msg_to "$chat" "✅ Usuario *$user* extendido hasta $new_exp"
}

list_ssh() {
    local chat="$1"
    local list=$(awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd | paste -sd ', ')
    send_msg_to "$chat" "📋 Usuarios SSH: $list"
}

# --- Funciones de XRAY (con creación) ---
create_xray_account() {
    local chat="$1"
    local user="$2"
    local proto="$3"
    local days="$4"
    local uuid="$5"
    local exp=$(date -d "+$days days" +%Y-%m-%d)

    # Verificar duplicados
    if grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then
        send_msg_to "$chat" "❌ El usuario $user ya tiene cuenta Xray."
        return
    fi

    local success=0
    case "$proto" in
        vless)
            jq --arg uuid "$uuid" --arg user "$user" \
                '(.inbounds[] | select(.tag | test("vless")) | .settings.clients) += [{"id":$uuid,"email":$user}]' \
                /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
            echo "$user $uuid $exp" >> /etc/xray/vless.txt
            success=1
            ;;
        vmess)
            jq --arg uuid "$uuid" --arg user "$user" \
                '(.inbounds[] | select(.tag | test("vmess")) | .settings.clients) += [{"id":$uuid,"alterId":0,"email":$user}]' \
                /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
            echo "$user $uuid $exp" >> /etc/xray/vmess.txt
            success=1
            ;;
        trojan)
            local pass="HexTunnel${uuid:0:6}"
            jq --arg pass "$pass" --arg user "$user" \
                '(.inbounds[] | select(.tag == "trojan-ws") | .settings.clients) += [{"password":$pass,"email":$user}]' \
                /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
            echo "$user $pass $exp" >> /etc/xray/trojan.txt
            success=1
            ;;
        all)
            # VLESS
            jq --arg uuid "$uuid" --arg user "$user" \
                '(.inbounds[] | select(.tag | test("vless")) | .settings.clients) += [{"id":$uuid,"email":$user}]' \
                /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
            echo "$user $uuid $exp" >> /etc/xray/vless.txt
            # VMESS
            jq --arg uuid "$uuid" --arg user "$user" \
                '(.inbounds[] | select(.tag | test("vmess")) | .settings.clients) += [{"id":$uuid,"alterId":0,"email":$user}]' \
                /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
            echo "$user $uuid $exp" >> /etc/xray/vmess.txt
            # TROJAN
            local pass="HexTunnel${uuid:0:6}"
            jq --arg pass "$pass" --arg user "$user" \
                '(.inbounds[] | select(.tag == "trojan-ws") | .settings.clients) += [{"password":$pass,"email":$user}]' \
                /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
            echo "$user $pass $exp" >> /etc/xray/trojan.txt
            success=1
            ;;
        *)
            send_msg_to "$chat" "❌ Protocolo no soportado: $proto"
            return
            ;;
    esac

    if [ $success -eq 1 ]; then
        systemctl restart xray
        # Mostrar info (adaptar según protocolo)
        local domain=$(get_domain)
        local ip=$(get_server_ip)
        local insecure_param=""
        if [ -f /etc/xray/cert_type ] && grep -q "selfsigned" /etc/xray/cert_type; then
            insecure_param="&allowInsecure=1"
        fi

        local msg="✅ *Cuenta Xray ($proto) creada*\n"
        msg+="👤 Usuario: $user\n"
        msg+="📅 Expira: $exp\n"
        msg+="🌐 Dominio: $domain\n"
        msg+="🖥️ IP: $ip\n"

        # Agregar enlaces según protocolo
        case "$proto" in
            vless|all)
                msg+="\n*VLESS TLS (443)*\n"
                msg+="\`vless://${uuid}@${domain}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${domain}&sni=${domain}${insecure_param}#${user}-VLESS\`\n"
                msg+="\n*VLESS NTLS (80)*\n"
                msg+="\`vless://${uuid}@${domain}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${domain}#${user}-VLESS-NTLS\`\n"
                ;;
        esac
        case "$proto" in
            vmess|all)
                local vmess_json_tls="{\"v\":\"2\",\"ps\":\"${user}-TLS\",\"add\":\"${domain}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${domain}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${domain}\"}"
                local vmess_json_ntls="{\"v\":\"2\",\"ps\":\"${user}-NTLS\",\"add\":\"${domain}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${domain}\",\"path\":\"/vmess\",\"tls\":\"\"}"
                msg+="\n*VMESS TLS (443)*\n"
                msg+="\`vmess://$(echo -n "$vmess_json_tls" | base64 -w 0)\`\n"
                msg+="\n*VMESS NTLS (80)*\n"
                msg+="\`vmess://$(echo -n "$vmess_json_ntls" | base64 -w 0)\`\n"
                ;;
        esac
        case "$proto" in
            trojan|all)
                local pass="HexTunnel${uuid:0:6}"
                msg+="\n*TROJAN TLS (443)*\n"
                msg+="\`trojan://${pass}@${domain}:443?type=ws&security=tls&path=%2Ftrojan&host=${domain}&sni=${domain}${insecure_param}#${user}\`\n"
                ;;
        esac

        send_msg_to "$chat" "$msg"
    else
        send_msg_to "$chat" "❌ Falló la creación de la cuenta Xray."
    fi
}

add_xray() {
    # Modo rápido (llama a create_xray_account)
    create_xray_account "$1" "$2" "$3" "$4" "$5"
}

delete_xray() {
    local chat="$1"
    local user="$2"
    # Eliminar de config.json y de todos los .txt
    jq '(.inbounds[].settings.clients) |= map(select(.email != "'$user'"))' /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    sed -i "/^$user /d" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null
    systemctl restart xray
    send_msg_to "$chat" "✅ Usuario Xray *$user* eliminado."
}

list_xray() {
    local chat="$1"
    local vless=$(awk '{print $1}' /etc/xray/vless.txt 2>/dev/null | paste -sd ', ')
    local vmess=$(awk '{print $1}' /etc/xray/vmess.txt 2>/dev/null | paste -sd ', ')
    local trojan=$(awk '{print $1}' /etc/xray/trojan.txt 2>/dev/null | paste -sd ', ')
    send_msg_to "$chat" "📋 *VLESS:* $vless\n*VMESS:* $vmess\n*TROJAN:* $trojan"
}

# ==============================
#  BUCLE PRINCIPAL
# ==============================
while true; do
    updates=$(get_updates)
    if [ -n "$updates" ]; then
        echo "$updates" | while IFS='|' read -r update_id chat text; do
            # Actualizar offset
            echo "$((update_id + 1))" > "$OFFSET_FILE"
            if [ -n "$text" ]; then
                process_command "$text" "$chat" &
            fi
        done
    fi
    sleep 2
done
EOF_BOT

sed -i "s|MYBOTID|8710991931:AAEk7mdyVamfxX7mTvO3HE_stV_zwEjVxnY|g" /usr/local/bin/telegram-admin-bot
sed -i "s|MYCHATID|6857779956|g" /usr/local/bin/telegram-admin-bot

chmod 755 /usr/local/bin/telegram-admin-bot
mkdir -p /tmp/bot_sessions
chmod 755 /tmp/bot_sessions

touch /etc/telegram-admins.txt

systemctl daemon-reload
systemctl restart telegram-admin-bot.service
systemctl status telegram-admin-bot.service
# Crear servicio systemd para que el bot se ejecute siempre
cat > /etc/systemd/system/telegram-admin-bot.service <<EOF
[Unit]
Description=Telegram Admin Bot for HexAuto
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/telegram-admin-bot
Restart=always
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable telegram-admin-bot.service
systemctl start telegram-admin-bot.service

function ip_address(){
  local IP="$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipv4.icanhazip.com 2>/dev/null )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipinfo.io/ip 2>/dev/null )"
  [ ! -z "${IP}" ] && echo "${IP}" || echo
} 
IPADDR="$(ip_address)"

mostrar_banner_instalador

actualizar_sistema() {
    apt-get update -y > /dev/null 2>&1
}
step "Actualizando (Apt Update)..." actualizar_sistema

systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null

SSH_SERVICE="ssh"; STUNNEL_SERVICE="stunnel4"; SQUID_SERVICE="squid"; SSLH_SERVICE="sslh"; NGINX_SERVICE="nginx"; SFTP_SUBSYSTEM="internal-sftp"

mkdir -p /etc/stunnel /etc/nginx/conf.d /etc/deekayvpn /var/run/sslh /etc/xray > /dev/null 2>&1
echo "$DOMAIN" > /etc/deekayvpn/domain.txt
ssh-keygen -A >/dev/null 2>&1 || true

command -v ss >/dev/null 2>&1 || apt-get install -y iproute2 > /dev/null 2>&1
command -v netfilter-persistent >/dev/null 2>&1 || apt-get install -y netfilter-persistent iptables-persistent > /dev/null 2>&1
command -v jq >/dev/null 2>&1 || apt-get install -y jq > /dev/null 2>&1
command -v curl >/dev/null 2>&1 || apt-get install -y curl > /dev/null 2>&1

if ! systemctl list-unit-files | grep -q "^${STUNNEL_SERVICE}\.service"; then
  if systemctl list-unit-files | grep -q "^stunnel\.service"; then STUNNEL_SERVICE="stunnel"; fi
fi
if ! systemctl list-unit-files | grep -q "^${SQUID_SERVICE}\.service"; then
  if systemctl list-unit-files | grep -q "^squid3\.service"; then SQUID_SERVICE="squid3"; fi
fi

PACKAGE_LIST=(
  neofetch sslh dnsutils stunnel4 squid nano sudo wget unzip tar zip gzip
  iptables iptables-persistent netfilter-persistent bc cron dos2unix whois screen ruby
  apt-transport-https software-properties-common gnupg2 ca-certificates curl net-tools
  nginx haproxy certbot jq figlet git gcc make build-essential perl expect libdbi-perl vnstat socat
  libnet-ssleay-perl libauthen-pam-perl libio-pty-perl apt-show-versions openssh-server rsyslog lsof procps
)

AVAILABLE_PACKAGES=()
UNAVAILABLE_PACKAGES=()
for pkg in "${PACKAGE_LIST[@]}"; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    AVAILABLE_PACKAGES+=("$pkg")
  else
    UNAVAILABLE_PACKAGES+=("$pkg")
  fi
done

if [[ ${#UNAVAILABLE_PACKAGES[@]} -gt 0 ]]; then
  echo -e "${YELLOW}⚠️  Paquetes no disponibles en este repo (no se instalaran): ${UNAVAILABLE_PACKAGES[*]}${NC}"
fi

SSH_CLIENT_IP="$(echo "${SSH_CONNECTION:-}" | awk '{print $1}')"
if [[ "$SSH_CLIENT_IP" == *:* ]]; then
    echo -e "${CYAN}Tu sesion SSH actual usa IPv6 ($SSH_CLIENT_IP) - se omite deshabilitar IPv6 para no cortar la conexion.${NC}"
else
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null 2>&1
fi
rm -f /etc/resolv.conf > /dev/null 2>&1
printf 'nameserver %s\nnameserver %s\n' "$Dns_1" "$Dns_2" > /etc/resolv.conf
ln -fs /usr/share/zoneinfo/$MyVPS_Time /etc/localtime > /dev/null 2>&1

cat > /root/.profile <<'EOF_PROFILE'
clear
echo "Script Por NokasVip"
echo "Escribe 'menu' Para Ver Los Comandos"
EOF_PROFILE

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections > /dev/null 2>&1
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections > /dev/null 2>&1

FAILED_PACKAGES=()
for pkg in "${AVAILABLE_PACKAGES[@]}"; do
    if ! step "Instalando: ${pkg}" apt-get install -y -qq "$pkg"; then
        FAILED_PACKAGES+=("$pkg")
    fi
done
if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    echo -e "${RED}⚠ No se pudieron instalar: ${FAILED_PACKAGES[*]}${NC}"
fi

systemctl enable "$SSH_SERVICE" >/dev/null 2>&1 || true
systemctl enable rsyslog >/dev/null 2>&1 || true
systemctl restart rsyslog >/dev/null 2>&1 || true
gem install lolcat >/dev/null 2>&1
apt -y --purge remove apache2 ufw firewalld >/dev/null 2>&1
systemctl stop nginx > /dev/null 2>&1

wget -q https://github.com/webmin/webmin/releases/download/2.111/webmin_2.111_all.deb >/dev/null 2>&1
dpkg --install webmin_2.111_all.deb > /dev/null 2>&1 || apt-get install -f -y >/dev/null 2>&1
rm -rf webmin_2.111_all.deb >/dev/null 2>&1
sed -i 's|ssl=1|ssl=0|g' /etc/webmin/miniserv.conf > /dev/null 2>&1
systemctl restart webmin >/dev/null 2>&1 || true

cat <<'deekay77' > /etc/zorro-luffy
<font color="#ffcc00">╔═══════════════════════════════════════════════╗<br></font>
<font color="#ffcc00">║</font>  <font color="#ff6b6b">✦</font> <font color="#ffffff">ADM KYZ</font> <font color="#ff6b6b">✦</font>     <font color="#ff6b6b">✦</font> <font color="#00cccc">KYZ Community</font> <font color="#ff6b6b">✦</font>     <font color="#ffcc00">║<br></font>
<font color="#ffcc00">╠═══════════════════════════════════════════════╣<br></font>
<font color="#ffcc00">║</font>  <font color="#00ff00">▣</font> KYZ Community   <font color="#00ff00">▣</font> Socketdevz VPN        <font color="#ffcc00">║<br></font>
<font color="#ffcc00">║</font>  <font color="#00ff00">▣</font> HTTP Door       <font color="#00ff00">▣</font> FreeNet_KYZ            <font color="#ffcc00">║<br></font>
<font color="#ffcc00">╠═══════════════════════════════════════════════╣<br></font>
<font color="#ffcc00">║</font>  <font color="#00cccc">• Powered by KYZ Community</font>                 <font color="#ffcc00">║<br></font>
<font color="#ffcc00">║</font>  <font color="#00cccc">• Telegram: https://t.me/FreeNet_KYZ</font>         <font color="#ffcc00">║<br></font>
<font color="#ffcc00">╚═══════════════════════════════════════════════╝<br></font>
deekay77


# OpenSSH
rm -f /etc/ssh/sshd_config > /dev/null 2>&1
cat <<'MySSHConfig' > /etc/ssh/sshd_config
Port myPORT1
Port myPORT2
AddressFamily inet
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
MaxSessions 5000
MaxStartups 500:30:1000
LoginGraceTime 30
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
UsePAM yes
X11Forwarding yes
PrintMotd no
ClientAliveInterval 120
ClientAliveCountMax 3
UseDNS no
Banner /etc/zorro-luffy
LogLevel QUIET
AcceptEnv LANG LC_*
Subsystem sftp SFTP_SUBSYSTEM
MySSHConfig

sed -i "s|myPORT1|$SSH_Port1|g" /etc/ssh/sshd_config > /dev/null 2>&1
sed -i "s|myPORT2|$SSH_Port2|g" /etc/ssh/sshd_config > /dev/null 2>&1
sed -i "s|SFTP_SUBSYSTEM|$SFTP_SUBSYSTEM|g" /etc/ssh/sshd_config > /dev/null 2>&1
sed -i -E '/password\s+(requisite|required)\s+pam_(cracklib|pwquality)\.so.*/d' /etc/pam.d/common-password > /dev/null 2>&1
sed -i 's/use_authtok //g' /etc/pam.d/common-password > /dev/null 2>&1
sed -i '/\/bin\/false/d' /etc/shells > /dev/null 2>&1
sed -i '/\/usr\/sbin\/nologin/d' /etc/shells > /dev/null 2>&1
echo '/bin/false' >> /etc/shells; echo '/usr/sbin/nologin' >> /etc/shells
systemctl restart "$SSH_SERVICE" > /dev/null 2>&1

# SSLH
cd /etc/default/ > /dev/null 2>&1
cat << sslh > /etc/default/sslh
RUN=yes
DAEMON=/usr/sbin/sslh
DAEMON_OPTS="--user sslh --listen 127.0.0.1:$MainPort --ssh 127.0.0.1:$SSH_Port1 --http 127.0.0.1:$WsPort --pidfile /var/run/sslh/sslh.pid"
sslh
mkdir -p /var/run/sslh > /dev/null 2>&1; touch /var/run/sslh/sslh.pid > /dev/null 2>&1; chmod 777 /var/run/sslh/sslh.pid > /dev/null 2>&1
systemctl daemon-reload > /dev/null 2>&1; systemctl enable "$SSLH_SERVICE" > /dev/null 2>&1; systemctl restart "$SSLH_SERVICE" > /dev/null 2>&1
cd > /dev/null 2>&1

StunnelDir=$(ls /etc/default | grep stunnel | head -n1)
cat <<'MyStunnelD' > /etc/default/$StunnelDir
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
BANNER="/etc/zorro-luffy"
PPP_RESTART=0
RLIMITS=""
MyStunnelD

cat <<'MyStunnelC' > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
syslog = no
debug = 0
output = /dev/null
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
TIMEOUTclose = 0
[sslh]
accept = Stunnel_Port
connect = 127.0.0.1:MainPort
MyStunnelC

sed -i "s|Stunnel_Port|$Stunnel_Port|g" /etc/stunnel/stunnel.conf > /dev/null 2>&1
sed -i "s|MainPort|$MainPort|g" /etc/stunnel/stunnel.conf > /dev/null 2>&1
systemctl enable "$STUNNEL_SERVICE" > /dev/null 2>&1; systemctl restart "$STUNNEL_SERVICE" > /dev/null 2>&1

loc=/etc/socksproxy; mkdir -p $loc > /dev/null 2>&1; apt-get install -y nodejs > /dev/null 2>&1

cat <<EOF > $loc/proxy.js
const net = require('net');
process.on('uncaughtException', (err) => { console.error('Unhandled Exception:', err); });
const TARGET_HOST = '127.0.0.1'; const TARGET_PORT = $SSH_Port1;
const LISTEN_PORT = parseInt(process.argv[2]);
if (!LISTEN_PORT) { process.exit(1); }
const handleConnection = (clientSocket) => {
    clientSocket.once('data', (data) => {
        const targetSocket = net.connect(TARGET_PORT, TARGET_HOST, () => {
            clientSocket.write('HTTP/1.1 101 <font color="yellow">KYZ Tunnel</font>\r\n\r\n');
            clientSocket.pipe(targetSocket); targetSocket.pipe(clientSocket);
        });
        targetSocket.on('error', () => clientSocket.destroy());
        targetSocket.on('close', () => clientSocket.destroy());
    });
    clientSocket.on('error', () => {}); clientSocket.on('close', () => {});
};
const server = net.createServer(handleConnection);
server.listen(LISTEN_PORT, '0.0.0.0', () => { console.log(\`WS Proxy active on isolated port \${LISTEN_PORT}\`); });
EOF

cat <<'service' > /etc/systemd/system/ws-proxy@.service
[Unit]
Description=Node.js WebSocket Proxy on port %i
After=network.target nss-lookup.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/socksproxy
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576
Restart=always
RestartSec=1
ExecStart=/usr/bin/node /etc/socksproxy/proxy.js %i
SyslogIdentifier=ws-proxy-%i
[Install]
WantedBy=multi-user.target
service

systemctl daemon-reload > /dev/null 2>&1
for port in "${WsPorts[@]}"; do systemctl enable ws-proxy@$port > /dev/null 2>&1; systemctl restart ws-proxy@$port > /dev/null 2>&1; done

clear

echo -e "${CYAN}Installing Hiddify-aligned stable Xray Core v26.3.27...${NC}"
XRAY_VER="v26.3.27"

cat <<'EOF_XRAY_INSTALLER' > /usr/local/sbin/xray-install-version
#!/bin/bash
set -o pipefail
umask 077

version="${1:?Usage: xray-install-version VERSION}"
case "$(uname -m)" in
  x86_64|amd64) asset="Xray-linux-64.zip" ;;
  i386|i486|i586|i686) asset="Xray-linux-32.zip" ;;
  aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
  armv7l|armv7*) asset="Xray-linux-arm32-v7a.zip" ;;
  *) echo "Unsupported Xray architecture: $(uname -m)" >&2; exit 1 ;;
esac

tmp_dir=$(mktemp -d /tmp/xray-install.XXXXXX) || exit 1
trap 'rm -rf "$tmp_dir"' EXIT
base_url="https://github.com/XTLS/Xray-core/releases/download/${version}/${asset}"

wget -qO "$tmp_dir/xray.zip" "$base_url" 2>/dev/null || { echo "Xray download failed." >&2; exit 1; }
wget -qO "$tmp_dir/xray.zip.dgst" "$base_url.dgst" 2>/dev/null || { echo "Xray digest download failed." >&2; exit 1; }
expected=$(awk -F'= *' 'toupper($1) == "SHA2-256" {print tolower($2); exit}' "$tmp_dir/xray.zip.dgst")
actual=$(sha256sum "$tmp_dir/xray.zip" | awk '{print tolower($1)}')
[ -n "$expected" ] && [ "$actual" = "$expected" ] || { echo "Xray SHA-256 verification failed." >&2; exit 1; }

unzip -q "$tmp_dir/xray.zip" -d "$tmp_dir/unpacked" 2>/dev/null || exit 1
[ -f "$tmp_dir/unpacked/xray" ] || { echo "Xray binary missing from archive." >&2; exit 1; }
chmod 755 "$tmp_dir/unpacked/xray" > /dev/null 2>&1
if [ -s /etc/xray/config.json ]; then
  "$tmp_dir/unpacked/xray" run -test -config /etc/xray/config.json > /dev/null 2>&1 || {
    echo "The downloaded Xray version rejected the current configuration." >&2
    exit 1
  }
fi
install -m 755 "$tmp_dir/unpacked/xray" /usr/local/bin/xray.new > /dev/null 2>&1
mv -f /usr/local/bin/xray.new /usr/local/bin/xray > /dev/null 2>&1
EOF_XRAY_INSTALLER
chmod 700 /usr/local/sbin/xray-install-version

if ! step "Instalando V2Ray..." /usr/local/sbin/xray-install-version "$XRAY_VER"; then
  echo -e "${RED}No se pudo instalar una versión verificada de Xray Core ${XRAY_VER}.${NC}"
  exit 1
fi

touch /etc/xray/vless.txt > /dev/null 2>&1
chmod 600 /etc/xray/vless.txt > /dev/null 2>&1

{
  printf 'XRAY_TLS_ALLOW_INSECURE=%q\n' "$XRAY_TLS_ALLOW_INSECURE"
  printf 'XRAY_CERT_SOURCE=%q\n' "$XRAY_CERT_SOURCE"
} > /etc/xray/server.env
chmod 600 /etc/xray/server.env > /dev/null 2>&1

cat <<EOF > /etc/xray/config.json
{
  "log": { "access": "none", "error": "/var/log/xray/error.log", "loglevel": "error" },
  "inbounds": [
    {
      "tag": "vless-tls-dispatcher",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [
          { "path": "/httpupgrade", "dest": 10005, "xver": 2 },
          { "path": "/vless-tcp", "dest": 10007, "xver": 2 },
          { "path": "/vmess-hup", "dest": 10011, "xver": 2 },
          { "path": "/vmess-tcp", "dest": 10008, "xver": 2 },
          { "path": "/trojan", "dest": 10013, "xver": 2 },
          { "path": "/vless", "dest": 10003, "xver": 2 },
          { "path": "/vmess", "dest": 10009, "xver": 2 },
          { "alpn": "h2", "dest": 10444, "xver": 2 },
          { "dest": 666 }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h2", "http/1.1"],
          "certificates": [
            { "certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key" }
          ]
        },
        "sockopt": { "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-tcp-http",
      "listen": "127.0.0.1",
      "port": 10007,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": { "header": { "type": "http", "request": { "path": ["/vless-tcp"] } } },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-plain-public",
      "port": "80,8080,8880,8081",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [
          { "path": "/xhttp", "dest": 10004, "xver": 2 },
          { "path": "/vmess-xhttp", "dest": 10010, "xver": 2 },
          { "path": "/vless-tcp", "dest": 10007, "xver": 2 },
          { "path": "/vmess-tcp", "dest": 10008, "xver": 2 },
          { "path": "/vmess-hup", "dest": 10011, "xver": 2 },
          { "path": "/vless", "dest": 10003, "xver": 2 },
          { "path": "/vmess", "dest": 10009, "xver": 2 },
          { "path": "/httpupgrade", "dest": 10005, "xver": 2 },
          { "dest": 10080 }
        ]
      },
      "streamSettings": { "network": "tcp", "security": "none" }
    },
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vless" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-xhttp",
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "/xhttp", "mode": "auto" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-httpupgrade",
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "none",
        "httpupgradeSettings": { "path": "/httpupgrade", "host": "" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-grpc",
      "listen": "127.0.0.1",
      "port": 10006,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "grpc-svc" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-tcp-http",
      "listen": "127.0.0.1",
      "port": 10008,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": { "header": { "type": "http", "request": { "path": ["/vmess-tcp"] } } },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10009,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vmess" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-xhttp",
      "listen": "127.0.0.1",
      "port": 10010,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "/vmess-xhttp", "mode": "auto" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-httpupgrade",
      "listen": "127.0.0.1",
      "port": 10011,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "none",
        "httpupgradeSettings": { "path": "/vmess-hup", "host": "" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1",
      "port": 10012,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "vmess-grpc-svc" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10013,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/trojan" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-grpc-ntls",
      "port": 8082,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "grpc-svc" }
      }
    },
    {
      "tag": "vmess-grpc-ntls",
      "port": 8083,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "vmess-grpc-svc" }
      }
    },
    {
      "tag": "vless-kcp-ntls",
      "port": "8084",
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "mkcp",
        "security": "none",
        "kcpSettings": {
          "mtu": 1350, "tti": 20, "uplinkCapacity": 5, "downlinkCapacity": 20,
          "congestion": false, "readBufferSize": 2, "writeBufferSize": 2
        }
      }
    },
    {
      "tag": "vmess-kcp-ntls",
      "port": "8085",
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "mkcp",
        "security": "none",
        "kcpSettings": {
          "mtu": 1350, "tti": 20, "uplinkCapacity": 5, "downlinkCapacity": 20,
          "congestion": false, "readBufferSize": 2, "writeBufferSize": 2
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ]
}
EOF
chmod 600 /etc/xray/config.json > /dev/null 2>&1

mkdir -p /var/log/xray > /dev/null 2>&1
if ! /usr/local/bin/xray run -test -config /etc/xray/config.json > /dev/null 2>&1; then
  echo -e "${RED}Xray configuration validation failed. Review the Xray error printed above.${NC}"
  exit 1
fi

cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=2
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload > /dev/null 2>&1
systemctl disable --now haproxy 2>/dev/null || true
systemctl enable xray > /dev/null 2>&1
systemctl restart xray > /dev/null 2>&1

if false; then
mkdir -p /etc/haproxy/certs > /dev/null 2>&1
install -m 600 /etc/stunnel/stunnel.pem /etc/haproxy/certs/xray.pem > /dev/null 2>&1
cat <<EOF_HAPROXY > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 100000
    daemon

defaults
    log global
    mode tcp
    option dontlognull
    timeout connect 5s
    timeout client 1h
    timeout client-fin 1h
    timeout server 1h
    timeout tunnel 1h
    timeout http-request 15s

frontend public_tls_443
    bind :443 v4v6 tfo ssl crt /etc/haproxy/certs/xray.pem alpn h2,http/1.1
    mode tcp
    acl negotiated_h2 ssl_fc_alpn -i h2
    acl h2_preface req.payload(0,24) -m bin 505249202a20485454502f322e300d0a0d0a534d0d0a0d0a
    acl h1_vless_xhttp req.payload(0,500) -m reg /xhttp
    acl h1_vless_httpupgrade req.payload(0,500) -m reg /httpupgrade
    acl h1_vless_tcp req.payload(0,500) -m reg /vless-tcp
    acl h1_vless_ws req.payload(0,500) -m reg /vless
    acl clear_ssh req.payload(0,4) -m str SSH-

    # Do not accept generic HTTP as soon as its method is visible. Wait until
    # the complete VLESS path is buffered, otherwise /vless falls through to
    # the generic SSH WebSocket proxy.
    tcp-request inspect-delay 5s
    tcp-request content accept if h2_preface
    tcp-request content accept if h1_vless_xhttp
    tcp-request content accept if h1_vless_httpupgrade
    tcp-request content accept if h1_vless_tcp
    tcp-request content accept if h1_vless_ws
    tcp-request content accept if clear_ssh

    use_backend h2_dispatch if negotiated_h2 h2_preface

    # Specific paths must precede the shorter WebSocket path.
    use_backend vless_xhttp_h1 if h1_vless_xhttp
    use_backend vless_httpupgrade if h1_vless_httpupgrade
    use_backend vless_tcp_http if h1_vless_tcp
    use_backend vless_ws if h1_vless_ws

    use_backend sslh_clear if clear_ssh
    use_backend sslh_clear if HTTP

    default_backend sslh_clear

backend h2_dispatch
    server h2_router 127.0.0.1:10444 send-proxy-v2


frontend h2_router
    bind 127.0.0.1:10444 accept-proxy
    mode http

    # Match specific HTTP/2 transports first.
    use_backend vless_grpc_h2 if { path_beg /grpc-svc }
    use_backend vless_xhttp_h2 if { path_beg /xhttp }
    use_backend vless_httpupgrade if { path_beg /httpupgrade }
    use_backend vless_ws if { path_beg /vless }
    default_backend reject_h2

backend vless_tcp_http
    server xray 127.0.0.1:10007 send-proxy-v2

backend vless_ws
    mode http
    server xray 127.0.0.1:10003 send-proxy-v2

backend vless_httpupgrade
    mode http
    server xray 127.0.0.1:10005 send-proxy-v2

backend vless_xhttp_h1
    server xray 127.0.0.1:10004 send-proxy-v2

backend vless_xhttp_h2
    mode http
    server xray 127.0.0.1:10004 send-proxy-v2 proto h2

backend vless_grpc_h2
    mode http
    server xray 127.0.0.1:10006 send-proxy-v2 proto h2

backend sslh_clear
    server sslh 127.0.0.1:666

backend reject_h2
    mode http
    http-request return status 404
EOF_HAPROXY

if ! haproxy -c -f /etc/haproxy/haproxy.cfg > /dev/null 2>&1; then
  echo -e "${RED}HAProxy configuration validation failed.${NC}"
  exit 1
fi

mkdir -p /etc/systemd/system/haproxy.service.d > /dev/null 2>&1
cat <<'EOF_HAPROXY_UNIT' > /etc/systemd/system/haproxy.service.d/xray-order.conf
[Unit]
After=xray.service network-online.target
Wants=xray.service network-online.target
EOF_HAPROXY_UNIT
systemctl daemon-reload > /dev/null 2>&1
systemctl enable "$HAPROXY_SERVICE" > /dev/null 2>&1
systemctl restart "$HAPROXY_SERVICE" > /dev/null 2>&1
fi

cat <<'EOF_H2_ROUTER' > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 100000
    daemon

defaults
    log global
    mode http
    option dontlognull
    timeout connect 5s
    timeout client 1h
    timeout server 1h
    timeout tunnel 1h

frontend xray_h2_router
    bind 127.0.0.1:10444 accept-proxy proto h2
    mode http
    use_backend vless_grpc_h2 if { path_beg /grpc-svc/ }
    use_backend vmess_grpc_h2 if { path_beg /vmess-grpc-svc/ }
    use_backend vless_xhttp_h2 if { path_beg /xhttp }
    use_backend vmess_xhttp_h2 if { path_beg /vmess-xhttp }
    default_backend reject_h2

backend vless_grpc_h2
    mode http
    server xray 127.0.0.1:10006 send-proxy-v2 proto h2

backend vmess_grpc_h2
    mode http
    server xray 127.0.0.1:10012 send-proxy-v2 proto h2

backend vless_xhttp_h2
    mode http
    server xray 127.0.0.1:10004 send-proxy-v2 proto h2

backend vmess_xhttp_h2
    mode http
    server xray 127.0.0.1:10010 send-proxy-v2 proto h2

backend reject_h2
    mode http
    http-request return status 404
EOF_H2_ROUTER

if ! haproxy -c -f /etc/haproxy/haproxy.cfg > /dev/null 2>&1; then
  echo -e "${RED}Internal HTTP/2 router validation failed.${NC}"
  exit 1
fi
mkdir -p /etc/systemd/system/haproxy.service.d > /dev/null 2>&1
cat <<'EOF_H2_UNIT' > /etc/systemd/system/haproxy.service.d/xray-order.conf
[Unit]
After=xray.service network-online.target
Wants=xray.service network-online.target
EOF_H2_UNIT
systemctl daemon-reload > /dev/null 2>&1
systemctl enable haproxy > /dev/null 2>&1
systemctl restart haproxy > /dev/null 2>&1

# USER EXPIRY CRONJOB FOR XRAY
cat <<'EOF_EXP' > /usr/local/bin/exp-check
#!/bin/bash
set -o pipefail
umask 077
now=$(date +%Y-%m-%d)
CONFIG="/etc/xray/config.json"
[ -s "$CONFIG" ] || exit 0

exec 9>/run/lock/xray-config.lock
flock -w 30 9 || { logger -t xray-exp "Timed out waiting for the Xray config lock"; exit 1; }

work_dir=$(mktemp -d /tmp/xray-exp.XXXXXX) || exit 1
trap 'rm -rf "$work_dir"' EXIT

mapfile -t expired_users < <(
  for proto in vless vmess trojan; do
    db="/etc/xray/${proto}.txt"
    [ -f "$db" ] && awk -v d="$now" '$3 < d {print $1}' "$db"
  done | sort -u
)
[ "${#expired_users[@]}" -gt 0 ] || exit 0

expired_json=$(printf '%s\n' "${expired_users[@]}" | jq -R . | jq -s .) || exit 1
jq --argjson expired "$expired_json" '
  (.inbounds[] | select(((.settings.clients? // null) | type) == "array") | .settings.clients) |=
    map(. as $client | select(($expired | index($client.email)) == null)) |
  (.inbounds[] | select(((.settings.users? // null) | type) == "array") | .settings.users) |=
    map(. as $user | select(($expired | index($user.email)) == null))
' "$CONFIG" > "$work_dir/config.json" || exit 1

if ! /usr/local/bin/xray run -test -config "$work_dir/config.json" >/dev/null 2>&1; then
  logger -t xray-exp "Refusing expiry update: generated Xray config failed validation"
  exit 1
fi

cp -p "$CONFIG" "$work_dir/config.backup" || exit 1
install -m 600 "$work_dir/config.json" "$CONFIG" || exit 1
if ! systemctl restart xray; then
  install -m 600 "$work_dir/config.backup" "$CONFIG"
  systemctl restart xray || true
  logger -t xray-exp "Expiry update rolled back because Xray failed to restart"
  exit 1
fi

for proto in vless vmess trojan; do
  db="/etc/xray/${proto}.txt"
  [ -f "$db" ] || continue
  awk -v d="$now" '$3 >= d {print}' "$db" > "$work_dir/${proto}.txt" || exit 1
  install -m 600 "$work_dir/${proto}.txt" "$db" || exit 1
done
EOF_EXP
chmod +x /usr/local/bin/exp-check > /dev/null 2>&1
echo "0 0 * * * root /usr/local/bin/exp-check >/dev/null 2>&1" > /etc/cron.d/xray-expiry

# USER EXPIRY CRONJOB FOR HYSTERIA
cat <<'EOF_HYST_EXP' > /usr/local/bin/hysteria-exp
#!/bin/bash
now=$(date +%Y-%m-%d)
USER_DB="/etc/hysteria/users.txt"
CONFIG="/etc/hysteria/config.json"
changed=0

if [ -f "$USER_DB" ]; then
  # Read expired users into an array securely to avoid modifying the file while reading it
  mapfile -t expired_users < <(awk -v d="$now" '$2 < d {print $1}' "$USER_DB")
  
  for user in "${expired_users[@]}"; do
    # Remove from JSON config
    jq ".inbounds[0].users |= map(select(.auth_str != \"$user\"))" "$CONFIG" > /tmp/h.json && mv /tmp/h.json "$CONFIG"
    # Remove from TXT DB
    sed -i "/^$user /d" "$USER_DB"
    changed=1
  done
  
  # Only restart the UDP core if an account was actually scrubbed
  if [ "$changed" -eq 1 ]; then
    systemctl restart hysteria-server
  fi
fi
EOF_HYST_EXP

chmod +x /usr/local/bin/hysteria-exp > /dev/null 2>&1
echo "0 0 * * * root /usr/local/bin/hysteria-exp >/dev/null 2>&1" > /etc/cron.d/hysteria-expiry

# USER EXPIRY CRONJOB FOR HYSTERIA 2
cat <<'EOF_HYST2_EXP' > /usr/local/bin/hysteria2-exp
#!/bin/bash
now=$(date +%Y-%m-%d)
user_db="/etc/hysteria2/users.txt"
if [ -f "$user_db" ]; then
  exec 9>/run/lock/hysteria2-config.lock
  flock 9
  awk -v d="$now" '$3 >= d' "$user_db" > "${user_db}.tmp" && mv "${user_db}.tmp" "$user_db"
fi
EOF_HYST2_EXP
chmod 755 /usr/local/bin/hysteria2-exp > /dev/null 2>&1
echo "5 0 * * * root /usr/local/bin/hysteria2-exp >/dev/null 2>&1" > /etc/cron.d/hysteria2-expiry

# USER EXPIRY CRONJOB FOR ZIVPN
cat <<'EOF_ZIVPN_EXP' > /usr/local/bin/zivpn-exp
#!/bin/bash
now=$(date +%Y-%m-%d)
ZIVPN_USER_DB="/etc/zivpn/users.txt"
ZIVPN_CONFIG="/etc/zivpn/config.json"
changed=0
if [ -f "$ZIVPN_USER_DB" ]; then
  # Solo desactiva (no borra) a los que vencieron y siguen marcados 'active' (o sin campo de status = active por compatibilidad).
  mapfile -t expired_users < <(awk '$2 < "'"$now"'" && ($3=="" || $3=="active") {print $1}' "$ZIVPN_USER_DB")
  for user in "${expired_users[@]}"; do
    jq --arg u "$user" '.auth.config |= map(select(. != $u))' "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    awk -v u="$user" 'BEGIN{OFS=" "} $1==u{$3="inactive"} {print}' "$ZIVPN_USER_DB" > /tmp/zdb.$$ && mv /tmp/zdb.$$ "$ZIVPN_USER_DB"
    changed=1
  done
  if [ "$changed" -eq 1 ]; then
    systemctl restart zivpn.service
  fi
fi
EOF_ZIVPN_EXP
chmod +x /usr/local/bin/zivpn-exp > /dev/null 2>&1
echo "0 0 * * * root /usr/local/bin/zivpn-exp >/dev/null 2>&1" > /etc/cron.d/zivpn-expiry

# Nginx & Squid
rm -rf /home/vps/public_html /etc/nginx/sites-* /etc/nginx/nginx.conf > /dev/null 2>&1; mkdir -p /home/vps/public_html > /dev/null 2>&1
cat <<'myNginxC' > /etc/nginx/nginx.conf
user www-data; worker_processes auto; pid /var/run/nginx.pid;
events { multi_accept on; worker_connections 8192; }
http { gzip on; gzip_vary on; gzip_comp_level 5; gzip_types text/plain application/x-javascript text/xml text/css; autoindex on; sendfile on; tcp_nopush on; tcp_nodelay on; keepalive_timeout 65; types_hash_max_size 2048; server_tokens off; include /etc/nginx/mime.types; default_type application/octet-stream; access_log /var/log/nginx/access.log; error_log /var/log/nginx/error.log; client_max_body_size 32M; client_header_buffer_size 8m; large_client_header_buffers 8 8m; fastcgi_buffer_size 8m; fastcgi_buffers 8 8m; fastcgi_read_timeout 600; include /etc/nginx/conf.d/*.conf; }
myNginxC
cat <<'myvpsC' > /etc/nginx/conf.d/vps.conf
server { listen Nginx_Port; server_name 127.0.0.1 localhost; root /home/vps/public_html; location / { try_files $uri $uri/ /index.php?$args; } }
myvpsC
sed -i "s|Nginx_Port|$Nginx_Port|g" /etc/nginx/conf.d/vps.conf > /dev/null 2>&1
systemctl restart "$NGINX_SERVICE" > /dev/null 2>&1

rm -rf /etc/squid/squid.con* > /dev/null 2>&1
cat <<'mySquid' > /etc/squid/squid.conf
acl server dst IP-ADDRESS/32 localhost
acl ports_ port 14 22 53 21 8081 25 8000 3128 443 80 8080 8880 2082 2086 36712
http_port Squid_Port1
http_port Squid_Port2
http_access allow server
http_access deny all
http_access allow all
visible_hostname IP-ADDRESS
mySquid
sed -i "s|IP-ADDRESS|$IPADDR|g" /etc/squid/squid.conf > /dev/null 2>&1; sed -i "s|Squid_Port1|$Squid_Port1|g" /etc/squid/squid.conf > /dev/null 2>&1; sed -i "s|Squid_Port2|$Squid_Port2|g" /etc/squid/squid.conf > /dev/null 2>&1
systemctl restart "$SQUID_SERVICE" > /dev/null 2>&1

# Health Checks
mkdir -p /etc/deekayvpn/health > /dev/null 2>&1
cat <<'ServiceChecker' > /etc/deekayvpn/service_checker.sh
#!/bin/bash
MYID="MYCHATID"; KEY="MYBOTID"; URL="https://api.telegram.org/bot${KEY}/sendMessage"
send_telegram_message() { curl -s --max-time 10 --retry 5 --retry-delay 2 --retry-max-time 10 -d "chat_id=${MYID}&text=$1&disable_web_page_preview=true&parse_mode=markdown" "${URL}" >/dev/null 2>&1; }
server_ip="IPADDRESS"; datenow=$(date +"%Y-%m-%d %T"); IPCOUNTRY=$(curl -s "https://freeipapi.com/api/json/${server_ip}" | jq -r '.countryName')
STATE_DIR="/etc/deekayvpn/health"
check_port() { ss -lnt | awk '{print $4}' | grep -q ":$1$"; }
mark_fail() { local f="$STATE_DIR/$1.fail"; local n=0; [ -f "$f" ] && n=$(cat "$f"); n=$((n+1)); echo "$n" > "$f"; echo "$n"; }
clear_fail() { rm -f "$STATE_DIR/$1.fail"; }
restart_after_3_fails() {
    local fails=$(mark_fail "$1")
    if [ "$fails" -ge 3 ]; then
        systemctl restart "$2" >/dev/null 2>&1
        send_telegram_message "Service *$2* was offline or missing port(s) *$3* on server *${IPCOUNTRY}* ($server_ip). It has been auto-restarted at *${datenow}*."
        clear_fail "$1"
    fi
}
if check_port SSHPORT1 && check_port SSHPORT2 && systemctl is-active --quiet ssh; then clear_fail ssh; else restart_after_3_fails ssh ssh "SSHPORT1,SSHPORT2"; fi
if check_port STUNNELPORT && systemctl is-active --quiet stunnel4; then clear_fail stunnel4; else restart_after_3_fails stunnel4 stunnel4 "STUNNELPORT"; fi
if check_port SSLHPORT && systemctl is-active --quiet sslh; then clear_fail sslh; else restart_after_3_fails sslh sslh "SSLHPORT"; fi
if check_port SQUIDPORT1 && check_port SQUIDPORT2 && systemctl is-active --quiet squid; then clear_fail squid; else restart_after_3_fails squid squid "SQUIDPORT1,SQUIDPORT2"; fi
if check_port NGINXPORT && systemctl is-active --quiet nginx; then clear_fail nginx; else restart_after_3_fails nginx nginx "NGINXPORT"; fi
for port in 10080 25 2082 2086; do if check_port $port && systemctl is-active --quiet ws-proxy@$port; then clear_fail ws-proxy-$port; else restart_after_3_fails ws-proxy-$port ws-proxy@$port "$port"; fi; done
if check_port 443 && systemctl is-active --quiet xray; then clear_fail xray; else restart_after_3_fails xray xray "443, 80"; fi
if systemctl is-active --quiet hysteria-server; then clear_fail hysteria-server; else restart_after_3_fails hysteria-server hysteria-server "UDP"; fi
ServiceChecker

chmod 755 /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|MYCHATID|$My_Chat_ID|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|MYBOTID|$My_Bot_Key|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|IPADDRESS|$IPADDR|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|STUNNELPORT|$Stunnel_Port_Num|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SSLHPORT|$MainPort|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SQUIDPORT1|$Squid_Port1|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SQUIDPORT2|$Squid_Port2|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|NGINXPORT|$Nginx_Port|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SSHPORT1|$SSH_Port1|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SSHPORT2|$SSH_Port2|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1

echo "*/3 * * * * root /bin/bash /etc/deekayvpn/service_checker.sh >/dev/null 2>&1" > /etc/cron.d/service-checker

mkdir -p /etc/deekayvpn > /dev/null 2>&1
touch /etc/deekayvpn/ssh_limits.txt > /dev/null 2>&1
cat <<'SSHLimitChecker' > /etc/deekayvpn/ssh_limit_checker.sh
#!/bin/bash
DB="/etc/deekayvpn/ssh_limits.txt"
[ -s "$DB" ] || exit 0
while read -r suser slimit; do
  [ -z "$suser" ] && continue
  [[ "$slimit" =~ ^[0-9]+$ ]] || continue
  [ "$slimit" -le 0 ] && continue
  id "$suser" >/dev/null 2>&1 || continue
  mapfile -t sessions < <(ps -u "$suser" -o pid=,etimes=,cmd= 2>/dev/null | awk '$0 ~ /sshd/ {print $1" "$2}')
  count=${#sessions[@]}
  [ "$count" -le "$slimit" ] && continue
  excess=$((count - slimit))
  mapfile -t sorted < <(printf '%s\n' "${sessions[@]}" | sort -k2,2n)
  for ((i=0; i<excess; i++)); do
    pid=$(awk '{print $1}' <<< "${sorted[$i]}")
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  done
done < "$DB"
SSHLimitChecker
chmod 755 /etc/deekayvpn/ssh_limit_checker.sh > /dev/null 2>&1
echo "* * * * * root /bin/bash /etc/deekayvpn/ssh_limit_checker.sh >/dev/null 2>&1" > /etc/cron.d/ssh-limit-checker
rm -f /etc/logrotate.d/rsyslog > /dev/null 2>&1
cat <<'logrotate' > /etc/logrotate.d/rsyslog
/var/log/syslog /var/log/kern.log /var/log/auth.log /var/log/xray/access.log /var/log/xray/error.log { rotate 7; daily; missingok; notifempty; compress; delaycompress; sharedscripts; postrotate; /usr/lib/rsyslog/rsyslog-rotate; endscript; }
logrotate
chown root:root /var/log > /dev/null 2>&1; chmod 755 /var/log > /dev/null 2>&1; chown syslog:adm /var/log/syslog > /dev/null 2>&1; chmod 640 /var/log/syslog > /dev/null 2>&1
echo "*/5 * * * * root /usr/sbin/logrotate -v -f /etc/logrotate.d/rsyslog >/dev/null 2>&1" > /etc/cron.d/logrotate
echo "0 3 * * * root sync; echo 3 > /proc/sys/vm/drop_caches" > /etc/cron.d/drop-cache

# ==========================================
# AGGRESSIVE SYSTEM & CONNTRACK TUNING
# ==========================================
# Force load nf_conntrack module
modprobe nf_conntrack 2>/dev/null || true; echo "nf_conntrack" > /etc/modules-load.d/freenet.conf
cat <<'SYSCTL' > /etc/sysctl.d/99-freenet-tuning.conf
# File Descriptors
fs.file-max = 1048576

# Network Core
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384

# TCP Settings
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10

# SOCKS / WARP Local Loopback Optimization
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1

# Connection Tracking Limits (Prevents silent drops)
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 1200
net.netfilter.nf_conntrack_udp_timeout = 60
SYSCTL
sysctl --system > /dev/null 2>&1 || true
mkdir -p /etc/security/limits.d > /dev/null 2>&1
cat <<'LIMITS' > /etc/security/limits.d/99-freenet.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS

# SLOWDNS
rm -rf /etc/slowdns > /dev/null 2>&1; mkdir -m 777 /etc/slowdns > /dev/null 2>&1
cat > /etc/slowdns/server.key << END
$Serverkey
END
cat > /etc/slowdns/server.pub << END
$Serverpub
END
wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server" 2>/dev/null
chmod +x /etc/slowdns/server.key /etc/slowdns/server.pub /etc/slowdns/sldns-server > /dev/null 2>&1
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT > /dev/null 2>&1
cat > /etc/systemd/system/server-sldns.service << END
[Unit]
Description=Server SlowDNS
After=network.target
[Service]
ExecStart=/etc/slowdns/sldns-server -udp :53 -privkey-file /etc/slowdns/server.key $Nameserver 127.0.0.1:$SSH_Port2
Restart=on-failure
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload > /dev/null 2>&1; systemctl enable server-sldns > /dev/null 2>&1; systemctl restart server-sldns > /dev/null 2>&1


# === HYSTERIA v1 (Sing-box v1.12.22) & CLOUDFLARE WARP ===
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg > /dev/null 2>&1
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list > /dev/null 2>&1
apt-get update > /dev/null 2>&1 && apt-get install -y cloudflare-warp > /dev/null 2>&1

warp-cli --accept-tos disconnect 2>/dev/null || true
warp-cli --accept-tos registration delete 2>/dev/null || true
warp-cli --accept-tos registration new 2>/dev/null || warp-cli --accept-tos register > /dev/null 2>&1
warp-cli --accept-tos mode proxy > /dev/null 2>&1
warp-cli --accept-tos proxy port 40000 > /dev/null 2>&1
warp-cli --accept-tos connect > /dev/null 2>&1
sleep 2

wget -qO /tmp/sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v1.12.22/sing-box_1.12.22_linux_amd64.deb" 2>/dev/null
dpkg -i /tmp/sing-box.deb > /dev/null 2>&1
apt-mark hold sing-box > /dev/null 2>&1
rm -f /tmp/sing-box.deb > /dev/null 2>&1

mkdir -p /etc/hysteria > /dev/null 2>&1
HYST_PORT="${UDP_PORT##*:}"

cat << EOF > /etc/hysteria/hysteria.crt
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 40:26:da:91:18:2b:77:9c:85:6a:0c:bb:ca:90:53:fe
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN=KobZ
        Validity
            Not Before: Jul 22 22:23:55 2020 GMT
            Not After : Jul 20 22:23:55 2030 GMT
        Subject: CN=server
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                RSA Public-Key: (1024 bit)
                Modulus:
                    00:ce:35:23:d8:5d:9f:b6:9b:cb:6a:89:e1:90:af:
                    42:df:5f:f8:bd:ad:a7:78:9a:ca:20:f0:3d:5b:d6:
                    c9:ef:4c:4a:99:96:c3:38:fd:59:b4:d7:65:ed:d4:
                    a7:fa:ab:03:e2:be:88:2f:ca:fc:90:dd:b0:b7:bc:
                    23:cb:83:ac:36:e2:01:57:69:64:b8:e1:9e:51:f0:
                    a6:9d:13:d9:92:6b:4d:04:a6:10:64:a3:3f:6b:ff:
                    fe:32:ac:91:63:c2:71:24:be:9e:76:4f:87:cc:3a:
                    03:a1:9e:48:3f:11:92:33:3b:19:16:9c:d0:5d:16:
                    ee:c1:42:67:99:47:66:67:67
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Basic Constraints: CA:FALSE
            X509v3 Subject Key Identifier: 6B:08:C0:64:10:71:A8:32:7F:0B:FE:1E:98:1F:BD:72:74:0F:C8:66
            X509v3 Authority Key Identifier: keyid:64:49:32:6F:FE:66:62:F1:57:4D:BB:91:A8:5D:BD:26:3E:51:A4:D2
                DirName:/CN=KobZ
                serial:01:A4:01:02:93:12:D9:D6:01:A9:83:DC:03:73:DA:ED:C8:E3:C3:B7
            X509v3 Extended Key Usage: TLS Web Server Authentication
            X509v3 Key Usage: Digital Signature, Key Encipherment
            X509v3 Subject Alternative Name: DNS:server
    Signature Algorithm: sha256WithRSAEncryption
         a1:3e:ac:83:0b:e5:5d:ca:36:b7:d0:ab:d0:d9:73:66:d1:62:
         88:ce:3d:47:9e:08:0b:a0:5b:51:13:fc:7e:d7:6e:17:0e:bd:
         f5:d9:a9:d9:06:78:52:88:5a:e5:df:d3:32:22:4a:4b:08:6f:
         b1:22:80:4f:19:d1:5f:9d:b6:5a:17:f7:ad:70:a9:04:00:ff:
         fe:84:aa:e1:cb:0e:74:c0:1a:75:0b:3e:98:90:1d:22:ba:a4:
         7a:26:65:7d:d1:3b:5c:45:a1:77:22:ed:b6:6b:18:a3:c4:ee:
         3e:06:bb:0b:ec:12:ac:16:a5:50:b3:ed:46:43:87:72:fd:75:8c:38
-----BEGIN CERTIFICATE-----
MIICVDCCAb2gAwIBAgIQQCbakRgrd5yFagy7ypBT/jANBgkqhkiG9w0BAQsFADAP
MQ0wCwYDVQQDDARLb2JaMB4XDTIwMDcyMjIyMjM1NVoXDTMwMDcyMDIyMjM1NVow
ETEPMA0GA1UEAwwGc2VydmVyMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDO
NSPYXZ+2m8tqieGQr0LfX/i9rad4msog8D1b1snvTEqZlsM4/Vm012Xt1Kf6qwPi
vogvyvyQ3bC3vCPLg6w24gFXaWS44Z5R8KadE9mSa00EphBkoz9r//4yrJFjwnEk
vp52T4fMOgOhnkg/EZIzOxkWnNBdFu7BQmeZR2ZnZwIDAQABo4GuMIGrMAkGA1Ud
EwQCMAAwHQYDVR0OBBYEFGsIwGQQcagyfwv+HpgfvXJ0D8hmMEoGA1UdIwRDMEGA
FGRJMm/+ZmLxV027kahdvSY+UaTSoROkETAPMQ0wCwYDVQQDDARLb2JaghQBpAEC
kxLZ1gGpg9wDc9rtyOPDtzATBgNVHSUEDDAKBggrBgEFBQcDATALBgNVHQ8EBAMC
BaAwEQYDVR0RBAowCIIGc2VydmVyMA0GCSqGSIb3DQEBCwUAA4GBAKE+rIML5V3K
NrfQq9DZc2bRYojOPUeeCAugW1ET/H7XbhcOvfXZqdkGeFKIWuXf0zIiSksIb7Ei
gE8Z0V+dtloX961wqQQA//6EquHLDnTAGnULPpiQHSK6pHomZX3RO1xFoXci7bZr
GKPE7j4GuwvsEqwWpVCz7UZDh3L9dYw4
-----END CERTIFICATE-----
EOF

cat << EOF > /etc/hysteria/hysteria.key
-----BEGIN PRIVATE KEY-----
MIICdQIBADANBgkqhkiG9w0BAQEFAASCAl8wggJbAgEAAoGBAM41I9hdn7aby2qJ
4ZCvQt9f+L2tp3iayiDwPVvWye9MSpmWwzj9WbTXZe3Up/qrA+K+iC/K/JDdsLe8
I8uDrDbiAVdpZLjhnlHwpp0T2ZJrTQSmEGSjP2v//jKskWPCcSS+nnZPh8w6A6Ge
SD8RkjM7GRac0F0W7sFCZ5lHZmdnAgMBAAECgYAFNrC+UresDUpaWjwaxWOidDG8
0fwu/3Lm3Ewg21BlvX8RXQ94jGdNPDj2h27r1pEVlY2p767tFr3WF2qsRZsACJpI
qO1BaSbmhek6H++Fw3M4Y/YY+JD+t1eEBjJMa+DR5i8Vx3AE8XOdTXmkl/xK4jaB
EmLYA7POyK+xaDCeEQJBAPJadiYd3k9OeOaOMIX+StCs9OIMniRz+090AJZK4CMd
jiOJv0mbRy945D/TkcqoFhhScrke9qhgZbgFj11VbDkCQQDZ0aKBPiZdvDMjx8WE
y7jaltEDINTCxzmjEBZSeqNr14/2PG0X4GkBL6AAOLjEYgXiIvwfpoYE6IIWl3re
ebCfAkAHxPimrixzVGux0HsjwIw7dl//YzIqrwEugeSG7O2Ukpz87KySOoUks3Z1
yV2SJqNWskX1Q1Xa/gQkyyDWeCeZAkAbyDBI+ctc8082hhl8WZunTcs08fARM+X3
FWszc+76J1F2X7iubfIWs6Ndw95VNgd4E2xDATNg1uMYzJNgYvcTAkBoE8o3rKkp
em2n0WtGh6uXI9IC29tTQGr3jtxLckN/l9KsJ4gabbeKNoes74zdena1tRdfGqUG
JQbf7qSE3mg2
-----END PRIVATE KEY-----
EOF

cat > /etc/hysteria/config.json <<EOF
{
  "log": { "level": "fatal" },
  "inbounds": [
    {
      "type": "hysteria",
      "tag": "hy1-inbound",
      "listen": "::",
      "listen_port": $HYST_PORT,
      "up_mbps": 100, "down_mbps": 100,
      "obfs": "$OBFS",
      "users": [ { "auth_str": "$PASSWORD" } ],
      "tls": { "enabled": true, "certificate_path": "/etc/hysteria/hysteria.crt", "key_path": "/etc/hysteria/hysteria.key" }
    }
  ],
  "outbounds": [
    { "type": "socks", "tag": "warp-proxy", "server": "127.0.0.1", "server_port": 40000 },
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      {
        "inbound": "hy1-inbound",
        "network": "udp",
        "domain_suffix": [ "doubleclick.net", "googlesyndication.com", "googleadservices.com", "admob.com", "google-analytics.com", "app-measurement.com", "adservice.google.com", "g.doubleclick.net", "google.com", "pagead2.googlesyndication.com", "tpc.googlesyndication.com", "googlevideo.com", "gvt1.com", "gvt2.com", "gvt3.com", "ytimg.com", "youtube.com", "gstatic.com", "googleusercontent.com", "ggpht.com", "play.google.com", "firebaseio.com", "firebase.googleapis.com", "crashlytics.com", "fundingchoicesmessages.google.com", "imasdk.googleapis.com", "googleanalytics.com", "analytics.google.com", "fcm.googleapis.com", "mtalk.google.com", "firebaseinstallations.googleapis.com", "firebaselogging.googleapis.com", "firebaselogging-pa.googleapis.com", "firebaseremoteconfig.googleapis.com", "googleadapis.com", "accounts.google.com", "play.googleapis.com", "android.apis.google.com", "adsense.com", "1e100.net" ],
        "outbound": "block"
      },
      {
        "inbound": "hy1-inbound",
        "domain_suffix": [ "doubleclick.net", "googlesyndication.com", "googleadservices.com", "admob.com", "google-analytics.com", "app-measurement.com", "adservice.google.com", "g.doubleclick.net", "google.com", "pagead2.googlesyndication.com", "tpc.googlesyndication.com", "googlevideo.com", "gvt1.com", "gvt2.com", "gvt3.com", "ytimg.com", "youtube.com", "gstatic.com", "googleusercontent.com", "ggpht.com", "play.google.com", "firebaseio.com", "firebase.googleapis.com", "crashlytics.com", "fundingchoicesmessages.google.com", "imasdk.googleapis.com", "googleanalytics.com", "analytics.google.com", "fcm.googleapis.com", "mtalk.google.com", "firebaseinstallations.googleapis.com", "firebaselogging.googleapis.com", "firebaselogging-pa.googleapis.com", "firebaseremoteconfig.googleapis.com", "googleadapis.com", "accounts.google.com", "play.googleapis.com", "android.apis.google.com", "adsense.com", "1e100.net" ],
        "outbound": "warp-proxy"
      },
      { "inbound": "hy1-inbound", "outbound": "direct" }
    ],
    "auto_detect_interface": true
  }
}
EOF

chmod 755 /etc/hysteria/config.json /etc/hysteria/hysteria.crt /etc/hysteria/hysteria.key > /dev/null 2>&1
echo "$PASSWORD $(date -d "+365 days" +"%Y-%m-%d")" > /etc/hysteria/users.txt

cat > /etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Sing-Box Hysteria v1 Core
After=network.target
[Service]
User=root
ExecStart=/usr/bin/sing-box run -c /etc/hysteria/config.json
Restart=on-failure
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload > /dev/null 2>&1; systemctl enable hysteria-server.service > /dev/null 2>&1; systemctl start hysteria-server.service > /dev/null 2>&1

# NAT & Iptables Configuration
IFACE="$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)"
cat > /etc/systemd/system/hysteria-nat.service <<EOF
[Unit]
Description=Restore Hysteria UDP NAT rules
After=network-online.target
Wants=network-online.target
Before=hysteria-server.service
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IFACE=\$(ip -4 route ls|grep default|grep -Po "(?<=dev )(\\\\S+)"|head -1); [ -n "\$IFACE" ] && (iptables -t nat -C PREROUTING -i "\$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :$HYST_PORT 2>/dev/null || iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :$HYST_PORT)'
ExecStart=/bin/bash -c 'iptables -C INPUT -p udp --dport $HYST_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $HYST_PORT -j ACCEPT'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload > /dev/null 2>&1; systemctl enable hysteria-nat.service > /dev/null 2>&1; systemctl start hysteria-nat.service > /dev/null 2>&1

# === HYSTERIA 2 (official core, separate from Hysteria v1) ===
HYSTERIA2_VER="app/v2.9.3"
case "$(uname -m)" in
  x86_64|amd64) HYSTERIA2_ASSET="hysteria-linux-amd64" ;;
  i386|i486|i586|i686) HYSTERIA2_ASSET="hysteria-linux-386" ;;
  aarch64|arm64) HYSTERIA2_ASSET="hysteria-linux-arm64" ;;
  armv7l|armv7*) HYSTERIA2_ASSET="hysteria-linux-arm" ;;
  *) echo "Unsupported Hysteria 2 architecture: $(uname -m)"; exit 1 ;;
esac

HYSTERIA2_RELEASE_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA2_VER}"
hyst2_tmp=$(mktemp -d /tmp/hysteria2-install.XXXXXX) || exit 1
if ! curl -fL --retry 3 -o "$hyst2_tmp/$HYSTERIA2_ASSET" "$HYSTERIA2_RELEASE_URL/$HYSTERIA2_ASSET" 2>/dev/null ||
   ! curl -fL --retry 3 -o "$hyst2_tmp/hashes.txt" "$HYSTERIA2_RELEASE_URL/hashes.txt" 2>/dev/null; then
  rm -rf "$hyst2_tmp"
  echo -e "${RED}Hysteria 2 download failed.${NC}"
  exit 1
fi
hyst2_expected=$(awk -v asset="$HYSTERIA2_ASSET" '$2 == asset || $2 == "build/" asset || $2 == "*" asset {print tolower($1); exit}' "$hyst2_tmp/hashes.txt")
hyst2_actual=$(sha256sum "$hyst2_tmp/$HYSTERIA2_ASSET" | awk '{print tolower($1)}')
if [ -z "$hyst2_expected" ] || [ "$hyst2_actual" != "$hyst2_expected" ]; then
  rm -rf "$hyst2_tmp"
  echo -e "${RED}Hysteria 2 SHA-256 verification failed.${NC}"
  exit 1
fi
install -m 755 "$hyst2_tmp/$HYSTERIA2_ASSET" /usr/local/bin/hysteria2 > /dev/null 2>&1
rm -rf "$hyst2_tmp" > /dev/null 2>&1

mkdir -p /etc/hysteria2 > /dev/null 2>&1
mkdir -p /usr/local/libexec > /dev/null 2>&1
cat <<'EOF_HYST2_AUTH' > /usr/local/libexec/hysteria2-auth
#!/bin/bash
user_db="/etc/hysteria2/users.txt"
auth="$2"
[ -n "$auth" ] && [ -r "$user_db" ] || exit 1
awk -v token="$auth" '$2 == token {print $1; found=1; exit} END {exit !found}' "$user_db"
EOF_HYST2_AUTH
chmod 700 /usr/local/libexec/hysteria2-auth > /dev/null 2>&1

HYST2_INITIAL_TOKEN=$(cat /proc/sys/kernel/random/uuid)
jq -n \
  --arg listen ":$HYST2_PORT" \
  --arg cert "/etc/xray/xray.crt" \
  --arg key "/etc/xray/xray.key" \
  --arg obfs "$OBFS" '
  {
    listen: $listen,
    tls: {cert: $cert, key: $key},
    auth: {type: "command", command: "/usr/local/libexec/hysteria2-auth"},
    obfs: {type: "salamander", salamander: {password: $obfs}},
    masquerade: {
      type: "proxy",
      proxy: {url: "https://www.microsoft.com/", rewriteHost: true}
    }
  }
' > /etc/hysteria2/config.json
chmod 600 /etc/hysteria2/config.json > /dev/null 2>&1
printf 'default %s %s\n' "$HYST2_INITIAL_TOKEN" "$(date -d '+365 days' +%Y-%m-%d)" > /etc/hysteria2/users.txt
chmod 600 /etc/hysteria2/users.txt > /dev/null 2>&1

cat <<'EOF_HYST2_SERVICE' > /etc/systemd/system/hysteria2-server.service
[Unit]
Description=Official Hysteria 2 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.json
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=/etc/xray/xray.crt /etc/xray/xray.key
ReadWritePaths=/etc/hysteria2

[Install]
WantedBy=multi-user.target
EOF_HYST2_SERVICE

iptables -C INPUT -p udp --dport "$HYST2_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$HYST2_PORT" -j ACCEPT > /dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1 || true
systemctl daemon-reload > /dev/null 2>&1
systemctl enable hysteria2-server.service > /dev/null 2>&1
if ! systemctl restart hysteria2-server.service > /dev/null 2>&1; then
  journalctl -u hysteria2-server -n 50 --no-pager
  echo -e "${RED}Hysteria 2 failed to start.${NC}"
  exit 1
fi

# Creating startup script
cat <<'deekayz' > /etc/deekaystartup
#!/bin/sh
ln -fs /usr/share/zoneinfo/MyTimeZone /etc/localtime
export DEBIAN_FRONTEND=noninteractive
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo "nameserver DNS1" > /etc/resolv.conf; echo "nameserver DNS2" >> /etc/resolv.conf
mkdir -p /var/run/sslh; touch /var/run/sslh/sslh.pid; chmod 777 /var/run/sslh/sslh.pid

# Standard INPUT rule for Port 53
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT

# 🚨 NEW FIX: VIP Pass for Port 53 (Prevents UDP Custom from swallowing SlowDNS traffic)
iptables -t nat -C PREROUTING -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -t nat -I PREROUTING 1 -p udp --dport 53 -j ACCEPT

# Keep Hysteria 2 out of the broad Hysteria 1 and UDP-Custom DNAT ranges.
# These exemptions must remain ahead of all range/catch-all DNAT rules.
iptables -t nat -C PREROUTING -p udp --dport 36713 -j ACCEPT 2>/dev/null || iptables -t nat -I PREROUTING 1 -p udp --dport 36713 -j ACCEPT
iptables -t nat -C PREROUTING -p udp --dport 443 -j ACCEPT 2>/dev/null || iptables -t nat -I PREROUTING 1 -p udp --dport 443 -j ACCEPT

# Hysteria NAT Routing
IFACE=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :36712 2>/dev/null || iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :36712
deekayz

sed -i "s|MyTimeZone|$MyVPS_Time|g" /etc/deekaystartup > /dev/null 2>&1
sed -i "s|DNS1|$Dns_1|g" /etc/deekaystartup > /dev/null 2>&1
sed -i "s|DNS2|$Dns_2|g" /etc/deekaystartup > /dev/null 2>&1

cat <<'deekayx' > /etc/systemd/system/deekaystartup.service
[Unit]
Description=Custom startup script
ConditionPathExists=/etc/deekaystartup
[Service]
Type=oneshot
ExecStart=/etc/deekaystartup
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
deekayx
chmod +x /etc/deekaystartup > /dev/null 2>&1; systemctl enable deekaystartup > /dev/null 2>&1

# BadVPN (127.0.0.1:7300) + UDP Custom (36717), como un solo paso "UDP"
instalar_udp() {
    if [ "$(getconf LONG_BIT)" == "64" ]; then
        wget -q -O /usr/bin/badvpn-udpgw "https://www.dropbox.com/s/jo6qznzwbsf1xhi/badvpn-udpgw64" 2>/dev/null
    else
        wget -q -O /usr/bin/badvpn-udpgw "https://www.dropbox.com/s/8gemt9c6k1fph26/badvpn-udpgw" 2>/dev/null
    fi
    chmod +x /usr/bin/badvpn-udpgw > /dev/null 2>&1

    cat <<'deekayb' > /etc/systemd/system/badvpn.service
[Unit]
Description=badvpn tun2socks service
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
[Install]
WantedBy=multi-user.target
deekayb
    systemctl enable badvpn > /dev/null 2>&1; systemctl start badvpn > /dev/null 2>&1

    # === UDP CUSTOM (Port 36717) ===
    mkdir -p /root/udp > /dev/null 2>&1
    wget -q -O /root/udp/udp-custom "https://raw.githubusercontent.com/mahpud896/UDP-Custom/main/bin/udp-custom-linux-amd64" 2>/dev/null || true
    chmod +x /root/udp/udp-custom 2>/dev/null || true
    wget -q -O /root/udp/config.json "https://raw.githubusercontent.com/mahpud896/UDP-Custom/main/config/config.json" 2>/dev/null || true
    sed -i "s/\":36712\"/\":36717\"/g" /root/udp/config.json 2>/dev/null || true
    chmod 644 /root/udp/config.json 2>/dev/null || true

    cat > /etc/systemd/system/udp-custom.service <<EOF
[Unit]
Description=UDP Custom Proxy
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root/udp
ExecStart=/root/udp/udp-custom server -c /root/udp/config.json
Restart=always
RestartSec=2s
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload > /dev/null 2>&1; systemctl enable udp-custom > /dev/null 2>&1; systemctl start udp-custom 2>/dev/null || true
}
step "Instalando UDP..." instalar_udp

# === ZIVPN (Port 5667) ===
instalar_zivpn_bin() {
    mkdir -p /etc/zivpn > /dev/null 2>&1
wget -q -O /usr/local/bin/zivpn "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" 2>/dev/null || true
chmod +x /usr/local/bin/zivpn 2>/dev/null || true
cp /etc/hysteria/hysteria.crt /etc/zivpn/zivpn.crt 2>/dev/null || true
cp /etc/hysteria/hysteria.key /etc/zivpn/zivpn.key 2>/dev/null || true
chmod 644 /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key 2>/dev/null || true
cat > /etc/zivpn/config.json <<EOF
{
  "listen": ":5667",
   "cert": "/etc/zivpn/zivpn.crt",
   "key": "/etc/zivpn/zivpn.key",
   "obfs": "zivpn",
   "auth": {
    "mode": "passwords", 
    "config": ["$PASSWORD"]
  }
}
EOF
chmod 644 /etc/zivpn/config.json > /dev/null 2>&1
echo "$PASSWORD $(date -d "+365 days" +"%Y-%m-%d") active" > /etc/zivpn/users.txt

cat > /etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=zivpn VPN Server
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/zivpn-nat.service <<EOF
[Unit]
Description=Restore ZiVPN UDP NAT rules
After=network-online.target
Wants=network-online.target
Before=zivpn.service
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IFACE=\$(ip -4 route ls|grep default|grep -Po "(?<=dev )(\\\\S+)"|head -1); [ -n "\$IFACE" ] && (iptables -t nat -C PREROUTING -i "\$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667)'
ExecStart=/bin/bash -c 'iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5667 -j ACCEPT'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload > /dev/null 2>&1; systemctl enable zivpn.service > /dev/null 2>&1; systemctl start zivpn.service 2>/dev/null || true
systemctl enable zivpn-nat.service > /dev/null 2>&1; systemctl start zivpn-nat.service 2>/dev/null || true
}
step "Instalando ZiVPN..." instalar_zivpn_bin

# VNSTAT INITIALIZATION
IFACE="$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)"
vnstat -u -i "$IFACE" 2>/dev/null || true
systemctl enable vnstat > /dev/null 2>&1
systemctl restart vnstat > /dev/null 2>&1

# MENU CREATION - FULL AND UNCOMPRESSED
mkdir -p /usr/local/bin > /dev/null 2>&1
sed -i '/# HEXTUNNEL_MENU_AUTOSTART_START/,/# HEXTUNNEL_MENU_AUTOSTART_END/d' ~/.bashrc 2>/dev/null || true
cat >> ~/.bashrc <<'EOF_BASHRC_AUTOSTART'
 
# HEXTUNNEL_MENU_AUTOSTART_START
if [[ $- == *i* ]] && [ -z "$HEXTUNNEL_MENU_SHOWN" ]; then
    export HEXTUNNEL_MENU_SHOWN=1
    menu
fi
# HEXTUNNEL_MENU_AUTOSTART_END
EOF_BASHRC_AUTOSTART
cat > /usr/local/bin/menu <<'EOF_MENU'
#!/bin/bash

# Detecta si el certificado activo es real (Let's Encrypt) o autofirmado
if [ -f /etc/xray/cert_type ] && grep -q "letsencrypt" /etc/xray/cert_type; then
    XRAY_INSECURE="0"
else
    XRAY_INSECURE="1"
fi
if [ "$XRAY_INSECURE" = "1" ]; then
    INSECURE_PARAM="&allowInsecure=1"
else
    INSECURE_PARAM=""
fi

# Modern Color Palette
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'
BG_TITLE='\033[48;5;25m\033[97m\033[1m'   # Barra de título con fondo azul
ACC='\033[38;5;44m'                        # Acento turquesa para separadores

DOMAIN=$(cat /etc/deekayvpn/domain.txt 2>/dev/null || curl -4 -s --max-time 2 ipv4.icanhazip.com)

HYST_CONFIG="/etc/hysteria/config.json"
HYST_USER_DB="/etc/hysteria/users.txt"
touch "$HYST_USER_DB" 2>/dev/null || true

HYST2_CONFIG="/etc/hysteria2/config.json"
HYST2_USER_DB="/etc/hysteria2/users.txt"
HYST2_PORT="${HYST2_PORT:-36713}"
touch "$HYST2_USER_DB" 2>/dev/null || true
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_DB="/etc/zivpn/users.txt"
SSH_LIMIT_DB="/etc/deekayvpn/ssh_limits.txt"
mkdir -p /etc/deekayvpn 2>/dev/null || true
touch "$SSH_LIMIT_DB" 2>/dev/null || true

# --- Utility Functions ---
server_ip() { curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'; }
cpu_count() { nproc 2>/dev/null || echo "1"; }
mem_stats() { free -h 2>/dev/null | awk '/Mem:/ {print $2 "|" $7 "|" $3}'; }
ram_percent() { free 2>/dev/null | awk '/Mem:/ { if ($2>0) printf "%.1f%%", ($3/$2)*100; else print "0.0%" }'; }
cpu_percent() { top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/ { gsub("%us","",$1); gsub(" ","",$1); split($1,a,":"); if (a[2] == "") print "0.0%"; else printf "%.1f%%", a[2]+0 }'; }
buffer_mem() { free -m 2>/dev/null | awk '/Mem:/ {print $6 "M"}'; }

server_status() {
  local ok=0
  for s in ssh stunnel4 squid nginx server-sldns hysteria-server hysteria2-server ws-proxy@10080 xray; do
    systemctl is-active --quiet "$s" 2>/dev/null && ok=$((ok+1))
  done
  [ "$ok" -ge 4 ] && echo -e "${GREEN}EN LÍNEA${NC}" || echo -e "${RED}PROBLEMAS DETECTADOS${NC}"
}
pause_return() { echo; read -rp "Presiona ENTER para volver... " _; }

# --- ZIVPN MANAGEMENT FUNCTIONS ---
add_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Ingresa Contraseña: " new_pass
    
    if grep -qw "^$new_pass" "$ZIVPN_USER_DB" 2>/dev/null; then
        echo -e "\n${RED}Error: Contraseña ya existe!${NC}"
        pause_return; return
    fi
    read -rp " Validez (Dias): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Numero Invalido.${NC}"; pause_return; return; fi
    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    
    jq ".auth.config += [\"$new_pass\"]" "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    echo "$new_pass $exp_date active" >> "$ZIVPN_USER_DB"
    systemctl restart zivpn.service
    
    OBFS_VAL=$(jq -r '.obfs' "$ZIVPN_CONFIG" 2>/dev/null || echo "zivpn")
    
    echo -e "\n${GREEN}✔ Usuario creado exitosamente!${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e " ${BOLD}IP:${NC}          ${YELLOW}$(server_ip)${NC}"
    echo -e " ${BOLD}Dominio:${NC}      ${YELLOW}${DOMAIN:-$(server_ip)}${NC}"
    echo -e " ${BOLD}Puerto De Rango:${NC}  ${YELLOW}6000-19999${NC}"
    echo -e " ${BOLD}Usuario (Contraseña):${NC} ${YELLOW}${new_pass}${NC}"
    echo -e " ${BOLD}Obfuscación (obfs):${NC} ${YELLOW}${OBFS_VAL}${NC}"
    echo -e " ${BOLD}Fecha de Expiración:${NC} ${YELLOW}${exp_date}${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    pause_return
}

del_zivpn() {
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO ZIVPN${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "No Hay Usuarios."; pause_return; return; fi
    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3" | Estado: "($4==""?"active":$4)}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a eliminar: " del_id
    if ! [[ "$del_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi

    del_pass=$(sed -n "${del_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    if [ -z "$del_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi
    jq --arg p "$del_pass" '.auth.config |= map(select(. != $p))' "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    sed -i "${del_id}d" "$ZIVPN_USER_DB"
    systemctl restart zivpn.service
    echo -e "\n${GREEN}✔ Usuario '$del_pass' eliminado exitosamente!${NC}"
    pause_return
}

activar_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ACTIVAR USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "No Hay Usuarios."; pause_return; return; fi
    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3" | Estado: "($4==""?"active":$4)}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a activar: " act_id
    if ! [[ "$act_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi

    act_pass=$(sed -n "${act_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    act_exp=$(sed -n "${act_id}p" "$ZIVPN_USER_DB" | awk '{print $2}')
    if [ -z "$act_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi

    today=$(date +%Y-%m-%d)
    if [ "$act_exp" \< "$today" ]; then
        echo -e "\n${RED}✘ No se puede activar, la cuenta ya expiró (${act_exp}). Extiéndela primero.${NC}"
        pause_return; return
    fi

    jq --arg p "$act_pass" '.auth.config |= ((. + [$p]) | unique)' "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    awk -v id="$act_id" 'BEGIN{OFS=" "} NR==id{$3="active"} {print}' "$ZIVPN_USER_DB" > /tmp/zdb.$$ && mv /tmp/zdb.$$ "$ZIVPN_USER_DB"
    systemctl restart zivpn.service
    echo -e "\n${GREEN}✔ Usuario '$act_pass' activado.${NC}"
    pause_return
}

desactivar_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}DESACTIVAR USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "No Hay Usuarios."; pause_return; return; fi
    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3" | Estado: "($4==""?"active":$4)}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a desactivar: " deact_id
    if ! [[ "$deact_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi

    deact_pass=$(sed -n "${deact_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    if [ -z "$deact_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi

    jq --arg p "$deact_pass" '.auth.config |= map(select(. != $p))' "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    awk -v id="$deact_id" 'BEGIN{OFS=" "} NR==id{$3="inactive"} {print}' "$ZIVPN_USER_DB" > /tmp/zdb.$$ && mv /tmp/zdb.$$ "$ZIVPN_USER_DB"
    systemctl restart zivpn.service
    echo -e "\n${GREEN}✔ Usuario '$deact_pass' desactivado (queda guardado, no se borró).${NC}"
    pause_return
}

extend_zivpn() {
    clear
      echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
      echo -e "                 ${BOLD}EXTENDER USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "Usuarios No Encontrados."; pause_return; return; fi

    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3" | Estado: "($4==""?"active":$4)}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a extender: " ext_id
    if ! [[ "$ext_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}Número de ID inválido.${NC}"; pause_return; return; fi
    
    ext_pass=$(sed -n "${ext_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    current_exp=$(sed -n "${ext_id}p" "$ZIVPN_USER_DB" | awk '{print $2}')
    if [ -z "$ext_pass" ]; then echo -e "${RED}ID No Encontrado.${NC}"; pause_return; return; fi
  
    read -rp " Agregar Validez (Dias): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Numero Invalido.${NC}"; pause_return; return; fi
    
    new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
    awk -v id="$ext_id" -v ne="$new_exp" 'BEGIN{OFS=" "} NR==id{$2=ne; $3="active"} {print}' "$ZIVPN_USER_DB" > /tmp/zdb.$$ && mv /tmp/zdb.$$ "$ZIVPN_USER_DB"

    # Extender reactiva la cuenta automáticamente (si estaba desactivada, vuelve a servir)
    jq --arg p "$ext_pass" '.auth.config |= ((. + [$p]) | unique)' "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    systemctl restart zivpn.service
    
    echo -e "\n${GREEN}✔ Usuario '$ext_pass' Extendido Exitosamente!${NC}\n New Expiry: ${YELLOW}$new_exp${NC}"
    pause_return
}

list_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}LISTA DE USUARIOS ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "\n No Hay Usuarios En Linea.\n"
    else
        printf " %-5s | %-25s | %-15s | %-10s\n" "ID" "PASSWORD" "EXPIRY DATE" "ESTADO"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        cat -n "$ZIVPN_USER_DB" | while read -r num user exp status; do
            status="${status:-active}"
            [ "$status" = "active" ] && st_color="${GREEN}" || st_color="${RED}"
            printf " [%-3s] | %-25s | %-15s | ${st_color}%-10s${NC}\n" "$num" "$user" "$exp" "$status"
        done
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        echo -e " Total Usuarios       : ${YELLOW}$(wc -l < "$ZIVPN_USER_DB")${NC}"
        echo -e " Total Activos        : ${GREEN}$(awk '{print ($3=="" || $3=="active")}' "$ZIVPN_USER_DB" | grep -c 1)${NC}"
    fi
    pause_return
}


# --- HYSTERIA MANAGEMENT FUNCTIONS ---
add_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR USUARIO HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Ingresa Contraseña/Cadena de Auth: " new_pass
    
    if grep -qw "^$new_pass" "$HYST_USER_DB" 2>/dev/null || jq -e ".inbounds[0].users[] | select(.auth_str == \"$new_pass\")" "$HYST_CONFIG" >/dev/null; then
        echo -e "\n${RED}Error: ¡El usuario/contraseña ya existe!${NC}"
        pause_return; return
    fi
    read -rp " Validez (Días): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Número inválido.${NC}"; pause_return; return; fi
    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    
    jq ".inbounds[0].users += [{\"auth_str\": \"$new_pass\"}]" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
    echo "$new_pass $exp_date" >> "$HYST_USER_DB"
    systemctl restart hysteria-server
    
    OBFS_VAL=$(jq -r '.inbounds[0].obfs' "$HYST_CONFIG" 2>/dev/null || echo "HexTunnel")
    
    echo -e "\n${GREEN}✔ ¡Usuario creado exitosamente!${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e " ${BOLD}IP:${NC}          ${YELLOW}$(server_ip)${NC}"
    echo -e " ${BOLD}Dominio:${NC}      ${YELLOW}${DOMAIN:-$(server_ip)}${NC}"
    echo -e " ${BOLD}Rango de Puertos:${NC}  ${YELLOW}20000-50000 (-> 36712)${NC}"
    echo -e " ${BOLD}Usuario (Contraseña):${NC} ${YELLOW}${new_pass}${NC}"
    echo -e " ${BOLD}Obfs:${NC}        ${YELLOW}${OBFS_VAL}${NC}"
    echo -e " ${BOLD}Fecha de Expiración:${NC} ${YELLOW}${exp_date}${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    pause_return
}

del_hysteria() {
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO HYSTERIA${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then echo -e "No se encontraron usuarios."; pause_return; return; fi
    cat -n "$HYST_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingresa el número de ID del usuario a eliminar: " del_id
    if ! [[ "$del_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi

    del_pass=$(sed -n "${del_id}p" "$HYST_USER_DB" | awk '{print $1}')
    if [ -z "$del_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi

    jq ".inbounds[0].users |= map(select(.auth_str != \"$del_pass\"))" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
    sed -i "${del_id}d" "$HYST_USER_DB"
    systemctl restart hysteria-server
    echo -e "\n${GREEN}✔ ¡Usuario '$del_pass' eliminado exitosamente!${NC}"
    pause_return
}

extend_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EXTENDER USUARIO HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then echo -e "No se encontraron usuarios."; pause_return; return; fi

    cat -n "$HYST_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingresa el número de ID del usuario a extender: " ext_id
    if ! [[ "$ext_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi
    
    ext_pass=$(sed -n "${ext_id}p" "$HYST_USER_DB" | awk '{print $1}')
    current_exp=$(sed -n "${ext_id}p" "$HYST_USER_DB" | awk '{print $2}')
    if [ -z "$ext_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi
    
    read -rp " Días a Agregar: " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Número inválido.${NC}"; pause_return; return; fi
    
    new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
    sed -i "${ext_id}s/.*/$ext_pass $new_exp/" "$HYST_USER_DB"
    
    echo -e "\n${GREEN}✔ ¡Usuario '$ext_pass' extendido exitosamente!${NC}\n Nueva Expiración: ${YELLOW}$new_exp${NC}"
    pause_return
}

list_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}LISTA DE USUARIOS HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then echo -e "\n No se encontraron usuarios activos.\n"
    else
        printf " %-5s | %-25s | %-15s\n" "ID" "PASSWORD (AUTH STRING)" "EXPIRY DATE"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        cat -n "$HYST_USER_DB" | while read -r num user exp; do
            printf " [%-3s] | %-25s | %-15s\n" "$num" "$user" "$exp"
        done
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        echo -e " Total de Usuarios Activos: ${YELLOW}$(wc -l < "$HYST_USER_DB")${NC}"
    fi
    pause_return
}

speed_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EDITAR VELOCIDADES SUBIDA/BAJADA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_up=$(jq -r '.inbounds[0].up_mbps' "$HYST_CONFIG" 2>/dev/null || echo "100")
    current_down=$(jq -r '.inbounds[0].down_mbps' "$HYST_CONFIG" 2>/dev/null || echo "100")
    echo -e " Subida Actual:    ${YELLOW}${current_up} Mbps${NC}"
    echo -e " Bajada Actual:    ${YELLOW}${current_down} Mbps${NC}\n"
    read -rp " Ingresa Nueva Velocidad de Subida (Mbps): " new_up
    read -rp " Ingresa Nueva Velocidad de Bajada (Mbps): " new_down
    if [[ "$new_up" =~ ^[0-9]+$ ]] && [[ "$new_down" =~ ^[0-9]+$ ]]; then
        jq ".inbounds[0].up_mbps = $new_up | .inbounds[0].down_mbps = $new_down" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
        systemctl restart hysteria-server
        echo -e "\n${GREEN}✔ ¡Velocidades actualizadas exitosamente!${NC}"
    else echo -e "\n${RED}Entrada inválida. Solo números.${NC}"; fi
    pause_return
}

change_obfs_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CAMBIAR OBFS DE HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_obfs=$(jq -r '.inbounds[0].obfs' "$HYST_CONFIG" 2>/dev/null || echo "HexTunnel")
    echo -e " Obfs Actual: ${YELLOW}${current_obfs}${NC}\n"
    read -rp " Ingresa Nuevo Obfs: " new_obfs
    if [ -n "$new_obfs" ]; then
        jq ".inbounds[0].obfs = \"$new_obfs\"" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
        systemctl restart hysteria-server
        echo -e "\n${GREEN}✔ ¡Obfs actualizado exitosamente a: $new_obfs!${NC}"
    else echo -e "\n${RED}Acción cancelada.${NC}"; fi
    pause_return
}

# --- HYSTERIA 2 MANAGEMENT FUNCTIONS ---
print_hysteria2_link() {
  local user="$1" token="$2" encoded_token encoded_obfs insecure
  encoded_token=$(jq -nr --arg v "$token" '$v|@uri')
  encoded_obfs=$(jq -nr --arg v "$(jq -r '.obfs.salamander.password' "$HYST2_CONFIG")" '$v|@uri')
  insecure="1"
  echo "hysteria2://${encoded_token}@${DOMAIN}:${HYST2_PORT}?insecure=${insecure}&sni=${DOMAIN}&obfs=salamander&obfs-password=${encoded_obfs}#${user}-HY2"
}

add_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR CUENTA HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Usuario: " user
    [[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || { echo -e "\n${RED}Usuario inválido.${NC}"; pause_return; return; }
    if awk -v u="$user" '$1 == u {found=1} END {exit !found}' "$HYST2_USER_DB" 2>/dev/null; then
        echo -e "\n${RED}El usuario ya existe.${NC}"; pause_return; return
    fi
    read -rp " Validez (Días): " days
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { echo -e "\n${RED}Validez inválida.${NC}"; pause_return; return; }

    read -rp " ¿Usar un token/UUID personalizado (ej. el mismo que ya usas en V2Ray)? (y/N): " custom_token_prompt
    if [[ "$custom_token_prompt" =~ ^[Yy]$ ]]; then
        read -rp " Ingresa el token/UUID personalizado: " token
        if [[ -z "$token" ]] || [[ "$token" =~ [[:space:]] ]]; then
            echo -e "\n${RED}Token inválido: no puede estar vacío ni contener espacios.${NC}"; pause_return; return
        fi
        if awk -v t="$token" '$2 == t {found=1} END {exit !found}' "$HYST2_USER_DB" 2>/dev/null; then
            echo -e "\n${RED}Ese token ya está en uso por otro usuario de Hysteria 2.${NC}"; pause_return; return
        fi
    else
        token=$(cat /proc/sys/kernel/random/uuid)
    fi

    exp=$(date -d "+${days} days" +%Y-%m-%d)
    printf '%s %s %s\n' "$user" "$token" "$exp" >> "$HYST2_USER_DB"
    chmod 600 "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Cuenta Hysteria 2 creada.${NC}\nUsuario: $user\nToken: $token\nExpira: $exp\n"
    print_hysteria2_link "$user" "$token"
    pause_return
}

del_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario a eliminar: " id
    [[ "$id" =~ ^[0-9]+$ ]] || { echo -e "\n${RED}ID inválido.${NC}"; pause_return; return; }
    user=$(sed -n "${id}p" "$HYST2_USER_DB" | awk '{print $1}')
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    sed -i "${id}d" "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Usuario Hysteria 2 '$user' eliminado.${NC}"
    pause_return
}

extend_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EXTENDER USUARIO HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario a renovar: " id
    [[ "$id" =~ ^[0-9]+$ ]] || { echo -e "\n${RED}ID inválido.${NC}"; pause_return; return; }
    line=$(sed -n "${id}p" "$HYST2_USER_DB")
    user=$(awk '{print $1}' <<< "$line"); token=$(awk '{print $2}' <<< "$line"); old_exp=$(awk '{print $3}' <<< "$line")
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    read -rp " Días a agregar: " days
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { echo -e "\n${RED}Validez inválida.${NC}"; pause_return; return; }
    base="$old_exp"; [ "$old_exp" \< "$(date +%Y-%m-%d)" ] && base="$(date +%Y-%m-%d)"
    new_exp=$(date -d "$base +${days} days" +%Y-%m-%d)
    sed -i "${id}s/.*/$user $token $new_exp/" "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Usuario Hysteria 2 renovado hasta $new_exp.${NC}"
    pause_return
}

list_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}LISTA DE USUARIOS HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ -s "$HYST2_USER_DB" ]; then nl -w2 -s'. ' "$HYST2_USER_DB"; else echo "No se encontraron usuarios."; fi
    pause_return
}

show_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ENLACE HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario: " id
    line=$(sed -n "${id}p" "$HYST2_USER_DB")
    user=$(awk '{print $1}' <<< "$line"); token=$(awk '{print $2}' <<< "$line")
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    echo
    print_hysteria2_link "$user" "$token"
    pause_return
}

# --- XRAY MANAGEMENT FUNCTIONS ---
add_xray() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}CREAR CUENTA XRAY${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e " [1] VLESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
  echo -e " [2] VMESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
  echo -e " [3] TROJAN (TLS)"
  echo -e " [4] TODO-EN-UNO (VLESS + VMESS + TROJAN)"
  read -rp " Selecciona Protocolo: " prot
  read -rp " Nombre de usuario: " user
  
  if grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then
    echo -e "${RED}¡El nombre de usuario ya existe!${NC}"; pause_return; return
  fi

  read -rp " Validez (Días): " masa
  exp=$(date -d "+${masa} days" +"%Y-%m-%d")

  read -rp " ¿Quieres usar un UUID personalizado? (y/N): " custom_uuid_prompt
  if [[ "$custom_uuid_prompt" =~ ^[Yy]$ ]]; then
    read -rp " Ingresa el UUID personalizado: " uuid
  else
    uuid=$(cat /proc/sys/kernel/random/uuid)
  fi

  pass="HexTunnel${uuid:0:6}"
  
  VLESS_TAGS='["vless-tls-dispatcher","vless-tcp-http","vless-plain-public","vless-ws","vless-xhttp","vless-httpupgrade","vless-grpc","vless-grpc-ntls","vless-kcp-ntls"]'
  VMESS_TAGS='["vmess-tcp-http","vmess-ws","vmess-xhttp","vmess-httpupgrade","vmess-grpc","vmess-grpc-ntls","vmess-kcp-ntls"]'
  TROJAN_TAGS='["trojan-ws"]'

  if [ "$prot" == "1" ]; then
    jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VLESS_TAGS" \
      '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $uuid $exp" >> /etc/xray/vless.txt
    
    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CUENTA VLESS CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario  : $user\nExpira   : $exp"
  echo -e "\n${YELLOW}[ VLESS TLS / SHARED PORT 443 ]${NC}\n"
  echo -e "TCP HTTP: vless://${uuid}@${DOMAIN}:443?type=tcp&headerType=http&security=tls&encryption=none&host=${DOMAIN}&path=%2Fvless-tcp&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-TCP\n"
  echo -e "WS: vless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-WS\n"
  echo -e "XHTTP: vless://${uuid}@${DOMAIN}:443?type=xhttp&security=tls&encryption=none&path=%2Fxhttp&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}&mode=auto&alpn=h2%2Chttp%2F1.1#${user}-VLESS-XHTTP\n"
  echo -e "HTTPUp: vless://${uuid}@${DOMAIN}:443?type=httpupgrade&security=tls&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-HTTPUp\n"
  echo -e "gRPC: vless://${uuid}@${DOMAIN}:443?type=grpc&security=tls&encryption=none&serviceName=grpc-svc&sni=${DOMAIN}${INSECURE_PARAM}&alpn=h2#${user}-VLESS-gRPC\n"

  echo -e "${YELLOW}[ VLESS NTLS (80/8080/8880/8081) ]${NC}\n"
  echo -e "TCP: vless://${uuid}@${DOMAIN}:80?type=tcp&headerType=http&security=none&encryption=none&path=%2Fvless-tcp&host=${DOMAIN}#${user}-VLESS-NTLS-TCP\n"
  echo -e "WS: vless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}-VLESS-NTLS-WS\n"
  echo -e "XHTTP: vless://${uuid}@${DOMAIN}:80?type=xhttp&security=none&encryption=none&path=%2Fxhttp&host=${DOMAIN}&mode=auto#${user}-VLESS-NTLS-XHTTP\n"
  echo -e "HUP: vless://${uuid}@${DOMAIN}:80?type=httpupgrade&security=none&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}#${user}-VLESS-NTLS-HTTPUp\n"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  
  elif [ "$prot" == "2" ]; then
    jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VMESS_TAGS" \
      '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $uuid $exp" >> /etc/xray/vmess.txt
    
    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CUENTA VMESS CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario: $user\nExpira: $exp"
      echo -e "\n${YELLOW}[ VMESS TLS / PORT 443 ]${NC}"
VMESS_TCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "TCP: vmess://$(echo -n "$VMESS_TCP_JSON" | base64 -w 0)"
VMESS_WS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "WS: vmess://$(echo -n "$VMESS_WS_JSON" | base64 -w 0)"
VMESS_XHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "XHTTP: vmess://$(echo -n "$VMESS_XHTTP_JSON" | base64 -w 0)"
VMESS_HUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "HTTPUp: vmess://$(echo -n "$VMESS_HUP_JSON" | base64 -w 0)"
VMESS_GRPC_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-gRPC\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"serviceName\":\"vmess-grpc-svc\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "gRPC: vmess://$(echo -n "$VMESS_GRPC_JSON" | base64 -w 0)"
echo -e "\n${YELLOW}[ VMESS NTLS / PORT 80/8080/8880/8081 ]${NC}"
VMESS_NTCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"\"}"
echo -e "TCP: vmess://$(echo -n "$VMESS_NTCP_JSON" | base64 -w 0)"
VMESS_NWS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
echo -e "WS: vmess://$(echo -n "$VMESS_NWS_JSON" | base64 -w 0)"
VMESS_NXHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"\"}"
echo -e "XHTTP: vmess://$(echo -n "$VMESS_NXHTTP_JSON" | base64 -w 0)"
VMESS_NHUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"\"}"
echo -e "HTTPUp: vmess://$(echo -n "$VMESS_NHUP_JSON" | base64 -w 0)"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  
  elif [ "$prot" == "3" ]; then
    jq --arg pass "$pass" --arg user "$user" --argjson tags "$TROJAN_TAGS" \
      '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $pass $exp" >> /etc/xray/trojan.txt
    
    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CUENTA TROJAN CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario: $user\nContraseña: $pass\nExpira: $exp"
    echo -e "\n${YELLOW}TLS (443):${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

  elif [ "$prot" == "4" ]; then
    jq --arg uuid "$uuid" --arg pass "$pass" --arg user "$user" \
      --argjson vtags "$VLESS_TAGS" --argjson mtags "$VMESS_TAGS" --argjson ttags "$TROJAN_TAGS" \
      '(.inbounds[] | select(.tag as $t | $vtags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}]
       | (.inbounds[] | select(.tag as $t | $mtags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}]
       | (.inbounds[] | select(.tag as $t | $ttags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    
    echo "$user $uuid $exp" >> /etc/xray/vless.txt
    echo "$user $uuid $exp" >> /etc/xray/vmess.txt
    echo "$user $pass $exp" >> /etc/xray/trojan.txt

    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "               ${BOLD}CUENTA TODO-EN-UNO CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario: $user\nExpira:   $exp"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
   echo -e "\n${YELLOW}[ VLESS TLS / SHARED PORT 443 ]${NC}\n"
  echo -e "TCP HTTP: vless://${uuid}@${DOMAIN}:443?type=tcp&headerType=http&security=tls&encryption=none&host=${DOMAIN}&path=%2Fvless-tcp&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-TCP\n"
  echo -e "WS: vless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-WS\n"
  echo -e "XHTTP: vless://${uuid}@${DOMAIN}:443?type=xhttp&security=tls&encryption=none&path=%2Fxhttp&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}&mode=auto&alpn=h2%2Chttp%2F1.1#${user}-VLESS-XHTTP\n"
  echo -e "HTTPUp: vless://${uuid}@${DOMAIN}:443?type=httpupgrade&security=tls&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-HTTPUp\n"
  echo -e "gRPC: vless://${uuid}@${DOMAIN}:443?type=grpc&security=tls&encryption=none&serviceName=grpc-svc&sni=${DOMAIN}${INSECURE_PARAM}&alpn=h2#${user}-VLESS-gRPC\n"
  echo -e "${YELLOW}[ VLESS NTLS (80/8080/8880/8081) ]${NC}\n"
  echo -e "TCP: vless://${uuid}@${DOMAIN}:80?type=tcp&headerType=http&security=none&encryption=none&path=%2Fvless-tcp&host=${DOMAIN}#${user}-VLESS-NTLS-TCP\n"
  echo -e "WS: vless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}-VLESS-NTLS-WS\n"
  echo -e "XHTTP: vless://${uuid}@${DOMAIN}:80?type=xhttp&security=none&encryption=none&path=%2Fxhttp&host=${DOMAIN}&mode=auto#${user}-VLESS-NTLS-XHTTP\n"
  echo -e "HUP: vless://${uuid}@${DOMAIN}:80?type=httpupgrade&security=none&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}#${user}-VLESS-NTLS-HTTPUp\n"
  echo -e "\n${YELLOW}[ VMESS TLS / PORT 443 ]${NC}"
VMESS_TCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "TCP: vmess://$(echo -n "$VMESS_TCP_JSON" | base64 -w 0)"
VMESS_WS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "WS: vmess://$(echo -n "$VMESS_WS_JSON" | base64 -w 0)"
VMESS_XHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "XHTTP: vmess://$(echo -n "$VMESS_XHTTP_JSON" | base64 -w 0)"
VMESS_HUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "HTTPUp: vmess://$(echo -n "$VMESS_HUP_JSON" | base64 -w 0)"
VMESS_GRPC_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-gRPC\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"serviceName\":\"vmess-grpc-svc\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "gRPC: vmess://$(echo -n "$VMESS_GRPC_JSON" | base64 -w 0)"
echo -e "\n${YELLOW}[ VMESS NTLS / PORT 80/8080/8880/8081 ]${NC}"
VMESS_NTCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"\"}"
echo -e "TCP: vmess://$(echo -n "$VMESS_NTCP_JSON" | base64 -w 0)"
VMESS_NWS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
echo -e "WS: vmess://$(echo -n "$VMESS_NWS_JSON" | base64 -w 0)"
VMESS_NXHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"\"}"
echo -e "XHTTP: vmess://$(echo -n "$VMESS_NXHTTP_JSON" | base64 -w 0)"
VMESS_NHUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"\"}"
echo -e "HTTPUp: vmess://$(echo -n "$VMESS_NHUP_JSON" | base64 -w 0)"
    echo -e "\n${YELLOW}[ TROJAN TLS (443) ]${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  fi
  systemctl restart xray
  pause_return
}

del_xray() {
  clear
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}ELIMINAR CUENTA XRAY${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  
  mapfile -t users < <(cat /etc/xray/*.txt 2>/dev/null | awk '{print $1}' | sort -u)
  
  if [ ${#users[@]} -eq 0 ]; then 
      echo -e "${YELLOW}No se encontraron usuarios de Xray.${NC}"; pause_return; return
  fi
  for i in "${!users[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${users[$i]}"; done
  echo -e "\n  [${YELLOW}00${NC}] Cancelar\n"

  read -rp "  Selecciona usuario a eliminar: " idx
  if [[ "$idx" == "00" || "$idx" == "0" ]]; then return; fi
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -le 0 ] || [ "$idx" -gt "${#users[@]}" ]; then 
      echo -e "${RED}Selección inválida.${NC}"; pause_return; return 
  fi

  user="${users[$((idx-1))]}"
  jq "(.inbounds[].settings.clients) |= map(select(.email != \"$user\"))" /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
  sed -i "/^$user /d" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null
  systemctl restart xray
  echo -e "\n${GREEN}✔ Usuario $user eliminado exitosamente.${NC}"
  pause_return
}

renew_xray() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}RENOVAR CUENTA XRAY${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  read -rp " Usuario a renovar: " user
  
  if ! grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then 
    echo -e "${RED}Usuario no encontrado.${NC}"; pause_return; return
  fi
  read -rp " Días a Agregar: " days
  for proto in vless vmess trojan; do 
    if grep -qw "^$user" "/etc/xray/${proto}.txt"; then
      current_exp=$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $3}')
      new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
      sed -i "s/^$user .* $current_exp/$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $1 " " $2}') $new_exp/" "/etc/xray/${proto}.txt"
    fi
  done
  echo -e "\n${GREEN}✔ Usuario '$user' renovado exitosamente.${NC}\nNueva Expiración: $new_exp"
  pause_return
}

show_xray() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}MOSTRAR ENLACES DE CONFIG XRAY${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  read -rp " Usuario a ver: " user
  local found=0
  if grep -qw "^$user" /etc/xray/vless.txt; then
    uuid=$(grep -w "^$user" /etc/xray/vless.txt | awk '{print $2}')
    echo -e "${YELLOW}VLESS TLS (443):${NC}\nvless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
    echo -e "\n${YELLOW}VLESS NTLS (80):${NC}\nvless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}\n"
    echo -e "${YELLOW}VLESS NTLS XHTTP (80/8080/8880/8081):${NC}\nvless://${uuid}@${DOMAIN}:8081?type=xhttp&security=none&encryption=none&path=%2Fxhttp&host=${DOMAIN}&mode=auto#${user}-XHTTP\n"
    found=1
  fi
  if grep -qw "^$user" /etc/xray/vmess.txt; then
    uuid=$(grep -w "^$user" /etc/xray/vmess.txt | awk '{print $2}')
    VMESS_TLS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
    echo -e "${YELLOW}VMESS TLS (443):${NC}\nvmess://$(echo -n "$VMESS_TLS_JSON" | base64 -w 0)"
    VMESS_NTLS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
    echo -e "\n${YELLOW}VMESS NTLS (80):${NC}\nvmess://$(echo -n "$VMESS_NTLS_JSON" | base64 -w 0)\n"
    VMESS_NTLS_XHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"8081\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"\"}"
    echo -e "\n${YELLOW}VMESS NTLS XHTTP (80/8080/8880/8081):${NC}\nvmess://$(echo -n "$VMESS_NTLS_XHTTP_JSON" | base64 -w 0)\n"
    found=1
  fi
  if grep -qw "^$user" /etc/xray/trojan.txt; then
    pass=$(grep -w "^$user" /etc/xray/trojan.txt | awk '{print $2}')
    echo -e "${YELLOW}TROJAN TLS (443):${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}\n"
    found=1
  fi
  if [ "$found" -eq 0 ]; then echo -e "${RED}Usuario no encontrado en ningún protocolo.${NC}"; fi
  pause_return
}

# --- SSH USER FUNCTIONS ---
list_real_users() { awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-network" && $1 != "messagebus" {print $1}' /etc/passwd 2>/dev/null; }

select_user() {
  local purpose="$1"
  mapfile -t USERS < <(list_real_users)
  if [ "${#USERS[@]}" -eq 0 ]; then echo -e "${RED}No se encontraron cuentas de usuario activas.${NC}"; return 1; fi
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  printf " %-56s \n" "${BOLD}$purpose${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  for i in "${!USERS[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${USERS[$i]}"; done
  echo -e "\n  [${YELLOW}00${NC}] Atrás\n"
  read -rp "  Selecciona un número de cuenta: " idx
  [[ "$idx" == "00" || "$idx" == "0" ]] && return 1
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#USERS[@]}" ]; then echo -e "${RED}  Selección inválida.${NC}"; return 1; fi
  SELECTED_USER="${USERS[$((idx-1))]}"
  return 0
}

create_user() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}CREAR NUEVO USUARIO SSH${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "  ${YELLOW}(Escribe 00 en cualquier campo para cancelar y volver)${NC}\n"

  while true; do
    read -rp "  Nombre de usuario: " user
    user="$(echo -n "$user" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$user" = "00" ] && return
    if [ -z "$user" ]; then echo -e "${RED}  Error: El usuario no puede estar vacío.${NC}\n"; continue; fi
    if ! [[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then echo -e "${RED}  Error: Nombre inválido (letras/números/guiones, sin espacios).${NC}\n"; continue; fi
    if id "$user" >/dev/null 2>&1; then echo -e "${RED}  Error: El usuario '$user' ya existe.${NC}\n"; continue; fi
    break
  done

  while true; do
    read -rp "  Contraseña: " pass
    pass="$(echo -n "$pass" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$pass" = "00" ] && return
    if [ -z "$pass" ]; then echo -e "${RED}  Error: La contraseña no puede estar vacía.${NC}\n"; continue; fi
    if [[ "$pass" =~ [[:space:]] ]]; then echo -e "${RED}  Error: La contraseña no puede contener espacios.${NC}\n"; continue; fi
    break
  done

  while true; do
    read -rp "  Válido por (días): " days
    days="$(echo -n "$days" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$days" = "00" ] && return
    if ! [[ "$days" =~ ^[0-9]+$ ]] || [ "$days" -eq 0 ]; then echo -e "${RED}  Error: Debe ser un número de días mayor a 0.${NC}\n"; continue; fi
    break
  done

  while true; do
    read -rp "  Límite de conexiones simultáneas (0 = sin límite): " conn_limit
    conn_limit="$(echo -n "$conn_limit" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$conn_limit" = "00" ] && return
    [ -z "$conn_limit" ] && conn_limit=0
    if ! [[ "$conn_limit" =~ ^[0-9]+$ ]]; then echo -e "${RED}  Error: Debe ser un número.${NC}\n"; continue; fi
    break
  done

  ua_err=$(useradd --badname -e "$(date -d "+$days days" +%Y-%m-%d)" -s /bin/false -M "$user" 2>&1 1>/dev/null)
  if [ $? -ne 0 ]; then
    echo -e "\n${RED}  Error: No se pudo crear el usuario '$user'.${NC}"
    echo -e "  ${YELLOW}Detalle:${NC} ${ua_err:-desconocido}"
    echo "$(date '+%F %T') create_user FALLÓ useradd user=$user :: ${ua_err:-desconocido}" >> /var/log/deekayvpn-menu-errors.log
    pause_return; return
  fi
  cp_err=$(echo "$user:$pass" | chpasswd 2>&1 1>/dev/null)
  if [ $? -ne 0 ]; then
    echo -e "\n${RED}  Error: No se pudo establecer la contraseña. Eliminando cuenta incompleta...${NC}"
    echo -e "  ${YELLOW}Detalle:${NC} ${cp_err:-desconocido}"
    echo "$(date '+%F %T') create_user FALLÓ chpasswd user=$user :: ${cp_err:-desconocido}" >> /var/log/deekayvpn-menu-errors.log
    userdel -f "$user" 2>/dev/null
    pause_return; return
  fi

  sed -i "/^$user /d" "$SSH_LIMIT_DB" 2>/dev/null
  if [ "$conn_limit" -gt 0 ]; then echo "$user $conn_limit" >> "$SSH_LIMIT_DB"; fi

  IP=$(curl -s ipv4.icanhazip.com)
  CURRENT_NS=$(grep 'ExecStart=' /etc/systemd/system/server-sldns.service 2>/dev/null | sed 's/.*server\.key \([^ ]*\) .*/\1/')

  clear
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}CUENTA CREADA EXITOSAMENTE${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "  ${BOLD}Dominio/Host${NC}: ${YELLOW}$DOMAIN${NC}"
  echo -e "  ${BOLD}Dirección IP${NC} : ${YELLOW}$IP${NC}"
  echo -e "  ${BOLD}Usuario${NC}   : ${YELLOW}$user${NC}"
  echo -e "  ${BOLD}Contraseña${NC}   : ${YELLOW}$pass${NC}"
  echo -e "  ${BOLD}Expiración${NC}     : ${YELLOW}$(date -d "+$days days" +%Y-%m-%d)${NC}"
  echo -e "  ${BOLD}Límite Conexiones${NC}: ${YELLOW}$([ "$conn_limit" -gt 0 ] && echo "$conn_limit" || echo "Sin límite")${NC}"
  echo -e "${CYAN}--------------------------------------------------------------${NC}"
  echo -e "  SSH Port   : 22, 299"
  echo -e "  SSL/TLS    : 443"
  echo -e "  SSL/WS     : 443"
  echo -e "  WebSocket  : 80, 8080, 8880, 2082, 2086, 25"
  echo -e "  SlowDNS    : 53"
  echo -e "  BadVPN     : 7300"
  echo -e "  UDP Custom : 1-65535"
  echo -e "${CYAN}--------------------------------------------------------------${NC}"
  echo -e "  ${BOLD}Payload HTTP     :${NC}"
  echo -e "  ${YELLOW}GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]${NC}"
  echo -e ""
  echo -e "  ${BOLD}Payload Mejorado :${NC}"
  echo -e "  ${YELLOW}GET / HTTP/1.1[crlf]Host: bug.com[crlf][crlf]PATCH / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]${NC}"
  echo -e "${CYAN}--------------------------------------------------------------${NC}"
  echo -e "  ${BOLD}SlowDNS NS ${NC}: ${YELLOW}${CURRENT_NS:-No configurado}${NC}"
  echo -e "  ${BOLD}DNS PUB KEY${NC}: 7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  pause_return
}

delete_user() {
  if ! select_user "DELETE SSH USER"; then pause_return; return; fi
  clear; echo -e "${RED}Advertencia: Estás a punto de eliminar al usuario: ${YELLOW}$SELECTED_USER${NC}"
  read -rp "¿Estás seguro? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    # Force kill all processes owned by the user to free up the account
    pkill -u "$SELECTED_USER" 2>/dev/null
    
    # Execute forced deletion
    if userdel -r -f "$SELECTED_USER" 2>/dev/null || userdel -f "$SELECTED_USER" 2>/dev/null; then
        sed -i "/^$SELECTED_USER /d" "$SSH_LIMIT_DB" 2>/dev/null
        echo -e "${GREEN}El usuario $SELECTED_USER ha sido eliminado.${NC}"
    else
        echo -e "${RED}Fallo al eliminar $SELECTED_USER. Revisa archivos bloqueados.${NC}"
    fi
  fi
  pause_return
}

extend_user() {
  if ! select_user "EXTEND USER EXPIRY"; then pause_return; return; fi
  clear; echo -e "Extendiendo cuenta de: ${YELLOW}$SELECTED_USER${NC}"
  read -rp "Ingresa número de días a agregar: " days
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Formato de número inválido.${NC}"; pause_return; return; fi
  current=$(chage -l "$SELECTED_USER" 2>/dev/null | awk -F": " '/Account expires/ {print $2}')
  if [ "$current" = "never" ] || [ -z "$current" ]; then new_exp=$(date -d "+$days days" +%Y-%m-%d)
  else new_exp=$(date -d "$current +$days days" +%Y-%m-%d); fi
  chage -E "$new_exp" "$SELECTED_USER"
  echo -e "${GREEN}¡Éxito!${NC} Cuenta extendida.\nNueva Fecha de Expiración: ${YELLOW}$new_exp${NC}"
  pause_return
}

# --- Monitor ---
online_users() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "               ${BOLD}MONITOR DE SESIONES ACTIVAS${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  echo -e "${YELLOW}--- SSH LEGADO ---${NC}"
  declare -A active_ssh
  mapfile -t USERS < <(awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-network" && $1 != "messagebus" {print $1}' /etc/passwd 2>/dev/null)
  
  for user in "${USERS[@]}"; do
      ssh_count=$(ps -u "$user" 2>/dev/null | grep -c "sshd")
      total=$ssh_count
      if [ "$total" -gt 0 ]; then active_ssh["$user"]=$total; fi
  done

  if [ "${#active_ssh[@]}" -eq 0 ]; then 
      echo -e "  No hay usuarios de SSH legado autenticados en línea actualmente.\n"
  else
    printf "  %-25s %-15s\n" "USERNAME" "ACTIVE SESSIONS"
    echo -e "${CYAN}  ----------------------------------------------------------${NC}"
    for user in "${!active_ssh[@]}"; do 
        if [ "${active_ssh[$user]}" -gt 1 ]; then
            printf "  %-25s ${RED}%-15s (Multi-Login)${NC}\n" "$user" "${active_ssh[$user]}"
        else
            printf "  %-25s ${GREEN}%-15s${NC}\n" "$user" "${active_ssh[$user]}"
        fi
    done | sort
    echo
  fi

  echo -e "${YELLOW}--- INICIOS DE SESIÓN ACTIVOS XRAY CORE (IPs Únicas Recientes) ---${NC}"
  if grep -q '"loglevel": "warning"' /etc/xray/config.json 2>/dev/null; then
      sed -i 's/"loglevel": "warning"/"loglevel": "info"/g' /etc/xray/config.json
      systemctl restart xray 2>/dev/null
      echo -e "  [Nota del Sistema] Registro de Xray habilitado. Reconecta a los usuarios para ver los logs.\n"
  elif [ -f /var/log/xray/access.log ]; then
      active_xray=$(tail -n 10000 /var/log/xray/access.log 2>/dev/null | grep "accepted" | awk '{ user=""; for(i=1;i<=NF;i++) if($i=="email:") user=$(i+1); if(user!="") { split($3, a, ":"); print user " " a[1] } }' | sort -u | awk '{print $1}' | uniq -c | sort -nr)
      if [ -z "$active_xray" ]; then 
          echo -e "  No se encontraron usuarios activos de Xray en los logs recientes.\n"
      else
          printf "  %-15s %-25s\n" "UNIQUE IPs" "USERNAME"
          echo -e "${CYAN}  ----------------------------------------------------------${NC}"
          while read -r count username; do 
              if [ -n "$username" ]; then 
                  if [ "$count" -gt 1 ]; then
                      printf "  ${RED}%-15s${NC} %-25s ${RED}(Multi-IP)${NC}\n" "$count" "$username"
                  else
                      printf "  %-15s %-25s\n" "$count" "$username"
                  fi
              fi
          done <<< "$active_xray"
      fi
  else echo -e "  Log de acceso de Xray no encontrado.\n"; fi
  
  pause_return
}

# --- Service Controls ---
restart_service() {
  local service_name="$1"
  local display_name="$2"
  echo -e "Reiniciando ${display_name}..."
  systemctl restart $service_name 2>/dev/null || true
  echo -e "${GREEN}✔ ${display_name} reiniciado.${NC}"
}

service_control_menu() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CONTROL DE SERVICIOS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  [${YELLOW}01${NC}] Reiniciar Todos Los Servicios"
    echo -e "  [${YELLOW}02${NC}] Reiniciar SSH"
    echo -e "  [${YELLOW}03${NC}] Reiniciar Proxies WebSocket de Node"
    echo -e "  [${YELLOW}04${NC}] Reiniciar Stunnel y Xray Core"
    echo -e "  [${YELLOW}05${NC}] Reiniciar Squid Proxy y Nginx"
    echo -e "  [${YELLOW}06${NC}] Reiniciar Núcleo UDP (SlowDNS / Hysteria / BadVPN)"
    echo -e "  [${YELLOW}00${NC}] Atrás\n"
    read -rp "  Selecciona una opción: " opt
    case "$opt" in
      1|01) restart_service "ssh stunnel4 sslh squid nginx server-sldns hysteria-server hysteria2-server badvpn ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086 xray" "All Services"; pause_return ;;
      2|02) restart_service "ssh" "SSH"; pause_return ;;
      3|03) restart_service "ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086" "Node WebSocket Proxies"; pause_return ;;
      4|04) restart_service "stunnel4 xray" "Stunnel & Xray Core"; pause_return ;;
      5|05) restart_service "squid nginx" "Squid Proxy & Nginx"; pause_return ;;
      6|06) restart_service "server-sldns hysteria-server hysteria2-server badvpn" "UDP Core Services"; pause_return ;;
      0|00) break ;;
      *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
    esac
  done
}

# --- Backup & Restore ---
backup_snapshot() {
  clear; local out="/root/hextunnel_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
  echo -e "Empaquetando configuraciones del servidor..."
  tar -czf "$out" /etc/ssh /etc/stunnel /etc/squid /etc/hysteria /etc/hysteria2 /etc/deekayvpn /etc/systemd/system/ws-proxy@.service /etc/xray 2>/dev/null
  echo -e "\n${GREEN}✔ ¡Respaldo creado exitosamente!${NC}\nUbicación: ${YELLOW}$out${NC}"
  pause_return
}

restore_snapshot() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}RESTAURAR CONFIGURACIÓN${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  shopt -s nullglob
  backups=(/root/hextunnel_backup_*.tar.gz)
  if [ ${#backups[@]} -eq 0 ]; then echo -e "${RED}  No se encontraron archivos de respaldo en /root/.${NC}"; pause_return; return; fi
  echo -e "  Respaldos Disponibles:\n"
  for i in "${!backups[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "$(basename "${backups[$i]}")"; done
  echo -e "\n  [${YELLOW}00${NC}] Cancelar\n"
  read -rp "  Selecciona respaldo a restaurar: " sel
  if [[ "$sel" == "00" || "$sel" == "0" ]]; then return; fi
  idx=$((sel-1))
  if [ -n "${backups[$idx]}" ]; then
    echo -e "\nRestaurando ${YELLOW}$(basename "${backups[$idx]}")${NC}..."
    tar -xzf "${backups[$idx]}" -C /
    systemctl daemon-reload; systemctl restart ssh stunnel4 sslh squid nginx server-sldns hysteria-server badvpn ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086 xray 2>/dev/null || true
    echo -e "${GREEN}✔ ¡Restauración completa!${NC}"
  else echo -e "${RED}Selección inválida.${NC}"; fi
  pause_return
}

# --- System Utilities ---
utilities_menu() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}UTILIDADES DEL SISTEMA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  [${YELLOW}1${NC}] Activar BBR Nativo del Kernel (Rápido y Silencioso)"
    echo -e "  [${YELLOW}2${NC}] Verificar Desbloqueos de Netflix y Streaming (Inglés)"
    echo -e "  [${YELLOW}0${NC}] Atrás\n"
    read -rp "  Selecciona una opción: " subopt
    case "$subopt" in 
      1) 
         echo -e "\nActivando BBR Nativo del Kernel..."
         sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
         sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
         echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
         echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
         sysctl -p >/dev/null 2>&1
         if [[ "$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null)" == *"bbr"* ]]; then echo -e "${GREEN}✔ ¡BBR Activado Exitosamente!${NC}"
         else echo -e "${RED}✖ Fallo al activar BBR (puede que el kernel no lo soporte).${NC}"; fi
         pause_return
         ;; 
      2) 
         clear
         echo -e "${YELLOW}Ejecutando Verificación de Restricción Regional (Inglés)...${NC}\n"
         bash <(curl -sL https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh) -E en
         echo ""
         pause_return 
         ;;
      0) break ;;
      *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
    esac
  done
}

# --- Domain & DNS Management ---
change_domain() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CAMBIAR DOMINIO DEL SERVIDOR${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_dom=$(cat /etc/deekayvpn/domain.txt 2>/dev/null || echo "No configurado")
    current_cert=$(cat /etc/xray/cert_type 2>/dev/null || echo "desconocido")
    echo -e " Dominio/IP Actual: ${YELLOW}$current_dom${NC}  (certificado: ${YELLOW}$current_cert${NC})\n"
    read -rp " Ingresa Nuevo Dominio o IP: " new_dom

    if [ -z "$new_dom" ]; then echo -e "\n${RED}Acción cancelada.${NC}"; pause_return; return; fi
    if [ "$new_dom" = "$current_dom" ]; then echo -e "\n${RED}Es el mismo dominio/IP, sin cambios.${NC}"; pause_return; return; fi

    SERVER_IP=$(curl -4 -s --max-time 2 ipv4.icanhazip.com || hostname -I | awk '{print $1}')

    if [[ "$new_dom" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "\n${YELLOW}Generando certificado autofirmado para la IP $new_dom...${NC}"
        systemctl stop xray 2>/dev/null || true
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
          -keyout /etc/xray/xray.key \
          -out /etc/xray/xray.crt \
          -subj "/CN=${new_dom}/O=HexTunnel/C=US" > /dev/null 2>&1
        echo "selfsigned" > /etc/xray/cert_type
        rm -f /etc/cron.d/certbot-renew
        NEW_CERT_TYPE="selfsigned"
    else
        echo -e "\n${YELLOW}Verificando que $new_dom resuelva a $SERVER_IP...${NC}"
        command -v dig >/dev/null 2>&1 || apt-get install -y dnsutils >/dev/null 2>&1
        DOMAIN_IP=$(dig +short "$new_dom" @8.8.8.8 | tail -1)
        if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
            echo -e "\n${RED}✘ ERROR: $new_dom no apunta a $SERVER_IP todavía.${NC}"
            echo -e "  Crea/corrige el registro A en tu DNS y vuelve a intentar. No se cambió nada."
            pause_return; return
        fi
        echo -e "${GREEN}Dominio verificado. Solicitando certificado Let's Encrypt...${NC}"
        command -v certbot >/dev/null 2>&1 || apt-get install -y certbot >/dev/null 2>&1
        systemctl stop xray 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        if ! certbot certonly --standalone --non-interactive --agree-tos --email "admin@${new_dom}" -d "${new_dom}" > /dev/null 2>&1; then
            echo -e "\n${RED}✘ Falló la emisión del certificado Let's Encrypt. No se cambió el dominio.${NC}"
            systemctl start xray 2>/dev/null || true
            pause_return; return
        fi
        cp "/etc/letsencrypt/live/${new_dom}/fullchain.pem" /etc/xray/xray.crt > /dev/null 2>&1
        cp "/etc/letsencrypt/live/${new_dom}/privkey.pem" /etc/xray/xray.key > /dev/null 2>&1
        echo "letsencrypt" > /etc/xray/cert_type
        NEW_CERT_TYPE="letsencrypt"

        mkdir -p /etc/letsencrypt/renewal-hooks/deploy > /dev/null 2>&1
        cat <<'EOF_RENEW' > /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh
#!/bin/bash
set -e
for domain in $RENEWED_DOMAINS; do
    cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/xray/xray.crt
    cp /etc/letsencrypt/live/$domain/privkey.pem /etc/xray/xray.key
    cat /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/live/$domain/fullchain.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem /etc/xray/xray.key
    chmod 644 /etc/xray/xray.crt
    systemctl restart xray stunnel4
    break
done
EOF_RENEW
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh > /dev/null 2>&1
        echo "0 3 * * * root certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh" > /etc/cron.d/certbot-renew
    fi

    chmod 644 /etc/xray/xray.crt > /dev/null 2>&1
    chmod 600 /etc/xray/xray.key > /dev/null 2>&1
    cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem 2>/dev/null
    chmod 600 /etc/stunnel/stunnel.pem > /dev/null 2>&1
    chown root:root /etc/stunnel/stunnel.pem > /dev/null 2>&1

    echo "$new_dom" > /etc/deekayvpn/domain.txt
    DOMAIN="$new_dom"

    systemctl start xray 2>/dev/null || true
    if ! /usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1; then
        echo -e "\n${RED}✘ Advertencia: el nuevo certificado no pasó la validación de Xray.${NC}"
    fi
    systemctl restart xray stunnel4 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true

    echo -e "\n${GREEN}✔ Dominio actualizado a: $new_dom${NC}"
    echo -e "${GREEN}✔ Certificado regenerado (${NEW_CERT_TYPE}) y Xray/Stunnel reiniciados.${NC}"
    echo -e "${YELLOW}Nota: los enlaces vless/vmess/trojan que ya diste a usuarios usaban el dominio/cert${NC}"
    echo -e "${YELLOW}anterior. Genera enlaces nuevos desde el menú de Xray (opción 4, Mostrar Enlaces).${NC}"
    pause_return
}

change_slowdns() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "               ${BOLD}CAMBIAR NAMESERVER DE SLOWDNS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    svc_file="/etc/systemd/system/server-sldns.service"
    if [ ! -f "$svc_file" ]; then echo -e "${RED}Archivo de servicio SlowDNS no encontrado.${NC}"; pause_return; return; fi
    current_ns=$(grep 'ExecStart=' "$svc_file" | sed 's/.*server\.key \([^ ]*\) .*/\1/')
    echo -e " Nameserver Actual: ${YELLOW}$current_ns${NC}\n"
    read -rp " Ingresa Nuevo Nameserver (ej. ns1.dominio.com): " new_ns
    if [ -n "$new_ns" ] && [ "$new_ns" != "$current_ns" ]; then
        sed -i "s/$current_ns/$new_ns/g" "$svc_file" > /dev/null 2>&1
        systemctl daemon-reload; systemctl restart server-sldns > /dev/null 2>&1
        echo -e "\n${GREEN}✔ Nameserver de SlowDNS actualizado a: $new_ns${NC}"
    else echo -e "\n${RED}Acción cancelada o se ingresó el mismo NS.${NC}"; fi
    pause_return
}

change_status() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "             ${BOLD}CAMBIAR MENSAJE DE STATUS (WS)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    proxy_file="/etc/socksproxy/proxy.js"
    if [ ! -f "$proxy_file" ]; then echo -e "${RED}Archivo proxy.js no encontrado.${NC}"; pause_return; return; fi
    line_num=$(grep -n "clientSocket.write('HTTP/1.1 101" "$proxy_file" | head -n1 | cut -d: -f1)
    if [ -z "$line_num" ]; then echo -e "${RED}No se encontró la línea de status en proxy.js.${NC}"; pause_return; return; fi
    current_status=$(sed -n "${line_num}p" "$proxy_file" | sed 's/^[[:space:]]*//')
    echo -e " Línea Actual:\n ${YELLOW}${current_status}${NC}\n"
    echo -e " Escribe el mensaje completo, libre: texto plano o HTML"
    echo -e " (ej: <font color=\"red\">Mi Texto</font> <b>Extra</b>)."
    echo -e " Nota: no uses comillas simples (') dentro del mensaje.\n"
    read -rp " Nuevo Mensaje de Status: " new_status
    if [ -n "$new_status" ]; then
        esc_msg=$(printf '%s' "$new_status" | sed "s/'/’/g")
        awk -v ln="$line_num" -v msg="$esc_msg" 'NR==ln{printf "            clientSocket.write(%cHTTP/1.1 101 %s\\r\\n\\r\\n%c);\n", 39, msg, 39; next} {print}' "$proxy_file" > "${proxy_file}.tmp" && mv "${proxy_file}.tmp" "$proxy_file"
        for u in $(systemctl list-units --all --type=service --no-legend 'ws-proxy@*' 2>/dev/null | awk '{print $1}'); do systemctl restart "$u"; done
        echo -e "\n${GREEN}✔ Mensaje de status actualizado.${NC}"
    else echo -e "\n${RED}Acción cancelada.${NC}"; fi
    pause_return
}

change_banner() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EDITAR BANNER (SSH / STUNNEL)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e " Se abrirá el banner en nano para que lo edites a tu gusto."
    echo -e " Guarda con ${YELLOW}CTRL+O${NC} + ENTER y sal con ${YELLOW}CTRL+X${NC}.\n"
    read -rp " Presiona ENTER para continuar o escribe 0 para cancelar: " conf
    if [ "$conf" = "0" ]; then echo -e "\n${RED}Acción cancelada.${NC}"; pause_return; return; fi
    nano /etc/zorro-luffy
    systemctl restart ssh stunnel4 2>/dev/null
    echo -e "\n${GREEN}✔ Banner actualizado y servicios reiniciados.${NC}"
    pause_return
}

# --- Advanced / Danger Zone ---
advanced_menu() {
  while true; do
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                     ${BOLD}CONFIGURACIÓN AVANZADA${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  [${YELLOW}01${NC}] Ver JSON Crudo de Hysteria"
    echo -e "  [${YELLOW}02${NC}] Ver Logs de Acciones de Servicios (Journalctl)"
    echo -e "  [${YELLOW}03${NC}] Cambiar Dominio/IP del Servidor"
    echo -e "  [${YELLOW}04${NC}] Cambiar Nameserver de SlowDNS (NS)"
    echo -e "  [${RED}05${NC}] Desinstalar Script Completo (Peligro)"
    echo -e "  [${YELLOW}06${NC}] Cambiar Mensaje de Status (WS, HTML/Texto Libre)"
    echo -e "  [${YELLOW}07${NC}] Editar Banner (SSH / Stunnel)"
    echo -e "  [${YELLOW}08${NC}] Reiniciar UDP Core (SlowDNS/Hysteria/ZiVPN/UDP-Custom)"
    echo -e "  [${YELLOW}00${NC}] Atrás\n"
    read -rp "  Selecciona una opción: " opt
    case "$opt" in
      1|01) clear; cat /etc/hysteria/config.json 2>/dev/null || echo "No encontrado."; pause_return ;;
    2|02) 
        clear; echo -e "[1] SSH  [2] WS-Proxies  [3] Hysteria  [4] Stunnel  [5] SlowDNS  [6] Xray  [7] Hysteria 2\n"
        read -rp "Selecciona log: " lopt
        case "$lopt" in
          1) journalctl -u ssh -n 50 --no-pager ;;
          2) journalctl -u ws-proxy@10080 -n 50 --no-pager ;;
          3) journalctl -u hysteria-server -n 50 --no-pager ;;
          4) journalctl -u stunnel4 -n 50 --no-pager ;;
          5) journalctl -u server-sldns -n 50 --no-pager ;;
          6) journalctl -u xray -n 50 --no-pager ;;
          7) journalctl -u hysteria2-server -n 50 --no-pager ;;
        esac; pause_return ;;
      3|03) change_domain ;;
      4|04) change_slowdns ;;
      6|06) change_status ;;
      7|07) change_banner ;;
      8|08) restart_service "server-sldns hysteria-server hysteria2-server badvpn udp-custom zivpn" "UDP Core Services"; pause_return ;;
      5|05) remove_script ;;
      0|00) break ;;
    esac
  done
}

remove_script() {
  clear
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                     ${BOLD}DESINSTALACIÓN COMPLETA${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  read -rp "  ¿Estás completamente seguro? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
      echo -e "\nDeteniendo servicios..."
      systemctl stop ws-proxy@* server-sldns badvpn hysteria-server hysteria2-server sslh stunnel4 squid nginx xray 2>/dev/null || true
      systemctl disable ws-proxy@* server-sldns badvpn hysteria-server hysteria2-server xray 2>/dev/null || true
      echo "Eliminando archivos..."
      rm -f /etc/systemd/system/ws-proxy@.service /etc/systemd/system/server-sldns.service /etc/systemd/system/badvpn.service /etc/systemd/system/xray.service /etc/systemd/system/hysteria2-server.service
      rm -f /etc/cron.d/service-checker /etc/cron.d/logrotate /etc/cron.d/xray-expiry /etc/cron.d/hysteria-expiry /etc/cron.d/hysteria2-expiry /etc/sysctl.d/99-freenet-tuning.conf /etc/security/limits.d/99-freenet.conf
      rm -rf /etc/deekayvpn /etc/slowdns /etc/socksproxy /etc/xray /etc/hysteria /etc/hysteria2 /usr/local/bin/hysteria2 /usr/local/libexec/hysteria2-auth /usr/local/bin/menu /usr/bin/menu /usr/bin/Menu
      systemctl daemon-reload; sysctl --system >/dev/null 2>&1 || true
      echo -e "${GREEN}✔ Eliminación completa.${NC}"
  else echo "Cancelado."; fi
  pause_return
}

# --- Main Dashboard ---
draw_item() { printf "${ACC}║${NC}  ${WHITE}[${YELLOW}%s${WHITE}]${NC} %-56s${ACC}║${NC}\n" "$1" "$2"; }
draw_header() {
  local os_name=$(. /etc/os-release 2>/dev/null; echo "${ID:-UNKNOWN}" | tr '[:lower:]' '[:upper:]')
  local os_ver=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
  local os="${os_name} ${os_ver}"
  local arch=$(uname -m)
  local cores=$(cpu_count)
  local ip=$(server_ip)
  local time=$(date '+%H:%M %Z')
  local status=$(server_status)
  local ram=$(ram_percent)
  local cpu=$(cpu_percent)
  local buf=$(buffer_mem)

  echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
  printf "${ACC}║${NC}${BG_TITLE}   🐉  Kyz Auto  ✸  Por NokasVip  🐉%-25s${NC}${ACC}║${NC}\n" ""
  echo -e "${ACC}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf "${ACC}║${NC}  ${DIM}OS:${NC}    ${WHITE}%-17s${NC} ${DIM}Arch:${NC} ${WHITE}%-11s${NC} ${DIM}Cores:${NC} ${WHITE}%-10s${NC}${ACC}║${NC}\n" "$os" "$arch" "$cores"
  printf "${ACC}║${NC}  ${DIM}IP:${NC}    ${WHITE}%-17s${NC} ${DIM}Hora:${NC} ${WHITE}%-11s${NC} ${DIM}Estado:${NC} ${GREEN}%-9s${NC}${ACC}║${NC}\n" "$ip" "$time" "$status"
  echo -e "${ACC}╠────────────────────── ${BOLD}Puertos Abiertos${NC} ${ACC}──────────────────────╣${NC}"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "SSH:" "22, 299" "System-DNS:" "53"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "WEB-Nginx:" "85" "SSL:" "443"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "SSL/PYTHON:" "443" "Squid:" "3128, 8000"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "WS/PYTHON:" "80, 8080, 8880" "BadVPN:" "7300"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "WS/PYTHON:" "2082,2086,25" "XRAY NTLS:" "80,8080,8880"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "XRAY TLS:" "443" "SlowDNS:" "53"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "SOCKS:" "127.0.0.1:1080" "Hysteria 1:" "20000-50000"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "Hysteria 2:" "36713/UDP" "UDPCustom:" "1-65535"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}%-29s${ACC}║${NC}\n" "ZiVPN:" "6000-19999" ""
  echo -e "${ACC}╠──────────────────── ${BOLD}Recursos Del Sistema${NC} ${ACC}────────────────────╣${NC}"
  printf "${ACC}║${NC}  ${DIM}RAM:${NC} ${YELLOW}%-14s${NC} ${DIM}CPU:${NC} ${YELLOW}%-10s${NC} ${DIM}Buffer:${NC} ${YELLOW}%-16s${NC}${ACC}║${NC}\n" "$ram" "$cpu" "$buf"
  echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
}
while true; do
  clear; draw_header; echo
  echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "01" "Cuentas SSH (Legado)" "02" "Cuentas Xray (V2ray)"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "03" "Cuentas Hysteria (UDP)" "04" "Cuentas Hysteria 2 (UDP)"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "05" "Cuentas ZiVPN (UDP)" "06" "Conexiones Activas"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "07" "Control de Servicios" "08" "Backup y Restaurar"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "09" "Utilidades (BBR/Netflix)" "10" "Config. Avanzada"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${RED}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "11" "Reiniciar Servidor" "00" "Salir"
  echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ${WHITE}Selecciona una opción:${NC} ")" opt
  case "$opt" in
    1|01) 
      while true; do
        clear
        echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${ACC}╠───────────────────${NC} ${BOLD}GESTIÓN DE CUENTAS SSH${NC} ${ACC}───────────────────╣${NC}"
        draw_item "1" "Crear Usuario SSH"
        draw_item "2" "Extender Expiracion"
        draw_item "3" "Eliminar Usuario SSH"
        draw_item "4" "Listar Todas Las Cuentas"
        draw_item "0" "Atras"
        echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
        read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ")" sub; case "$sub" in 1) create_user;; 2) extend_user;; 3) delete_user;; 4) list_real_users | nl -w2 -s'. '; pause_return;; 0) break;; esac
      done ;;
    2|02) 
      while true; do
        clear
        echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${ACC}╠──────────────────${NC} ${BOLD}GESTIÓN DE CUENTAS XRAY${NC} ${ACC}───────────────────╣${NC}"
        draw_item "1" "Agregar Cuenta Xray"
        draw_item "2" "Renovar Cuenta Xray"
        draw_item "3" "Eliminar Cuenta Xray"
        draw_item "4" "Mostrar Enlaces de Config"
        draw_item "5" "Forzar Eliminacion de Usuarios Xray Expirados"
        draw_item "6" "Actualizar Version de Xray Core"
        draw_item "0" "Atras"
        echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
        read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ")" sub; case "$sub" in 1) add_xray;; 2) renew_xray;; 3) del_xray;; 4) show_xray;; 5) /usr/local/bin/exp-check; echo "Usuarios Xray expirados eliminados."; pause_return;; 6) systemctl stop xray; XRAY_VER="v26.5.9"; echo "Reinstalando Xray Core ${XRAY_VER}..."; wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip"; unzip -q -o /tmp/xray.zip -d /tmp/xray/ && mv -f /tmp/xray/xray /usr/local/bin/xray; systemctl start xray; echo -e "${GREEN}✔ ¡Xray Restaurado a ${XRAY_VER}!${NC}"; pause_return;; 0) break;; esac
      done ;;
    3|03)
      while true; do
        clear
        echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${ACC}╠────────────────${NC} ${BOLD}GESTIÓN DE CUENTAS HYSTERIA${NC} ${ACC}─────────────────╣${NC}"
        draw_item "1" "Agregar Cuenta Hysteria"
        draw_item "2" "Renovar Cuenta Hysteria"
        draw_item "3" "Eliminar Cuenta Hysteria"
        draw_item "4" "Listar Todas Las Cuentas"
        draw_item "5" "Editar Velocidades Subida/Bajada"
        draw_item "6" "Cambiar Obfs"
        draw_item "0" "Atras"
        echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
        read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ")" sub; case "$sub" in 1) add_hysteria;; 2) extend_hysteria;; 3) del_hysteria;; 4) list_hysteria;; 5) speed_hysteria;; 6) change_obfs_hysteria;; 0) break;; esac
      done ;;
    4|04)
      while true; do
        clear
        echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${ACC}╠───────────────${NC} ${BOLD}GESTIÓN DE CUENTAS HYSTERIA 2${NC} ${ACC}────────────────╣${NC}"
        draw_item "1" "Agregar Cuenta Hysteria 2"
        draw_item "2" "Renovar Cuenta Hysteria 2"
        draw_item "3" "Eliminar Cuenta Hysteria 2"
        draw_item "4" "Listar Todas Las Cuentas"
        draw_item "5" "Mostrar Enlace de Cuenta"
        draw_item "0" "Atras"
        echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
        read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ")" sub; case "$sub" in 1) add_hysteria2;; 2) extend_hysteria2;; 3) del_hysteria2;; 4) list_hysteria2;; 5) show_hysteria2;; 0) break;; esac
      done ;;
    5|05)
      while true; do
        clear
        echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${ACC}╠──────────────────${NC} ${BOLD}GESTIÓN DE CUENTAS ZIVPN${NC} ${ACC}──────────────────╣${NC}"
        draw_item "1" "Agregar Cuenta ZiVPN"
        draw_item "2" "Renovar Cuenta ZiVPN"
        draw_item "3" "Eliminar Cuenta ZiVPN"
        draw_item "4" "Listar Todas Las Cuentas"
        draw_item "5" "Activar Cuenta"
        draw_item "6" "Desactivar Cuenta"
        draw_item "0" "Atras"
        echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
        read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ")" sub; case "$sub" in 1) add_zivpn;; 2) extend_zivpn;; 3) del_zivpn;; 4) list_zivpn;; 5) activar_zivpn;; 6) desactivar_zivpn;; 0) break;; esac
      done ;;
    6|06) online_users ;;
    7|07) service_control_menu ;;
    8|08)
      clear; echo -e "  [1] Respaldar Configuraciones del Sistema\n  [2] Restaurar Desde Respaldo\n  [0] Atrás"
      read -rp " Selecciona: " subopt; case "$subopt" in 1) backup_snapshot;; 2) restore_snapshot;; esac ;;
    9|09) utilities_menu ;;
    10) advanced_menu ;;
    11) clear; read -rp "¿Reiniciar el servidor ahora? [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]] && reboot ;;
    0|00) clear; exit 0 ;;
  esac
done
EOF_MENU

sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" /usr/local/bin/menu > /dev/null 2>&1
chmod +x /usr/local/bin/menu > /dev/null 2>&1
cp /usr/local/bin/menu /usr/bin/menu > /dev/null 2>&1
cp /usr/local/bin/menu /usr/bin/Menu > /dev/null 2>&1

# LET'S ENCRYPT RENEWAL HOOK (solo si se usó Let's Encrypt)
if [ "$USE_LETSENCRYPT" = true ]; then
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy > /dev/null 2>&1
    cat <<'EOF_RENEW' > /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh
#!/bin/bash
set -e
for domain in $RENEWED_DOMAINS; do
    cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/xray/xray.crt
    cp /etc/letsencrypt/live/$domain/privkey.pem /etc/xray/xray.key
    cat /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/live/$domain/fullchain.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem /etc/xray/xray.key
    chmod 644 /etc/xray/xray.crt
    systemctl restart xray stunnel4
    break
done
EOF_RENEW
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh > /dev/null 2>&1
    echo "0 3 * * * root certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh" > /etc/cron.d/certbot-renew
fi

# Finishing
chown -R www-data:www-data /home/vps/public_html > /dev/null 2>&1
clear
figlet Kyz Auto Script By NokasVip -c | lolcat 2>/dev/null
echo -e "${GREEN}       ¡Instalación Completa! El sistema necesita reiniciarse para aplicar todos los cambios! ${NC}"
history -c > /dev/null 2>&1; rm /root/full.sh 2>/dev/null || true
echo -e "${CYAN}           ¡El servidor se reiniciará en 10 segundos! ${NC}"
sleep 10
reboot