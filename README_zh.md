# Hex Player

一款现代，极简风格的 macOS 音乐播放器。

[![hexplayer preview](res/preview.png)](https://www.youtube.com/watch?v=GultB_Iz56E)

## 提醒：

当你遇到“hexplayer.app”不能打开，因为它来自身份不明的开发者。不要担心，因为软件没有签名导致的。请在“系统偏好设置”中选择“安全性与隐私”，然后点击“仍然打开”即可。

为什么不签名呢？因为我不想花钱（99美刀一年）去买证书。

担心安全怎么办？代码是开源的，请自行编译。

## 下载

访问 [最新版本](https://github.com/ahxj/hexplayer/releases/latest) 下载适合您系统的版本：

* **hexplayer.app** - 通用架构版本
* **hexplayer-arm64.app** - 专为 Apple M 系列芯片优化版本

> 推荐：M 芯片 Mac 用户请使用 arm64 版本，其他 Mac 用户使用通用版本。

## 特点

* ✅ 兼容 macOS 12.4 及以上版本
* ✅ 极简界面，专注于音乐播放体验
* ✅ 轻量级设计 - arm64 版本仅 500KB
* ✅ 极低的系统资源占用，优化的 CPU 和内存使用
* ✅ 支持播放列表功能，可按播放次数顺序排序
* ✅ 喜欢歌曲标记功能，快速找到您喜爱的音乐
* ✅ 支持喜欢歌单的导入导出

## 格式支持说明

Hex Player 使用 AVFoundation 进行音频解码，支持大多数常见音频格式。由于保持软件简洁性的理念，未集成额外的解码库，因此：

* 部分非常见格式如 opus、ogg 等可能存在兼容性问题
* 如需更广泛的格式支持，建议使用集成 ffmpeg 等第三方解码库的播放器

## 更新计划

开发重点将放在：

* 🛠️ Bug 修复
* ⚡ 性能优化

## 反馈与支持

如有问题或建议，请通过 GitHub Issues 提交反馈。
