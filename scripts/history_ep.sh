#!/usr/bin/env bash
set -euo pipefail

export JAVA_HOME=/opt/java/openjdk

# 统一配置/日志目录（和 master/worker 保持一致）
export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
export HADOOP_LOG_DIR=/opt/hadoop/logs
export MAPRED_LOG_DIR=/opt/hadoop/logs
export SPARK_HOME=/opt/spark-4.0.1-bin-hadoop3
export SPARK_LOG_DIR=/opt/spark/logs
mkdir -p "$HADOOP_LOG_DIR" "$SPARK_LOG_DIR"

# Spark HS 指向 HDFS 事件日志目录 + 指定端口
export SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=hdfs://master:9000/spark-logs \
                           -Dspark.history.ui.port=18080"

# 为了 JDK17 反射兼容（和 master/worker 一致）
OPEN_OPTS="--add-opens=java.base/java.lang=ALL-UNNAMED \
           --add-opens=java.base/java.lang.reflect=ALL-UNNAMED \
           --add-opens=java.base/java.io=ALL-UNNAMED \
           --add-opens=java.base/java.net=ALL-UNNAMED \
           --add-opens=java.base/java.util=ALL-UNNAMED"
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} ${OPEN_OPTS}"

# ---- 启动 Spark History Server（前台）----
export SPARK_NO_DAEMONIZE=1
"$SPARK_HOME"/sbin/start-history-server.sh &

# ---- 启动 MapReduce JobHistory Server（后台守护）----
# 也可前台：直接 `exec mapred historyserver`；此处用守护 + tail 保活
mapred --daemon start historyserver || true

# ---- 保活：持续输出两个日志目录 ----
shopt -s nullglob
touch "$SPARK_LOG_DIR/.keep" "$HADOOP_LOG_DIR/.keep"
tail -n+0 -F "$SPARK_LOG_DIR"/*.out "$SPARK_LOG_DIR"/*.log \
  "$HADOOP_LOG_DIR"/mapred-*-historyserver-*.log \
  "$HADOOP_LOG_DIR/.keep" "$SPARK_LOG_DIR/.keep"
