# DeepFaceLab-Next 下一聊天上下文

更新时间：2026-07-20

## 项目定位

仓库：`xli471380-lab/DeepFaceLab-Next`

目标：保留 DeepFaceLab 专属人物训练、旧模型和 DFM 生态兼容性，同时改善 Windows 安装、GPU 兼容、测试、日志和训练工作流。

项目只用于获得明确授权、经过同意并按要求披露的合成媒体。不得提交私人脸部素材、训练数据、模型、DFM 或输出视频。

## 仓库与分支

- 上游冻结基线：`e4b7543ffa1d73b26fce1e31852727f658ba490c`
- 历史分支：`master`
- 集成分支：`develop`
- 当前分支：`agent/p0-reproducible-baseline`
- 草稿 PR：`#1 P0: establish reproducible baseline framework`

## 当前阶段

当前里程碑：`P0 — 可复现历史基线`

P0 先证明一套历史 DeepFaceLab 环境能完成：

```text
提取人脸 → 短训练 → 保存退出 → 恢复训练 → 合成短视频 → 导出 DFM → VisoMaster Fusion 加载
```

P0 期间不直接升级 TensorFlow、Python、CUDA、NumPy、OpenCV 或模型结构。

## 两台电脑的正确开发模式

两台电脑都是完整开发节点，做同一套开发工作，不做固定分工。

共同部分：

- 同一个 GitHub 仓库。
- 同一个开发计划、进度文件和上下文文件。
- 同一个功能分支和 PR 流程。
- 同一个 P0 验收标准。

独立部分：

- 各自的本地仓库目录。
- 各自的 Python、CUDA、cuDNN、FFmpeg 和整合包。
- 各自的 `config/local/*.psd1`。
- 各自的 `artifacts/`、`workspace/`、数据集、模型和 DFM。

GitHub 只同步源码和共享文档，不同步虚拟环境、训练数据、检查点、DFM 或报告。

### 已知电脑

`hp-a2000`：

- Windows 11 Pro build 26200，PowerShell 5.1
- i5-12500，约 16 GB 内存
- RTX A2000，约 6 GB 显存
- `system-py312` 环境档案已通过 P0 environment scaffold

`rtx5880-ada`：

- RTX 5880 Ada，约 46 GB 显存
- 约 64 GB 内存
- 当前不在身边，稍后可用时再建立它自己的独立环境档案

两台电脑都可以进行代码修改、脚本开发、依赖处理、提取、训练、保存恢复、合成、DFM 导出、文档和 PR 工作。硬件差异只记录为环境事实，不构成固定职责。

## 配置文件

模板：

```text
config/machine-profile.example.psd1
```

每台电脑复制到本地忽略目录：

```text
config/local/<MachineId>-<EnvironmentId>.psd1
```

新档案默认使用：

```powershell
Role = 'full-development'
```

`Role` 只描述当前本地档案或验收用途，不代表电脑的永久职责。旧值 `engineering`、`baseline` 和 `performance` 仍兼容。

报告目录：

```text
artifacts\p0\<MachineId>\<EnvironmentId>\
```

## 当前已验证

`hp-a2000 × system-py312`：

- P0 environment scaffold passed
- Python 3.12.10 探针通过
- Git、分支、仓库完整性和隐私文件检查通过
- FFmpeg 与 nvcc 未在 PATH 中，属于非阻塞警告
- 这不是历史 DeepFaceLab 端到端基线

## 两台电脑之间切换

离开电脑 A 前：

```powershell
git status
git add <已审查文件>
git commit -m "说明性提交信息"
git push origin <当前分支>
```

项目状态变化时同步更新：

```text
PROGRESS.md
NEXT_CHAT_CONTEXT.md
```

切换到电脑 B 后：

```powershell
git fetch origin
git switch <当前分支>
git pull --ff-only
git status
```

电脑 B 使用自己的本地环境档案继续同一项开发工作。

不要通过复制整个仓库目录或云盘同步未提交改动。先提交并推送。

两台电脑同时开发时使用不同功能分支；只在一台电脑工作时，可以顺序使用同一个功能分支。

## 当前下一步

第二台电脑不在身边，不阻塞当前工作。现在继续在 A2000 电脑上：

1. 拉取最新分支。
2. 研究并确定自包含的历史 DeepFaceLab Windows 运行环境。
3. 不复用系统 Python、FaceFusion、VisoMaster 或 ComfyUI 环境。
4. 建立 `hp-a2000-legacy-dfl.psd1` 本地档案。
5. 完成提取、短训练、保存恢复、合成、DFM 导出和加载验证。
6. 第二台电脑以后拉取相同代码，再建立自己的独立 `legacy-dfl` 环境进行相同开发和复验。

## 重要约束

- 不把付费服务作为项目必需依赖。
- 不复用 FaceFusion、VisoMaster 或 ComfyUI 的 Python 环境。
- 不在 P0 完成前重写为 PyTorch。
- 不提交素材、脸集、训练模型、DFM 或含个人信息的报告。
- 任何性能和兼容性结论都必须注明机器、环境、提交和参数。
