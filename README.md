# tidbx-ha-toolkit

平凯 V7.1.9 两节点敏捷模式一键部署与高可用测试工具。

## 功能特性

- **一键安装** Docker + Docker Compose 基础环境（支持 CentOS/Ubuntu）
- **一键部署** 两节点敏捷模式 TiDB 集群（含脚本仲裁）
- **一键配置** Keepalived + VIP 高可用
- **自动化 HA 测试**：节点重启、网络延迟、数据损坏、业务模拟

## 快速开始

### 1. 准备配置文件

```bash
cd tidbx-ha-toolkit
cp config/node1.env.example config/node1.env
cp config/node2.env.example config/node2.env
```

编辑 `config/node1.env`（Master 节点）和 `config/node2.env`（Backup 节点），填入实际 IP 和网络信息。

### 2. 在两个节点分别部署

**离线安装模式（推荐）:**

将离线安装包放到 `offline/` 目录：
```
offline/
├── docker/           # Docker 离线包 (.rpm/.deb/.tgz)
├── docker-compose/   # Docker Compose 二进制文件
└── tidbx-719.tar     # 平凯镜像文件
```

```bash
# 在 Node 1 执行（离线模式）
sudo bash deploy/deploy-cluster.sh --env config/node1.env --offline-dir ./offline/docker

# 在 Node 2 执行（离线模式）
sudo bash deploy/deploy-cluster.sh --env config/node2.env --offline-dir ./offline/docker
```

**在线安装模式:**

```bash
# 在 Node 1 执行
sudo bash deploy/deploy-cluster.sh --env config/node1.env

# 在 Node 2 执行
sudo bash deploy/deploy-cluster.sh --env config/node2.env
```

### 3. 验证集群

```bash
bash deploy/verify.sh --env config/node1.env
```

### 4. 运行 HA 测试

```bash
cd /root/tidbx-ha-toolkit
sudo bash ha-test/run-all.sh --env config/node1.env
```

## 项目结构

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

## 配置参数说明

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

## HA 测试场景

### 节点重启测试
- Master 关机 → VIP 漂移到 Backup → 复制降级 ASYNC
- Master 恢复 → VIP 漂回 → 复制恢复 SYNC
- Backup 关机 → 复制降级 ASYNC
- Backup 恢复 → 复制恢复 SYNC

### 网络延迟测试
- 1s 延迟 → 复制保持 SYNC
- 10s 延迟 → 复制降级 ASYNC
- 延迟清除 → 复制恢复 SYNC

### 数据损坏测试
- 删除 Backup TiKV 数据 → 验证集群降级

### 业务模拟
- 持续通过 VIP 写入 SQL
- 统计 QPS、延迟、错误率、中断时长

## 清理

```bash
# 停止集群（保留数据）
sudo bash deploy/cleanup.sh --env config/node1.env

# 停止集群（删除数据）
sudo bash deploy/cleanup.sh --env config/node1.env --remove-data
```

## 监控指南

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

## 前置条件

- 两台 Linux 服务器（CentOS 7+ / Ubuntu 18.04+）
- 至少 4GB 内存、2 CPU
- 服务器间网络互通
- Root 权限
- 平凯 tidbx Docker 镜像文件 (`tidbx-719.tar`)

## License

Apache 2.0
