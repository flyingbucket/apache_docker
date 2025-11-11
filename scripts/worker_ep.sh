#!/usr/bin/env bash
# worker_ep.sh
set -euo pipefail

unset YARN_CONF_DIR || true
export JAVA_HOME=/opt/java/openjdk
export HADOOP_HOME=/opt/hadoop-3.4.1
export SPARK_HOME=/opt/spark-4.0.1-bin-hadoop3

# --- 自动探测 Hadoop 配置目录（与 master 同步策略） ---
if [ -f /opt/hadoop-3.4.1/etc/hadoop/core-site.xml ]; then
  export HADOOP_CONF_DIR=/opt/hadoop-3.4.1/etc/hadoop
elif [ -f /opt/hadoop/etc/hadoop/core-site.xml ]; then
  export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
else
  echo "[worker] FATAL: cannot find core-site.xml under /opt/hadoop-3.4.1/etc/hadoop or /opt/hadoop/etc/hadoop" >&2
  ls -l /opt/hadoop-3.4.1/etc || true
  ls -l /opt/hadoop/etc || true
  exit 1
fi

export PATH="$PATH:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${SPARK_HOME}/bin:${SPARK_HOME}/sbin"

HDFS_BIN="${HADOOP_HOME}/bin/hdfs"
YARN_BIN="${HADOOP_HOME}/bin/yarn"
log() { echo "[$(date +'%F %T')] [worker] $*"; }

# --- 本地数据目录（需与 hdfs-site.xml 的 dfs.datanode.data.dir 对齐）---
mkdir -p /hadoop/dfs/data

# --- 等待 NameNode Web 就绪（也可换成 RPC 端口探测）---
until curl -fsS http://master:9870/ >/dev/null; do
  log "Waiting for master (NameNode UI at :9870)..."
  sleep 3
done

# --- 可选：打印一下默认 FS，排查配置是否命中 ---
${HDFS_BIN} getconf -confKey fs.defaultFS || true

# --- 启动 DataNode ---
log "Starting HDFS DataNode..."
"${HDFS_BIN}" --daemon start datanode || log "WARN: DataNode start returned non-zero"

# --- 启动 NodeManager ---
log "Starting YARN NodeManager..."
"${YARN_BIN}" --daemon start nodemanager || log "WARN: NodeManager start returned non-zero"

# --- 启动 Spark Worker ---
: "${SPARK_WORKER_CORES:=2}"
: "${SPARK_WORKER_MEMORY:=2g}"
log "Starting Spark Worker cores=${SPARK_WORKER_CORES} mem=${SPARK_WORKER_MEMORY}..."
"${SPARK_HOME}/sbin/start-worker.sh" "spark://master:7077" \
  --cores "${SPARK_WORKER_CORES}" \
  --memory "${SPARK_WORKER_MEMORY}"

# --- 优雅退出：只停掉本脚本实际拉起的服务 ---
trap '
  log "Shutting down...";
  ${SPARK_HOME}/sbin/stop-worker.sh || true;
  ${YARN_BIN} --daemon stop nodemanager || true;
  ${HDFS_BIN} --daemon stop datanode || true;
  exit 0
' SIGTERM SIGINT

# --- 日志保活 ---
shopt -s nullglob
mkdir -p "$HADOOP_HOME/logs" "$SPARK_HOME/logs"
touch "$HADOOP_HOME/logs/.keep" "$SPARK_HOME/logs/.keep"
tail -F "$HADOOP_HOME"/logs/* "$SPARK_HOME"/logs/* "$HADOOP_HOME/logs/.keep" "$SPARK_HOME/logs/.keep"
