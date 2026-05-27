# tidbx-ha-toolkit

平凯 V7.1.9 两节点敏捷模式一键部署与高可用测试工具。

## 功能特性

- **一键安装** Docker + Docker Compose 基础环境（支持 CentOS/Ubuntu）
- **一键部署** 两节点敏捷模式 TiDB 集群（含脚本仲裁）
- **一键配置** Keepalived + VIP 高可用
- **自动化 HA 测试**：节点重启、网络延迟、数据损坏、业务模拟

---

## 📋 部署前准备

在开始之前，请确保你已准备好以下条件：

### 硬件要求
- **两台 Linux 服务器**（CentOS 7+ / Rocky Linux / Ubuntu 18.04+）
- 每台至少 **4GB 内存**、**2 CPU**
- 两台服务器之间 **网络互通**（能互相 ping 通）

### 软件要求
- Root 权限（需要 sudo）
- 平凯 tidbx Docker 镜像文件（`tidbx-719.tar`），请联系平凯工程师获取

### 网络规划

你需要提前确定以下网络信息（后面填写配置时会用到）：

| 信息 | 示例 | 说明 |
|------|------|------|
| Node1 IP | 192.168.2.24 | 第一台服务器的 IP 地址 |
| Node2 IP | 192.168.2.25 | 第二台服务器的 IP 地址 |
| VIP（虚拟 IP） | 192.168.2.100 | 客户端连接用的浮动 IP，必须和两台服务器在同一网段且未被占用 |
| 网卡名称 | ens33 | 通过 `ip addr` 命令查看，通常是 ens33、eth0 等 |

> 💡 **如何查看 IP 和网卡名称？** 登录服务器后执行 `ip addr`，找到你用来通信的网卡和对应的 IP 地址。

---

## 🚀 快速开始（5 步完成部署）

### 第 1 步：下载并上传工具包

将 `tidbx-ha-toolkit` 项目目录上传到两台服务器的 `/home/tidb/` 下。

如果你是从 GitHub 获取的：
```bash
# 在两台服务器上分别执行
git clone https://github.com/michaelliuyuan/tidbx-ha-toolkit.git /home/tidb/tidbx-ha-toolkit
```

如果是手动上传：
```bash
# 确保两台服务器上都有这个目录
/home/tidb/tidbx-ha-toolkit/
```

### 第 2 步：准备离线安装包（推荐）

如果服务器无法访问外网，需要准备离线安装包。在两台服务器上创建离线包目录：

```bash
mkdir -p /home/tidb/offline/docker
mkdir -p /home/tidb/offline/docker-compose
```

然后将以下文件放到对应目录：

```
/home/tidb/offline/
├── docker/              ← Docker 离线安装包（.rpm 或 .deb 文件）
├── docker-compose/      ← Docker Compose 二进制文件（docker-compose）
└── tidbx-719.tar        ← 平凯镜像文件（直接放在 offline/ 下）
```

> 💡 **如何获取离线包？** Docker RPM/DEB 包可从 <https://download.docker.com/linux/> 下载；Docker Compose 二进制可从 <https://github.com/docker/compose/releases> 下载。

### 第 3 步：编辑配置文件

**在 Node1（Master 节点）上：**

```bash
cd /home/tidb/tidbx-ha-toolkit

# 复制配置模板
cp config/node1.env.example config/node1.env

# 用文本编辑器编辑
vi config/node1.env
```

编辑以下关键参数（其他参数保持默认即可）：

```bash
# ===== 必须修改的参数 =====
NODE_ROLE=master              # 保持 master
NODE_IP=192.168.2.24          # ← 改为 Node1 的实际 IP
PEER_IP=192.168.2.25          # ← 改为 Node2 的实际 IP
NIC=ens33                     # ← 改为实际网卡名称（通过 ip addr 查看）
VIP=192.168.2.100             # ← 改为你规划的虚拟 IP
TIDBX_IMAGE_FILE=/home/tidb/offline/tidbx-719.tar  # ← 镜像文件路径
```

**在 Node2（Backup 节点）上：**

```bash
cd /home/tidb/tidbx-ha-toolkit

# 复制配置模板
cp config/node2.env.example config/node2.env

# 用文本编辑器编辑
vi config/node2.env
```

```bash
# ===== 必须修改的参数 =====
NODE_ROLE=backup              # 保持 backup
NODE_IP=192.168.2.25          # ← 改为 Node2 的实际 IP
PEER_IP=192.168.2.24          # ← 改为 Node1 的实际 IP
NIC=ens33                     # ← 改为实际网卡名称
VIP=192.168.2.100             # ← 与 Node1 相同的 VIP
TIDBX_IMAGE_FILE=/home/tidb/offline/tidbx-719.tar  # ← 镜像文件路径
```

