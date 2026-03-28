![Platform:macOS](https://img.shields.io/badge/platform-macOS-blue)
[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](http://www.gnu.org/licenses/gpl-3.0)
[![GitHub downloads](https://img.shields.io/github/downloads/OMEG-Lu/Typeflow/total?label=Downloads&labelColor=27303D&color=0D1117&logo=github&logoColor=FFFFFF&style=flat)](https://github.com/OMEG-Lu/Typeflow/releases)

# Typeflow

Typeflow 是一款面向 macOS 的英文输入法。它基于音近、形近和拼音输入来帮你更快找到想打的英文单词，并在此基础上加入了基于本地语言模型的上下文 next-word prediction。

这个项目适合这样的输入习惯：

1. 你知道单词大概怎么读，但不确定准确拼写。
2. 你习惯先用中文拼音去联想英文表达。
3. 你希望输入法不仅纠错，还能根据上下文继续联想下一个词。

## 主要特性

1. 模糊拼写输入：支持按大概读音、近似字形输入英文单词。
2. 拼音联想英文：例如输入中文拼音时，可以给出对应英文候选。
3. 即时翻译与注释：候选词可显示释义和辅助信息。
4. 本地 next-word prediction：输入一个词后，可结合上下文预测后续词语。
5. 多档模型可选：支持 `Small / Medium / Large / XLarge` 本地模型。
6. 应用内下载模型：安装输入法后可直接在偏好设置里下载模型，不需要手动跑脚本。
7. 注重隐私：默认不记录用户输入内容；在 macOS `Secure Event Input` 场景下会停用上下文预测。

## 下载与安装

1. 从 [Releases](https://github.com/OMEG-Lu/Typeflow/releases) 下载最新的 [Typeflow-Installer.pkg](https://github.com/OMEG-Lu/Typeflow/releases/latest)。
2. 双击安装包完成安装。
3. 如果系统没有自动切换成功，可以在 macOS 的 `Keyboard` -> `Input Sources` 中手动添加 `Typeflow`。
4. 首次使用 next-word prediction 时，打开 Typeflow 偏好设置，选择模型大小并点击下载。

如果 macOS 提示安装包来自未认证开发者，可以右键安装包并选择 `Open` 继续安装。

## 用户流程

安装完成后的典型流程如下：

1. 安装 `Typeflow-Installer.pkg`
2. 在输入源中启用 `Typeflow`
3. 打开偏好设置
4. 勾选 `Enable next-word prediction`
5. 选择模型大小
6. 点击下载按钮，等待模型下载到 `~/Library/Application Support/Typeflow/models`
7. 下载完成后开始正常使用预测功能

## 隐私说明

Typeflow 当前的设计原则是本地优先：

1. 预测模型运行在本机。
2. 不会把用户输入内容写入调试日志。
3. 当 macOS 进入 `Secure Event Input` 时，会停止读取上下文并停用预测逻辑。

这不能替代所有应用对密码框的正确实现，但在标准 macOS 安全输入场景下，输入法会尽量避免处理敏感上下文。

## 开发

常用命令：

```bash
bash scripts/setup-llama.sh --build-only
bash scripts/build-and-install.sh --build
bash scripts/create-installer.sh
```

模型下载脚本也支持单独下载指定模型：

```bash
bash scripts/setup-llama.sh --model small
bash scripts/setup-llama.sh --model medium
bash scripts/setup-llama.sh --model large
bash scripts/setup-llama.sh --model xlarge
```

## 项目来源

Typeflow 基于开源项目 [dongyuwei/hallelujahIM](https://github.com/dongyuwei/hallelujahIM) 修改而来，并在其输入体验之上加入了本地 LLM next-word prediction、模型下载管理和相关隐私保护改进。

## 开源协议

本项目以 GPL-3.0 协议开源。请在分发修改版本时遵守相应许可证要求。
