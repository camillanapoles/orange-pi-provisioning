#!/bin/bash

# Script para coleta automática de dados da máquina local Pop!_OS
# Autor: Orange Pi Provisioning System
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATE_FILE="$PROJECT_DIR/state/local-info.json"
LOG_FILE="$PROJECT_DIR/logs/collect-info-$(date +%Y%m%d_%H%M%S).log"

# Criar diretórios se não existirem
mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$LOG_FILE")"

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Função para detectar interface de rede principal
get_primary_interface() {
    # Buscar interface com gateway padrão
    ip route | grep default | head -1 | awk '{print $5}' || echo "eth0"
}

# Função para obter informações de WiFi
get_wifi_info() {
    local interface="$1"
    local wifi_info="{}"
    
    if command -v nmcli >/dev/null 2>&1; then
        # Usar NetworkManager se disponível
        local ssid
        ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 | head -1 || echo "")
        
        if [[ -n "$ssid" ]]; then
            wifi_info=$(jq -n \
                --arg ssid "$ssid" \
                --arg method "networkmanager" \
                '{ssid: $ssid, method: $method}')
        fi
    elif [[ -f /proc/net/wireless ]]; then
        # Fallback para interfaces wireless
        local ssid
        ssid=$(iwgetid -r 2>/dev/null || echo "")
        
        if [[ -n "$ssid" ]]; then
            wifi_info=$(jq -n \
                --arg ssid "$ssid" \
                --arg method "iwconfig" \
                '{ssid: $ssid, method: $method}')
        fi
    fi
    
    echo "$wifi_info"
}

# Função principal de coleta
collect_system_info() {
    log "Iniciando coleta de informações do sistema..."
    
    # Informações básicas do sistema
    local hostname
    hostname=$(hostname)
    
    local username
    username=$(whoami)
    
    local os_info
    os_info=$(lsb_release -d 2>/dev/null | cut -f2 || echo "Linux")
    
    # Informações de rede
    local primary_interface
    primary_interface=$(get_primary_interface)
    
    local local_ip
    local_ip=$(ip addr show "$primary_interface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1 || echo "")
    
    local gateway
    gateway=$(ip route | grep default | awk '{print $3}' | head -1 || echo "")
    
    local dns_servers
    dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | jq -R . | jq -s . || echo "[]")
    
    # Informações de WiFi
    local wifi_info
    wifi_info=$(get_wifi_info "$primary_interface")
    
    # Informações SSH
    local ssh_port
    ssh_port=$(grep -E '^Port' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    
    local ssh_key_path="$HOME/.ssh/id_rsa.pub"
    local ssh_public_key=""
    if [[ -f "$ssh_key_path" ]]; then
        ssh_public_key=$(cat "$ssh_key_path")
    fi
    
    # Informações de timezone
    local timezone
    timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
    
    # Construir JSON com todas as informações
    local system_info
    system_info=$(jq -n \
        --arg hostname "$hostname" \
        --arg username "$username" \
        --arg os_info "$os_info" \
        --arg primary_interface "$primary_interface" \
        --arg local_ip "$local_ip" \
        --arg gateway "$gateway" \
        --argjson dns_servers "$dns_servers" \
        --argjson wifi_info "$wifi_info" \
        --arg ssh_port "$ssh_port" \
        --arg ssh_public_key "$ssh_public_key" \
        --arg timezone "$timezone" \
        --arg collected_at "$(date -Iseconds)" \
        '{
            system: {
                hostname: $hostname,
                username: $username,
                os_info: $os_info,
                timezone: $timezone
            },
            network: {
                primary_interface: $primary_interface,
                local_ip: $local_ip,
                gateway: $gateway,
                dns_servers: $dns_servers,
                wifi: $wifi_info
            },
            ssh: {
                port: ($ssh_port | tonumber),
                public_key: $ssh_public_key
            },
            metadata: {
                collected_at: $collected_at,
                version: "1.0"
            }
        }')
    
    # Salvar informações no arquivo de estado
    echo "$system_info" > "$STATE_FILE"
    
    log "Informações coletadas e salvas em: $STATE_FILE"
    log "Sistema: $hostname ($os_info)"
    log "Rede: $local_ip via $primary_interface"
    log "Gateway: $gateway"
    
    if [[ "$(echo "$wifi_info" | jq -r '.ssid // empty')" != "" ]]; then
        log "WiFi: $(echo "$wifi_info" | jq -r '.ssid')"
    fi
    
    return 0
}

# Função para validar informações coletadas
validate_collected_info() {
    log "Validando informações coletadas..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log "ERRO: Arquivo de estado não encontrado: $STATE_FILE"
        return 1
    fi
    
    # Validar estrutura JSON
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        log "ERRO: Arquivo de estado contém JSON inválido"
        return 1
    fi
    
    # Validar campos obrigatórios
    local required_fields=(
        ".system.hostname"
        ".system.username"
        ".network.local_ip"
        ".network.gateway"
    )
    
    for field in "${required_fields[@]}"; do
        if [[ "$(jq -r "$field // empty" "$STATE_FILE")" == "" ]]; then
            log "ERRO: Campo obrigatório ausente: $field"
            return 1
        fi
    done
    
    log "Validação concluída com sucesso"
    return 0
}

# Função principal
main() {
    log "=== Coleta de Informações do Sistema Local ==="
    
    collect_system_info
    validate_collected_info
    
    log "=== Coleta Concluída ==="
    
    # Exibir resumo
    if [[ -f "$STATE_FILE" ]]; then
        echo
        echo "=== RESUMO DAS INFORMAÇÕES COLETADAS ==="
        jq -r '
            "Sistema: \(.system.hostname) (\(.system.os_info))",
            "Usuário: \(.system.username)",
            "IP Local: \(.network.local_ip)",
            "Interface: \(.network.primary_interface)",
            "Gateway: \(.network.gateway)",
            "WiFi: \(.network.wifi.ssid // "N/A")",
            "SSH: porta \(.ssh.port)",
            "Coletado em: \(.metadata.collected_at)"
        ' "$STATE_FILE"
    fi
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
