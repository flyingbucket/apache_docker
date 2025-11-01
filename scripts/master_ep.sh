#!/usr/bin/env bash
set -euo pipefail

# ---- 显式声明环境，避免 PATH 丢失 ----
export JAVA_HOME=/opt/java/openjdk
export HADOOP_HOME=/opt/hadoop-3.4.1
export SPARK_HOME=/opt/spark-4.0.1-bin-hadoop3
export PATH="$PATH:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${SPARK_HOME}/bin:${SPARK_HOME}/sbin"

HDFS_BIN="${HADOOP_HOME}/bin/hdfs"
YARN_BIN="${HADOOP_HOME}/bin/yarn"

log() { echo "[$(date +'%F %T')] [master] $*"; }

# 快速自检：看二进制是否存在
if [ ! -x "${HDFS_BIN}" ]; then
  log "ERROR: ${HDFS_BIN} 不存在或不可执行；请在容器内检查 /opt 目录布局："
  log "      ls -l /opt ; ls -l /opt/hadoop ; ls -l /opt/hadoop/bin"
  exit 127
fi

# 等配置文件就绪
test -f /opt/hadoop/etc/hadoop/core-site.xml

# 首次格式化 NN（目录为空才执行）
if [ -z "$(ls -A /hadoop/dfs/name 2>/dev/null || true)" ]; then
  log "Formatting NameNode..."
  "${HDFS_BIN}" namenode -format -force -nonInteractive
fi

# 起 NameNode
log "Starting HDFS NameNode..."
"${HDFS_BIN}" --daemon start namenode

# 起 ResourceManager
log "Starting YARN ResourceManager..."
"${YARN_BIN}" --daemon start resourcemanager

# 准备 HDFS 目录
log "Preparing HDFS directories..."
"${HDFS_BIN}" dfs -mkdir -p /tmp /user/root /spark-logs || true
"${HDFS_BIN}" dfs -chmod -R 1777 /tmp || true
"${HDFS_BIN}" dfs -chmod -R 777 /spark-logs || true

# 起 Spark Master
log "Starting Spark Master..."
"${SPARK_HOME}/sbin/start-master.sh" --host master --port 7077 --webui-port 8080

log "UIs: NN http://master:9870, RM http://master:8088, Spark Master http://master:8080"

trap 'log "Shutting down..."; ${SPARK_HOME}/sbin/stop-master.sh; '"${YARN_BIN}"' --daemon stop resourcemanager; '"${HDFS_BIN}"' --daemon stop namenode' SIGTERM SIGINT
tail -f /opt/hadoop/logs/* /opt/spark/logs/* 2>/dev/null &
wait
