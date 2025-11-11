#!/usr/bin/env bash
# master_ep.sh
set -euo pipefail

unset YARN_CONF_DIR || true
export JAVA_HOME=/opt/java/openjdk
export HADOOP_HOME=/opt/hadoop-3.4.1
export SPARK_HOME=/opt/spark-4.0.1-bin-hadoop3

# --- 自动探测 conf 目录 ---
if [ -f /opt/hadoop-3.4.1/etc/hadoop/core-site.xml ]; then
  export HADOOP_CONF_DIR=/opt/hadoop-3.4.1/etc/hadoop
elif [ -f /opt/hadoop/etc/hadoop/core-site.xml ]; then
  export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
else
  echo "[master] FATAL: cannot find core-site.xml under /opt/hadoop-3.4.1/etc/hadoop or /opt/hadoop/etc/hadoop" >&2
  ls -l /opt/hadoop-3.4.1/etc || true
  ls -l /opt/hadoop/etc || true
  exit 1
fi

export PATH="$PATH:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${SPARK_HOME}/bin:${SPARK_HOME}/sbin"

HDFS_BIN="${HADOOP_HOME}/bin/hdfs"
YARN_BIN="${HADOOP_HOME}/bin/yarn"
log() { echo "[$(date +'%F %T')] [master] $*"; }

# --- 等配置就绪（用变量，不要硬编码）---
test -f "${HADOOP_CONF_DIR}/core-site.xml"
test -f "${HADOOP_CONF_DIR}/hdfs-site.xml" || true

mkdir -p /hadoop/dfs/name
if [ -z "$(ls -A /hadoop/dfs/name 2>/dev/null || true)" ]; then
  log "Formatting NameNode..."
  "${HDFS_BIN}" namenode -format -force -nonInteractive
fi

log "Starting HDFS NameNode..."
"${HDFS_BIN}" --daemon start namenode || log "WARN: NN start returned non-zero (usually ok)"

log "Starting YARN ResourceManager..."
if ! "${YARN_BIN}" --daemon start resourcemanager; then
  log "ERROR: ResourceManager start failed, dumping last log ..."
  sleep 2
  LOG_DIR="${HADOOP_LOG_DIR:-$HADOOP_HOME/logs}"
  LOG_FILE=$(ls -t "$LOG_DIR"/yarn-*-resourcemanager-*.log 2>/dev/null | head -1 || true)
  [ -n "$LOG_FILE" ] && tail -n 200 "$LOG_FILE"
fi

# 可选：等 NN 进入正常状态
"${HDFS_BIN}" dfsadmin -safemode wait || true

log "Preparing HDFS directories..."
"${HDFS_BIN}" dfs -mkdir -p /tmp /user/root /spark-logs || true
"${HDFS_BIN}" dfs -chmod 1777 /tmp || true
"${HDFS_BIN}" dfs -chmod 777 /spark-logs || true

log "Starting Spark Master..."
"${SPARK_HOME}/sbin/start-master.sh" --host master --port 7077 --webui-port 8080

log "UIs: NN http://master:9870, RM http://master:8088, Spark Master http://master:8080"

# --- 正确的优雅退出：停掉我们真正启动的服务 ---
trap '
  log "Shutting down...";
  ${SPARK_HOME}/sbin/stop-master.sh || true;
  ${YARN_BIN} --daemon stop resourcemanager || true;
  ${HDFS_BIN} --daemon stop namenode || true;
  exit 0
' SIGTERM SIGINT

# 日志保活
shopt -s nullglob
mkdir -p "$HADOOP_HOME/logs" "$SPARK_HOME/logs"
touch "$HADOOP_HOME/logs/.keep" "$SPARK_HOME/logs/.keep"
tail -F "$HADOOP_HOME"/logs/* "$SPARK_HOME"/logs/* "$HADOOP_HOME/logs/.keep" "$SPARK_HOME/logs/.keep"
