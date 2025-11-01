#!/usr/bin/env bash
set -euo pipefail

export JAVA_HOME=/opt/java/openjdk
export HADOOP_HOME=/opt/hadoop-3.4.1
export SPARK_HOME=/opt/spark-4.0.1-bin-hadoop3
export PATH="$PATH:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${SPARK_HOME}/bin:${SPARK_HOME}/sbin"

HDFS_BIN="${HADOOP_HOME}/bin/hdfs"
YARN_BIN="${HADOOP_HOME}/bin/yarn"

log() { echo "[$(date +'%F %T')] [worker] $*"; }

until curl -fsS http://master:9870/ >/dev/null; do
  log "Waiting for master..."
  sleep 3
done

log "Starting HDFS DataNode..."
"${HDFS_BIN}" --daemon start datanode

log "Starting YARN NodeManager..."
"${YARN_BIN}" --daemon start nodemanager

: "${SPARK_WORKER_CORES:=2}"
: "${SPARK_WORKER_MEMORY:=2g}"
log "Starting Spark Worker cores=${SPARK_WORKER_CORES} mem=${SPARK_WORKER_MEMORY}..."
"${SPARK_HOME}/sbin/start-worker.sh" "spark://master:7077" \
  --cores "${SPARK_WORKER_CORES}" \
  --memory "${SPARK_WORKER_MEMORY}"

trap 'log "Shutting down..."; ${SPARK_HOME}/sbin/stop-worker.sh; '"${YARN_BIN}"' --daemon stop nodemanager; '"${HDFS_BIN}"' --daemon stop datanode' SIGTERM SIGINT
tail -f /opt/hadoop/logs/* /opt/spark/logs/* 2>/dev/null &
wait
