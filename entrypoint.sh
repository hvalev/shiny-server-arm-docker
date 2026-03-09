#!/bin/bash
set -e

# Entrypoint wrapper that ensures required configuration files exist before execution
# This solves the issue where users mount a volume over /etc/shiny-server/
# but haven't copied the configuration files to their host yet

DEFAULT_INIT="/opt/default-init.sh"
USER_INIT="/etc/shiny-server/init.sh"
DEFAULT_CONF="/opt/default-shiny-server.conf"
USER_CONF="/etc/shiny-server/shiny-server.conf"

# Check if user provided their own shiny-server.conf via volume mount
if [ ! -f "$USER_CONF" ]; then
    echo "No shiny-server.conf found at $USER_CONF, copying default..."
    cp "$DEFAULT_CONF" "$USER_CONF"
fi

# Check if user provided their own init.sh via volume mount
if [ ! -f "$USER_INIT" ]; then
    echo "No init.sh found at $USER_INIT, copying default..."
    cp "$DEFAULT_INIT" "$USER_INIT"
    chmod +x "$USER_INIT"
fi

# Execute the init script
exec "$USER_INIT"
