#!/bin/bash
#commands to execute on the first run of the container. Useful to supplement any missing libraries for your projects
#when done an init_done file will appear which will skip the set-up phase on consecutive runs

FILE=/etc/shiny-server/init_done
if [ ! -f "$FILE" ]; then
    #example for installing R libraries
	#R -e "install.packages(c('shinyjs','filelock'), repos='http://cran.rstudio.com/')"
	touch /etc/shiny-server/init_done
fi

shiny-server