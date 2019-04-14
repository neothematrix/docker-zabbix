FROM centos:centos7 as builder

ARG YUM_FLAGS_COMMON="-y"
ARG YUM_FLAGS_DEV="${YUM_FLAGS_COMMON}"

ARG MAJOR_VERSION=4.2
ARG ZBX_VERSION=${MAJOR_VERSION}.0
ARG ZBX_SOURCES=svn://svn.zabbix.com/tags/${ZBX_VERSION}/
ENV TERM=xterm ZBX_VERSION=${ZBX_VERSION} ZBX_SOURCES=${ZBX_SOURCES} \
    ZBX_TYPE=agent

RUN yum --quiet makecache && \
    yum ${YUM_FLAGS_DEV} install \
            autoconf \
            automake \
            make \
            openssl-devel \
            openldap-devel \
            subversion \
            git \
            pcre-devel \
            gcc && \
    cd /tmp/ && \
    git clone -q https://github.com/monitoringartist/zabbix-docker-monitoring && \
    svn --quiet export ${ZBX_SOURCES} zabbix-${ZBX_VERSION} && \
    cd /tmp/zabbix-${ZBX_VERSION} && \
    zabbix_revision=`set -o pipefail && svn info ${ZBX_SOURCES} | grep "Last Changed Rev"|awk '{print $4;}'` && \
    sed -i "s/{ZABBIX_REVISION}/$zabbix_revision/g" include/version.h && \
    ./bootstrap.sh && \
    export CFLAGS="-fPIC -pie -Wl,-z,relro -Wl,-z,now" && \
    ./configure \
            --datadir=/usr/lib \
            --libdir=/usr/lib/zabbix \
            --prefix=/usr \
            --sysconfdir=/etc/zabbix \
            --prefix=/usr \
            --enable-agent \
            --with-ldap \
            --with-openssl \
            --enable-ipv6 \
            --silent && \
    cp -R /tmp/zabbix-docker-monitoring/src/modules/zabbix_module_docker /tmp/zabbix-${ZBX_VERSION}/src/modules/ && \
    make -j"$(nproc)" -s && \
    cd /tmp/zabbix-${ZBX_VERSION}/src/modules/zabbix_module_docker && \
    make -j"$(nproc)" -s

FROM centos:centos7
LABEL maintainer="Alexey Pustovalov <alexey.pustovalov@zabbix.com>"

ARG BUILD_DATE
ARG VCS_REF

ARG YUM_FLAGS_COMMON="-y"
ARG YUM_FLAGS_PERSISTENT="${YUM_FLAGS_COMMON}"

ARG MAJOR_VERSION=4.2
ARG ZBX_VERSION=${MAJOR_VERSION}.0
ARG ZBX_SOURCES=svn://svn.zabbix.com/tags/${ZBX_VERSION}/
ENV TERM=xterm ZBX_VERSION=${ZBX_VERSION} ZBX_SOURCES=${ZBX_SOURCES} \
    ZBX_TYPE=agent ZBX_DB_TYPE=none ZBX_OPT_TYPE=none
ENV TINI_VERSION v0.18.0

LABEL org.label-schema.name="zabbix-${ZBX_TYPE}-centos" \
      org.label-schema.vendor="Zabbix LLC" \
      org.label-schema.url="https://zabbix.com/" \
      org.label-schema.description="Zabbix agent is deployed on a monitoring target to actively monitor local resources and applications" \
      org.label-schema.vcs-ref="${VCS_REF}" \
      org.label-schema.build-date="${BUILD_DATE}" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.license="GPL v2.0" \
      org.label-schema.usage="https://www.zabbix.com/documentation/${MAJOR_VERSION}/manual/installation/containers" \
      org.label-schema.version="${ZBX_VERSION}" \
      org.label-schema.vcs-url="${ZBX_SOURCES}" \
      org.label-schema.docker.cmd="docker run --name zabbix-${ZBX_TYPE} --link zabbix-server:zabbix-server -p 10050:10050 -d zabbix-${ZBX_TYPE}:centos-${ZBX_VERSION}"

STOPSIGNAL SIGTERM

COPY --from=builder /tmp/zabbix-${ZBX_VERSION}/src/zabbix_agent/zabbix_agentd /usr/sbin/zabbix_agentd
COPY --from=builder /tmp/zabbix-${ZBX_VERSION}/src/zabbix_get/zabbix_get /usr/bin/zabbix_get
COPY --from=builder /tmp/zabbix-${ZBX_VERSION}/src/zabbix_sender/zabbix_sender /usr/bin/zabbix_sender
COPY --from=builder /tmp/zabbix-${ZBX_VERSION}/src/modules/zabbix_module_docker/zabbix_module_docker.so /tmp/zabbix_module_docker.so
COPY --from=builder  /tmp/zabbix-${ZBX_VERSION}/conf/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /sbin/tini

RUN groupadd --system zabbix && \
    adduser -r --shell /sbin/nologin \
            -g zabbix \
            -d /var/lib/zabbix/ \
        zabbix && \
    mkdir -p /etc/zabbix && \
    mkdir -p /etc/zabbix/zabbix_agentd.d && \
    mkdir -p /var/lib/zabbix && \
    mkdir -p /var/lib/zabbix/enc && \
    mkdir -p /var/lib/zabbix/modules && \
    mv /tmp/zabbix_module_docker.so /var/lib/zabbix/modules/zabbix_module_docker.so && \
    chown --quiet -R zabbix:root /var/lib/zabbix && \
    yum ${YUM_FLAGS_COMMON} makecache && \
    yum ${YUM_FLAGS_PERSISTENT} install epel-release && \
    yum ${YUM_FLAGS_PERSISTENT} install \
            libldap \
            nc \
            python36 \
            openssl-libs && \
    yum ${YUM_FLAGS_PERSISTENT} clean all && \
    rm -rf /var/cache/yum && \
    chmod +x /sbin/tini

EXPOSE 10050/TCP

WORKDIR /var/lib/zabbix

VOLUME ["/etc/zabbix/zabbix_agentd.d"]

COPY ["docker-entrypoint.sh", "/usr/bin/"]

ENTRYPOINT ["/sbin/tini", "--"]

CMD ["docker-entrypoint.sh"]
