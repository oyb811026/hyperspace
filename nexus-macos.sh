#!/bin/bash

################################################################################
# 🚀 NEXUS CLI 一键解锁脚本 (macOS 中文版)
# 自动移除任何 Nexus CLI 版本的线程限制和内存限制
# 使用方法：在终端执行: bash nexus-unleash-macos-cn.sh
# 系统要求：macOS（Intel 或 Apple Silicon），建议至少 16GB 内存
################################################################################

# 颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
print_header() {
    echo -e "\n${PURPLE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

################################################################################
# 第 1 步：欢迎和系统检查
################################################################################

print_header "🚀 Nexus CLI 一键解锁脚本 for macOS"

echo "本脚本将执行以下操作："
echo "  1. 克隆/更新 Nexus CLI 源代码"
echo "  2. 自动检测您的版本"
echo "  3. 移除人工线程和内存限制"
echo "  4. 构建并安装优化版本"
echo ""
print_warning "确保您至少有 16GB 内存"
print_warning "每个线程使用约 3-4GB 内存"
echo ""

# 获取系统信息
if [[ $(uname -m) == "arm64" ]]; then
    ARCH="Apple Silicon (M1/M2/M3)"
    TOTAL_CORES=$(sysctl -n hw.ncpu)
else
    ARCH="Intel"
    TOTAL_CORES=$(sysctl -n hw.ncpu)
fi

TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))

print_info "您的系统：${ARCH}, ${TOTAL_CORES} CPU 核心, ${TOTAL_RAM_GB}GB 内存"

# 计算安全线程数
SAFE_THREADS=$((TOTAL_RAM_GB / 4))
if [ $SAFE_THREADS -gt $TOTAL_CORES ]; then
    SAFE_THREADS=$TOTAL_CORES
fi
if [ $SAFE_THREADS -lt 1 ]; then
    SAFE_THREADS=1
fi

print_info "推荐最大线程数：${SAFE_THREADS}（基于您的内存）"
echo ""

if [[ $TOTAL_RAM_GB -lt 16 ]]; then
    print_warning "警告：检测到内存少于 16GB。性能可能受限。"
    print_warning "建议在运行 Nexus 前关闭其他应用程序。"
fi

echo -e "${YELLOW}Apple Silicon 用户注意：${NC}"
echo -e "${YELLOW}性能核心（P-cores）比能效核心（E-cores）快得多${NC}"
echo ""

read -p "是否继续？(y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "用户取消操作"
    exit 1
fi

################################################################################
# 第 2 步：安装依赖
################################################################################

print_header "📦 检查依赖项"

# 检查 Homebrew
if ! command -v brew &> /dev/null; then
    print_warning "未找到 Homebrew。正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    print_success "Homebrew 安装成功"
else
    print_success "Homebrew 已安装"
    brew update > /dev/null 2>&1
    print_success "Homebrew 已更新"
fi

# 安装构建依赖
print_info "安装构建依赖项..."
brew install cmake pkg-config git wget

if [[ $(uname -m) == "x86_64" ]]; then
    brew install llvm
    echo 'export PATH="/usr/local/opt/llvm/bin:$PATH"' >> ~/.zshrc
    export PATH="/usr/local/opt/llvm/bin:$PATH"
fi

print_success "构建依赖项安装完成"

# 安装 Rust
print_header "🦀 检查 Rust 安装"

if ! command -v cargo &> /dev/null; then
    print_warning "未找到 Rust。正在安装 Rust..."
    export RUSTUP_INIT_SKIP_PATH_CHECK=yes
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    
    if [[ $(uname -m) == "arm64" ]]; then
        rustup default stable-aarch64-apple-darwin
    fi
    
    print_success "Rust 安装成功"
else
    print_success "Rust 已安装"
    rustup update > /dev/null 2>&1
    print_success "Rust 已更新到最新版本"
fi

################################################################################
# 第 3 步：获取 Nexus CLI 源代码
################################################################################

print_header "📥 获取 Nexus CLI 源代码"

cd ~

if [ -d "nexus-cli" ]; then
    print_info "nexus-cli 目录已存在。正在更新..."
    cd nexus-cli
    git fetch origin
    git reset --hard origin/main
    print_success "更新到最新版本"
else
    print_info "正在克隆 Nexus CLI 仓库..."
    git clone https://github.com/nexus-xyz/nexus-cli.git
    cd nexus-cli
    print_success "克隆成功"
