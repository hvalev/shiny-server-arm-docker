###########################
# Builder image
###########################
FROM debian:trixie-20260803 AS builder

ENV V_RStudio=R-4.6.1
ENV V_ShinyServer=v1.5.23.1030

# Parallelism for the native builds. Defaults are conservative (small ARM
# devices); override for fast hosts, e.g. --build-arg R_BUILD_JOBS=16
ARG R_BUILD_JOBS=4
ARG BUILD_JOBS=4

RUN apt-get update && apt-get install -y \
    gfortran \
    file \
    libblas-dev \
    liblapack-dev \
    libreadline-dev \
    libx11-dev \
    libxt-dev \
    libpng-dev \
    libjpeg-dev \
    libcairo2-dev \
    xvfb \
    libbz2-dev \
    libzstd-dev \
    liblzma-dev \
    libcurl4-openssl-dev \
    texinfo \
    texlive \
    texlive-fonts-extra \
    screen \
    wget \
    tar \
    xz-utils \
    coreutils \
    libpcre2-dev \
    git \
    apt-utils \
    sed \
    make \
    cmake \
    g++ \
    python3 \
    python3-dev \
    python3-setuptools \
    default-jdk && \
    rm -rf /var/lib/apt/lists/*

#Install R with blas and lapack support. Remove '--with-blas --with-lapack' to disable
# CRAN only serves the current release at the R-latest alias; the test below
# fails the build if CRAN's latest release no longer matches the pinned version.
WORKDIR /usr/local/src
RUN wget https://cran.r-project.org/src/base/R-latest.tar.gz && \
    tar xzf R-latest.tar.gz && \
    test -d ${V_RStudio} && \
    cd ${V_RStudio} && \
    ./configure --enable-R-shlib --with-blas --with-lapack && \
    make -j${R_BUILD_JOBS} && \
    make -j${R_BUILD_JOBS} install && \
    cd /usr/local/src/ && \
    rm -rf ${V_RStudio} R-latest.tar.gz

#Install shiny-server with fix for arm architectures
WORKDIR /
RUN git clone --depth 1 --branch ${V_ShinyServer} https://github.com/rstudio/shiny-server.git && \
    mkdir shiny-server/tmp
COPY binding.gyp /shiny-server/tmp/binding.gyp

WORKDIR /shiny-server/tmp/
RUN mkdir ../build
RUN cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DPYTHON="$(which python3)" ../
RUN make -j${BUILD_JOBS}

# Omit install_node.sh and do that manually here
# The reason is discrepencies between arch detection
# on bare metal and in docker qemu arch emulation
RUN apt-get update && apt-get install -y \
    wget \
    xz-utils \
    curl \
    tar \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Get the correct node version for the builder arch of the system
ARG TARGETARCH
RUN mkdir -p /shiny-server/ext/node
# Node 22 ("Jod"), newest release that still ships linux-armv7l binaries
# (Node 24+ dropped them). Maintenance LTS until April 2027.
ENV V_Node=v22.23.2
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      curl -fsSL https://nodejs.org/dist/${V_Node}/node-${V_Node}-linux-x64.tar.xz \
      | tar -xJ -C /shiny-server/ext/node --strip-components=1; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
      curl -fsSL https://nodejs.org/dist/${V_Node}/node-${V_Node}-linux-arm64.tar.xz \
      | tar -xJ -C /shiny-server/ext/node --strip-components=1; \
    elif [ "$TARGETARCH" = "arm" ]; then \
      curl -fsSL https://nodejs.org/dist/${V_Node}/node-${V_Node}-linux-armv7l.tar.xz \
      | tar -xJ -C /shiny-server/ext/node --strip-components=1; \
    else \
      echo "Unsupported architecture $TARGETARCH" && exit 1; \
    fi

# The C++ launcher (bin/shiny-server) execs the node binary under the name
# "shiny-server" (see src/launcher.cc in the shiny-server repo). The original
# install_node.sh created that copy; without it the launcher silently exits 0
# and no logs are produced at all.
RUN cp /shiny-server/ext/node/bin/node /shiny-server/ext/node/bin/shiny-server
RUN chmod +x /shiny-server/ext/node/bin/node /shiny-server/ext/node/bin/npm /shiny-server/ext/node/bin/shiny-server
ENV PATH=$PATH:/shiny-server/ext/node/bin/:/shiny-server/bin/

RUN node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js configure
RUN node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js --python="$(which python3)" rebuild

WORKDIR /shiny-server/
RUN npm --python="$(which python3)" install --no-optional
RUN npm --python="$(which python3)" install --no-optional --unsafe-perm
RUN npm --python="$(which python3)" rebuild

WORKDIR /shiny-server/tmp/
RUN make -j${BUILD_JOBS} install

###########################
# Production image
###########################
FROM debian:trixie-20260803 AS shiny
COPY --from=builder /usr/local/bin/R /usr/local/bin/R
COPY --from=builder /usr/local/lib/R /usr/local/lib/R
COPY --from=builder /usr/local/bin/Rscript /usr/local/bin/Rscript
COPY --from=builder /usr/local/shiny-server /usr/local/shiny-server

WORKDIR /
RUN useradd -r -m shiny
RUN ln -s /usr/local/shiny-server/bin/shiny-server /usr/bin/shiny-server

#Create folder structure and set permissions
RUN mkdir -p        /var/log/shiny-server && \
    chown shiny     /var/log/shiny-server && \
    chmod -R 777    /var/log/shiny-server && \
    mkdir -p        /srv/shiny-server     && \
    chmod -R 777    /srv/shiny-server     && \
    mkdir -p        /var/lib/shiny-server && \
    chmod -R 777    /var/lib/shiny-server && \
    mkdir -p        /etc/shiny-server     && \
    chmod -R 777    /srv/shiny-server

#Shiny server configuration
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

#Init file for installing R-packages from host
COPY init.sh /etc/shiny-server/init.sh
RUN chmod 777 /etc/shiny-server/init.sh

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gfortran \
    libblas3 \
    liblapack3 \
    libuv1-dev \
    libreadline-dev \
    libcurl4-openssl-dev \
    ca-certificates \
    libcairo2-dev \
    xvfb \
    libx11-dev \
    libxt-dev \
    libpng-dev \
    libjpeg-dev \
    libbz2-dev \
    libzstd-dev \
    liblzma-dev \
    libatomic1 \
    libgomp1 \
    libpcre2-8-0 \
    libssl-dev \
    libxml2-dev \
    g++ \
    make && \
    rm -rf /var/lib/apt/lists/*

#Preload hello world project
# Note: COPY hello/ (not hello/*) on purpose - the glob drops dotfiles and
# the app's per-app config is hello/.shiny_app.conf (yes, with the
# underscore - that's the name shiny-server 1.5.x looks for), so without
# this the file would never make it into the image.
COPY hello/ /srv/shiny-server/hello/
#Prevent installation from hanging for multi-arch builds due to insufficient ram
ARG PKG_CPUS=4
# install.packages() exits 0 even when a package fails, so verify explicitly
RUN R -e "install.packages(c('shiny', 'Cairo'), repos='http://cran.rstudio.com/', clean = TRUE, Ncpus = ${PKG_CPUS})" && \
    R -e "stopifnot(all(c('shiny', 'Cairo') %in% rownames(installed.packages())))"

ENTRYPOINT ["/etc/shiny-server/init.sh"]

###########################
# Devtools Production image
###########################
FROM shiny AS shiny-with-devtools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libzmq3-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    build-essential \
    libcurl4-openssl-dev \
    libxml2-dev \
    libssl-dev \
    libfontconfig1-dev \
    libgit2-dev \
    libicu-dev && \
    rm -rf /var/lib/apt/lists/*

ARG PKG_CPUS=4
# installing devtools
RUN R -e "install.packages('devtools', repos='http://cran.rstudio.com/', type='source', clean = TRUE, Ncpus = ${PKG_CPUS})" && \
    R -e "stopifnot('devtools' %in% rownames(installed.packages()))"
