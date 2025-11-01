FROM apache/hadoop-runner:jdk17-u2204

# ====== 可调参数（版本/用户/校验）======
ARG HADOOP_VERSION=3.4.1
# 可选：填入官方发布页的 SHA512，用于校验；留空则跳过校验
ARG HADOOP_SHA512=""
# 可选：固定 UID/GID，便于与宿主机文件权限对齐
ARG HADOOP_UID=1000
ARG HADOOP_GID=1000
ARG HADOOP_USER=hadoop

# ====== 环境变量 ======
ENV HADOOP_HOME=/opt/hadoop \
    HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop \
    PATH=/opt/hadoop/bin:/opt/hadoop/sbin:$PATH \
    # JDK 17 下常见 add-opens，减少反射/Unsafe 相关报错
    HADOOP_OPTS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED"

# ====== 以 root 安装依赖 + 创建目录 + 安装 Hadoop ======
USER root
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates tar tini gosu \
 # 创建系统目录（HDFS/YARN/日志），一次搞定
 && mkdir -p \
      ${HADOOP_HOME} \
      /hadoop/dfs/name \
      /hadoop/dfs/data \
      /var/log/hadoop \
      /var/hadoop/yarn/local \
      /var/hadoop/yarn/logs \
      /var/hadoop/mapred \
 # 下载 Hadoop 压缩包（版本可通过 ARG 控制）
 && curl -fsSLo /tmp/hadoop.tgz https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz \
 # 校验（若提供了 SHA512）
 && if [ -n "${HADOOP_SHA512}" ]; then \
        echo "${HADOOP_SHA512}  /tmp/hadoop.tgz" | sha512sum -c - ; \
    else \
        echo "SKIP sha512 check (HADOOP_SHA512 not set)"; \
    fi \
 # 解压到 /opt/hadoop（去掉最外层目录）
 && tar -xzf /tmp/hadoop.tgz --strip-components=1 -C ${HADOOP_HOME} --no-same-owner --no-same-permissions \
 && rm -f /tmp/hadoop.tgz \
 # 创建 hadoop 用户与组（如已存在则跳过）
 && if ! getent group ${HADOOP_GID} >/dev/null; then groupadd -g ${HADOOP_GID} ${HADOOP_USER}; fi \
 && if ! id -u ${HADOOP_UID} >/dev/null 2>&1; then \
        useradd -m -u ${HADOOP_UID} -g ${HADOOP_GID} -s /bin/bash ${HADOOP_USER}; \
    fi \
 # 授权运行目录给 hadoop 用户
 && chown -R ${HADOOP_USER}:${HADOOP_USER} ${HADOOP_HOME} /hadoop /var/log/hadoop /var/hadoop

# 构建期自检（提早发现 PATH/JAVA/HADOOP 安装问题）
RUN ${HADOOP_HOME}/bin/hdfs version

# ====== 切到 hadoop 用户，默认工作目录放家目录 ======
USER ${HADOOP_USER}
WORKDIR /opt/${HADOOP_USER}

#（可选）把常用 add-opens 也给到 HDFS/YARN 子进程（需要时再开启）
# ENV HADOOP_NAMENODE_OPTS="${HADOOP_OPTS}" \
#     HADOOP_DATANODE_OPTS="${HADOOP_OPTS}" \
#     YARN_OPTS="${HADOOP_OPTS}" \
#     MAPRED_OPTS="${HADOOP_OPTS}"

# 方便用 tini 作为 init，处理僵尸进程；也可按需定制 entrypoint/cmd
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
# FROM apache/hadoop-runner:jdk17-u2204
# ARG HADOOP_VERSION=3.4.1
# ENV HADOOP_HOME=/opt/hadoop PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH
# USER root
#
# COPY hadoop-${HADOOP_VERSION}.tar.gz /tmp/hadoop.tgz
#
# RUN mkdir -p $HADOOP_HOME \
#  && tar -xzf /tmp/hadoop.tgz --strip-components=1 -C $HADOOP_HOME --no-same-owner --no-same-permissions \
#  && rm -f /tmp/hadoop.tgz
#
# RUN hdfs version
# syntax=docker/dockerfile:1.7
