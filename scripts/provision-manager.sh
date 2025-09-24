#!/bin/bash

# Interface principal para seleção e execução de projetos
# Autor: Orange Pi Provisioning System
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/configs/projects-config.json"
STATE_DIR="$PROJECT_DIR/state"
LOG_FILE="$PROJECT_DIR/logs/provision-manager-$(date +%Y%m%d_%H%M%S).log"

# Criar diretórios se não existirem
mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Função para exibir banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                Orange Pi Provisioning System                ║
║                     CI/CD Docker Edition                    ║
╠══════════════════════════════════════════════════════════════╣
║  Provisionamento automatizado de microSDs para Orange Pi    ║
║  com ambientes isolados e validação automática              ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# Função para exibir menu de projetos
show_project_menu() {
    echo "=== PROJETOS DISPONÍVEIS ==="
    echo
    echo "1) Ender 3 SE - Orange Pi Zero 3 (2GB)"
    echo "   • Klipper + firmware fix + screen"
    echo "   • IP: Detecção automática de rede"
    echo "   • Hostname: ender3-pi"
    echo
    echo "2) LaserTree K1 - Orange Pi Zero 2W (1GB)"
    echo "   • LightBurn + controle de laser"
    echo "   • IP: Detecção automática de rede"
    echo "   • Hostname: laser-pi"
    echo
    echo "3) Validar deployment existente"
    echo "4) Coletar informações do sistema local"
    echo "5) Exibir status dos projetos"
    echo "0) Sair"
    echo
}

# Função para coletar informações do sistema
collect_system_info() {
    log "Coletando informações do sistema local..."
    
    if "$SCRIPT_DIR/collect-local-info.sh"; then
        echo "✓ Informações do sistema coletadas com sucesso"
        
        # Exibir resumo
        local local_info="$STATE_DIR/local-info.json"
        if [[ -f "$local_info" ]]; then
            echo
            echo "=== INFORMAÇÕES COLETADAS ==="
            jq -r '
                "Sistema: \(.system.hostname) (\(.system.os_info))",
                "Usuário: \(.system.username)",
                "IP Local: \(.network.local_ip)",
                "Gateway: \(.network.gateway)",
                "WiFi: \(.network.wifi.ssid // "N/A")"
            ' "$local_info"
        fi
    else
        echo "✗ Falha ao coletar informações do sistema"
        return 1
    fi
}

# Função para executar deployment do Ender3
deploy_ender3() {
    log "Iniciando deployment do projeto Ender3..."
    
    echo "=== DEPLOYMENT ENDER 3 SE ==="
    echo
    echo "Este processo irá:"
    echo "• Baixar imagem Armbian para Orange Pi Zero 3"
    echo "• Detectar e gravar microSD"
    echo "• Configurar Klipper e dependências"
    echo "• Configurar rede com detecção automática de IP"
    echo
    
    # Verificar se informações WiFi estão configuradas
    if ! check_wifi_config "ender3"; then
        return 1
    fi
    
    read -p "Continuar com o deployment? (s/N): " -r
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Deployment cancelado"
        return 0
    fi
    
    if "$SCRIPT_DIR/deploy-ender3.sh"; then
        echo "✓ Deployment do Ender3 concluído com sucesso"
        echo
        echo "Próximos passos:"
        echo "1. Inserir microSD no Orange Pi Zero 3"
        echo "2. Conectar à alimentação"
        echo "3. Aguardar 5-10 minutos para primeira inicialização"
        echo "4. Executar validação"
    else
        echo "✗ Falha no deployment do Ender3"
        return 1
    fi
}

# Função para executar deployment do Laser
deploy_laser() {
    log "Iniciando deployment do projeto Laser..."
    
    echo "=== DEPLOYMENT LASERTREE K1 ==="
    echo
    echo "Este processo irá:"
    echo "• Baixar imagem Armbian para Orange Pi Zero 2W"
    echo "• Detectar e gravar microSD"
    echo "• Configurar LightBurn e controle de laser"
    echo "• Configurar rede com detecção automática de IP"
    echo
    
    # Verificar se informações WiFi estão configuradas
    if ! check_wifi_config "laser"; then
        return 1
    fi
    
    read -p "Continuar com o deployment? (s/N): " -r
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Deployment cancelado"
        return 0
    fi
    
    if "$SCRIPT_DIR/deploy-laser.sh"; then
        echo "✓ Deployment do Laser concluído com sucesso"
        echo
        echo "Próximos passos:"
        echo "1. Inserir microSD no Orange Pi Zero 2W"
        echo "2. Conectar à alimentação"
        echo "3. Aguardar 5-10 minutos para primeira inicialização"
        echo "4. Executar validação"
    else
        echo "✗ Falha no deployment do Laser"
        return 1
    fi
}

