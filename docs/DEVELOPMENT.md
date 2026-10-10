# 开发与验证

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `macos/` | Swift/AppKit 窗口、原生力度事件、本地存储、WebKit 内置资源加载 |
| `web/` | 离线游戏、启动弹窗、原生消息桥和桌面界面 |
| `web-original/` | 原样保存的网页已发布前端文件，是适配脚本的输入 |
| `scripts/generate_web.py` | 从保留的发布脚本生成适配后的游戏，断言替换位置 |
| `scripts/build.py` | 编译两种架构、生成图标与签名、打包三份 ZIP 和校验文件 |
| `scripts/test.py` | 运行 JavaScript 行为测试与 Swift 存储测试 |
| `tests/` | 力度物理、键鼠控制、启动门槛、设置升级和成绩持久化测试 |
| `docs/provenance/` | 下载文件摘要和原始资源探测记录 |
| `docs/images/` | 原生 App 的启动与游戏画面 |
| `docs/releases/` | 版本发布说明 |

`build/` 与 `dist/` 均被 Git 忽略。安装包通过 GitHub Release 发布，不提交二进制文件到源码历史。

## 构建

在 macOS 上安装 Apple Command Line Tools 和 Python 3 后，从仓库根目录运行：

```sh
python3 scripts/build.py
```

脚本使用 `swiftc` 分别编译 arm64 和 x86_64，最低目标系统为 macOS 13。通用版通过 `lipo` 合并两种架构；另生成 Intel 专用 App、三份 ZIP 和 SHA-256 校验值。构建无需联网安装前端依赖。

`web/game.js` 和 `web/original.css` 由适配脚本生成，请修改 `scripts/generate_web.py` 或其他独立适配文件，再重新构建。`web-original/` 应保持原样；摘要见 [下载清单](provenance/download-manifest.json)。

## 输入与离线实现

力度模式使用 AppKit 的独立 `NSEvent.pressure` 事件与 `.primaryGeneric` 配置，读取 0～1 相对力度。普通鼠标事件中的 pressure 字段不用于硬件验证。真实信号验证通过并松开后才允许进入该模式。

键鼠模式需要用户确认备用提醒，使用独立的空格和鼠标按住状态，沿用原游戏加力、卸力和断裂参数。失焦、暂停与窗口外松开鼠标会清除输入，避免恢复时残留刹车。

页面通过 `WKURLSchemeHandler` 加载 App 内置资源，无需 HTTP 服务。原在线成绩接口和预加载网络代码已移除；CSP 禁止外部连接，导航仅允许内置地址。WebKit 子进程启动仍需要 `network.client` 沙盒权限，因此保留该框架权限；游戏自身不包含在线功能。

本地成绩由 Swift 以 JSON 原子写入应用数据目录，网页采用临时数据存储。最高分按昵称分组，全部保存记录均保留。原数据格式版本 1 的 50% 阈值升级为 100%，其他设置和成绩不变；版本 2 中明确选定的 50% 会保留。

## 验证

运行行为与存储测试需要 Node.js 18 或更高、Python 3 和 Apple Command Line Tools：

```sh
python3 scripts/test.py
```

可用 `--node /path/to/node` 指定 Node.js。测试覆盖压力与原始键鼠两种制动物理、100 km/h 门槛、断裂与刹停、短按峰值、模式切换、硬件缺失提醒及确认、键鼠独立释放、暂停、输入框、1%/100% 边界、默认值升级、成绩持久化及写入失败。

已构建的 App 还提供原生自检模式：

```sh
'dist/BREaK!BRaKE!BREaK!.app/Contents/MacOS/BreakBrake' --smoke-test
```

请在有图形界面的 macOS 登录会话中运行。自检使用独立临时成绩文件，验证实际 WebGL 渲染、原生消息桥、离线存储、默认 100%、备用提醒和确认、空格/鼠标输入及刹车图标文字边界，输出 `BREAK_SMOKE` JSON 和界面截图。测试数据不会进入正常排行榜。

v1.1.0 已通过当前 Apple Silicon Mac 的 arm64 原生自检及 Rosetta 下的 x86_64 自检，三份 ZIP 的结构、二进制架构与签名验证通过。尚未在实体 Intel Mac 上验证，也未逐一验证所有 macOS 13 及以上版本。真实触控板手感需要使用兼容设备进行人工体验。

App 使用本地 ad-hoc 签名，没有 Developer ID 签名或 Apple 公证。许可证与第三方声明随 App 一同打包到 `Contents/Resources/`。
