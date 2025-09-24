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

# Função para detectar informações de rede inteligentemente
detect_network_info() {
    local network_info="{}"
    
    # Detectar gateway e interface principal
    local gateway_info
    gateway_info=$(ip route | grep default | head -1)
    local gateway=$(echo "$gateway_info" | awk '{print $3}')
    local interface=$(echo "$gateway_info" | awk '{print $5}')
    
    if [[ -z "$gateway" || -z "$interface" ]]; then
        log "AVISO: Não foi possível detectar gateway ou interface principal"
        return 1
    fi
    
    # Obter IP atual e máscara de rede
    local ip_info
    ip_info=$(ip addr show "$interface" | grep 'inet ' | head -1)
    local current_ip=$(echo "$ip_info" | awk '{print $2}' | cut -d/ -f1)
    local cidr=$(echo "$ip_info" | awk '{print $2}' | cut -d/ -f2)
    
    # Calcular rede base
    local network_base
    network_base=$(ipcalc -n "$current_ip/$cidr" 2>/dev/null | grep Network | awk '{print $2}' || echo "")
    
    if [[ -z "$network_base" ]]; then
        # Fallback: calcular manualmente para redes comuns
        case "$cidr" in
            32)
                # Rede ponto-a-ponto, usar IP atual como base
                network_base="$current_ip/32"
                ;;
            24)
                network_base=$(echo "$current_ip" | cut -d. -f1-3).0/24
                ;;
            16)
                network_base=$(echo "$current_ip" | cut -d. -f1-2).0.0/16
                ;;
            8)
                network_base=$(echo "$current_ip" | cut -d. -f1).0.0.0/8
                ;;
            *)
                log "AVISO: CIDR $cidr não suportado para cálculo automático"
                network_base="$current_ip/$cidr"
                ;;
        esac
    fi
    
    # Determinar tipo de rede
    local network_type="unknown"
    if [[ "$current_ip" =~ ^192\.168\. ]]; then
        network_type="private_class_c"
    elif [[ "$current_ip" =~ ^10\. ]]; then
        network_type="private_class_a"
    elif [[ "$current_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        network_type="private_class_b"
    elif [[ "$current_ip" =~ ^169\.254\. ]]; then
        network_type="link_local"
    else
        network_type="public_or_other"
    fi
    
    # Garantir que CIDR seja um número válido
    if [[ -z "$cidr" || ! "$cidr" =~ ^[0-9]+$ ]]; then
        cidr="24"
    fi
    
    network_info=$(jq -n \
        --arg gateway "$gateway" \
        --arg interface "$interface" \
        --arg current_ip "$current_ip" \
        --arg cidr "$cidr" \
        --arg network_base "$network_base" \
        --arg network_type "$network_type" \
        '{
            gateway: $gateway,
            interface: $interface,
            current_ip: $current_ip,
            cidr: ($cidr | tonumber),
            network_base: $network_base,
            network_type: $network_type
        }')
    
    echo "$network_info"
}

# Função para escanear IPs disponíveis na rede
scan_available_ips() {
    local network_base="$1"
    local exclude_ips="$2"  # JSON array de IPs para excluir
    local max_scan="${3:-50}"  # Máximo de IPs para escanear
    
    log "Escaneando IPs disponíveis na rede $network_base..."
    
    # Verificar se é uma rede /32 (ponto-a-ponto)
    local cidr
    cidr=$(echo "$network_base" | cut -d/ -f2)
    
    if [[ "$cidr" == "32" ]]; then
        log "Rede /32 detectada (ponto-a-ponto). Escaneamento não aplicável."
        log "Sugerindo faixa padrão 192.168.1.x para configuração local."
        
        # Para redes /32, sugerir IPs na faixa 192.168.1.x
        local available_ips="[]"
        for i in 100 101 102 103 104; do
            available_ips=$(echo "$available_ips" | jq --arg ip "192.168.1.$i" '. + [$ip]')
        done
        
        log "IPs sugeridos para configuração local: $(echo "$available_ips" | jq -r 'join(", ")')"
        echo "$available_ips"
        return 0
    fi
    
    # Extrair base da rede para escaneamento
    local base_ip
    base_ip=$(echo "$network_base" | cut -d/ -f1 | cut -d. -f1-3)
    
    local available_ips="[]"
    local scanned=0
    
    # Escanear faixa de IPs (evitar .1 que geralmente é gateway, começar do .100)
    for i in $(seq 100 254); do
        if [[ $scanned -ge $max_scan ]]; then
            break
        fi
        
        local test_ip="$base_ip.$i"
        
        # Verificar se IP está na lista de exclusão
        if echo "$exclude_ips" | jq -e --arg ip "$test_ip" 'map(select(. == $ip)) | length > 0' >/dev/null 2>&1; then
            continue
        fi
        
        # Ping rápido para verificar se IP está em uso
        if ! ping -c 1 -W 1 "$test_ip" >/dev/null 2>&1; then
            available_ips=$(echo "$available_ips" | jq --arg ip "$test_ip" '. + [$ip]')
            log "IP disponível encontrado: $test_ip"
            
            # Limitar a 10 IPs disponíveis para não sobrecarregar
            if [[ $(echo "$available_ips" | jq 'length') -ge 10 ]]; then
                break
            fi
        fi
        
        ((scanned++))
    done
    
    log "Escaneamento concluído. $(echo "$available_ips" | jq 'length') IPs disponíveis encontrados."
    echo "$available_ips"
}

# Função para sugerir IPs para projetos
suggest_project_ips() {
    local network_info="$1"
    local available_ips="$2"
    
    local current_ip
    current_ip=$(echo "$network_info" | jq -r '.current_ip')
    
    # Criar lista de IPs para excluir (gateway, IP atual, broadcast)
    local gateway
    gateway=$(echo "$network_info" | jq -r '.gateway')
    
    local exclude_list
    exclude_list=$(jq -n --arg current "$current_ip" --arg gateway "$gateway" '[$current, $gateway]')
    
    # Sugerir IPs específicos para cada projeto
    local suggestions="{}"
    local available_count
    available_count=$(echo "$available_ips" | jq 'length')
    
    if [[ $available_count -ge 2 ]]; then
        local ender3_ip
        local laser_ip
        
        ender3_ip=$(echo "$available_ips" | jq -r '.[0]')
        laser_ip=$(echo "$available_ips" | jq -r '.[1]')
        
        suggestions=$(jq -n \
            --arg ender3_ip "$ender3_ip" \
            --arg laser_ip "$laser_ip" \
            --argjson available "$available_ips" \
            '{
                ender3: $ender3_ip,
                laser: $laser_ip,
                available_ips: $available,
                status: "success"
            }')
    else
        suggestions=$(jq -n \
            --argjson available "$available_ips" \
            '{
                available_ips: $available,
                status: "insufficient_ips",
                message: "Poucos IPs disponíveis encontrados. Considere usar DHCP ou expandir faixa de escaneamento."
            }')
    fi
    
    echo "$suggestions"
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
    
    # Informações de rede inteligente
    log "Detectando configuração de rede..."
    local network_info
    if network_info=$(detect_network_info); then
        log "Rede detectada: $(echo "$network_info" | jq -r '.network_type') - $(echo "$network_info" | jq -r '.network_base')"
        
        # Escanear IPs disponíveis
        local available_ips
        local exclude_ips
        local current_ip_val
        local gateway_val
        current_ip_val=$(echo "$network_info" | jq -r '.current_ip')
        gateway_val=$(echo "$network_info" | jq -r '.gateway')
        exclude_ips=$(jq -n --arg current "$current_ip_val" --arg gateway "$gateway_val" '[$current, $gateway]')
        available_ips=$(scan_available_ips "$(echo "$network_info" | jq -r '.network_base')" "$exclude_ips")
        
        # Sugerir IPs para projetos
        local ip_suggestions
        ip_suggestions=$(suggest_project_ips "$network_info" "$available_ips")
        
        log "Sugestões de IP geradas: $(echo "$ip_suggestions" | jq -r '.status')"
    else
        log "AVISO: Falha na detecção inteligente de rede, usando método tradicional"
        # Fallback para método tradicional
        network_info=$(jq -n \
            --arg gateway "$(ip route | grep default | awk '{print $3}' | head -1)" \
            --arg interface "$(get_primary_interface)" \
            --arg current_ip "$(ip addr show "$(get_primary_interface)" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)" \
            --arg network_type "fallback" \
            '{
                gateway: $gateway,
                interface: $interface,
                current_ip: $current_ip,
                network_type: $network_type
            }')
        available_ips="[]"
        ip_suggestions='{"status": "fallback", "message": "Detecção automática falhou"}'
    fi
    
    # Informações de DNS
    local dns_servers
    dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | jq -R . | jq -s . || echo "[]")
    
    # Informações de WiFi
    local wifi_info
    wifi_info=$(get_wifi_info "$(echo "$network_info" | jq -r '.interface')")
    
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
        --argjson network_info "$network_info" \
        --argjson dns_servers "$dns_servers" \
        --argjson wifi_info "$wifi_info" \
        --argjson available_ips "$available_ips" \
        --argjson ip_suggestions "$ip_suggestions" \
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
                detection: $network_info,
                dns_servers: $dns_servers,
                wifi: $wifi_info,
                available_ips: $available_ips,
                ip_suggestions: $ip_suggestions,
                # Manter compatibilidade com versão anterior
                primary_interface: $network_info.interface,
                local_ip: $network_info.current_ip,
                gateway: $network_info.gateway
            },
            ssh: {
                port: ($ssh_port | tonumber),
                public_key: $ssh_public_key
            },
            metadata: {
                collected_at: $collected_at,
                version: "2.0"
            }
        }')
    
    # Salvar informações no arquivo de estado
    echo "$system_info" > "$STATE_FILE"
    
    log "Informações coletadas e salvas em: $STATE_FILE"
    log "Sistema: $hostname ($os_info)"
    log "Rede: $(echo "$network_info" | jq -r '.current_ip') via $(echo "$network_info" | jq -r '.interface')"
    log "Gateway: $(echo "$network_info" | jq -r '.gateway')"
    log "Tipo de rede: $(echo "$network_info" | jq -r '.network_type')"
    
    if [[ "$(echo "$wifi_info" | jq -r '.ssid // empty')" != "" ]]; then
        log "WiFi: $(echo "$wifi_info" | jq -r '.ssid')"
    fi
    
    # Log das sugestões de IP
    if [[ "$(echo "$ip_suggestions" | jq -r '.status')" == "success" ]]; then
        log "IPs sugeridos - Ender3: $(echo "$ip_suggestions" | jq -r '.ender3'), Laser: $(echo "$ip_suggestions" | jq -r '.laser')"
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
            "Tipo de Rede: \(.network.detection.network_type // "N/A")",
            "Rede Base: \(.network.detection.network_base // "N/A")",
            "WiFi: \(.network.wifi.ssid // "N/A")",
            "SSH: porta \(.ssh.port)",
            "IPs Disponíveis: \(.network.available_ips | length) encontrados",
            if .network.ip_suggestions.status == "success" then
                "IP Sugerido Ender3: \(.network.ip_suggestions.ender3)",
                "IP Sugerido Laser: \(.network.ip_suggestions.laser)"
            else
                "Status Sugestões: \(.network.ip_suggestions.status)"
            end,
            "Coletado em: \(.metadata.collected_at)"
        ' "$STATE_FILE"
    fi
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
