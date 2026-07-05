#!/bin/bash
# Version: 2.0.0
# Time: 2026-07-05 18:55:12 (Beijing Time)
# System: Linux (Ubuntu/Debian) & macOS (Intel/Apple Silicon)
#
# Description:
#   跨平台安装 OpenCV 和 ONNX Runtime (C++ 开发环境)。
#   自动识别操作系统 (macOS/Linux) 和 CPU 架构 (x86_64/arm64)。
#   OpenCV 通过包管理器 (apt/brew) 安装。
#   ONNX Runtime 通过下载官方 Release 安装到 /usr/local/ 系统目录。
#
# Pre-conditions (前置条件):
#   1. 执行用户需具有 sudo 权限 (用于将文件复制到 /usr/local/)。
#   2. 如果是 macOS 系统，必须已提前安装 Homebrew (https://brew.sh/)。
#   3. 需确保网络能访问 GitHub 进行 Release 压缩包下载。
#
# Usage (用法):
#   chmod +x install_cpp_env.sh
#   ./install_cpp_env.sh
#
# Parameters (参数):
#   ORT_VERSION: 在脚本内部指定要安装的 ONNX Runtime 版本号。

set -e

# 1. 定义 ONNX Runtime 版本 (可根据需要修改)
ORT_VERSION="1.18.0"

# 2. 自动检测操作系统和架构
OS=$(uname -s)
ARCH=$(uname -m)

echo ">>> 检测到系统: $OS, 架构: $ARCH"

# 3. 动态组装下载文件名
if [ "$OS" = "Linux" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        ORT_FILE="onnxruntime-linux-x64-${ORT_VERSION}.tgz"
    elif [ "$ARCH" = "aarch64" ]; then
        ORT_FILE="onnxruntime-linux-aarch64-${ORT_VERSION}.tgz"
    else
        echo "不支持的 Linux 架构: $ARCH"
        exit 1
    fi
elif [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        ORT_FILE="onnxruntime-osx-x86_64-${ORT_VERSION}.tgz"
    elif [ "$ARCH" = "arm64" ]; then
        ORT_FILE="onnxruntime-osx-arm64-${ORT_VERSION}.tgz"
    else
        echo "不支持的 macOS 架构: $ARCH"
        exit 1
    fi
else
    echo "不支持的操作系统: $OS"
    exit 1
fi

ORT_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/${ORT_FILE}"

# 4. 更新包管理器并安装 OpenCV 及基础依赖
echo ">>> [1/5] 更新源并安装基础构建工具及 OpenCV 开发库..."
if [ "$OS" = "Linux" ]; then
    sudo apt-get update
    sudo apt-get install -y build-essential cmake wget unzip libopencv-dev
    OPENCV_INC="/usr/include/opencv4"
elif [ "$OS" = "Darwin" ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "错误: 未找到 Homebrew。请先在终端执行以下命令安装:"
        echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
    brew update
    brew install cmake wget unzip opencv
    # 动态获取 macOS 上 brew 安装的 OpenCV 路径 (适配 Apple Silicon /opt/homebrew 和 Intel /usr/local)
    OPENCV_INC="$(brew --prefix opencv)/include/opencv4"
fi

# 5. 下载 ONNX Runtime
echo ">>> [2/5] 下载 ONNX Runtime C++ 库 (v${ORT_VERSION})..."
if [ ! -f "$ORT_FILE" ]; then
    echo "正在下载: $ORT_URL"
    wget -c "$ORT_URL"
else
    echo "检测到本地已存在安装包，跳过下载。"
fi

# 6. 解压并安装到系统目录
echo ">>> [3/5] 解压并安装 ONNX Runtime 到 /usr/local..."
tar -zxvf "$ORT_FILE"

# 动态提取解压后的目录名 (直接去除 .tgz 后缀)
EXTRACT_DIR="${ORT_FILE%.tgz}"

# 安装头文件
echo "正在复制头文件..."
sudo mkdir -p /usr/local/include/onnxruntime
sudo cp -r "$EXTRACT_DIR/include/"* /usr/local/include/onnxruntime/

# 安装库文件
echo "正在复制库文件..."
sudo cp -r "$EXTRACT_DIR/lib/"* /usr/local/lib/

# 7. 清理收尾工作
echo ">>> [4/5] 清理临时解压文件..."
rm -rf "$EXTRACT_DIR"
# 如果想保留压缩包下次用，注释掉下面这行
# rm "$ORT_FILE"

echo ">>> [5/5] 刷新系统动态链接库缓存..."
if [ "$OS" = "Linux" ]; then
    sudo ldconfig
else
    echo "macOS 环境无需执行 ldconfig，跳过。"
fi

echo ">>> 安装全部完成。"
echo "--------------------------------------------------"
echo "OpenCV 头文件路径: $OPENCV_INC"
echo "ONNX Runtime 头文件路径: /usr/local/include/onnxruntime"
echo "ONNX Runtime 库文件路径: /usr/local/lib"
echo "--------------------------------------------------"
