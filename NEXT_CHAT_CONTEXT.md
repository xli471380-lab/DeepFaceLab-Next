# DeepFaceLab-Next 下一聊天上下文

更新时间：2026-07-19

## 项目定位

项目名称：`DeepFaceLab-Next`

仓库：`xli471380-lab/DeepFaceLab-Next`

目标：在保留 DeepFaceLab 专属人物训练、旧模型和 DFM 生态兼容性的前提下，解决 Windows 安装困难、依赖陈旧、新显卡兼容、缺少测试、日志不清晰和工作流落后的问题。

项目只用于获得明确授权、经过同意并按要求披露的合成媒体。不得把私人脸部素材、训练数据、模型、DFM 或输出视频提交到仓库。

## 已完成

- 已从 `iperov/DeepFaceLab` 创建公开 Fork。
- Fork 归属账号：`xli471380-lab`。
- 仓库默认分支：`master`。
- 上游冻结基线提交：`e4b7543ffa1d73b26fce1e31852727f658ba490c`。
- 已创建集成分支：`develop`。
- 已创建当前开发分支：`agent/p0-reproducible-baseline`。
- 已添加开发路线、进度、P0 验收协议、安全规范和 Windows 诊断/验收脚本。

## 当前阶段

当前里程碑：`P0 — 可复现历史基线`

P0 的目标不是升级算法，而是先证明原版可以在一套完整记录的 Windows/NVIDIA 环境中跑通：

```text
提取人脸
→ 短训练
→ 保存并退出
→ 恢复训练
→ 合成短视频
→ 导出 DFM
→ VisoMaster Fusion 加载验证
```

P0 期间禁止直接升级 TensorFlow、Python、CUDA、NumPy、OpenCV 或模型结构。

## 分支规则

```text
master
  保留历史上游基线，暂不直接开发

develop
  经过评审的集成分支

agent/p0-reproducible-baseline
  当前 P0 文档、诊断和验收工作分支
```

当前第一批 PR 应从：

```text
agent/p0-reproducible-baseline
```

合并到：

```text
develop
```

## 下一步本地操作

建议在新的目录克隆，不要与 FaceFusion、VisoMaster 或其他 Python 环境混用：

```powershell
cd D:\
git clone https://github.com/xli471380-lab/DeepFaceLab-Next.git DeepFaceLab-Next
cd D:\DeepFaceLab-Next
git fetch origin
git switch agent/p0-reproducible-baseline
```

确认：

```powershell
git remote -v
git branch --show-current
git rev-parse HEAD
git status
```

运行第一轮机器诊断：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\system-diagnostics.ps1
```

运行 P0 环境验收框架：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\p0-acceptance.ps1
```

如果历史整合包使用独立 Python，可指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\p0-acceptance.ps1 `
  -PythonExe "完整的历史 Python 路径"
```

报告会保存在：

```text
artifacts\p0\
```

该目录中的报告可能包含本机用户名或路径，发到聊天或 GitHub 前要先脱敏。

## 下一轮开发需要的信息

把以下输出交给开发助手：

```powershell
Get-ChildItem .\artifacts\p0\ | Sort-Object LastWriteTime
Get-Content .\artifacts\p0\acceptance-summary-*.json -Raw
Get-Content .\artifacts\p0\system-diagnostics-*.json -Raw
```

另外需要确认本机准备使用的 DeepFaceLab 历史运行方式：

- 官方/社区 Windows 整合包路径。
- 内置 Python 路径。
- NVIDIA 显卡型号和驱动。
- 是否能正常打开原版训练菜单。
- 是否已经准备获得授权的小型测试素材。

## P0 后续任务顺序

1. 根据诊断结果确定历史环境，而不是立即装最新版依赖。
2. 建立最小授权测试工作区。
3. 记录提取参数和帧数。
4. 完成短训练并记录速度、显存和损失。
5. 验证保存、退出、恢复和再次保存。
6. 合成短片并检查帧数、时长和音频。
7. 导出 DFM，记录哈希与文件大小。
8. 在 VisoMaster Fusion 加载并记录结果。
9. 更新 `PROGRESS.md`，完成 P0 评审。

## 重要约束

- 不把付费服务作为项目必需依赖，优先开源或本地方案。
- 不复用 FaceFusion 或 VisoMaster 的虚拟环境。
- 不在 P0 通过前重写为 PyTorch。
- 不提交人物素材、脸集、训练模型、DFM 或包含个人信息的日志。
- 所有兼容性或性能结论必须有报告和验收记录支持。
