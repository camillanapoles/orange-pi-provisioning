#!/bin/bash

# Script de deployment para Orange Pi Zero 3 (2GB) + Ender 3 SE + Klipper
# Autor: Orange Pi Provisioning System
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/configs/projects-config.json"
STATE_DIR="$PROJECT_DIR/state"
LOG_FILE="$PROJECT_DIR/logs/deploy-ender3-$(date +%Y%m%d_%H%M%S).log"

# Criar diretórios se não existirem
mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Carregar configurações do projeto
load_project_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERRO: Arquivo de configuração não encontrado: $CONFIG_FILE"
        exit 1
    fi
    
    # Extrair configuração do projeto Ender3
    jq -r '.projects.ender3' "$CONFIG_FILE" > "$STATE_DIR/ender3-config.json"
    
    if [[ "$(jq -r '. // empty' "$STATE_DIR/ender3-config.json")" == "" ]]; then
        log "ERRO: Configuração do projeto Ender3 não encontrada"
        exit 1
    fi
    
    log "Configuração do projeto Ender3 carregada"
}

# Carregar informações do sistema local
load_local_info() {
    local local_info_file="$STATE_DIR/local-info.json"
    
    if [[ ! -f "$local_info_file" ]]; then
        log "Informações locais não encontradas. Executando coleta..."
        "$SCRIPT_DIR/collect-local-info.sh"
    fi
    
    if [[ ! -f "$local_info_file" ]]; then
        log "ERRO: Falha ao obter informações locais"
        exit 1
    fi
    
    log "Informações locais carregadas"
}

# Função para resolver IP dinâmico do projeto
resolve_project_ip() {
    local project_name="$1"
    local local_info_file="$STATE_DIR/local-info.json"
    local config_file="$STATE_DIR/ender3-config.json"
    
    log "Resolvendo IP para projeto $project_name..."
    
    # Verificar se configuração usa IP automático
    local static_ip
    static_ip=$(jq -r '.network.static_ip' "$config_file")
    
    if [[ "$static_ip" != "auto" ]]; then
        log "Usando IP fixo configurado: $static_ip"
        echo "$static_ip"
        return 0
    fi
    
    # Tentar usar sugestão inteligente
    local suggested_ip
    suggested_ip=$(jq -r ".network.ip_suggestions.${project_name} // empty" "$local_info_file")
    
    if [[ -n "$suggested_ip" && "$suggested_ip" != "null" ]]; then
        log "Usando IP sugerido pela detecção inteligente: $suggested_ip"
        echo "$suggested_ip"
        return 0
    fi
    
    # Fallback para IP configurado
    local fallback_ip
    fallback_ip=$(jq -r '.network.ip_detection.fallback_ip // empty' "$config_file")
    
    if [[ -n "$fallback_ip" && "$fallback_ip" != "null" ]]; then
        log "AVISO: Usando IP de fallback: $fallback_ip"
        log "AVISO: Verifique se este IP não está em uso na rede!"
        echo "$fallback_ip"
        return 0
    fi
    
    log "ERRO: Não foi possível resolver IP para o projeto"
    return 1
}

# Função para calcular máscara de rede
resolve_subnet_mask() {
    local local_info_file="$STATE_DIR/local-info.json"
    local config_file="$STATE_DIR/ender3-config.json"
    
    # Verificar se configuração usa máscara automática
    local subnet_mask
    subnet_mask=$(jq -r '.network.subnet_mask' "$config_file")
    
    if [[ "$subnet_mask" != "auto" ]]; then
        echo "$subnet_mask"
        return 0
    fi
    
    # Usar CIDR da rede detectada
    local cidr
    cidr=$(jq -r '.network.detection.cidr // empty' "$local_info_file")
    
    if [[ -n "$cidr" && "$cidr" != "null" ]]; then
        case "$cidr" in
            24) echo "255.255.255.0" ;;
            16) echo "255.255.0.0" ;;
            8) echo "255.0.0.0" ;;
            *) 
                log "AVISO: CIDR $cidr não reconhecido, usando /24"
                echo "255.255.255.0"
                ;;
        esac
    else
        log "AVISO: CIDR não detectado, usando máscara padrão /24"
        echo "255.255.255.0"
    fi
}

# Baixar imagem do Armbian para Orange Pi Zero 3
download_armbian_image() {
    local image_dir="$PROJECT_DIR/images"
    local image_url
    local image_file
    
    mkdir -p "$image_dir"
    
    # Obter URL da imagem da configuração
    image_url=$(jq -r '.armbian.image_url' "$STATE_DIR/ender3-config.json")
    image_file="$image_dir/$(basename "$image_url")"
    
    if [[ -f "$image_file" ]]; then
        log "Imagem já existe: $image_file"
        return 0
    fi
    
    log "Baixando imagem Armbian: $image_url"
    
    if ! wget -O "$image_file.tmp" "$image_url"; then
        log "ERRO: Falha ao baixar imagem"
        rm -f "$image_file.tmp"
        exit 1
    fi
    
    mv "$image_file.tmp" "$image_file"
    log "Imagem baixada: $image_file"
    
    # Salvar caminho da imagem no estado
    jq --arg image_path "$image_file" '.image_path = $image_path' \
        "$STATE_DIR/ender3-config.json" > "$STATE_DIR/ender3-config.json.tmp"
    mv "$STATE_DIR/ender3-config.json.tmp" "$STATE_DIR/ender3-config.json"
}

