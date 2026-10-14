# Windows Cache Cleaner（Windows 一键缓存清理工具）

> 双击即用、带图形界面的 Windows 缓存清理工具，一键释放磁盘临时文件与内存占用。

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

## ✨ 简介

一个轻量、开源的 Windows 缓存清理小程序。无需安装任何第三方软件，双击即可运行，自动请求管理员权限，通过图形界面勾选清理项目，一键完成清理并统计释放的空间。

## 🚀 功能特性

- 🖱️ **一键清理**：双击 `Clear-Cache.bat` 即可启动，自动提权（UAC）
- 🎛️ **图形界面**：基于 WinForms，勾选式操作，界面简洁直观
- 📊 **实时统计**：逐项显示进度，并统计每一项以及总共释放的空间
- 🛡️ **安全可控**：默认只勾选安全项目，危险/有副作用的项目默认不选，执行前二次确认
- 💾 **内存释放**：支持清理待机内存与工作集，缓解内存占用过高的问题
- 📦 **零依赖**：纯 PowerShell + 系统自带组件，不写入注册表、不联网、不驻留后台

## 📸 界面预览

> 将你的截图上传后替换为 `screenshot.png` 即可展示。

```
┌─────────────────────────────────────────────┐
│  Windows 一键缓存清理工具                     │
│  请勾选要清理的项目                            │
│  ☑ 用户临时文件  —— 清理当前用户 %TEMP% ...    │
│  ☑ 系统临时文件  —— 清理 C:\Windows\Temp ...  │
│  ☑ DNS 解析缓存 —— 刷新 DNS 缓存 ...          │
│  ☑ 内存缓存      —— 清理待机内存与工作集 ...   │
│  ☑ 缩略图与图标缓存 —— ...                    │
│  ☑ 浏览器缓存    —— 清理 Edge 与 Chrome ...   │
│  ☐ Windows 更新缓存 —— ...                    │
│  ☐ 预取文件 (Prefetch) —— ...                 │
│  ☐ 回收站        —— 彻底清空回收站 ...         │
│                                   [开始清理]   │
│  进度条 / 日志输出                            │
└─────────────────────────────────────────────┘
```

## 📥 快速开始

1. 下载或克隆本仓库：

   ```bash
   git clone https://github.com/你的用户名/Windows-Cache-Cleaner.git
   ```

2. 双击运行 `Clear-Cache.bat`
3. 在 UAC 弹窗中点击「是」（清理系统缓存需要管理员权限）
4. 勾选要清理的项目，点击「开始清理」
5. 确认后自动执行，底部实时显示释放的空间

## 🧹 支持的清理项目

| 清理项目 | 说明 | 默认勾选 |
| --- | --- | :---: |
| 用户临时文件 | 清理当前用户 `%TEMP%` 目录 | ✅ |
| 系统临时文件 | 清理 `C:\Windows\Temp` | ✅ |
| DNS 解析缓存 | 刷新 DNS（`ipconfig /flushdns`） | ✅ |
| 内存缓存 | 清理待机内存与工作集，释放物理内存 | ✅ |
| 缩略图与图标缓存 | 桌面会短暂闪一下，属正常现象 | ✅ |
| 浏览器缓存 | Edge / Chrome，不影响书签、密码、历史记录 | ✅ |
| Windows 更新缓存 | 下次检查更新时可能需要重新下载 | ❌ |
| 预取文件 (Prefetch) | 可能略微增加启动时间，一般不建议 | ❌ |
| 回收站 | **不可恢复**，请确认无需要保留的文件 | ❌ |

## 🔧 工作原理

- **临时文件清理**：删除 `%TEMP%`、`C:\Windows\Temp`、软件更新下载缓存、浏览器缓存等目录下的文件；正在被占用的文件会自动跳过。
- **内存释放**：调用系统底层接口 `NtSetSystemInformation`（`SystemMemoryListInformation`）执行「清理待机内存」与「清空工作集」，等效于 RAMMap 的 Empty Standby List / Empty Working Set，并对比前后可用内存统计释放量。
- **自提权**：脚本启动时检测当前是否为管理员，若不是则通过 `Start-Process -Verb RunAs` 自动重新以管理员身份运行。

## 🗂️ 文件结构

```
Windows-Cache-Cleaner/
├── Clear-Cache.bat    # 启动器：双击运行，加载脚本
├── Clear-Cache.ps1    # 核心程序：图形界面 + 清理逻辑
└── README.md
```

## ⚠️ 免责声明

- 「回收站」「Windows 更新缓存」「预取文件」默认不勾选，请谨慎使用。
- 清理缓存通常安全，但使用前建议确认没有未保存的工作。
- 内存缓存清理的效果是暂时的，Windows 会在后续使用中重新积累缓存，这是系统的正常设计。

## 📄 许可证

[MIT License](LICENSE)
