# Sirius

> **外接显示器时，自动变暗 MacBook 屏幕的原生轻量工具。**  
> 移开视线时深度暗淡降温省电，光标划回时瞬时唤醒，守护专注心流与屏幕寿命。

[English](README.md) · **简体中文**

[![Release](https://img.shields.io/github/v/release/AlphaLeonX/yaology-sirius?style=flat-square&color=38bdf8)](https://github.com/AlphaLeonX/yaology-sirius/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple)](https://github.com/AlphaLeonX/yaology-sirius)
[![License](https://img.shields.io/badge/License-MIT-emerald?style=flat-square)](LICENSE)

[🌐 访问官网 (sirius.yaology.com)](https://sirius.yaology.com) · [⬇️ 下载最新版](https://github.com/AlphaLeonX/yaology-sirius/releases/latest/download/Sirius-latest.dmg)

---

## 🎯 为什么需要 Sirius？解决什么痛点？

在使用 MacBook 外接大屏幕显示器办公或敲代码时，大部分人往往面临两难：

1. **双屏干扰视线**：主视野在外接大屏上，但旁边的 MacBook 屏幕依然全亮，余光频频受到色彩与动态画面干扰，难以长时间深度专注。
2. **合盖（Clamshell）体验糟糕**：
   - 失去了 MacBook 原生的顺滑触控板与 Touch ID 指纹解锁；
   - 键盘区域的辅助散热通道被堵住，机身更容易发热降频。
3. **不合盖又费电发热**：屏幕常亮白白消耗电池、增加被动散热压力，长时间高亮度还会加剧屏幕老化。
4. **市面同类软件大多是“伪调光”**：市面上很多调光软件只是在屏幕上**盖了一层半透明黑色窗口**，屏幕背光依然 100% 全开，既不降温也不省电，还会干扰截图和色彩显示。

---

## ✨ 核心特性与技术方案

### 1. 真实硬件级背光调节 (Hardware PWM)
Sirius 直接调用 macOS 显示器硬件接口控制内置屏幕的物理背光芯片：
- **真降温、真省电**：屏幕背光从物理层降低至微光，机身显著降温，延长电池续航与屏幕背光寿命；
- **不污染截图**：由于没有覆盖任何虚拟图层，截屏与色彩管理不受任何干扰。

### 2. 毫秒级自适应光标感知
- **划入即刻唤醒**：光标一旦移入 MacBook 屏幕，**0 秒等待、0.15 秒极速淡入**，眼睛看过去时亮度已完全恢复；
- **划出防抖冷却**：光标移回外接大屏后，静默等待 3 秒（防误触抖动），确认离开后以 0.4 秒平滑渐隐变暗。

### 3. 微光潜航底噪 (Ambient Floor)
- 默认保持 12% 微光（支持 0%~30% 自由微调），避免彻底黑屏带来的“断连感”或死机误解；
- 微信、飞书、邮件等通知弹窗依然保有辨识轮廓。

### 4. 真正零权限要求 (Zero-Permission)
- 采用原生系统级光标坐标检测与 Carbon 热键机制；
- **无需向系统申请“辅助功能”、“屏幕录制”或“输入监视”等敏感隐私权限**；
- 纯 Swift 原生打造，常驻内存仅 ~15MB，CPU 占用日常趋近 0.00%。

### 5. 灵活的快捷操作
- **全局热键**：按下 `⌥ + S`（Option + S）随时快速切换调光 / 恢复常亮；
- **定时暂停**：支持一键“暂停 30 分钟 / 1 小时”，开会或展示时无需临时退出软件。

---

## ⬇️ 下载与安装

### 方式一：直接下载安装包 (.dmg)
前往 [Releases 页面](https://github.com/AlphaLeonX/yaology-sirius/releases/latest) 下载最新的 `Sirius-latest.dmg`，双击后拖入 `Applications` 目录即可。

> **首次打开提示“无法验证开发者”？**  
> 因个人开源作品未购买苹果开发者年费证书，macOS Gatekeeper 可能会弹出拦截提示。只需在终端执行以下命令即可永久解除：
> ```bash
> xattr -cr /Applications/Sirius.app
> ```

### 方式二：终端一键安装
```bash
curl -fsSL https://raw.githubusercontent.com/AlphaLeonX/yaology-sirius/main/scripts/install.sh | bash
```

---

## 🛠️ 从源码编译 (可选)

本项目无任何第三方臃肿依赖，可直接使用系统原生 Swift 编译器构建：

```bash
# 1. 克隆仓库
git clone https://github.com/AlphaLeonX/yaology-sirius.git
cd yaology-sirius

# 2. 本地直接运行调试
make run

# 3. 构建为标准 macOS 应用程序 (.app)
make app
```

---

## ❓ 常见问题 (FAQ)

**Q：为什么外接单屏时 Sirius 默认不生效？**  
A：Sirius 是专为“双屏工作流”设计的护眼专注工具。仅在系统检测到连接了外接显示器且内建屏幕展开时才会自动激活调度；未外接屏幕时，MacBook 保持正常原生亮度模式。

**Q：微光底噪设置为 0% 会发生什么？**  
A：底噪滑块拉到 0% 时，离开 MacBook 屏幕后物理背光将完全熄灭（达到彻底全黑）；若需要保留屏幕轮廓与后台窗口提示，推荐保持默认的 10%~15%。

**Q：为什么不需要任何系统辅助功能权限？**  
A：Sirius 仅利用系统公有事件机制获取当前鼠标在全局屏幕绝对坐标系下的位置，判断光标是否落在内置屏幕矩形范围之内，不监听任何键盘按键内容，也不读取任何屏幕像素，因此无需索取高危系统权限。

---

## 📄 开源协议

本项目采用 [MIT 许可证](LICENSE) 开源。无广告、无内购、无任何网络追踪上报。