# Detectar dispositivo microSD
detect_microsd() {
    log "Detectando dispositivo microSD..."
    
    # Listar dispositivos de bloco removíveis
    local devices
    devices=$(lsblk -d -o NAME,SIZE,TRAN | grep usb | awk '{print "/dev/" $1}' || true)
    
    if [[ -z "$devices" ]]; then
        log "ERRO: Nenhum dispositivo USB/microSD detectado"
        log "Insira o microSD e tente novamente"
        exit 1
    fi
    
    log "Dispositivos detectados:"
    echo "$devices" | while read -r device; do
        local size
        size=$(lsblk -d -o SIZE "$device" | tail -1)
        log "  $device ($size)"
    done
    
    # Se apenas um dispositivo, usar automaticamente
    local device_count
    device_count=$(echo "$devices" | wc -l)
    
    if [[ $device_count -eq 1 ]]; then
        local selected_device
        selected_device=$(echo "$devices" | head -1)
        log "Usando dispositivo: $selected_device"
        
        # Salvar dispositivo no estado
        jq --arg device "$selected_device" '.microsd_device = $device' \
            "$STATE_DIR/ender3-config.json" > "$STATE_DIR/ender3-config.json.tmp"
        mv "$STATE_DIR/ender3-config.json.tmp" "$STATE_DIR/ender3-config.json"
        
        return 0
    fi
    
    log "ERRO: Múltiplos dispositivos detectados. Implementar seleção manual."
    exit 1
}

# Gravar imagem no microSD
flash_microsd() {
    local image_path
    local device
    
    image_path=$(jq -r '.image_path' "$STATE_DIR/ender3-config.json")
    device=$(jq -r '.microsd_device' "$STATE_DIR/ender3-config.json")
    
    log "Gravando imagem no microSD..."
    log "Imagem: $image_path"
    log "Dispositivo: $device"
    
    # Verificar se a imagem existe
    if [[ ! -f "$image_path" ]]; then
        log "ERRO: Imagem não encontrada: $image_path"
        exit 1
    fi
    
    # Desmontar partições do dispositivo
    log "Desmontando partições..."
    umount "${device}"* 2>/dev/null || true
    
    # Gravar imagem
    log "Iniciando gravação (isso pode demorar alguns minutos)..."
    
    if [[ "$image_path" == *.xz ]]; then
        # Imagem comprimida
        if ! xz -dc "$image_path" | sudo dd of="$device" bs=4M status=progress; then
            log "ERRO: Falha na gravação da imagem"
            exit 1
        fi
    else
        # Imagem não comprimida
        if ! sudo dd if="$image_path" of="$device" bs=4M status=progress; then
            log "ERRO: Falha na gravação da imagem"
            exit 1
        fi
    fi
    
    # Sincronizar
    sync
    log "Gravação concluída"
}

