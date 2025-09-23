#!/bin/bash

# Script de deployment para Orange Pi Zero 2W (1GB) + LaserTree K1 + LightBurn
# Autor: Orange Pi Provisioning System
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/configs/projects-config.json"
STATE_DIR="$PROJECT_DIR/state"
LOG_FILE="$PROJECT_DIR/logs/deploy-laser-$(date +%Y%m%d_%H%M%S).log"

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
    
    # Extrair configuração do projeto Laser
    jq -r '.projects.laser' "$CONFIG_FILE" > "$STATE_DIR/laser-config.json"
    
    if [[ "$(jq -r '. // empty' "$STATE_DIR/laser-config.json")" == "" ]]; then
        log "ERRO: Configuração do projeto Laser não encontrada"
        exit 1
    fi
    
    log "Configuração do projeto Laser carregada"
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

# Baixar imagem do Armbian para Orange Pi Zero 2W
download_armbian_image() {
    local image_dir="$PROJECT_DIR/images"
    local image_url
    local image_file
    
    mkdir -p "$image_dir"
    
    # Obter URL da imagem da configuração
    image_url=$(jq -r '.armbian.image_url' "$STATE_DIR/laser-config.json")
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
        "$STATE_DIR/laser-config.json" > "$STATE_DIR/laser-config.json.tmp"
    mv "$STATE_DIR/laser-config.json.tmp" "$STATE_DIR/laser-config.json"
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
            "$STATE_DIR/laser-config.json" > "$STATE_DIR/laser-config.json.tmp"
        mv "$STATE_DIR/laser-config.json.tmp" "$STATE_DIR/laser-config.json"
        
        return 0
    fi
    
    log "ERRO: Múltiplos dispositivos detectados. Implementar seleção manual."
    exit 1
}

# Gravar imagem no microSD
flash_microsd() {
    local image_path
    local device
    
    image_path=$(jq -r '.image_path' "$STATE_DIR/laser-config.json")
    device=$(jq -r '.microsd_device' "$STATE_DIR/laser-config.json")
    
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
    
    # Montar partição boot
    local mount_point="/tmp/orange-pi-boot"
    local device
    device=$(jq -r '.microsd_device' "$STATE_DIR/laser-config.json")
    
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
    local local_info="$STATE_DIR/local-info.json"
    local wifi_ssid
    local wifi_password
    local ssh_key
    
    wifi_ssid=$(jq -r '.network.wifi.ssid // ""' "$local_info")
    ssh_key=$(jq -r '.ssh.public_key // ""' "$local_info")
    
    # Obter senha WiFi da configuração (deve ser fornecida pelo usuário)
    wifi_password=$(jq -r '.wifi.password // ""' "$STATE_DIR/laser-config.json")
    
    # Gerar configuração de primeira inicialização
    cat > "$mount_point/armbian_first_run.txt" << EOF
#!/bin/bash

# Configuração automática Orange Pi Zero 2W - LaserTree K1
# Gerado em: $(date)

# Configurar hostname
hostnamectl set-hostname laser-pi

# Configurar usuário
useradd -m -s /bin/bash -G sudo laser
echo 'laser:laserpi2024' | chpasswd

# Configurar SSH
mkdir -p /home/laser/.ssh
echo "$ssh_key" > /home/laser/.ssh/authorized_keys
chown -R laser:laser /home/laser/.ssh
chmod 700 /home/laser/.ssh
chmod 600 /home/laser/.ssh/authorized_keys

# Configurar IP estático
cat > /etc/netplan/01-netcfg.yaml << 'NETPLAN_EOF'
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      dhcp4: false
      addresses: [192.168.1.101/24]
      gateway4: $(jq -r '.network.gateway' "$local_info")
      nameservers:
        addresses: $(jq -r '.network.dns_servers | join(", ")' "$local_info")
      access-points:
        "$wifi_ssid":
          password: "$wifi_password"
NETPLAN_EOF

# Aplicar configuração de rede
netplan apply

# Atualizar sistema
apt update && apt upgrade -y

# Instalar dependências para controle de laser
apt install -y git python3-pip python3-venv nodejs npm \
    libusb-1.0-0-dev libudev-dev build-essential \
    python3-serial python3-usb

# Instalar grbl-server para controle de laser
pip3 install grbl-server pyserial

# Configurar serviços para LaserTree K1
systemctl enable ssh
systemctl start ssh

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
    local state_file="$STATE_DIR/laser-deployment.json"
    local deployment_state
    
    deployment_state=$(jq -n \
        --arg project "laser" \
        --arg device "$(jq -r '.microsd_device' "$STATE_DIR/laser-config.json")" \
        --arg image "$(jq -r '.image_path' "$STATE_DIR/laser-config.json")" \
        --arg hostname "laser-pi" \
        --arg ip "192.168.1.101" \
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
                ip: $ip
            },
            status: $status,
            deployed_at: $timestamp,
            next_steps: [
                "Inserir microSD no Orange Pi Zero 2W",
                "Conectar à rede elétrica",
                "Aguardar primeira inicialização (5-10 minutos)",
                "Executar validação: ./scripts/validate-deployment.sh laser"
            ]
        }')
    
    echo "$deployment_state" > "$state_file"
    log "Estado do deployment salvo: $state_file"
}

# Função principal
main() {
    log "=== Deployment Orange Pi Zero 2W - LaserTree K1 ==="
    
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
    echo "2. Inserir microSD no Orange Pi Zero 2W"
    echo "3. Conectar Orange Pi à alimentação"
    echo "4. Aguardar primeira inicialização (5-10 minutos)"
    echo "5. Executar validação: ./scripts/validate-deployment.sh laser"
    echo
    echo "IP configurado: 192.168.1.101"
    echo "Hostname: laser-pi"
    echo "Usuário: laser"
    echo "Senha: laserpi2024"
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
