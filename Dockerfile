###########################
# Builder image
###########################
FROM debian:buster-20240110 AS builder

ENV V_RStudio=R-4.3.2
ENV V_ShinyServer=v1.5.20.1002

RUN apt-get update && apt-get install -y \
    gfortran libreadline6-dev libx11-dev libxt-dev \
    libpng-dev libjpeg-dev libcairo2-dev xvfb libbz2-dev \
    libzstd-dev liblzma-dev libcurl4-openssl-dev \
    texinfo texlive texlive-fonts-extra screen wget libpcre2-dev \
    git apt-utils sed make cmake g++ default-jdk 

#Install R with blas and lapack support. Remove '--with-blas --with-lapack' to disable
WORKDIR /usr/local/src
RUN wget https://cran.rstudio.com/src/base/R-4/${V_RStudio}.tar.gz && \
    tar zxvf ${V_RStudio}.tar.gz && \
    cd /usr/local/src/${V_RStudio} && \
    ./configure --enable-R-shlib --with-blas --with-lapack && \
    make -j4 && \
    make -j4 install && \
    cd /usr/local/src/ && \
    rm -rf ${V_RStudio}*

#Set python3 as the default python
RUN rm /usr/bin/python && \
    ln -s /usr/bin/python3 /usr/bin/python

#Install shiny-server with fix for arm architectures
WORKDIR /
RUN git clone --depth 1 --branch ${V_ShinyServer} https://github.com/rstudio/shiny-server.git && \
    mkdir shiny-server/tmp
COPY binding.gyp /shiny-server/tmp/binding.gyp

#Automagically determine arch and replace it in hash values and links
COPY determine_arch.sh /determine_arch.sh
RUN chmod +x determine_arch.sh && \
    ./determine_arch.sh

WORKDIR /shiny-server/tmp/

#Install node for rshiny. Currently only --unsafe-perm works (see https://github.com/npm/npm/issues/3497) 
RUN PYTHON=`which python` && \
    mkdir ../build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DPYTHON="$PYTHON" ../ && \
    make -j4 && \
    ../external/node/install-node.sh && \
    PATH=$PATH:/shiny-server/ext/node/bin/ && \
    ../bin/node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js configure && \
    ../bin/node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js --python="$PYTHON" rebuild && \
    ../bin/npm --python="${PYTHON}" install --no-optional && \
    ../bin/npm --python="${PYTHON}" install --no-optional --unsafe-perm && \
    ../bin/npm --python="${PYTHON}" rebuild && \
    make -j4 install

###########################
# Production image
###########################
FROM debian:buster-20240110 as shiny
#Copy artefacts from builder image
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

RUN apt-get update && apt-get install -y --no-install-recommends \
    gfortran libreadline6-dev libcurl4-openssl-dev ca-certificates \
    libcairo2-dev xvfb libx11-dev libxt-dev libpng-dev \
    libjpeg-dev libbz2-dev libzstd-dev liblzma-dev libatomic1 \
    libgomp1 libpcre2-8-0 libssl-dev libxml2-dev g++ make && \
    rm -rf /var/lib/apt/lists/*

#Preload hello world project
COPY hello/* /srv/shiny-server/hello/
#Prevent installation from hanging for multi-arch builds due to insufficient ram
#RUN R -e "install.packages(c('httpuv'), repos='http://cran.rstudio.com/', clean = TRUE, Ncpus = 1)"
RUN R -e "install.packages(c('shiny', 'Cairo'), repos='http://cran.rstudio.com/', clean = TRUE, Ncpus = 2)"

ENTRYPOINT ["/etc/shiny-server/init.sh"]

###########################
# Devtools Production image
###########################
FROM shiny AS shiny-with-devtools
RUN apt-get update && \
    apt-get install libzmq3-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
    libpng-dev libtiff5-dev libjpeg-dev build-essential libcurl4-openssl-dev \
    libxml2-dev libssl-dev libfontconfig1-dev libgit2-dev -y
	# installing devtools
RUN	R -e "install.packages('devtools', repos='http://cran.rstudio.com/', type='source', clean = TRUE, Ncpus = 2)"