> ⚠️ **重要提示**：两个节点的 `NODE_IP` 和 `PEER_IP` 是**互换**的，`VIP` 必须**相同**。

### 第 4 步：执行一键部署

**先在 Node1 上执行部署（Master 节点先启动）：**

```bash
cd /home/tidb/tidbx-ha-toolkit

# 离线安装模式（推荐）
sudo bash deploy/deploy-cluster.sh --env config/node1.env --offline-dir /home/tidb/offline/docker

# 如果服务器可以访问外网，也可以用在线模式
sudo bash deploy/deploy-cluster.sh --env config/node1.env
```

部署脚本会自动完成以下操作（无需手动干预）：
1. ✅ 安装 Docker 和 Docker Compose
2. ✅ 加载 tidbx Docker 镜像
3. ✅ 创建数据目录（/data/tidb/）
4. ✅ 生成 PD、TiKV、TiDB 配置文件
5. ✅ 安装并配置 Keepalived（VIP 自动绑定）
6. ✅ 启动 TiDB 集群容器

**等待 Node1 部署完成后，再在 Node2 上执行：**

```bash
cd /home/tidb/tidbx-ha-toolkit

sudo bash deploy/deploy-cluster.sh --env config/node2.env --offline-dir /home/tidb/offline/docker
```

> ⚠️ **重要**：**必须先完成 Node1 的部署，再部署 Node2**。两个节点会自动组成集群。

### 第 5 步：验证集群

在任意节点上执行：

```bash
cd /home/tidb/tidbx-ha-toolkit
bash deploy/verify.sh --env config/node1.env
```

如果看到所有检查项都显示 ✅，说明部署成功！

你也可以手动验证：

```bash
# 1. 检查容器是否运行
sudo docker ps
# 应该看到一个名为 tidb-node1 的容器，状态为 Up

# 2. 检查 VIP 是否生效
ip addr show | grep 192.168.2.100
# Master 节点上应该能看到 VIP

# 3. 尝试连接数据库
mysql -h 192.168.2.100 -P 4000 -u root -e "SELECT 1"
# 如果返回 1，说明集群正常工作
```

---

## 🧪 运行高可用（HA）测试

部署成功后，可以运行自动化测试来验证集群的高可用能力。

### 一键运行全部测试

在 Master 节点（Node1）上执行：

```bash
cd /home/tidb/tidbx-ha-toolkit
sudo bash ha-test/run-all.sh --env config/node1.env
```

这会自动运行以下所有测试场景，并生成测试报告：

### 测试场景说明

#### 1. 节点重启测试
模拟服务器关机/重启场景：
- **Master 关机** → VIP 自动漂移到 Backup 节点 → 数据库继续可用 → Master 恢复后 VIP 自动漂回
- **Backup 关机** → VIP 保持在 Master → Master 恢复后集群自动恢复同步

#### 2. 网络延迟测试
模拟网络抖动场景：
- **1 秒延迟** → 集群保持同步复制（SYNC），数据一致
- **10 秒延迟** → 集群自动降级为异步复制（ASYNC），数据库仍可用
- 延迟清除 → 集群自动恢复同步

#### 3. 数据损坏测试
模拟存储故障场景：
- 删除 Backup 节点 TiKV 数据目录 → 集群降级但 Master 仍可用

#### 4. 业务模拟
在故障注入期间持续写入数据，统计：
- QPS（每秒查询数）
- 响应延迟
- 错误率
- 业务中断时长

### 单独运行某个测试

如果你只想运行某一个测试：

```bash
# 只测试节点重启
sudo bash ha-test/test-node-restart.sh --env config/node1.env

# 只测试网络延迟
sudo bash ha-test/test-network-delay.sh --env config/node1.env

# 只测试数据损坏
sudo bash ha-test/test-data-corrupt.sh --env config/node1.env
```

---

## 📊 监控指南

部署完成后，你可以使用以下命令监控集群运行状态。

### 服务状态监控

**查看 Docker 容器状态：**

```bash
# 查看当前节点容器运行状态
sudo docker ps

# 查看容器日志（排查启动问题）
sudo docker compose -f config/docker-compose/docker-compose_node1.yml logs --tail=100

# 实时跟踪日志
sudo docker compose -f config/docker-compose/docker-compose_node1.yml logs -f
```

