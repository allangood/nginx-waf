FROM nginx:stable-alpine AS build
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# This image is based on:
# https://github.com/vlche/docker-nginx-waf

# nginx:alpine contains NGINX_VERSION environment variable, like so:
# ENV NGINX_VERSION 1.19.6

# MODSECURITY version
ENV VERSION=${NGINX_VERSION}
ENV MODSECURITY_VERSION=3.0.4
ENV OWASPCRS_VERSION=3.3.0

# Configuration directories
ENV MODSEC_CONF_DIR="/etc/nginx/modsec"
ENV NGINX_CONF_DIR="/etc/nginx"

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
ARG MODSECURITY_VERSION
ARG OWASPCRS_VERSION
LABEL maintainer="Allan GooD <allan.cassaro@gmail.com>" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="NGINX with ModSecurity and Brotli support" \
      org.label-schema.description="Provides nginx ${NGINX_VERSION} with ModSecurity v${MODSECURITY_VERSION} (OWASP ModSecurity CRS ${OWASPCRS_VERSION})" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/allangood/docker-nginx-waf" \
      org.label-schema.vendor="Allan GooD" \
      org.label-schema.version=v$VERSION \
      org.label-schema.schema-version="1.0"

WORKDIR /src
ENV WORKING_DIR="/src"

# Download dependencies
RUN apk add --no-cache --virtual .build-deps \
    gcc \
    libc-dev \
    make \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    linux-headers \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    perl-dev \
    libedit-dev \
    mercurial \
    bash \
    alpine-sdk \
    findutils \
    patch \
    curl \
  # modsecurity dependencies
    autoconf \
    automake \
    curl-dev \
    libmaxminddb-dev \
    libtool \
    lmdb-dev \
    yajl-dev

# Download ModSecurity files
RUN echo "Downloading sources..." \
  && cd ${WORKING_DIR} \
  && git clone --depth 1 -b v${MODSECURITY_VERSION} --single-branch https://github.com/SpiderLabs/ModSecurity \
  && git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git \
  && git clone --recursive https://github.com/google/ngx_brotli.git \
  && wget -qO modsecurity.conf https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v${MODSECURITY_VERSION}/modsecurity.conf-recommended \
  && wget -qO unicode.mapping  https://raw.githubusercontent.com/SpiderLabs/ModSecurity/49495f1925a14f74f93cb0ef01172e5abc3e4c55/unicode.mapping \
  && wget -qO - https://github.com/coreruleset/coreruleset/archive/v${OWASPCRS_VERSION}.tar.gz | tar xzf  - -C ${WORKING_DIR} \
  && wget -qO - https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xzf  - -C ${WORKING_DIR}

# Starting build process
## Build libmodsecurity
RUN echo "building modsecurity..." \
  && cd ModSecurity \
  && git submodule init && git submodule update \
  && wget https://gist.githubusercontent.com/crsgists/0e1f6f7f1bd1f239ded64cecee46a11d/raw/181bc852065e9782367f1dc67c96d4d250e73a46/cve-2020-15598.patch \
  && patch -p1 < cve-2020-15598.patch \
  && ./build.sh \
  && ./configure --prefix=/usr \
  && make -o 3 -j$(nproc) \
  && make install

## Build nginx modules
RUN echo "build nginx modules..." \
  && cd ${WORKING_DIR} \
  && CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p'| sed -e "s/--with-cc-opt='.*'//g") \
  && MODSECURITYDIR="$(pwd)/ModSecurity-nginx" \
  && cd ./nginx-$NGINX_VERSION \
  && ./configure --with-compat $CONFARGS \
    --with-cc-opt='-Os -fomit-frame-pointer' \
    --add-dynamic-module=$MODSECURITYDIR \
    --add-dynamic-module=${WORKING_DIR}/ngx_brotli \
  && make modules -o 3 -j$(nproc) \
  && strip objs/*.so \
  && mkdir -p /usr/lib/nginx/modules \
  && cp objs/*.so /usr/lib/nginx/modules

# Changing configuration files
RUN echo "configuring modsecurity rules..." \
  && mv ${WORKING_DIR}/coreruleset-${OWASPCRS_VERSION} ${MODSEC_CONF_DIR}/ \
  && echo "# Rule files" >> ${MODSEC_CONF_DIR}/modsec_rules.conf \
  && echo "Include ${MODSEC_CONF_DIR}/modsecurity.conf" >> ${MODSEC_CONF_DIR}/modsec_rules.conf \
  && echo "Include ${MODSEC_CONF_DIR}/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf" >> ${MODSEC_CONF_DIR}/modsec_rules.conf \
  && echo "Include ${MODSEC_CONF_DIR}/crs-setup.conf" >> ${MODSEC_CONF_DIR}/modsec_rules.conf \
  && for rule in $(ls -1 ${MODSEC_CONF_DIR}/rules/*.conf); do echo "Include ${rule}"; done >> ${MODSEC_CONF_DIR}/modsec_rules.conf \
  && echo "Include ${MODSEC_CONF_DIR}/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf" >> ${MODSEC_CONF_DIR}/modsec_rules.conf \
  #
  # Rename .example files
  && mv ${MODSEC_CONF_DIR}/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example ${MODSEC_CONF_DIR}/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf \
  && mv ${MODSEC_CONF_DIR}/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example ${MODSEC_CONF_DIR}/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf \
  #
  && mv ${WORKING_DIR}/unicode.mapping ${MODSEC_CONF_DIR} \
  && mv ${WORKING_DIR}/modsecurity.conf ${MODSEC_CONF_DIR} \
  && sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' ${MODSEC_CONF_DIR}/modsecurity.conf \
  && sed -i 's!SecAuditLog /var/log/modsec_audit.log!SecAuditLog /var/log/nginx/modsec_audit.log!g' ${MODSEC_CONF_DIR}/modsecurity.conf \
  && mv ${MODSEC_CONF_DIR}/crs-setup.conf.example ${MODSEC_CONF_DIR}/crs-setup.conf

# Cleaning phase
RUN echo "cleaning all after build..." \
  && echo "delete modsecurity archive and strip libmodsecurity" \
  && rm -rf ${MODSEC_CONF_DIR}/tests \
  && rm -rf ${MODSEC_CONF_DIR}/docs \
  && rm /usr/lib/libmodsecurity.a \
  && strip /usr/lib/libmodsecurity.so \
  && apk del .build-deps \
  && rm -rf ${WORKING_DIR} \
  && mv ${NGINX_CONF_DIR} ${NGINX_CONF_DIR}.orig \
  && mkdir ${NGINX_CONF_DIR}/

# New Layer
FROM nginx:alpine
COPY --from=build /usr/lib/libmodsecurity* /usr/lib/
COPY --from=build /etc/nginx.orig /etc/nginx.orig
COPY --from=build /usr/lib/nginx/modules /usr/lib/nginx/modules
COPY src /
COPY conf/nginx.conf /etc/nginx.orig/

WORKDIR /

# Final steps
RUN echo "adding modsecurity dependency & openssl..." \
  && apk add --no-cache libstdc++ yajl libmaxminddb openssl \
  && rm -rf /etc/nginx \
  && mkdir /etc/nginx

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80 443
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]
