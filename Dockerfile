FROM debian:buster-20200514 AS builder

RUN apt-get update -y
RUN apt-get install -y gfortran libreadline6-dev libx11-dev libxt-dev \
                               libpng-dev libjpeg-dev libcairo2-dev xvfb \
                               libbz2-dev libzstd-dev liblzma-dev \
                               libcurl4-openssl-dev \
                               texinfo texlive texlive-fonts-extra \
                               screen wget libpcre2-dev \
							   git apt-utils sed \
							   make cmake g++ \
							   default-jdk

#Install R
WORKDIR /usr/local/src
RUN wget https://cran.rstudio.com/src/base/R-4/R-4.0.3.tar.gz
RUN tar zxvf R-4.0.3.tar.gz
WORKDIR /usr/local/src/R-4.0.3
#Optional: include blas and lapack
#RUN ./configure --enable-R-shlib --with-blas --with-lapack
RUN ./configure --enable-R-shlib
RUN make -j4
RUN make -j4 install
WORKDIR /usr/local/src/
RUN rm -rf R-4.0.3*

WORKDIR /

#Install R libs
RUN R -e "install.packages(c('shiny', 'Cairo'), repos='http://cran.rstudio.com/')"

#Set python3 as the default python
RUN rm /usr/bin/python
RUN ln -s /usr/bin/python3 /usr/bin/python

#Install shiny-server
RUN git clone https://github.com/rstudio/shiny-server.git
RUN mkdir shiny-server/tmp
COPY binding.gyp /shiny-server/tmp/binding.gyp
RUN sed -i '8s/.*/NODE_SHA256=abef7d431d6d0e067fe5797d4fe44039a5577f01ed9e40d7a3496cbb22502f55/' shiny-server/external/node/install-node.sh
RUN sed -i 's/linux-x64.tar.xz/linux-armv7l.tar.xz/' /shiny-server/external/node/install-node.sh
RUN sed -i 's/https:\/\/github.com\/jcheng5\/node-centos6\/releases\/download\//https:\/\/nodejs.org\/dist\//' /shiny-server/external/node/install-node.sh
WORKDIR /shiny-server/tmp/
RUN PYTHON=`which python`
RUN mkdir ../build
RUN cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DPYTHON="$PYTHON" ../
RUN make -j4
RUN ../external/node/install-node.sh
RUN ../bin/node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js configure
RUN	../bin/node ../ext/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js --python="$PYTHON" rebuild
#Currently only --unsafe-perm works (see https://github.com/npm/npm/issues/3497)
#RUN ../bin/npm --python="${PYTHON}" install --no-optional
RUN ../bin/npm --python="${PYTHON}" install --no-optional --unsafe-perm
RUN ../bin/npm --python="${PYTHON}" rebuild
RUN make -j4 install

FROM debian:buster-20200514
#Copy packages from builder
COPY --from=builder /usr/local/bin/R /usr/local/bin/R
COPY --from=builder /usr/local/lib/R /usr/local/lib/R
COPY --from=builder /usr/local/bin/Rscript /usr/local/bin/Rscript
COPY --from=builder /usr/local/shiny-server /usr/local/shiny-server

WORKDIR /

RUN useradd -r -m shiny

RUN ln -s /usr/local/shiny-server/bin/shiny-server /usr/bin/shiny-server
RUN mkdir -p /var/log/shiny-server
RUN mkdir -p /srv/shiny-server
RUN chown shiny /var/log/shiny-server
RUN mkdir -p /var/lib/shiny-server
RUN mkdir -p /etc/shiny-server

#copy settings
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

#copy init file
COPY init.sh /etc/shiny-server/init.sh
RUN chmod 777 /etc/shiny-server/init.sh

#copy project
COPY hello/* /srv/shiny-server/hello/

#set permissions
RUN chmod -R 777 /var/log/shiny-server
RUN chmod -R 777 /srv/shiny-server
RUN chmod -R 777 /var/lib/shiny-server
RUN chmod -R 777 /srv/shiny-server

RUN apt-get update -y
RUN apt-get install -y gfortran libreadline6-dev libcurl4-openssl-dev libcairo2-dev xvfb libx11-dev libxt-dev libpng-dev libjpeg-dev libbz2-dev libzstd-dev liblzma-dev libatomic1 libgomp1 libpcre2-8-0 libssl-dev libxml2-dev g++ make

ENTRYPOINT ["/etc/shiny-server/init.sh"]
