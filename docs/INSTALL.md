# NotchSlip 安装说明

一个藏在 MacBook 刘海里的极简记事本。菜单栏常驻，没有 Dock 图标。

## 系统要求

- macOS 14 或更新（macOS 26 上开发验证）
- Apple Silicon 或 Intel 都可以（安装包是通用二进制）
- 不需要 Xcode，不需要辅助功能 / 屏幕录制等任何权限

## 安装（zip 包）

1. 解压 `NotchSlip-0.2.0.zip`
2. 把 `NotchSlip.app` 拖进「应用程序」文件夹
3. 双击打开。如果系统提示「无法验证开发者」：
   - 在 App 上 **右键 → 打开**，再点「打开」；或
   - 打开「系统设置 → 隐私与安全性」，在页面底部点「仍要打开」
   - 仍然不行的话，在终端执行一次：
     ```bash
     xattr -dr com.apple.quarantine /Applications/NotchSlip.app
     ```
     然后再双击打开
4. 启动后 Dock 里没有图标，**菜单栏会出现一个铅笔小图标**，说明它已经在运行
5. 把鼠标移到刘海，面板就会展开

> 用 U 盘、`scp`/`rsync` 直接拷贝（不经过浏览器下载或 AirDrop）通常不会带上隔离标记，双击即可打开。

## 设为开机启动

- 先把 App 放在 `/Applications`
- 点菜单栏铅笔图标 → 「开机时启动」
- 如果这一项报错，用系统兜底：**系统设置 → 通用 → 登录项 → 「+」→ 选择 NotchSlip**

## 迁移笔记

笔记就是一个纯文本文件：

```
~/Library/Application Support/NotchSlip/notes.txt
```

- 旧 Mac 上把这个文件拷到新 Mac 的同一路径即可
- 如果不是用「迁移助理」整机迁移，先在新 Mac 上启动一次 App，它会自动建好目录
- 窗口大小存在 `~/Library/Preferences/com.notchslip.app.plist`，不迁也没关系

## 卸载

1. 菜单栏图标 → 退出
2. 删除 `/Applications/NotchSlip.app`
3. 可选：删除 `~/Library/Application Support/NotchSlip` 和 `~/Library/Preferences/com.notchslip.app.plist`

## 为什么会有安全提示

这个包是在本地编译、用 ad-hoc 签名打的，没有走 Apple 的公证（notarization）。
公证需要付费开发者账号（Apple Developer Program），所以从网络传到新 Mac 时，
Gatekeeper 会要求你手动确认一次。上面的「右键 → 打开」或 `xattr` 命令就是为了这一步，
只需要做一次。

如果你有开发者账号，配置 Developer ID 签名 + 公证后，别人安装就完全无提示。
`scripts/build-dist.sh` 里已经预留了打包流程，加上签名和 `notarytool` 即可。

## 从源码重新构建（可选）

需要 Command Line Tools（`xcode-select --install`）：

```bash
./scripts/build.sh        # 只给本机用（arm64）
./scripts/build-dist.sh   # 通用二进制 + zip 安装包
```

`build-dist.sh` 在普通终端里还会额外生成一个 `.dmg`；如果环境里 `hdiutil` 不可用，会自动跳过，只出 zip。