fi

################################################################################
# 第 4 步：自动检测版本
################################################################################

print_header "🔍 检测版本和文件结构"

SETUP_FILE=""

if [ -f "clients/cli/src/session/setup.rs" ]; then
    SETUP_FILE="clients/cli/src/session/setup.rs"
    BUILD_DIR="clients/cli"
    BINARY_NAME="nexus-network"
    VERSION_TYPE="新版 (v0.10.17+)"
    print_success "检测到新版结构"
elif [ -f "src/session/setup.rs" ]; then
    SETUP_FILE="src/session/setup.rs"
    BUILD_DIR="."
    BINARY_NAME="nexus-cli"
    VERSION_TYPE="旧版 (v0.10.0-16)"
    print_success "检测到旧版结构"
else
    SETUP_FILE=$(find . -name "*.rs" -type f -exec grep -l "num_workers" {} \; | grep -E "(setup|session)" | head -1)
    
    if [ -z "$SETUP_FILE" ]; then
        print_error "找不到 setup.rs 文件！"
        exit 1
    fi
    
    BUILD_DIR=$(dirname $(find . -name "Cargo.toml" | grep -E "(cli|nexus)" | head -1))
    BINARY_NAME="nexus-cli"
    VERSION_TYPE="未知版本"
    print_success "找到设置文件: $SETUP_FILE"
fi

print_info "版本: ${VERSION_TYPE}"
print_info "设置文件: ${SETUP_FILE}"
print_info "构建目录: ${BUILD_DIR}"
print_info "二进制文件名: ${BINARY_NAME}"

################################################################################
# 第 5 步：创建备份
################################################################################

print_header "💾 创建备份"

BACKUP_FILE="${SETUP_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$SETUP_FILE" "$BACKUP_FILE"
print_success "备份创建在: $BACKUP_FILE"

################################################################################
# 第 6 步：修改代码移除限制
################################################################################

print_header "🔧 移除线程限制和内存检查"

TEMP_FILE=$(mktemp)

print_info "正在分析代码..."

HAS_75_LIMIT=false
HAS_8_CAP=false

if grep -q "0\.75" "$SETUP_FILE"; then
    HAS_75_LIMIT=true
fi

if grep -q "clamp(1, 8)" "$SETUP_FILE"; then
    HAS_8_CAP=true
fi

print_info "正在应用修改..."

cat "$SETUP_FILE" | \
    sed 's/\* 0\.75/\* 1.0/g' | \
    sed 's/\.clamp(1, 8)/.max(1)/g' | \
    sed 's/\.clamp(1, [0-9]\+)/.max(1)/g' | \
    sed 's/if max_threads\.is_some() || check_mem/if false/g' | \
    sed 's/if check_mem/if false/g' | \
    sed 's/if.*check_memory/if false/g' \
    > "$TEMP_FILE"

mv "$TEMP_FILE" "$SETUP_FILE"

print_success "代码修改成功！"

echo ""
print_info "已进行的更改："
if [ "$HAS_75_LIMIT" = true ]; then
    echo "  • 移除了 75% CPU 限制 → 现在使用 100% 的核心"
fi
if [ "$HAS_8_CAP" = true ]; then
    echo "  • 移除了 8 线程限制 → 现在无限制线程"
fi
echo "  • 禁用了内存检查 → 无自动线程减少"
echo ""

################################################################################
# 第 7 步：构建优化版本
################################################################################

print_header "🔨 构建优化版本"

cd ~/nexus-cli/$BUILD_DIR

print_info "这可能需要 10-30 分钟，请耐心等待..."
print_info "正在以发布模式构建以获得最大性能..."
echo ""

# 设置优化标志
if [[ $(uname -m) == "arm64" ]]; then
    export RUSTFLAGS="-C target-cpu=apple-m1 -C link-args=-Wl,-dead_strip"
    print_info "使用 Apple Silicon 优化"
else
    export RUSTFLAGS="-C target-cpu=native -C link-args=-Wl,-dead_strip"
    print_info "使用 Intel CPU 优化"
fi

# 清理
cargo clean > /dev/null 2>&1

print_info "开始构建过程..."
echo ""

