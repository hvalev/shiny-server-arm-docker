#!/bin/bash
# Script which executes during the containers' first run. 
# Useful to supplement any missing libraries for your projects.
# When executed, the script generates an init_done file.
# The file will prevent the execution of this script in consecutive runs.

# If you want to add further libraries along the way, delete the init_done file
# and append them to the R -e "install.packages..." command.

FILE=/etc/shiny-server/init_done
if [ ! -f "$FILE" ]; then
    #example for installing R libraries
    #R -e "install.packages(c('shinyjs','filelock'), repos='http://cran.rstudio.com/')"
    touch /etc/shiny-server/init_done
fi

shiny-server