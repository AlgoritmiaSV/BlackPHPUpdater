#!/bin/bash

# Ejecución de scripts de BlackPHP Updater

# Se requieren permisos de root (Sólo en Linux)
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	command="${0} ${@}"
	su -c "$command"
	exit 1
fi

# Ruta de los scripts
echo "Update web"
script_path=`realpath $0`
path=`dirname $script_path`

# Ejecución
$path/minify_js.sh
$path/sass.sh
$path/blackphp_sync.sh
$path/mysqldump.sh
$path/language.sh
$path/images.sh