**查看 Keepalived 状态：**

```bash
# 检查 Keepalived 服务状态
sudo systemctl status keepalived

# 查看当前角色（MASTER / BACKUP / FAULT）
cat /tmp/keepalived_state

# 查看 VIP 是否在本节点
ip addr show | grep <VIP>

# 示例输出：
#   inet 192.168.2.100/24 scope global ens33
```

**查看各组件进程状态（容器内）：**

```bash
# 进入容器
sudo docker exec -it <container_id> /bin/bash

# 查看 PD 日志
cat /var/lib/data/pd/log/pd.log | tail -50

# 查看 TiKV 日志
cat /var/lib/data/tikv/log/tikv.log | tail -50

# 查看 TiDB 日志
cat /var/lib/data/tidb/log/tidb.log | tail -50
```

### 数据库复制状态监控

**查看复制模式状态（最关键指标）：**

```bash
# 通过 VIP 查看（推荐）
sudo curl -s "http://<VIP>:2379/pd/api/v1/replication_mode/status" | python3 -m json.tool

# 通过节点 IP 查看
sudo curl -s "http://<NODE_IP>:2379/pd/api/v1/replication_mode/status" | python3 -m json.tool

# 正常状态输出：
# {
#   "mode": "even-replicas",
#   "even-replicas": {
#     "state": "SYNC"          ← 同步复制，数据一致
#   }
# }

# 降级状态输出：
# {
#   "mode": "even-replicas",
#   "even-replicas": {
#     "state": "ASYNC",        ← 异步复制，可能存在数据延迟
#     "available_label": "dc2" ← 当前可用区
#   }
# }
```

**查看 PD 集群成员和 Leader：**

```bash
sudo curl -s "http://<VIP>:2379/pd/api/v1/members" | python3 -m json.tool
```

**查看 PD Leader 信息：**

```bash
sudo curl -s "http://<VIP>:2379/pd/api/v1/leader" | python3 -m json.tool
```

**查看集群健康状态：**

```bash
sudo curl -s "http://<VIP>:2379/pd/api/v1/health" | python3 -m json.tool
```

**查看 Store（TiKV 节点）状态：**

```bash
sudo curl -s "http://<VIP>:2379/pd/api/v1/stores" | python3 -m json.tool
```

### 数据库连接验证

```bash
# 通过 VIP 连接（验证高可用）
mysql -h <VIP> -P 4000 -u root -e "SELECT 1"

# 通过节点 IP 连接
mysql -h <NODE1_IP> -P 4000 -u root -e "SELECT 1"
mysql -h <NODE2_IP> -P 4000 -u root -e "SELECT 1"

# 查看数据库版本
mysql -h <VIP> -P 4000 -u root -e "SELECT tidb_version()"
```

### 快速健康检查脚本

可以将以下命令组合为日常巡检脚本：

```bash
#!/bin/bash
VIP="192.168.2.100"
echo "=== 1. Docker 容器状态 ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""
echo "=== 2. Keepalived 角色 ==="
cat /tmp/keepalived_state
echo ""
echo "=== 3. VIP 归属 ==="
ip addr show | grep "$VIP" && echo "VIP 在本节点" || echo "VIP 不在本节点"
echo ""
echo "=== 4. 复制模式状态 ==="
curl -s "http://$VIP:2379/pd/api/v1/replication_mode/status"
echo ""
echo "=== 5. 数据库连接测试 ==="
mysql -h $VIP -P 4000 -u root -e "SELECT 1 AS connection_test" 2>/dev/null && echo "数据库连接正常" || echo "数据库连接失败"
echo ""
echo "=== 6. PD 集群成员 ==="
curl -s "http://$VIP:2379/pd/api/v1/members" | python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'  {m[\"name\"]}: {m[\"client_urls\"]}') for m in data.get('members',[])]" 2>/dev/null
```

### 状态对照表

| 复制状态 | 含义 | 是否需要关注 |
|---------|------|------------|
| `SYNC` | 两节点数据同步一致 | ✅ 正常 |
| `ASYNC` + `available_label=dc1` | Master 可用，Backup 不同步 | ⚠️ Backup 可能离线或网络异常 |
| `ASYNC` + `available_label=dc2` | Backup 可用，Master 不同步 | ⚠️ Master 可能离线或网络异常 |
| 请求超时 / 无响应 | PD 不可用 | ❌ 需要立即排查 |

| Keepalived 角色 | 含义 |
|----------------|------|
| `MASTER` | VIP 在本节点，对外提供服务 |
| `BACKUP` | 备用节点，等待接管 |
| `FAULT` | 故障状态，需排查 |

