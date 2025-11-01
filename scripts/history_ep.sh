#!/usr/bin/env bash
set -euo pipefail

export JAVA_HOME=/opt/java/openjdk
export HADOOP_HOME=/opt/hadoop-3.4.1
export SPARK_HOME=/opt/spark-4.0.1-bin-hadoop3
# export HADOOP_HOME=/opt/hadoop
# export SPARK_HOME=/opt/spark
export PATH="$PATH:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${SPARK_HOME}/bin:${SPARK_HOME}/sbin"

HDFS_BIN="${HADOOP_HOME}/bin/hdfs"

log() { echo "[$(date +'%F %T')] [history] $*"; }

until curl -fsS http://master:9870/ >/dev/null; do
  log "Waiting for master..."
  sleep 3
done

"${HDFS_BIN}" dfs -mkdir -p /spark-logs || true
"${HDFS_BIN}" dfs -chmod -R 777 /spark-logs || true

export SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=${SPARK_EVENTLOG_DIR:-hdfs://namenode:9000/spark-logs} -Dspark.history.ui.port=18080"

log "Starting Spark History Server..."
"${SPARK_HOME}/sbin/start-history-server.sh"

trap 'log "Shutting down..."; ${SPARK_HOME}/sbin/stop-history-server.sh' SIGTERM SIGINT
tail -f /opt/spark/logs/* 2>/dev/null &
wait
