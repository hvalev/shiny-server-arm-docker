# rpi-shiny-server-docker
This is a standalone docker container image which builds shiny-server for arm on debian buster. Tested on a raspberry pi 4b. Be aware that this is a 4,5GB behemoth which takes 3 to 4 hours to build!

In order to have it running on your Pi follow the instructions below:
* Install docker (Optional: docker-compose) <br/>

* Build & run the container
```
docker build https://github.com/hvalev/rpi-shiny-server-docker --tag rpi-shiny-server
docker run -d -p 3838:3838 --name rpi-shiny-server rpi-shiny-server
```
* (Optional) You can also use the following docker-compose code:<br/>
Note: Adjust your paths accordingly
```
version: "3.8"
services:
  rpi-shiny-server:
    container_name: rpi-shiny-server
    build: https://github.com/hvalev/rpi-shiny-server-docker.git
    ports:
      - 3838:3838
    volumes:
      - shiny-server/logs/:/var/log/shiny-server/
      - shiny-server/apps/:/srv/shiny-server/
      - shiny-server/conf/:/etc/shiny-server/
    restart: always
```

# Dockerhub
Precompiled image is available from on docker hub here https://hub.docker.com/repository/docker/hvalev/rpi-shiny-server-docker. Compressed image size - 1.7GB, uncompressed - 4.3GB
```
docker pull hvalev/rpi-shiny-server-docker
```

# Credit
The following resources were very helpful </br>
https://community.rstudio.com/t/setting-up-your-own-shiny-server-rstudio-server-on-a-raspberry-pi-3b/18982 </br>
https://emeraldreverie.org/2019/11/17/self-hosting-shiny-notes-from-edinbr/ </br>
https://github.com/rstudio/shiny-server/wiki/Building-Shiny-Server-from-Source

# Contents

## hello/
The dockerfile preloads the hello-world shiny app to test if everything is working post install.

## shiny-server.conf
Sample configuration file for shiny-server. The hello app is already configured there.

## init.sh
Will be ran only the first time the container is started. It creates an init_done file when completed. If you need to make any changes to the installed R libraries (or execute other commands) between restarts, simply delete the init_done file and indicate which libraries need to be installed in the file as shown below
```
R -e "install.packages(c('rcicr','shinyjs','filelock'), repos='http://cran.rstudio.com/')"
```

## Dockerfile
Here are some excerpts from the Dockerfile with some explanation on changes you can make.

### R
```
WORKDIR /usr/local/src
RUN wget https://cran.rstudio.com/src/base/R-4/R-4.0.0.tar.gz
RUN tar zxvf R-4.0.0.tar.gz
WORKDIR /usr/local/src/R-4.0.0
#Optional: include blas and lapack
#RUN ./configure --enable-R-shlib --with-blas --with-lapack
RUN ./configure --enable-R-shlib
RUN make
RUN make install
WORKDIR /usr/local/src/
RUN rm -rf R-4.0.0*
```
When installing R from source, you can compile it with blas and lapack support by switching the comment on the ./configure statements

### R libs
```
RUN R -e "install.packages(c('shiny', 'Cairo'), repos='http://cran.rstudio.com/')"
```
Cairo is needed for the hello-world preloaded app. If it's missing the histogram won't be loaded

### Cmake
```
#Info: libssl-dev is required to compile cmake 3.17.2, for 3.17.0 it's not needed
WORKDIR /usr/local/src
RUN apt-get install libssl-dev -y
RUN wget https://cmake.org/files/v3.17/cmake-3.17.2.tar.gz
RUN tar xzf cmake-3.17.2.tar.gz
WORKDIR /usr/local/src/cmake-3.17.2
RUN ./configure
RUN make
RUN make install
WORKDIR /usr/local/src/
RUN rm -rf cmake-3.17.2*
```
You can compile the most recent version of cmake 3.17.2 at the time of this writing. Alternatively you can also revert to cmake 3.17.0 without needing to install libssl-dev or avoid compiling cmake altogether by using an older precompiled binary as follows apt-get install cmake. The last option is untested.

