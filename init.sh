#!/usr/bin/env bash
set -euo pipefail

# Small helper to prepare local directories for the Hadoop+Spark docker compose stack.
# It creates folders, sets ownership to the container's 'hadoop' user, and applies sane permissions.
#
# Usage:
#   ./prepare_hadoop_dirs.sh
#
# Optional env:
#   HADOOP_IMAGE=apache/hadoop:3.4.0    # override image to probe uid/gid
#
# This script is idempotent and safe to re-run.

HADOOP_IMAGE="${HADOOP_IMAGE:-apache/hadoop:3.4.0}"

echo ">> Using image: ${HADOOP_IMAGE}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "!! Required command not found: $1" >&2
    exit 1
  }
}

need_cmd mkdir
need_cmd chmod

if ! command -v docker >/dev/null 2>&1; then
  echo "!! 'docker' not found. Will fallback to UID=1000 GID=100 for chown if needed." >&2
  HADOOP_UID=1000
  HADOOP_GID=100
else
  echo ">> Probing uid/gid for 'hadoop' user in image..."
  if HADOOP_UID=$(docker run --rm "$HADOOP_IMAGE" id -u hadoop 2>/dev/null) &&
    HADOOP_GID=$(docker run --rm "$HADOOP_IMAGE" id -g hadoop 2>/dev/null); then
    echo ">> Container hadoop uid:gid = ${HADOOP_UID}:${HADOOP_GID}"
  else
    echo "!! Failed to probe uid/gid from image. Falling back to 1000:100" >&2
    HADOOP_UID=1000
    HADOOP_GID=100
  fi
fi

# 1) Create directories
echo ">> Creating directories (if missing)..."
mkdir -p ./hadoop_namenode ./hadoop_datanode1 \
  ./tmp/hadoop-history ./spark-apps ./spark-events

# Add .gitkeep to keep empty folders in VCS (optional)
touch ./spark-apps/.gitkeep ./spark-events/.gitkeep ./tmp/hadoop-history/.gitkeep

# 2) Chown to container's hadoop user (try sudo first, then without)
chown_wrap() {
  if command -v sudo >/dev/null 2>&1; then
    sudo chown -R "$HADOOP_UID:$HADOOP_GID" "$@" || {
      echo "!! 'sudo chown' failed, trying without sudo..." >&2
      chown -R "$HADOOP_UID:$HADOOP_GID" "$@"
    }
  else
    chown -R "$HADOOP_UID:$HADOOP_GID" "$@"
  fi
}

echo ">> Setting ownership to ${HADOOP_UID}:${HADOOP_GID} ..."
chown_wrap ./hadoop_namenode ./hadoop_datanode1 \
  ./tmp/hadoop-history ./spark-apps ./spark-events

# 3) Permissions
echo ">> Applying permissions..."
chmod 700 ./hadoop_namenode ./hadoop_datanode1
chmod 777 ./tmp/hadoop-history
chmod 755 ./spark-apps ./spark-events

# 4) Summary
echo
echo "✅ Done. Summary:"
ls -ld ./hadoop_namenode ./hadoop_datanode1 ./tmp/hadoop-history ./spark-apps ./spark-events
echo
cat <<'EOF'
Next:
  - Ensure your conf/hdfs-site.xml uses:
      dfs.namenode.name.dir = file:///hadoop/dfs/name
      dfs.datanode.data.dir = file:///hadoop/dfs/data
  - Then run: docker compose up -d
EOF
