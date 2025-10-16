#!/usr/bin/env bash
# Initialize required HDFS dirs/permissions for Hadoop + Spark + MR History.
# Idempotent & configurable via env vars.

set -Eeuo pipefail

# -------- Config (env-overridable) --------
: "${HDFS_HADOOP_USER:=hadoop}"
: "${HDFS_HADOOP_GROUP:=supergroup}"

: "${HDFS_SPARK_USER:=spark}"
: "${HDFS_SPARK_GROUP:=hadoop}" # 若 spark 组就是 hadoop 组；不确定可设为 ${HDFS_SPARK_USER}

: "${HDFS_TMP_DIR:=/tmp}"
: "${HDFS_USER_ROOT:=/user}"
: "${HDFS_USER_HADOOP:=/user/${HDFS_HADOOP_USER}}"
: "${HDFS_USER_SPARK:=/user/${HDFS_SPARK_USER}}"

: "${HDFS_MR_TMP:=/mr-history/tmp}"
: "${HDFS_MR_DONE:=/mr-history/done}"

: "${HDFS_SPARK_LOG_DIR:=/spark-logs}" # spark.eventLog.dir 建议指向此目录

# 策略：chown 给 spark（干净）或公共可写（教学）
# 可设为: "chown" 或 "public"
: "${SPARK_LOG_DIR_POLICY:=chown}"

# -------- Helpers --------
log() { echo "[$(date +'%F %T')] [init-hdfs] $*"; }

hdfs_mkdir_p() { hdfs dfs -mkdir -p "$1" >/dev/null 2>&1 || true; }
hdfs_chmod() { hdfs dfs -chmod "$1" "$2" >/dev/null 2>&1 || true; }
hdfs_chown() { hdfs dfs -chown -R "$1":"$2" "$3" >/dev/null 2>&1 || true; }
hdfs_ls_d() { hdfs dfs -ls -d "$@" 2>/dev/null || true; }

# -------- Wait for HDFS --------
log "Waiting for HDFS NameNode RPC to be available..."
until hdfs dfs -ls / >/dev/null 2>&1; do sleep 1; done
log "HDFS is up."

# -------- Base dirs (/tmp, MR history) --------
log "Ensuring base temp & MR history dirs..."
hdfs_mkdir_p "${HDFS_TMP_DIR}" "${HDFS_MR_TMP}" "${HDFS_MR_DONE}"
# /tmp 与 MR history 建议 1777（粘滞位）
hdfs_chmod 1777 "${HDFS_TMP_DIR}"
hdfs_chmod 1777 "${HDFS_MR_TMP}"
hdfs_chmod 1777 "${HDFS_MR_DONE}"

# -------- /user tree --------
log "Ensuring /user tree and home dirs..."
hdfs_mkdir_p "${HDFS_USER_ROOT}"
hdfs_chmod 755 "${HDFS_USER_ROOT}"

hdfs_mkdir_p "${HDFS_USER_HADOOP}"
hdfs_chown "${HDFS_HADOOP_USER}" "${HDFS_HADOOP_GROUP}" "${HDFS_USER_HADOOP}"

hdfs_mkdir_p "${HDFS_USER_SPARK}"
# 给 spark 自己的家目录
hdfs_chown "${HDFS_SPARK_USER}" "${HDFS_SPARK_GROUP}" "${HDFS_USER_SPARK}" || hdfs_chmod 777 "${HDFS_USER_SPARK}"

# -------- Spark event logs --------
log "Ensuring Spark event log dir: ${HDFS_SPARK_LOG_DIR}"
hdfs_mkdir_p "${HDFS_SPARK_LOG_DIR}"

case "${SPARK_LOG_DIR_POLICY}" in
chown | CHOWN)
  log "Policy=chown → chown ${HDFS_SPARK_USER}:${HDFS_SPARK_GROUP} ${HDFS_SPARK_LOG_DIR}"
  hdfs_chown "${HDFS_SPARK_USER}" "${HDFS_SPARK_GROUP}" "${HDFS_SPARK_LOG_DIR}"
  ;;
public | PUBLIC)
  log "Policy=public → chmod 1777 ${HDFS_SPARK_LOG_DIR}"
  hdfs_chmod 1777 "${HDFS_SPARK_LOG_DIR}"
  ;;
*)
  log "Unknown SPARK_LOG_DIR_POLICY=${SPARK_LOG_DIR_POLICY}, defaulting to chown."
  hdfs_chown "${HDFS_SPARK_USER}" "${HDFS_SPARK_GROUP}" "${HDFS_SPARK_LOG_DIR}"
  ;;
esac

# -------- Summary --------
log "Summary of important dirs:"
hdfs_ls_d / "${HDFS_TMP_DIR}" "${HDFS_MR_TMP}" "${HDFS_MR_DONE}" \
  "${HDFS_USER_ROOT}" "${HDFS_USER_HADOOP}" "${HDFS_USER_SPARK}" \
  "${HDFS_SPARK_LOG_DIR}"

log "Initialization finished."
