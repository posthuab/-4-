# Fix-XboxLive

修《极限竞速：地平线 4》和 Xbox Live 在线模式连不上的 PowerShell 脚本，主要面向国内网络环境。

地平线 4 在线模式报 `0x89235108` 之后，我把 IPv6、Teredo、网络位置、Xbox 服务、系统时间挨个排查了一遍，发现这几个地方都可能出问题，而且经常是一起坏。这个脚本就是把这些修复步骤打包，一键跑完，省得每次手动敲命令。

全程只改本地系统配置，不下载、不安装任何第三方软件，也不访问外部网址。

## 背景

在中国大陆地区，地平线 4 等依赖 Xbox Live 的游戏经常出现在线模式无法使用的情况，报错常见为：

- `无法与 Xbox Live 服务器连接`
- 服务器 ID 失败 `0x89235108`（XAL `E_XAL_UIREQUIRED`，认证需要用户交互）
- 连接质量失败 `0x80600001`

这类问题的成因通常是系统层面的配置异常，而不是游戏本身损坏。常见诱因包括：

- IPv6 组件被禁用（注册表 `DisabledComponents` 或网卡 IPv6 绑定）
- Teredo 隧道处于 `disabled` / `offline` 状态
- 网络位置被误设为「公用网络」（Public），阻止入站 P2P 与 Teredo 隧道
- Xbox 相关服务未运行、或启动类型为「手动」
- 系统时间不同步（默认 NTP `time.windows.com` 在国内难以连通）
- Xbox 认证凭据损坏（token 过期或卡死）

## 快速开始

1. 将 `Fix-XboxLive.bat` 与 `Fix-XboxLive.ps1` 放在同一目录。
2. 双击运行 `Fix-XboxLive.bat`（会自动请求管理员权限，UAC 弹窗点「是」）。
3. 等待脚本执行完毕。
4. **重启电脑**，使 IPv6 与 Teredo 的改动完全生效。

也可以直接在管理员 PowerShell 中运行：

```powershell
.\Fix-XboxLive.ps1
```

## 修复内容

| 步骤 | 操作 | 说明 |
| --- | --- | --- |
| 1 | 启用 IPv6 组件 | 注册表 `DisabledComponents` 置 0，并启用所有网卡的 IPv6 绑定 |
| 2 | 配置 Teredo | 设为 `enterpriseclient` 模式，规避「托管网络」限制 |
| 3 | 网络位置 | 将有 Internet 连接的配置文件改为「专用网络」（Private） |
| 4 | Xbox 服务 | `XblAuthManager` 等 7 个服务设为「自动」并立即启动 |
| 5 | 时间同步 | 改用国内 NTP（`ntp.aliyun.com` / `ntp.tencent.com`）并强制同步 |
| 6 | 清理认证凭据 | 清除 Xbox Identity Provider 缓存与 `Xbl` 凭据（可选） |

## 命令行参数

| 参数 | 作用 |
| --- | --- |
| （无） | 执行步骤 1–5 |
| `-ResetAuth` | 追加执行步骤 6（清除认证凭据，下次进游戏需重新登录） |
| `-SkipTeredo` | 跳过步骤 1–2（Teredo / IPv6） |
| `-SkipTimeSync` | 跳过步骤 5（时间同步） |

示例：

```powershell
.\Fix-XboxLive.ps1 -ResetAuth
.\Fix-XboxLive.ps1 -SkipTeredo -SkipTimeSync
```

## 注意事项

- 脚本需要**管理员权限**，否则会直接报错退出。
- 步骤 6（`-ResetAuth`）会清除 Xbox 登录凭据，之后需要重新登录 Xbox / Microsoft 账户。
- 若修复后 NAT 类型仍为「严格」或「不可用」，问题可能出在路由器或运营商侧（需开启 UPnP 或申请公网 IP），脚本无法处理。
- 脚本可重复运行，各步骤均为幂等操作。

## 免责声明

本脚本会修改系统的网络与服务配置。使用前请确认理解上述改动。作者不对因使用本脚本造成的任何损失负责。
