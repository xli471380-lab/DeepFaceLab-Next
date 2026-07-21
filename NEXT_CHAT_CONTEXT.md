# DeepFaceLab-Next 下一聊天上下文

更新时间：2026-07-21

## 项目定位

仓库：`xli471380-lab/DeepFaceLab-Next`

目标：保留 DeepFaceLab 专属人物训练、旧模型和 DFM 生态兼容性，同时改善 Windows 安装、GPU 兼容、测试、日志、恢复与训练工作流。

项目只用于获得明确授权、经过同意并按要求披露的合成媒体。不得提交私人脸部素材、训练数据、对齐脸、模型、DFM、嵌入、输出视频、凭据或本地机器报告。

## 仓库与分支

- 上游冻结基线：`e4b7543ffa1d73b26fce1e31852727f658ba490c`
- 历史分支：`master`
- 集成分支：`develop`
- 当前收口分支：`agent/p0-reproducible-baseline`
- PR：`#1 P0: establish reproducible baseline framework`
- PR 合并后建立：`agent/p1-engineering-reliability`

## 当前阶段

`P0 — 可复现历史基线` 已在一套完整记录的本地环境上通过。

正式进入前的过渡工作：

```text
审查并合并 PR #1
→ 从最新 develop 创建 agent/p1-engineering-reliability
→ 开始 P1 工程可靠性
```

P1 不升级模型算法，也不直接更换历史 TensorFlow、Python、CUDA、NumPy 或 OpenCV。P1 先提高脚本可靠性、报告一致性、错误诊断、备份恢复和无 GPU 测试能力。

## P0 最终验收环境

```text
MachineId: rtx5880-ada
EnvironmentId: legacy-dfl-rtx3000-20211120
Computer: DESKTOP-84BCCU9
GPU: NVIDIA RTX 5880 Ada Generation
VRAM: 46068 MiB
Driver: 582.16
Historical Python: 3.6.8
Historical TensorFlow: 2.6.0
```

历史运行时：

```text
D:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series
```

隔离 P0 工作区：

```text
D:\DFL-P0-Authorized\workspace-p0
```

## P0 已通过的完整链路

```text
环境与 GPU 探针
→ 授权合成数据预检
→ 隔离工作区
→ 源/目标人脸提取
→ SAEHD 短训练到迭代 2
→ 保存退出
→ 同一检查点恢复到迭代 4
→ 3 张目标图合并与 3 张 Mask
→ 人工视觉复核
→ DFM 导出和 ONNX 校验
→ VisoMaster Fusion 识别、加载、检测目标脸并执行一次 DFM 推理
```

最终模型：

```text
Model: p0gate_SAEHD
Iteration: 4
Checkpoint files: 8
```

最终 DFM：

```text
D:\DFL-P0-Authorized\workspace-p0\dfm\p0gate_SAEHD_model.dfm
Size: 27654198 bytes
SHA-256: E2F7E8810384FCE392DA0FA8D036795A93282C223E743855E5BCCB1EF22047C8
ONNX opset: 12
Input: in_face
Outputs: out_face_mask, out_celeb_face, out_celeb_face_mask
```

VisoMaster Fusion：

```text
Outer root: E:\SECourses\VisoMaster-Fusion
Repository: E:\SECourses\VisoMaster-Fusion\VisoMaster-Fusion
Branch: main
Commit: 560c7645d63c07526fe7109fce6abcabf95768fa
Installed DFM: model_assets\dfm_models\p0gate_SAEHD_model.dfm
```

Gate F 已确认：

- `DeepFaceLive (DFM)` 可选；
- DFM 出现在模型列表；
- 授权合成目标图片可加载；
- 能检测到目标脸；
- `Swap Faces` 执行了一次 DFM 推理；
- 预览发生变化；
- 程序保持响应；
- 没有阻断性的 CUDA、TensorRT、provider、张量名或张量形状错误。

四次迭代模型只用于兼容性和可复现性，不代表画质。

## P0 最终报告

```text
Resume:
D:\DeepFaceLab-Next\artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\resume-training-save\p0-resume-training-save-v2-20260721T141856Z.json

Merge:
D:\DeepFaceLab-Next\artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\merge\p0-controlled-merge-20260721T142130Z.json

DFM export:
D:\DeepFaceLab-Next\artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\dfm-export\p0-controlled-dfm-export-20260721T142402Z.json

VisoMaster Fusion:
D:\DeepFaceLab-Next\artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\visomaster-fusion\p0-visomaster-fusion-acceptance-v2-20260721T150505Z.json

Workspace Gate F marker:
D:\DFL-P0-Authorized\workspace-p0\p0-visomaster-fusion-manifest.json
```

这些报告、模型、DFM 和媒体都属于本地忽略内容，不上传到 GitHub。

## 两台电脑的开发模式

两台电脑都是独立完整开发节点，共用源码、计划、文档和 PR 流程，但不共用本地运行环境。

共同部分：

- 同一个 GitHub 仓库；
- 同一个 `develop` 集成分支；
- 每项工作使用独立 `agent/*` 分支；
- 同一个安全与验收标准。

独立部分：

- 仓库目录；
- Python、CUDA、cuDNN、FFmpeg；
- 历史 DeepFaceLab 运行时；
- `config/local/*.psd1`；
- `artifacts/`、workspace、数据集、模型和 DFM；
- VisoMaster Fusion、FaceFusion 和 ComfyUI 环境。

不得复用 FaceFusion、旧 VisoMaster、ComfyUI 或其他项目的 Python 环境。

## PR #1 合并后的本地切换步骤

先确认 PR #1 已经合并到 `develop`，然后在当前电脑执行：

```powershell
cd D:\DeepFaceLab-Next

git status --short

git fetch origin
git switch develop
git pull --ff-only

git switch -c agent/p1-engineering-reliability
git push -u origin agent/p1-engineering-reliability
```

GitHub TLS 若临时出现 Schannel 握手失败，可以对单次命令使用：

```powershell
git -c http.sslBackend=openssl -c http.version=HTTP/1.1 fetch origin
```

不得关闭 SSL 证书验证。

## P1 第一批工作

P1 的第一批不执行训练，不修改检查点，不重新导出 DFM，也不启动 VisoMaster。

实施顺序：

1. 仓库隐私与路径边界验证器；
2. P0 步骤 10–18 报告 Schema 和状态一致性验证器；
3. 一条命令汇总本机环境与已有验收报告；
4. 结构化失败代码和可执行修复提示；
5. PowerShell/Python 辅助逻辑的 CPU-only 测试；
6. 无 GPU CI；
7. 检查点备份、原子替换、损坏识别与回滚设计；
8. 贡献、发布、安全、故障排查和回滚文档。

第一批验收要求：

- 在没有 GPU、没有历史运行时、没有媒体和模型的 CI 环境中运行；
- 不读取图片像素、对齐脸、检查点或 DFM 内容；
- 不修改本地 workspace；
- 对缺失、过期、损坏或字段不一致的报告给出稳定错误代码；
- 对私密文件进入 Git 工作区的风险进行 fail-closed 阻断。

## 重要约束

- 不把付费服务作为必需依赖；
- 不复用 FaceFusion、VisoMaster 或 ComfyUI 环境；
- P1 不重写模型为 PyTorch；
- 不提交素材、脸集、训练模型、DFM、嵌入或含个人信息的报告；
- 任何性能和兼容性结论必须注明机器、环境、提交和参数；
- 不因为 P0 已通过就删除最终本地模型、DFM、报告或 workspace；
- 后续修改训练、检查点、合并或导出路径时，必须以当前 P0 结果作为回归基线。
