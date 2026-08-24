# Shiny Server on Docker for x86 and ARM
[![build](https://github.com/hvalev/shiny-server-arm-docker/actions/workflows/build.yml/badge.svg)](https://github.com/hvalev/shiny-server-arm-docker/actions/workflows/build.yml)
![R%20version](https://img.shields.io/badge/R%20version-4.6.1-green)
![Shiny%20version](https://img.shields.io/badge/Shiny%20version-1.5.23.1030-green)
![Docker Pulls](https://img.shields.io/docker/pulls/hvalev/shiny-server-arm)
![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/hvalev/shiny-server-arm)

Docker image hosting Shiny-Server for x86 and ARM (armv7/arm64) architectures. The build features some fixes targeting ARM and comes in two flavours - with and without devtools installed.

## How to run it with docker
First we need to create the folder structure on the host, which will be used to host the shiny-server config, logs and applications.
```bash
mkdir ~/shiny-server
mkdir ~/shiny-server/logs
mkdir ~/shiny-server/conf
mkdir ~/shiny-server/apps
```
Then we need to copy over the server configuration from this repository as well as the hello world app to test if everything works.
```bash
git clone https://github.com/hvalev/shiny-server-arm-docker.git ~/shiny-server-arm-docker
cp ~/shiny-server-arm-docker/shiny-server.conf ~/shiny-server/conf/shiny-server.conf
cp ~/shiny-server-arm-docker/init.sh ~/shiny-server/conf/init.sh
cp -r ~/shiny-server-arm-docker/hello/ ~/shiny-server/apps/
rm -rf ~/shiny-server-arm-docker/
```
Run the container:
```bash
docker run -d -p 3838:3838 -v ~/shiny-server/apps:/srv/shiny-server/ -v ~/shiny-server/logs:/var/log/shiny-server/ -v ~/shiny-server/conf:/etc/shiny-server/ --name shiny-server hvalev/shiny-server-arm:latest
```
and navigate to:
```
http://localhost:3838/hello/
```

## How to run it with docker-compose
You need to create the folders and copy the configurations from the previous section and use the following docker-compose service:
```yaml
services:
  shiny-server:
    image: hvalev/shiny-server-arm:latest
    container_name: shiny-server-arm
    ports:
      - 3838:3838
    volumes:
       - ~/shiny-server/apps:/srv/shiny-server/
       - ~/shiny-server/logs:/var/log/shiny-server/
       - ~/shiny-server/conf:/etc/shiny-server/
    restart: always
```
Run: ```docker-compose up -d``` and navigate to: ```http://host-ip:3838/hello```

## How to use it
The following sections will explain how you can install libraries, import apps, and configure your shiny-server image.

### Installing libraries
Libraries can be installed by modifying the ```init.sh``` file under ```~/shiny-server/conf```. It contains and will execute the ```R -e "install.packages(c('lib1','lib2',...))``` command the first time the container is started. Simply add the libraries you wish installed there. In order to avoid installing the same libraries on each restart, the script generates an ```init_done``` file and will not run if the file is present on the system. To add additional libraries in subsequent runs, delete the ```init_done``` file and add the new libraries to ```init.sh``` as before. Please note that installed libraries will persist between restarts as long as the container image is not removed or recreated.

### Adding and configuring apps
Apps can be added to the ```~/shiny-server/apps``` folder and will be loaded into shiny-server. If you followed the steps in so far, the hello-world app will be accessible under ```http://host-ip:3838/hello```. You can add your own app by copying it over to the folder ```shiny-server/apps```, where it will be available under ```http://host-ip:3838/yourappfolder```. Each app can have an optional per-app configuration file under ```~/shiny-server/yourappfolder/.shiny_app.conf``` (note the underscore - that is the file name shiny-server looks for). When present, it is applied on top of the server configuration, so you can tune a single app (e.g. its timeouts) without touching the global settings. The hello-world app ships with one you can use as a reference, and as a staging ground for building your new app. 

### Configuring shiny-server
Shiny servers' configuration file can be found under ```~/shiny-server/conf/shiny-server.conf```. The default settings should be sufficient, however you can also modify it according to your needs. The [documentation of shiny-server](https://docs.rstudio.com/shiny-server/) is always a good place to start, when you want to tune your installation.

### Troubleshooting
If you run into any trouble along the way, it might be due to permission problems. You can try running the following command: ```chmod -R 777 ~/shiny-server/```.

## Build it yourself
The Dockerfile implements a multi-stage build and will produce a functional 1GB shiny-server image equipped with all necessary libraries to build and install most R-packages. The intermediate builder stage is not part of the final image; with modern BuildKit it only lives in the build cache, which you can clean up with ```docker builder prune```. Be aware that this will take at least 2 hours to build even on an SSD.

Build the container with the following command:
```bash
git clone https://github.com/hvalev/shiny-server-arm-docker.git
docker build shiny-server-arm-docker --tag shiny-server-arm
```

The build supports parallelism build args for fast hosts (defaults are
conservative for small ARM devices):
```bash
docker build shiny-server-arm-docker --tag shiny-server-arm \
    --build-arg R_BUILD_JOBS=8 --build-arg BUILD_JOBS=8 --build-arg PKG_CPUS=8
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
The image bundles Node.js, which shiny-server uses internally. The version is pinned in the Dockerfile (currently v22.23.2) and the matching tarball is downloaded for the architecture being built during the build. Node 22 is the newest release line that still provides linux-armv7l binaries; the newer LTS lines dropped them, and this image keeps supporting arm/v7 devices.

## Acknowledgements
The following resources were very helpful in putting this together:
* https://community.rstudio.com/t/setting-up-your-own-shiny-server-rstudio-server-on-a-raspberry-pi-3b/18982
* https://emeraldreverie.org/2019/11/17/self-hosting-shiny-notes-from-edinbr/
* https://github.com/rstudio/shiny-server/wiki/Building-Shiny-Server-from-Source
* https://www.brodrigues.co/blog/2020-09-20-shiny_raspberry/ for indicating a few libraries to be included in the build which are required for some packages.