---

## 📁 项目结构

```
tidbx-ha-toolkit/
├── setup/                    # 环境安装
│   ├── install-docker.sh     # 安装 Docker CE
│   └── install-compose.sh    # 安装 Docker Compose
├── deploy/                   # 集群部署
│   ├── deploy-cluster.sh     # 一键部署入口
│   ├── deploy-keepalived.sh  # Keepalived 配置
│   ├── init-data.sh          # 数据目录初始化
│   ├── load-image.sh         # Docker 镜像加载
│   ├── verify.sh             # 集群状态验证
│   └── cleanup.sh            # 清理集群
├── ha-test/                  # 高可用测试
│   ├── run-all.sh            # 一键全量测试
│   ├── test-node-restart.sh  # 节点重启测试
│   ├── test-network-delay.sh # 网络延迟测试
│   ├── test-data-corrupt.sh  # 数据损坏测试
│   ├── test-business.sh      # 业务模拟
│   └── lib/common.sh         # 测试框架函数库
├── config/                   # 配置模板
│   ├── node1.env.example     # Node1 配置
│   ├── node2.env.example     # Node2 配置
│   ├── template/             # PD/TiKV/TiDB/Keepalived 配置
│   └── docker-compose/       # Docker Compose 文件
└── docs/                     # 文档
```

## ⚙️ 配置参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `NODE_ROLE` | 节点角色 (master/backup) | master |
| `NODE_IP` | 本机 IP | - |
| `PEER_IP` | 对端 IP | - |
| `NIC` | 网卡名称 | ens33 |
| `VIP` | 虚拟 IP | - |
| `VIP_PREFIX` | VIP 子网前缀 | 24 |
| `KEEPALIVED_PRIORITY` | Keepalived 优先级 | 100/99 |
| `PD_CLI_PORT` | PD 客户端端口 | 2379 |
| `PD_PEER_PORT` | PD 对等端口 | 2380 |
| `TIKV_PORT` | TiKV 端口 | 20160 |
| `TIDB_PORT` | TiDB MySQL 端口 | 4000 |
| `TIDBX_IMAGE` | Docker 镜像 | tidbx:v7.1.9-0.0 |
| `TIDBX_IMAGE_FILE` | 镜像 tar 文件路径 | tidbx-719.tar |
| `CPU_LIMIT` | 容器 CPU 限制 | 2 |
| `MEMORY_LIMIT` | 容器内存限制 | 4G |

---

## 🧹 清理与卸载

### 停止集群（保留数据）

```bash
sudo bash deploy/cleanup.sh --env config/node1.env
```

### 完全清理（删除所有数据）

```bash
sudo bash deploy/cleanup.sh --env config/node1.env --remove-data
```

> ⚠️ `--remove-data` 会删除 `/data/tidb/var/` 下所有数据，操作不可逆！

---

## ❓ 常见问题

### Q: 部署脚本报错 "Docker 未安装"
**A:** 使用离线安装模式：`--offline-dir /home/tidb/offline/docker`

### Q: 部署脚本报错 "tidbx image not found"
**A:** 确保 `tidbx-719.tar` 文件已放到两台服务器上，并在 `.env` 文件中配置了正确的 `TIDBX_IMAGE_FILE` 路径。

### Q: 两个节点部署后集群无法组成
**A:** 检查：
1. 两台服务器之间能否互相 ping 通
2. 防火墙是否放通了 2379、2380、20160、20180、4000、10080 端口
3. Node1 的 `PEER_IP` 是否指向 Node2 的 IP，反之亦然

### Q: VIP 无法访问
**A:** 检查：
1. VIP 是否和两台服务器在同一网段
2. VIP 是否被其他设备占用
3. Keepalived 是否正常运行：`sudo systemctl status keepalived`
4. 在 Master 节点执行 `ip addr show` 查看 VIP 是否绑定

### Q: 数据库连接失败
**A:** 检查：
1. 容器是否正常运行：`sudo docker ps`
2. 通过节点 IP 连接测试：`mysql -h <NODE_IP> -P 4000 -u root -e "SELECT 1"`
3. 查看复制模式状态是否正常

### Q: 如何查看日志排查问题
**A:** 
```bash
# 查看容器日志
sudo docker compose -f config/docker-compose/docker-compose_node1.yml logs --tail=100

# 查看 Keepalived 日志
sudo journalctl -u keepalived --since "10 minutes ago"
```

---

## License

Apache 2.0