# 构建函数
build_with_progress() {
    local log_file="/tmp/nexus_build_$(date +%s).log"
    local timeout_minutes=45
    
    echo -e "${CYAN}构建日志: $log_file${NC}"
    echo -e "${CYAN}超时时间: ${timeout_minutes}分钟${NC}"
    echo ""
    
    # 启动构建
    timeout ${timeout_minutes}m cargo build --release 2>&1 | tee "$log_file" &
    local build_pid=$!
    
    # 进度显示
    local spin='-\|/'
    local i=0
    local elapsed=0
    
    while kill -0 $build_pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        
        # 检查日志状态
        if tail -n 5 "$log_file" 2>/dev/null | grep -q "Compiling"; then
            local pkg=$(tail -n 5 "$log_file" | grep "Compiling" | tail -1 | awk '{print $2}')
            echo -ne "\r${YELLOW}正在编译: ${pkg:0:30}... ${spin:$i:1}${NC} 已用时: ${elapsed}分钟"
        elif tail -n 5 "$log_file" 2>/dev/null | grep -q "Downloading"; then
            local pkg=$(tail -n 5 "$log_file" | grep "Downloading" | tail -1 | awk '{print $2}')
            echo -ne "\r${CYAN}正在下载: ${pkg:0:30}... ${spin:$i:1}${NC} 已用时: ${elapsed}分钟"
        else
            echo -ne "\r${GREEN}构建中 ${spin:$i:1}${NC} 已用时: ${elapsed}分钟"
        fi
        
        sleep 1
        if (( elapsed % 60 == 0 )); then
            ((elapsed++))
        fi
    done
    
    wait $build_pid
    return $?
}

# 执行构建
if build_with_progress; then
    print_success "构建完成！"
    
    BUILT_BINARY=$(find target/release -name "$BINARY_NAME" -type f -executable | head -1)
    if [ -f "$BUILT_BINARY" ]; then
        file "$BUILT_BINARY" | grep -q "Mach-O"
        if [ $? -eq 0 ]; then
            print_success "二进制文件是 macOS 原生格式 (Mach-O)"
        fi
        
        if [[ $(uname -m) == "arm64" ]]; then
            if file "$BUILT_BINARY" | grep -q "arm64"; then
                print_success "二进制文件已为 Apple Silicon 编译"
            fi
        fi
    fi
else
    BUILD_EXIT_CODE=$?
    
    if [ $BUILD_EXIT_CODE -eq 124 ]; then
        print_error "构建超时（45分钟）！"
        print_info "可能原因："
        print_info "  1. 网络连接慢"
        print_info "  2. 系统资源不足"
        print_info "  3. 编译任务过大"
        echo ""
        print_info "建议："
        print_info "  1. 检查网络连接"
        print_info "  2. 关闭其他应用程序"
        print_info "  3. 手动构建: cd ~/nexus-cli/$BUILD_DIR && cargo build --release"
    else
        print_error "构建失败，错误代码: $BUILD_EXIT_CODE"
        print_info "请检查构建日志: /tmp/nexus_build_*.log"
    fi
    
    exit 1
fi

################################################################################
# 第 8 步：安装优化版本
################################################################################

print_header "📦 安装优化二进制文件"

BUILT_BINARY=$(find target/release -name "$BINARY_NAME" -type f -executable | head -1)

if [ -z "$BUILT_BINARY" ]; then
    BUILT_BINARY=$(find target -name "$BINARY_NAME" -type f -executable | head -1)
fi

if [ -z "$BUILT_BINARY" ]; then
    print_error "找不到构建的二进制文件！"
    exit 1
fi

print_success "找到二进制文件: $BUILT_BINARY"

# 确定安装位置
INSTALL_LOCATION=""

if [ -f "/usr/local/bin/nexus-cli" ]; then
    INSTALL_LOCATION="/usr/local/bin/nexus-cli"
elif [ -f "$HOME/.cargo/bin/nexus-cli" ]; then
    INSTALL_LOCATION="$HOME/.cargo/bin/nexus-cli"
elif command -v nexus-cli &> /dev/null; then
    INSTALL_LOCATION=$(which nexus-cli)
else
    INSTALL_LOCATION="/usr/local/bin/nexus-cli"
fi

print_info "安装位置: $INSTALL_LOCATION"

