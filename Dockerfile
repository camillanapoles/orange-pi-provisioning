
FROM ubuntu:22.04

# Evitar prompts interativos durante instalação
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Sao_Paulo

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    xz-utils \
    fdisk \
    parted \
    kpartx \
    losetup \
    qemu-user-static \
    binfmt-support \
    rsync \
    ssh \
    sshpass \
    ping \
    iputils-ping \
    net-tools \
    jq \
    yq \
    shellcheck \
    python3 \
    python3-pip \
    sudo \
    systemd-container \
    && rm -rf /var/lib/apt/lists/*

# Instalar ferramentas Python para automação
RUN pip3 install \
    requests \
    pyyaml \
    paramiko \
    psutil

# Criar usuário não-root para operações
RUN useradd -m -s /bin/bash provisioner && \
    echo 'provisioner ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Criar diretórios de trabalho
RUN mkdir -p /workspace/{images,mounts,configs,scripts,logs,state} && \
    chown -R provisioner:provisioner /workspace

# Definir usuário de trabalho
USER provisioner
WORKDIR /workspace

# Copiar scripts e configurações
COPY --chown=provisioner:provisioner scripts/ ./scripts/
COPY --chown=provisioner:provisioner configs/ ./configs/

# Tornar scripts executáveis
RUN chmod +x scripts/*.sh

# Ponto de entrada padrão
ENTRYPOINT ["/bin/bash"]
