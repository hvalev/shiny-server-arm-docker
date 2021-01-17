###########################
# Builder image
###########################
FROM debian:buster-20210111 AS builder

RUN apt-get update -y && \
    apt-get install -y \
    gfortran libreadline6-dev libx11-dev libxt-dev \
    libpng-dev libjpeg-dev libcairo2-dev xvfb libbz2-dev \
    libzstd-dev liblzma-dev libcurl4-openssl-dev \
    texinfo texlive texlive-fonts-extra screen wget libpcre2-dev \
    git apt-utils sed make cmake g++ default-jdk 

#Install R with blas and lapack support. Remove '--with-blas --with-lapack' to disable
WORKDIR /usr/local/src
RUN wget https://cran.rstudio.com/src/base/R-4/R-4.0.3.tar.gz && \
    tar zxvf R-4.0.3.tar.gz && \
    cd /usr/local/src/R-4.0.3 && \
    ./configure --enable-R-shlib --with-blas --with-lapack && \
    make -j4 && \
    make -j4 install && \
    cd /usr/local/src/ && \
    rm -rf R-4.0.3*

#Set python3 as the default python
RUN rm /usr/bin/python && \
    ln -s /usr/bin/python3 /usr/bin/python

#Install shiny-server with fix for arm architectures
WORKDIR /
RUN git clone https://github.com/rstudio/shiny-server.git && \
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
    ../bin/node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js configure && \
    ../bin/node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js --python="$PYTHON" rebuild && \
    ../bin/npm --python="${PYTHON}" install --no-optional && \
    ../bin/npm --python="${PYTHON}" install --no-optional --unsafe-perm && \
    ../bin/npm --python="${PYTHON}" rebuild && \
    make -j4 install

###########################
# Production image
###########################
FROM debian:buster-20210111
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

RUN apt-get update -y && \
    apt-get install -y \
    gfortran libreadline6-dev libcurl4-openssl-dev \
    libcairo2-dev xvfb libx11-dev libxt-dev libpng-dev \
    libjpeg-dev libbz2-dev libzstd-dev liblzma-dev libatomic1 \
    libgomp1 libpcre2-8-0 libssl-dev libxml2-dev g++ make

#Preload hello world project
COPY hello/* /srv/shiny-server/hello/
RUN R -e "install.packages(c('shiny', 'Cairo'), repos='http://cran.rstudio.com/')"

ENTRYPOINT ["/etc/shiny-server/init.sh"]