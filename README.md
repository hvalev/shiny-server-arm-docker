# rpi-shiny-server-docker
This is a standalone docker container image which builds shiny-server for arm on debian buster. Tested on a raspberry pi 4b. Be aware that this is a 4,5GB behemoth which takes 3 to 4 hours to build! The image uses a multi-stage build, which will generate a 1GB functional shiny-server image with all (afaik) required packages to build other R-packages and a 4.5GB builder image, which you can remove afterwards.

In order to have it running on your Pi follow the instructions below: <br/>
Install docker (Optional: docker-compose)
```
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker pi
docker run hello-world
```
Optional: install docker-compose
```
sudo apt-get install libffi-dev libssl-dev -y
sudo apt-get install python3 python3-pip -y
sudo pip3 install --upgrade pip
sudo pip3 install docker-compose
```
Install git
```
sudo apt-get install git
```
Build the container
```
docker build https://github.com/hvalev/rpi-shiny-server-docker.git --tag rpi-shiny-server-docker
```
Create the necessary folders for binding docker-container folders to the host os
```
cd ~
mkdir shiny-server
mkdir shiny-server/logs
mkdir shiny-server/conf
mkdir shiny-server/apps
```
Create the named volumes
```
docker volume create --name shiny-apps --opt type=none --opt device=/home/pi/shiny-server/apps/ --opt o=bind
docker volume create --name shiny-logs --opt type=none --opt device=/home/pi/shiny-server/logs/ --opt o=bind
docker volume create --name shiny-conf --opt type=none --opt device=/home/pi/shiny-server/conf/ --opt o=bind
```
Run the container
```
docker run -d -p 3838:3838 -v shiny-apps:/srv/shiny-server/ -v shiny-logs:/var/log/shiny-server/ -v shiny-conf:/etc/shiny-server/ --name rpi-shiny-server hvalev/rpi-shiny-server-docker
```

Optional: Docker-compose variant<br/>
Note: Create the shiny-server folder structure on the host manually from the previous step before proceeding.
```
version: "3.8"
services:
  rpi-shiny-server:
    image: hvalev/rpi-shiny-server-docker
    container_name: rpi-shiny-server
    ports:
      - 3838:3838
    volumes:
       - shiny-apps:/srv/shiny-server/
       - shiny-logs:/var/log/shiny-server/
       - shiny-conf:/etc/shiny-server/
    restart: always

volumes:
  shiny-apps:
    name: shiny-apps
    driver_opts:
      type: none
      device: /home/pi/shiny-server/apps/
      o: bind
  shiny-logs:
    name: shiny-logs
    driver_opts:
      type: none
      device: /home/pi/shiny-server/logs/
      o: bind
  shiny-conf:
    name: shiny-conf
    driver_opts:
      type: none
      device: /home/pi/shiny-server/conf/
      o: bind
```

# Dockerhub
Precompiled image is available from on docker hub here https://hub.docker.com/repository/docker/hvalev/rpi-shiny-server-docker. Compressed image size - 363MB, uncompressed - 1GB
```
docker pull hvalev/rpi-shiny-server-docker
```

# Credit
The following resources were very helpful </br>
https://community.rstudio.com/t/setting-up-your-own-shiny-server-rstudio-server-on-a-raspberry-pi-3b/18982 </br>
https://emeraldreverie.org/2019/11/17/self-hosting-shiny-notes-from-edinbr/ </br>
https://github.com/rstudio/shiny-server/wiki/Building-Shiny-Server-from-Source

# Contents
To optimize the build time, I have inserted the -j4 flags to various make and install commands to utilize multiple cores. As a result, the RAM memory consumption is increased and goes slightly over 1GB at times. Be mindful of that and remove those flags, should you try to compile the image on devices with less than 1GB ram or allocate additional swap memory beforehand.

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
RUN make -j4
RUN make -j4 install
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
RUN make -j4
RUN make -j4 install
WORKDIR /usr/local/src/
RUN rm -rf cmake-3.17.2*
```
You can compile the most recent version of cmake (3.17.2 at the time of this writing). Alternatively you can also use cmake 3.17.0 without needing to install libssl-dev or avoid compiling cmake altogether and use a precompiled binary by substituting the above block with the following command. 
```
apt-get install cmake
```
The last option is untested.

### Shiny-Server
Since we are pulling the shiny-server source from a live repository, it's likely that the node.js version will change. In order to for the build to work, we need to make sure that we are giving the right hash value. Currently the node.js version is v12.16.3. You will see the new version number in the build output and you can simply substitute from here https://nodejs.org/dist/vX.X.X/, where you need to update the NODE_SHA256 as seen below
```
RUN sed -i '8s/.*/NODE_SHA256=8fdf1751c985c4e8048b23bbe9e36aa0cad0011c755427694ea0fda9efad6d97/' shiny-server/external/node/install-node.sh
```
with the value for node-vX.X.X-linux-armv7l.tar.xz in SHASUMS256.txt.
