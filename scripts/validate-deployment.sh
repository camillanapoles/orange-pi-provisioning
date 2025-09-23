#!/bin/bash

# Script de validação automática de deployments
# Autor: Orange Pi Provisioning System
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="$PROJECT_DIR/state"
LOG_FILE="$PROJECT_DIR/logs/validate-$(date +%Y%m%d_%H%M%S).log"

# Criar diretórios se não existirem
mkdir -p "$(dirname "$LOG_FILE")"

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Função para validar conectividade de rede
validate_network_connectivity() {
    local target_ip="$1"
    local hostname="$2"
    
    log "Validando conectividade de rede..."
    
    # Teste de ping
    log "Testando ping para $target_ip..."
    if ping -c 3 -W 5 "$target_ip" >/dev/null 2>&1; then
        log "✓ Ping para $target_ip: OK"
    else
        log "✗ Ping para $target_ip: FALHOU"
        return 1
    fi
    
    # Teste de resolução de hostname
    if [[ -n "$hostname" ]]; then
        log "Testando resolução de hostname $hostname..."
        if ping -c 1 -W 5 "$hostname" >/dev/null 2>&1; then
            log "✓ Resolução de hostname $hostname: OK"
        else
            log "⚠ Resolução de hostname $hostname: FALHOU (não crítico)"
        fi
    fi
    
    return 0
}

# Função para validar conectividade SSH
validate_ssh_connectivity() {
    local target_ip="$1"
    local username="$2"
    local ssh_port="${3:-22}"
    
    log "Validando conectividade SSH..."
    
    # Teste de porta SSH
    log "Testando porta SSH $ssh_port em $target_ip..."
    if timeout 10 bash -c "</dev/tcp/$target_ip/$ssh_port" 2>/dev/null; then
        log "✓ Porta SSH $ssh_port: ABERTA"
    else
        log "✗ Porta SSH $ssh_port: FECHADA ou INACESSÍVEL"
        return 1
    fi
    
    # Teste de autenticação SSH
    log "Testando autenticação SSH como $username@$target_ip..."
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes \
           "$username@$target_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
        log "✓ Autenticação SSH: OK"
    else
        log "✗ Autenticação SSH: FALHOU"
        log "Verifique se a chave SSH está configurada corretamente"
        return 1
    fi
    
    return 0
}

# Função para validar serviços do sistema
validate_system_services() {
    local target_ip="$1"
    local username="$2"
    local project="$3"
    
    log "Validando serviços do sistema..."
    
    # Comandos básicos de validação
    local commands=(
        "uptime"
        "df -h /"
        "free -h"
        "systemctl is-active ssh"
    )
    
    for cmd in "${commands[@]}"; do
        log "Executando: $cmd"
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
               "$username@$target_ip" "$cmd" >> "$LOG_FILE" 2>&1; then
            log "✓ Comando '$cmd': OK"
        else
            log "✗ Comando '$cmd': FALHOU"
        fi
    done
    
    # Validações específicas por projeto
    case "$project" in
        "ender3")
            validate_ender3_services "$target_ip" "$username"
            ;;
        "laser")
            validate_laser_services "$target_ip" "$username"
            ;;
        *)
            log "⚠ Projeto desconhecido: $project"
            ;;
    esac
    
    return 0
}

# Função para validar serviços específicos do Ender3
validate_ender3_services() {
    local target_ip="$1"
    local username="$2"
    
    log "Validando serviços específicos do Ender3..."
    
    # Verificar se dependências do Klipper estão instaladas
    local klipper_deps=(
        "python3"
        "git"
        "gcc-avr"
    )
    
    for dep in "${klipper_deps[@]}"; do
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
               "$username@$target_ip" "which $dep" >/dev/null 2>&1; then
            log "✓ Dependência '$dep': INSTALADA"
        else
            log "⚠ Dependência '$dep': NÃO ENCONTRADA"
        fi
    done
    
    # Verificar portas USB para impressora
    log "Verificando portas USB disponíveis..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$username@$target_ip" "ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo 'Nenhuma porta USB encontrada'" >> "$LOG_FILE"
}