# Função para verificar configuração WiFi
check_wifi_config() {
    local project="$1"
    local config_file="$STATE_DIR/${project}-config.json"
    
    # Se arquivo de configuração não existe, criar a partir do template
    if [[ ! -f "$config_file" ]]; then
        jq ".projects.$project" "$CONFIG_FILE" > "$config_file"
    fi
    
    local wifi_password
    wifi_password=$(jq -r '.wifi.password // ""' "$config_file")
    
    if [[ -z "$wifi_password" ]]; then
        echo
        echo "⚠ Configuração WiFi necessária"
        echo
        
        local local_info="$STATE_DIR/local-info.json"
        if [[ -f "$local_info" ]]; then
            local wifi_ssid
            wifi_ssid=$(jq -r '.network.wifi.ssid // ""' "$local_info")
            
            if [[ -n "$wifi_ssid" ]]; then
                echo "SSID detectado: $wifi_ssid"
                read -r -p "Senha do WiFi '$wifi_ssid': " -s wifi_password
                echo
                
                # Salvar senha na configuração
                jq --arg password "$wifi_password" '.wifi.password = $password' \
                    "$config_file" > "$config_file.tmp"
                mv "$config_file.tmp" "$config_file"
                
                echo "✓ Configuração WiFi salva"
            else
                echo "✗ SSID WiFi não detectado. Execute primeiro a coleta de informações."
                return 1
            fi
        else
            echo "✗ Informações do sistema não coletadas. Execute primeiro a coleta."
            return 1
        fi
    fi
    
    return 0
}

# Função para validar deployment
validate_deployment() {
    echo "=== VALIDAÇÃO DE DEPLOYMENT ==="
    echo
    echo "Projetos disponíveis para validação:"
    echo "1) Ender 3 SE (IP automático)"
    echo "2) LaserTree K1 (IP automático)"
    echo "0) Voltar"
    echo
    
    read -p "Escolha o projeto para validar: " -r choice
    
    case "$choice" in
        1)
            echo "Validando deployment Ender3..."
            if "$SCRIPT_DIR/validate-deployment.sh" ender3; then
                echo "✓ Validação do Ender3 concluída com sucesso"
            else
                echo "✗ Falha na validação do Ender3"
            fi
            ;;
        2)
            echo "Validando deployment Laser..."
            if "$SCRIPT_DIR/validate-deployment.sh" laser; then
                echo "✓ Validação do Laser concluída com sucesso"
            else
                echo "✗ Falha na validação do Laser"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            echo "Opção inválida"
            ;;
    esac
}

# Função para exibir status dos projetos
show_project_status() {
    echo "=== STATUS DOS PROJETOS ==="
    echo
    
    # Status Ender3
    local ender3_state="$STATE_DIR/ender3-deployment.json"
    if [[ -f "$ender3_state" ]]; then
        echo "🖨️  ENDER 3 SE:"
        jq -r '
            "   Status: \(.status)",
            "   IP: \(.network.ip)",
            "   Hostname: \(.network.hostname)",
            "   Deployment: \(.deployed_at // "N/A")",
            "   Validação: \(.validated_at // "Não validado")"
        ' "$ender3_state"
    else
        echo "🖨️  ENDER 3 SE: Não deployado"
    fi
    
    echo
    
    # Status Laser
    local laser_state="$STATE_DIR/laser-deployment.json"
    if [[ -f "$laser_state" ]]; then
        echo "🔥 LASERTREE K1:"
        jq -r '
            "   Status: \(.status)",
            "   IP: \(.network.ip)",
            "   Hostname: \(.network.hostname)",
            "   Deployment: \(.deployed_at // "N/A")",
            "   Validação: \(.validated_at // "Não validado")"
        ' "$laser_state"
    else
        echo "🔥 LASERTREE K1: Não deployado"
    fi
    
    echo
    
    # Informações do sistema local
    local local_info="$STATE_DIR/local-info.json"
    if [[ -f "$local_info" ]]; then
        echo "💻 SISTEMA LOCAL:"
        jq -r '
            "   Hostname: \(.system.hostname)",
            "   IP: \(.network.local_ip)",
            "   WiFi: \(.network.wifi.ssid // "N/A")",
            "   Coletado: \(.metadata.collected_at)"
        ' "$local_info"
    else
        echo "💻 SISTEMA LOCAL: Informações não coletadas"
    fi
}

# Função principal do menu
main_menu() {
    while true; do
        clear
        show_banner
        show_project_menu
        
        read -p "Escolha uma opção: " -r choice
        echo
        
        case "$choice" in
            1)
                deploy_ender3
                ;;
            2)
                deploy_laser
                ;;
            3)
                validate_deployment
                ;;
            4)
                collect_system_info
                ;;
            5)
                show_project_status
                ;;
            0)
                echo "Saindo..."
                exit 0
                ;;
            *)
                echo "Opção inválida. Tente novamente."
                ;;
        esac
        
        echo
        read -p "Pressione Enter para continuar..." -r
    done
}

# Função principal
main() {
    log "=== Orange Pi Provisioning Manager Iniciado ==="
    
    # Verificar se está executando no Docker
    if [[ -f /.dockerenv ]]; then
        log "Executando dentro do container Docker"
    else
        log "Executando diretamente no sistema host"
    fi
    
    # Verificar dependências
    local required_commands=("jq" "wget" "lsblk" "ping" "ssh")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "ERRO: Comando '$cmd' não encontrado"
            echo "Execute: apt update && apt install -y $cmd"
            exit 1
        fi
    done
    
    # Iniciar menu principal
    main_menu
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
