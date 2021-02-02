# Shiny Server on Docker for ARM
![build](https://github.com/hvalev/shiny-server-arm-docker/workflows/ci/badge.svg)
![Docker Pulls](https://img.shields.io/docker/pulls/hvalev/shiny-server-arm)
![Docker Stars](https://img.shields.io/docker/stars/hvalev/shiny-server-arm)
![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/hvalev/shiny-server-arm)

Docker image which builds Shiny-Server for ARM architectures (such as raspberry pi). Generates both an armv7 and arm64 image and is future-proof with new versions of node.js for Shiny-Server. The latest image is build with R v4.0.3 and Shiny-Server v1.5.16.958.

## How to run it
Create the shiny-server folders which the container will use:
```
cd ~
mkdir shiny-server
mkdir shiny-server/logs
mkdir shiny-server/conf
mkdir shiny-server/apps
```
Bind the folders as named volumes in order to expose the contents of the container to the host os:
```
docker volume create --name shiny-apps --opt type=none --opt device=/home/pi/shiny-server/apps/ --opt o=bind
docker volume create --name shiny-logs --opt type=none --opt device=/home/pi/shiny-server/logs/ --opt o=bind
docker volume create --name shiny-conf --opt type=none --opt device=/home/pi/shiny-server/conf/ --opt o=bind
```
Run the container:
```docker run -d -p 3838:3838 -v shiny-apps:/srv/shiny-server/ -v shiny-logs:/var/log/shiny-server/ -v shiny-conf:/etc/shiny-server/ --name shiny-server-arm hvalev/shiny-server-arm:0.2.0```
and navigate to:
```http://host-ip:3838/```

## How to run it with docker-compose
You need to create the folders from the previous section using the first command. It is not necessary to bind them. Use the following docker-compose.yml file:
```
version: "3.8"
services:
  rpi-shiny-server:
    image: hvalev/shiny-server-arm:0.2.0
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
      device: ~/shiny-server/apps/
      o: bind
  shiny-logs:
    name: shiny-logs
    driver_opts:
      type: none
      device: ~/shiny-server/logs/
      o: bind
  shiny-conf:
    name: shiny-conf
    driver_opts:
      type: none
      device: ~/shiny-server/conf/
      o: bind
```
Run: ```docker-compose up -d``` and navigate to: ```http://host-ip:3838/```

## How to use it (please read fully and carefully!)
The following sections will explain how you can install libraries and import your own projects.

### Installing libraries
Libraries can be installed by modifying the ```init.sh``` file. It contains and will execute the ```R -e "install.packages(c('lib1','lib2',...))``` command the first time the container is started. Simply add the libraries you wish installed there. In order to avoid installing the same libraries on each restart, the script generates an ```init_done``` file and will not run if the file is present on the system. To add additional libraries in subsequent runs, delete the ```init_done``` file and add the new libraries to ```init.sh``` as before. Please note that installed libraries will persist between restarts as long as the container image is not removed or recreated. **Make sure you use a versioned container (such as hvalev/shiny-server-arm:0.2.0), rather than the :latest tag or avoid using updater containers such as ouroboros or watchtower as an update might remove your installed applications and configurations!**

### Adding and configuring apps
The docker image comes with the hello-world app preloaded. Once the container is running, it will be accessible at ```http://host-ip:3838/hello```. Its configuration file can be found at ```shiny-server/conf/shiny-server.conf```. You can use the hello-world project as a staging ground for building new apps. You can add your own apps by copying them over to the folder ```shiny-server/apps```. The application will then be available on ```http://host-ip:3838/yourappfolder```.

### Configuring shiny-server
The file ```shiny-server/conf/shiny-server.conf``` also stores the configuration for shiny-server. The default settings should be sufficient, however you can also modify it according to your needs.

## Build it yourself
The Dockerfile implements a multi-stage build and will produce a functional 1GB shiny-server image equipped with all necessary libraries to build and install most R-packages. Additionally, it will leave a 4.5GB builder image behind post-build, which you can remove. Be aware that this will take at least 2 hours to build even on an SSD.

Build the container with the following command:
```
docker build https://github.com/hvalev/shiny-server-arm-docker.git --tag shiny-server-arm
```

### RAM usage
To speed-up building, I have used -j4 flags when applicable to utilize multiple cores. As a result RAM consumption goes slightly over 1GB at times. Should you compile the image on devices with less RAM, make sure you allocate some swap memory beforehand.

### Blas and Lapack support
Since this is an automated build, Blas and Lapack support have been included by default.
If you wish to compile R without them, remove the ```--with-blas --with-lapack``` from the following statement in the Dockerfile: ```./configure --enable-R-shlib --with-blas --with-lapack```

### Default R libraries
Although you can install R libraries post-install, you could also bake those in the image by adding them to the following run statement in the Dockerfile:
```RUN R -e "install.packages(c('shiny', 'Cairo'), repos='http://cran.rstudio.com/')"```.
Cairo is needed for the hello-world preloaded app. If it's missing the histogram won't be loaded.

### Node.js
~~The shiny server install script is pulled from a live repository. As a consequence, the node.js version might change. In order for the build to work, you need to identify in the console log the node.js version and modify the following statement with the correct hash.~~
~~`RUN sed -i '8s/.*/NODE_SHA256=8fdf1751c985c4e8048b23bbe9e36aa0cad0011c755427694ea0fda9efad6d97/' shiny-server/external/node/install-node.sh`~~
~~The hash value you can find in https://nodejs.org/dist/vX.X.X/. The value you're looking for will be in SHASUMS256.txt under node-vX.X.X-linux-armv7l.tar.xz.~~
I have written the [determine_arch.sh](https://github.com/hvalev/shiny-server-arm-docker/blob/master/determine_arch.sh) script, which automagically determines the architecture it's runnig on, fetches the appropriate node.js checksum and replaces it in the install-node.sh file. It should be future-proof as the reference node.js version is taken from the cloned shiny-server repository itself.

## Acknowledgements
The following resources were very helpful in putting this together:
* https://community.rstudio.com/t/setting-up-your-own-shiny-server-rstudio-server-on-a-raspberry-pi-3b/18982
* https://emeraldreverie.org/2019/11/17/self-hosting-shiny-notes-from-edinbr/
* https://github.com/rstudio/shiny-server/wiki/Building-Shiny-Server-from-Source
* https://www.brodrigues.co/blog/2020-09-20-shiny_raspberry/ for indicating a few libraries to be included in the build which are required for some packages.