# Configurar primeira inicialização
configure_first_boot() {
    log "Configurando primeira inicialização..."
    
    # Resolver IP e máscara dinamicamente
    local resolved_ip
    local resolved_mask
    local cidr
    local local_info="$STATE_DIR/local-info.json"
    
    if ! resolved_ip=$(resolve_project_ip "ender3"); then
        log "ERRO: Falha ao resolver IP para o projeto"
        exit 1
    fi
    
    resolved_mask=$(resolve_subnet_mask)
    cidr=$(jq -r '.network.detection.cidr // 24' "$local_info")
    
    log "IP resolvido: $resolved_ip/$cidr"
    log "Máscara: $resolved_mask"
    
    # Montar partição boot
    local mount_point="/tmp/orange-pi-boot"
    local device
    device=$(jq -r '.microsd_device' "$STATE_DIR/ender3-config.json")
    
    sudo mkdir -p "$mount_point"
    
    # Aguardar sistema reconhecer partições
    sleep 2
    partprobe "$device" 2>/dev/null || true
    sleep 2
    
    # Montar primeira partição (boot)
    if ! sudo mount "${device}1" "$mount_point"; then
        log "ERRO: Falha ao montar partição boot"
        exit 1
    fi
    
    # Configurar armbian_first_run.txt
    local wifi_ssid
    local wifi_password
    local ssh_key
    local gateway
    local dns_servers
    
    wifi_ssid=$(jq -r '.network.wifi.ssid // ""' "$local_info")
    ssh_key=$(jq -r '.ssh.public_key // ""' "$local_info")
    gateway=$(jq -r '.network.gateway' "$local_info")
    dns_servers=$(jq -r '.network.dns_servers | join(", ")' "$local_info")
    
    # Obter senha WiFi da configuração (deve ser fornecida pelo usuário)
    wifi_password=$(jq -r '.wifi.password // ""' "$STATE_DIR/ender3-config.json")
    
    # Gerar configuração de primeira inicialização
    cat > "$mount_point/armbian_first_run.txt" << EOF
#!/bin/bash

# Configuração automática Orange Pi Zero 3 - Ender 3 SE
# Gerado em: $(date)
# IP configurado: $resolved_ip/$cidr (detecção inteligente)

# Configurar hostname
hostnamectl set-hostname ender3-pi

# Configurar usuário
useradd -m -s /bin/bash -G sudo ender3
echo 'ender3:ender3pi2024' | chpasswd

# Configurar SSH
mkdir -p /home/ender3/.ssh
echo "$ssh_key" > /home/ender3/.ssh/authorized_keys
chown -R ender3:ender3 /home/ender3/.ssh
chmod 700 /home/ender3/.ssh
chmod 600 /home/ender3/.ssh/authorized_keys

# Configurar IP estático (detecção inteligente)
cat > /etc/netplan/01-netcfg.yaml << 'NETPLAN_EOF'
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      dhcp4: false
      addresses: [$resolved_ip/$cidr]
      gateway4: $gateway
      nameservers:
        addresses: [$dns_servers]
      access-points:
        "$wifi_ssid":
          password: "$wifi_password"
NETPLAN_EOF

# Aplicar configuração de rede
netplan apply

# Atualizar sistema
apt update && apt upgrade -y

# Instalar dependências para Klipper
apt install -y git python3-virtualenv python3-dev libffi-dev build-essential \
    libncurses-dev libusb-dev avrdude gcc-avr binutils-avr avr-libc \
    stm32flash libnewlib-arm-none-eabi gcc-arm-none-eabi binutils-arm-none-eabi

# Marcar primeira inicialização como concluída
touch /var/log/armbian_first_run_completed

# Reiniciar para aplicar todas as configurações
reboot
EOF

    chmod +x "$mount_point/armbian_first_run.txt"
    
    # Desmontar
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
    
    log "Configuração de primeira inicialização criada"
}

# Salvar estado do deployment
save_deployment_state() {
    local state_file="$STATE_DIR/ender3-deployment.json"
    local deployment_state
    
    # Obter IP resolvido dinamicamente
    local resolved_ip
    if ! resolved_ip=$(resolve_project_ip "ender3"); then
        resolved_ip="auto-detection-failed"
    fi
    
    deployment_state=$(jq -n \
        --arg project "ender3" \
        --arg device "$(jq -r '.microsd_device' "$STATE_DIR/ender3-config.json")" \
        --arg image "$(jq -r '.image_path' "$STATE_DIR/ender3-config.json")" \
        --arg hostname "ender3-pi" \
        --arg ip "$resolved_ip" \
        --arg ip_method "intelligent_detection" \
        --arg status "flashed" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            project: $project,
            hardware: {
                device: $device,
                image: $image
            },
            network: {
                hostname: $hostname,
                ip: $ip,
                ip_method: $ip_method
            },
            status: $status,
            deployed_at: $timestamp,
            next_steps: [
                "Inserir microSD no Orange Pi Zero 3",
                "Conectar à rede elétrica",
                "Aguardar primeira inicialização (5-10 minutos)",
                "Executar validação: ./scripts/validate-deployment.sh ender3"
            ]
        }')
    
    echo "$deployment_state" > "$state_file"
    log "Estado do deployment salvo: $state_file"
}

# Função principal
main() {
    log "=== Deployment Orange Pi Zero 3 - Ender 3 SE ==="
    
    load_project_config
    load_local_info
    download_armbian_image
    detect_microsd
    flash_microsd
    configure_first_boot
    save_deployment_state
    
    log "=== Deployment Concluído ==="
    
    echo
    echo "=== PRÓXIMOS PASSOS ==="
    echo "1. Remover microSD do computador"
    echo "2. Inserir microSD no Orange Pi Zero 3"
    echo "3. Conectar Orange Pi à alimentação"
    echo "4. Aguardar primeira inicialização (5-10 minutos)"
    echo "5. Executar validação: ./scripts/validate-deployment.sh ender3"
    echo
    # Mostrar IP resolvido dinamicamente
    local resolved_ip
    if resolved_ip=$(resolve_project_ip "ender3"); then
        echo "IP configurado: $resolved_ip (detecção inteligente)"
    else
        echo "IP configurado: auto-detection-failed (verifique logs)"
    fi
    echo "Hostname: ender3-pi"
    echo "Usuário: ender3"
    echo "Senha: ender3pi2024"
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
