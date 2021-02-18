#!/bin/bash
ARCH=$(uname -m); 
if [[ "$ARCH" = "aarch64" ]] ; then ARCH='arm64' ; fi 
if [[ "$ARCH" = "x86_64" ]] ; then ARCH='x64' ; fi 
NODE_VERSION=$(cat shiny-server/.nvmrc)
wget "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt"; 
SHA=$(grep "linux-$ARCH.tar.xz" SHASUMS256.txt | awk -F '  +' '{print $1}'); 
sed -i -e "8s/.*/NODE_SHA256=$SHA/" -e "s/linux-x64.tar.xz/linux-$ARCH.tar.xz/" -e "s/https:\/\/github.com\/jcheng5\/node-centos6\/releases\/download\//https:\/\/nodejs.org\/dist\//" shiny-server/external/node/install-node.sh