# 备份现有二进制文件
if [ -f "$INSTALL_LOCATION" ]; then
    BINARY_BACKUP="${INSTALL_LOCATION}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$INSTALL_LOCATION" "$BINARY_BACKUP"
    print_success "已备份现有二进制文件到: $BINARY_BACKUP"
fi

# 安装新二进制文件
print_info "正在安装二进制文件..."
if [[ "$INSTALL_LOCATION" == "/usr/local/bin/"* ]]; then
    sudo cp "$BUILT_BINARY" "$INSTALL_LOCATION"
    sudo chmod +x "$INSTALL_LOCATION"
else
    mkdir -p $(dirname "$INSTALL_LOCATION")
    cp "$BUILT_BINARY" "$INSTALL_LOCATION"
    chmod +x "$INSTALL_LOCATION"
fi

print_success "新二进制文件安装成功！"

################################################################################
# 第 9 步：完成和说明
################################################################################

print_header "✅ 安装完成！"

echo -e "${GREEN}您的 Nexus CLI 现已解锁！${NC}"
echo ""
print_info "已完成的更改："
echo "  • 无线程限制 - 使用所有 CPU 核心"
echo "  • 无内存检查 - 手动控制"
echo "  • 针对 macOS 优化的构建"
echo ""

print_header "🚀 如何在 macOS 上运行"

echo "使用最大线程数启动 Nexus："
echo -e "${CYAN}nexus-cli start --max-threads $TOTAL_CORES${NC}"
echo ""

echo "Apple Silicon 推荐（更好性能）："
echo -e "${CYAN}nexus-cli start --max-threads $SAFE_THREADS${NC}"
echo "  （保持在性能核心上以获得速度）"
echo ""

echo "在后台运行 Nexus："
echo "方法 1 - 使用 nohup："
echo -e "${CYAN}nohup nexus-cli start --max-threads $SAFE_THREADS > nexus.log 2>&1 &${NC}"
echo -e "${CYAN}tail -f nexus.log  # 监控日志${NC}"
echo ""
echo "方法 2 - 使用 screen："
echo -e "${CYAN}brew install screen${NC}"
echo -e "${CYAN}screen -S nexus${NC}"
echo -e "${CYAN}nexus-cli start --max-threads $SAFE_THREADS${NC}"
echo -e "${YELLOW}按 Ctrl+A 然后 D 分离${NC}"
echo -e "${CYAN}screen -r nexus  # 重新连接${NC}"
echo ""

print_header "🖥️ macOS 性能提示"

echo "1. 监控系统使用："
echo -e "${CYAN}htop  # 安装: brew install htop${NC}"
echo ""
echo "2. 保持系统冷却："
echo "   • 使用 Macs Fan Control 应用"
echo "   • 提升笔记本电脑以获得更好气流"
echo "   • 避免在电池上运行"
echo ""
echo "3. 释放内存："
echo "   • 关闭不必要的应用"
echo -e "${CYAN}sudo purge  # 清理内存${NC}"

print_header "⚠️ macOS 重要警告"

print_warning "每个线程使用约 3-4GB 内存"
print_warning "macOS 在过热时可能限制 CPU"
print_warning "Apple Silicon：能效核心比性能核心慢得多"
print_warning "从较少线程开始，逐渐增加"
echo ""

print_info "您的系统可以安全处理约 ${SAFE_THREADS} 个线程"
echo ""

print_header "🔄 恢复原始版本"

echo "如果想恢复到原始版本："
if [ -f "$BINARY_BACKUP" ]; then
    if [[ "$INSTALL_LOCATION" == "/usr/local/bin/"* ]]; then
        echo -e "${CYAN}sudo cp $BINARY_BACKUP $INSTALL_LOCATION${NC}"
    else
        echo -e "${CYAN}cp $BINARY_BACKUP $INSTALL_LOCATION${NC}"
    fi
fi
echo ""
echo "或重新安装："
echo -e "${CYAN}curl https://cli.nexus.xyz/ | sh${NC}"
echo ""

print_header "📊 快速测试"

echo "测试是否工作："
echo -e "${CYAN}nexus-cli start --max-threads 8${NC}"
echo ""
echo "如果看到 'clamped to X threads' - 出现问题"
echo "如果以 8 个线程启动 - 成功！🎉"
echo ""

print_success "全部完成！祝您挖矿愉快！ 🚀"
print_info "由您的编码助手制作 - 分享此脚本！"

################################################################################
# 脚本结束
################################################################################
