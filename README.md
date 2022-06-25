# Shiny Server on Docker for ARM
[![build](https://github.com/hvalev/shiny-server-arm-docker/actions/workflows/build.yml/badge.svg)](https://github.com/hvalev/shiny-server-arm-docker/actions/workflows/build.yml)
![R%20version](https://img.shields.io/badge/R%20version-4.2.1-green)
![Shiny%20version](https://img.shields.io/badge/Shiny%20version-1.5.17.973-green)
![Docker Pulls](https://img.shields.io/docker/pulls/hvalev/shiny-server-arm)
![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/hvalev/shiny-server-arm)

Docker image hosting Shiny-Server for ARM (armv7/arm64) and AMD (amd64) architectures. The build features some fixes targeting ARM and is primarily intended to be deployed on SBCs (Single Board Computers) such as Raspberry Pi.

## How to run it with docker
First we need to create the folder structure on the host, which will be used to host the shiny-server config, logs and applications.
```
mkdir ~/shiny-server
mkdir ~/shiny-server/logs
mkdir ~/shiny-server/conf
mkdir ~/shiny-server/apps
```
Then we need to copy over the server configuration from this repository as well as the hello world app to test if everything works.
```
git clone https://github.com/hvalev/shiny-server-arm-docker.git ~/shiny-server-arm-docker
cp ~/shiny-server-arm-docker/shiny-server.conf ~/shiny-server/conf/shiny-server.conf
cp ~/shiny-server-arm-docker/init.sh ~/shiny-server/conf/init.sh
cp -r ~/shiny-server-arm-docker/hello/ ~/shiny-server/apps/
rm -rf ~/shiny-server-arm-docker/
```
Run the container:
```docker run -d -p 3838:3838 -v ~/shiny-server/apps:/srv/shiny-server/ -v ~/shiny-server/logs:/var/log/shiny-server/ -v ~/shiny-server/conf:/etc/shiny-server/ --name shiny-server hvalev/shiny-server-arm:latest```
and navigate to:
```http://host-ip:3838/hello```

## How to run it with docker-compose
You need to create the folders and copy the configurations from the previous section and use the following docker-compose service:
```
version: "3.8"
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
Apps can be added to the ```~/shiny-server/apps``` folder and will be loaded into shiny-server. If you followed the steps in so far, the hello-world app will be accessible under ```http://host-ip:3838/hello```. You can add your own app by copying it over to the folder ```shiny-server/apps```, where it will be available under ```http://host-ip:3838/yourappfolder```. Be aware that each app will need to have its own configuration file under ```~/shiny-server/yourappfolder/.shiny_app.conf```. You can use the hello-world app as staging ground for building your new app. 

### Configuring shiny-server
Shiny servers' configuration file can be found under ```~/shiny-server/conf/shiny-server.conf```. The default settings should be sufficient, however you can also modify it according to your needs. The [documentation of shiny-server](https://docs.rstudio.com/shiny-server/) is always a good place to start, when you want to tune your installation.

### Troubleshooting
If you run into any trouble along the way, it might be due to permission problems. You can try running the following command: ```chmod -R 777 ~/shiny-server/```.

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
I have written the [determine_arch.sh](https://github.com/hvalev/shiny-server-arm-docker/blob/master/determine_arch.sh) script, which automagically determines the architecture it's running on, fetches the appropriate node.js checksum and replaces it in the install-node.sh file. It should be future-proof as the reference node.js version is taken from the cloned shiny-server repository itself.

## Acknowledgements
The following resources were very helpful in putting this together:
* https://community.rstudio.com/t/setting-up-your-own-shiny-server-rstudio-server-on-a-raspberry-pi-3b/18982
* https://emeraldreverie.org/2019/11/17/self-hosting-shiny-notes-from-edinbr/
* https://github.com/rstudio/shiny-server/wiki/Building-Shiny-Server-from-Source
* https://www.brodrigues.co/blog/2020-09-20-shiny_raspberry/ for indicating a few libraries to be included in the build which are required for some packages.
