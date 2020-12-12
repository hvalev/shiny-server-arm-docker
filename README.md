# Shiny Server on Docker for ARM
This is a standalone docker container image which builds shiny-server for arm on debian buster. Tested on a raspberry pi 4b. Be aware that this is a 4,5GB behemoth which takes a few hours to build! The image uses a multi-stage build, which will generate a 1GB functional shiny-server image with all (afaik) necessary libraries to build most R-packages and a 4.5GB builder image, which you can remove afterwards.

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
docker build https://github.com/hvalev/shiny-server-arm-docker.git --tag shiny-server-arm
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
docker run -d -p 3838:3838 -v shiny-apps:/srv/shiny-server/ -v shiny-logs:/var/log/shiny-server/ -v shiny-conf:/etc/shiny-server/ --name rpi-shiny-server hvalev/shiny-server-arm
```

Optional: Docker-compose variant<br/>
Note: Create the shiny-server folder structure on the host manually from the previous step before proceeding.
```
version: "3.8"
services:
  rpi-shiny-server:
    image: hvalev/shiny-server-arm
    container_name: shiny-server-arm
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

### Dockerhub
A Docker image is available here https://hub.docker.com/r/hvalev/shiny-server-arm. Compressed image size ~ 400MB; uncompressed - 1GB.

### Credit
The following resources were very helpful </br>
https://community.rstudio.com/t/setting-up-your-own-shiny-server-rstudio-server-on-a-raspberry-pi-3b/18982 </br>
https://emeraldreverie.org/2019/11/17/self-hosting-shiny-notes-from-edinbr/ </br>
https://github.com/rstudio/shiny-server/wiki/Building-Shiny-Server-from-Source </br>
https://www.brodrigues.co/blog/2020-09-20-shiny_raspberry/ for indicating a few libraries to be included in the build which are required for some packages.

# How to use

### hello/
The dockerfile preloads the hello-world shiny app to test if everything is working post install.

### shiny-server.conf
Sample configuration file for shiny-server. The hello app is already configured there.

### init.sh
Will be executed once when the container is first started. It generates an init_done file when completed. If you need to make any changes to the installed R libraries (or execute other commands) between restarts, simply delete the init_done file and append to the init.sh the libraries you wish to add as shown below.
```
R -e "install.packages(c('shinyjs','filelock'), repos='http://cran.rstudio.com/')"
```

# Build it yourself
Read below if you'd like to make some modifications to the base image or compile it yourself.

### RAM usage
To optimize build time, I have used the -j4 flags to utilize multiple cores in various make and install commands. As a result RAM consumption is increased and goes slightly over 1GB at times. Should you compile the image on devices with less RAM, make sure you allocate some swap memory beforehand. </br>

### Blas and Lapack support
To enable blas and lapack support, switch the comment in the following ./configure statements.
```
#Optional: include blas and lapack
#RUN ./configure --enable-R-shlib --with-blas --with-lapack
RUN ./configure --enable-R-shlib
```

### Default R libraries
Although you can install R libraries post-install, you could also bake those in the image by adding them to the run statement below in the Dockerfile.
```
RUN R -e "install.packages(c('shiny', 'Cairo'), repos='http://cran.rstudio.com/')"
```
Cairo is needed for the hello-world preloaded app. If it's missing the histogram won't be loaded.

### Node.js
The shiny server install script is pulled from a live repository. As a consequence, the node.js version might change. In order for the build to work, you need to identify in the console log the node.js version and modify the following statement with the correct hash.
```
RUN sed -i '8s/.*/NODE_SHA256=8fdf1751c985c4e8048b23bbe9e36aa0cad0011c755427694ea0fda9efad6d97/' shiny-server/external/node/install-node.sh
```
The hash value you can find in https://nodejs.org/dist/vX.X.X/. The value you're looking for will be in SHASUMS256.txt under node-vX.X.X-linux-armv7l.tar.xz.