## 公开仓库版注意

本包是可公开推送到 Git 仓库的版本：config.json 里的 UUID 已换成占位符，
不含任何真实凭证。部署时必须在 ZevCloud 服务的 Variables 标签页设置
VLESS_UUID 为真实 UUID（见私有的 zevcloud-node.json），否则节点无法使用。
VLESS_DOMAIN 也可在 Variables 里设置，用于覆盖 WS Host 头。

# ZevCloud 部署包 — VLESS + WebSocket（平台终止 TLS）

## 包里有什么

| 文件 | 说明 |
|---|---|
| `Dockerfile` | ZevCloud Dockerfile 构建。Alpine 3.21 + sing-box v1.14.4（musl 版，版本号钉死，不用 latest）。 |
| `entrypoint.sh` | 容器启动脚本：读平台注入的 `$PORT` 改写监听端口；可选从环境变量覆盖 UUID / WS Host；校验配置后启动 sing-box。 |
| `config.json` | 由舰队 `render.py` 渲染的 sing-box 配置（VLESS + WS，passthrough 模式，无 TLS 块——TLS 由平台终止）。 |
| `README.md` | 本文件。 |
| `.dockerignore` | 构建上下文排除项。 |

## 部署步骤（按 ZevCloud 官方文档）

> **先说清楚一个文档要点**：ZevCloud 文档里「Upload / Drag & Drop」是**静态站**类型（由 Nginx 直接 serving）；带 Dockerfile 的 Web 应用走的是 **Git 仓库 → Web Application 服务**，平台在仓库根目录发现 `Dockerfile` 后自动用 Dockerfile 构建（Build Pack 变成 Dockerfile，Port 从 `EXPOSE` 读取）。所以正确流程是把本包的 4 个文件放进一个 Git 仓库，再到控制台创建服务时指向该仓库；如果控制台里有其他免 Git 的上传入口，以控制台实际提供的为准。

1. 把本包文件推到一个 Git 仓库根目录（或确认控制台的等价上传方式）。
2. 在已建好的项目里 Add Service → Web Application → 选择该仓库，Root Directory 选仓库根目录。
3. 确认 Build Pack 显示为 **Dockerfile**，Port 显示为 **8080**（来自 `EXPOSE 8080`）。
4. 在 Variables 标签页按需设置（见下）。
5. 点 Deploy。首次构建较慢是正常的（冷构建几分钟）；构建超时 10 分钟（免费档）。
6. 服务状态变为 Running 后即可验证。

## 端口如何取（不要写死端口）

- ZevCloud 在每个服务上注入环境变量 `PORT`。`entrypoint.sh` 在容器启动时用 `jq` 把 `config.json` 的 `listen_port` 改写为 `$PORT`（未注入时 fallback 8080，与 `EXPOSE 8080` 一致）。
- 监听地址是 `::`（即 0.0.0.0 + IPv6），符合文档「不要绑 127.0.0.1」的要求。
- 服务 Port 设置（8080，来自 EXPOSE）必须与容器实际监听端口一致，否则会出现 Bad Gateway。

## Variables 标签页（可选但建议设置）

| 变量 | 必填 | 说明 |
|---|---|---|
| `VLESS_DOMAIN` | 建议 | 设为服务的真实域名（形如 `xxx.zevcloud.app`）。`entrypoint.sh` 会用它覆盖 WS Host 头。**不设的话用的是渲染时写死的域名**，若与真实域名不一致，WS 握手可能路由失败。 |
| `VLESS_UUID` | 建议 | 设为一个新的 UUID。`entrypoint.sh` 会用它覆盖 `config.json` 里渲染时生成的 UUID。这样真实凭证只存在于运行期，不进镜像层（ZevCloud 文档明确要求 secrets 走运行期变量，不要 baked 进镜像）。**改了这个 UUID 后，订阅链接里的 UUID 也要同步更新**（见下）。 |
| `PORT` | 不用设 | 平台自动注入，不要手动设置。 |

> 注意：`config.json` 里自带一个渲染时生成的 UUID（部署包能直接跑起来就靠它）。如果你在 Variables 里设置了 `VLESS_UUID`，运行时以环境变量为准，镜像里那个就作废了；但它仍然留在镜像层里，所以**不要把这个镜像公开分享**。分享节点必须单独部署、独立 UUID（舰队坑 10）。

## 部署后如何验证

1. 控制台 Deployments 页：构建成功、服务状态 Running；日志里应有 sing-box 启动输出，无报错。
2. **浏览器直接打开服务域名看不到网页是正常的**：这是一个 VLESS + WS 节点，不是网站，普通 HTTP 请求不会返回页面。不要据此判死刑。
3. 用客户端验证（以订阅链接为准，见下）：导入订阅，选这个节点，能正常打开网页即通过。
4. 再跑舰队验收脚本（`accept.sh`）做四件套：连通性三次、出口 IP 与地理位置核对、三库交叉定性、真实下载测速。

## 订阅链接怎么来

- 节点记录文件（`zevcloud-node.json`，在部署套件目录里，不在本包内）保存了渲染时生成的 UUID 等信息。
- **部署前先把节点记录里的 `address` / `sni` / `host` 改成服务的真实域名**（目前是渲染时的占位域名），`port` 已是客户端视角的 443，`tls` 已是 true（平台 443 终止 TLS，客户端必须走 TLS）。
- 然后用舰队 `subgen.py` 生成订阅：
  `python3 subgen.py --nodes zevcloud-node.json --out out/`
  手机导入 `out/fleet.txt` 的内容。
- 如果部署时在 Variables 里设置了 `VLESS_UUID`，生成订阅前先把节点记录里的 `uuid` 改成同一个值。

## 免费档与限制（以核实文件为准）

- 每服务 512 MB 内存 / 1 vCPU / 1 GB 存储；带宽不限量；不休眠；每团队 5 个免费服务；无持久卷；无公网 IPv4（平台给 `*.zevcloud.app` 域名 + 自动 SSL）。
- 构建超时 10 分钟；部署后 10 次连续启动崩溃会被自动停服并邮件通知。

## 不确定的地方（部署时以实测为准）

1. **健康检查语义**：文档只说容器必须在配置的 Port 上“有响应”才算通过，未说明是 TCP 连通即可还是要求 HTTP 2xx。sing-box 的 WS 入站对普通 HTTP 请求不会返回 2xx 页面；如果平台要求 HTTP 2xx，首次部署可能在健康检查失败，需要再看日志调整。
2. **“上传部署”路径**：文档中 Upload 类型是静态站；Dockerfile 应用的标准来源是 Git 仓库。本包按 Git 仓库源准备；若控制台对 Web 应用也提供 ZIP 上传，以控制台实际选项为准。
3. **$PORT 与 EXPOSE 的关系**：文档示例是 `ENV PORT=8000` + `EXPOSE 8000` + CMD 用 `${PORT:-8000}`，即运行期 PORT 与 EXPOSE 一致；`entrypoint.sh` 跟随 `$PORT`，若平台注入值与 EXPOSE 不同，以 `$PORT` 为准，服务 Port 设置需同步检查。
4. **出口定性**：ZevCloud 是 PaaS，出口为机房档；是否多库交叉定性为机房以验收为准。