# Função para validar serviços específicos do Laser
validate_laser_services() {
    local target_ip="$1"
    local username="$2"
    
    log "Validando serviços específicos do Laser..."
    
    # Verificar se dependências do controle de laser estão instaladas
    local laser_deps=(
        "python3"
        "pip3"
        "node"
        "npm"
    )
    
    for dep in "${laser_deps[@]}"; do
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
               "$username@$target_ip" "which $dep" >/dev/null 2>&1; then
            log "✓ Dependência '$dep': INSTALADA"
        else
            log "⚠ Dependência '$dep': NÃO ENCONTRADA"
        fi
    done
    
    # Verificar portas seriais para laser
    log "Verificando portas seriais disponíveis..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$username@$target_ip" "ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo 'Nenhuma porta serial encontrada'" >> "$LOG_FILE"
}

# Função para gerar relatório de validação
generate_validation_report() {
    local project="$1"
    local target_ip="$2"
    local validation_result="$3"
    
    local report_file
    report_file="$PROJECT_DIR/reports/validation_report_${project}_$(date +%Y%m%d_%H%M%S).md"
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
# Relatório de Validação - Projeto $project

**Data:** $(date '+%Y-%m-%d %H:%M:%S')  
**Projeto:** $project  
**IP de Destino:** $target_ip  
**Status:** $validation_result  

## Resumo da Validação

EOF
    
    # Adicionar logs da validação
    {
        echo "## Logs Detalhados"
        echo ""
        echo '```'
        cat "$LOG_FILE"
        echo '```'
    } >> "$report_file"
    
    log "Relatório de validação gerado: $report_file"
}

# Função para atualizar estado do deployment
update_deployment_state() {
    local project="$1"
    local validation_result="$2"
    
    local state_file="$STATE_DIR/${project}-deployment.json"
    
    if [[ -f "$state_file" ]]; then
        # Atualizar estado existente
        jq --arg status "$validation_result" \
           --arg validated_at "$(date -Iseconds)" \
           '.status = $status | .validated_at = $validated_at' \
           "$state_file" > "$state_file.tmp"
        mv "$state_file.tmp" "$state_file"
        
        log "Estado do deployment atualizado: $state_file"
    else
        log "⚠ Arquivo de estado não encontrado: $state_file"
    fi
}

# Função principal de validação
validate_project() {
    local project="$1"
    local state_file="$STATE_DIR/${project}-deployment.json"
    
    if [[ ! -f "$state_file" ]]; then
        log "ERRO: Estado do deployment não encontrado: $state_file"
        log "Execute primeiro o deployment do projeto $project"
        exit 1
    fi
    
    # Carregar informações do deployment
    local target_ip
    local hostname
    local username
    
    target_ip=$(jq -r '.network.ip' "$state_file")
    hostname=$(jq -r '.network.hostname' "$state_file")
    
    case "$project" in
        "ender3")
            username="ender3"
            ;;
        "laser")
            username="laser"
            ;;
        *)
            log "ERRO: Projeto desconhecido: $project"
            exit 1
            ;;
    esac
    
    log "=== Validação do Projeto $project ==="
    log "IP: $target_ip"
    log "Hostname: $hostname"
    log "Usuário: $username"
    
    # Executar validações
    local validation_success=true
    
    if ! validate_network_connectivity "$target_ip" "$hostname"; then
        validation_success=false
    fi
    
    if ! validate_ssh_connectivity "$target_ip" "$username"; then
        validation_success=false
    fi
    
    if ! validate_system_services "$target_ip" "$username" "$project"; then
        validation_success=false
    fi
    
    # Determinar resultado final
    local validation_result
    if [[ "$validation_success" == "true" ]]; then
        validation_result="validated"
        log "=== Validação CONCLUÍDA COM SUCESSO ==="
    else
        validation_result="validation_failed"
        log "=== Validação FALHOU ==="
    fi
    
    # Gerar relatório e atualizar estado
    generate_validation_report "$project" "$target_ip" "$validation_result"
    update_deployment_state "$project" "$validation_result"
    
    if [[ "$validation_success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Função de ajuda
show_help() {
    cat << EOF
Uso: $0 <projeto>

Projetos disponíveis:
  ender3  - Validar deployment Orange Pi Zero 3 + Ender 3 SE
  laser   - Validar deployment Orange Pi Zero 2W + LaserTree K1

Exemplos:
  $0 ender3
  $0 laser

EOF
}

# Função principal
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    local project="$1"
    
    case "$project" in
        "ender3"|"laser")
            validate_project "$project"
            ;;
        "-h"|"--help"|"help")
            show_help
            exit 0
            ;;
        *)
            log "ERRO: Projeto desconhecido: $project"
            show_help
            exit 1
            ;;
    esac
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
