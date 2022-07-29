#!/bin/bash

# Volcado de tablas y datos iniciales en las bases de datos de los proyectos

# Realiza un volcado de la estructura de las bases de datos y los datos iniciales a archivos separados por cada proyecto. Se consideran datos iniciales en una base de datos, los contenidos en todas las tablas que inician con app_*

# Para cada nombre de base de datos (Clave) se define un directorio (Valor)
declare -A databases
databases[blackphp]=blackphp
databases[negkit]=negkit
databases[sicoimWebApp]=sicoim
databases[acrossdesk]=acrossdesk
databases[mimakit]=mimakit
databases[rtinfo]=rtinfo

# Si se ejecuta sin parámetros, se hace un volcado de todas las bases de datos definidas en el arreglo; sino, se realiza sólo de las que han sido especificadas.
if [ "$#" = "0" ]; then
	$0 ${!databases[@]}
	exit 1
fi

# Se guardan todos los volcados en una carpeta temporal, para luego comparar si hubieron cambios. Esto, para evitar que la sincronización en la nuble se repita si solo cambia la fecha de actualización.
temp_dir=/store/blackphp/mysqldump
# Por cada nombre de base de datos recibida por parámetro...
for folder in "$@"; do
	# Comprueba si existe en el arreglo; sino, devolverá un error.
	if [ -v databases[$folder] ]; then
		echo "------------ MYSQLDUMP > ${databases[$folder]} to $folder"

		# Navegamos hacia la carpeta db dentro del proyecto seleccionado
		cd /store/Clouds/Mega/www/$folder/db/

		# Volcado de la estructura, sin el valor de AUTO_INCREMENT
		mysqldump -u root -pldi14517 -d --skip-dump-date ${databases[$folder]} | sed 's/ AUTO_INCREMENT=[0-9]*//g' | sed -e 's/DEFINER[ ]*=[ ]*[^*]*\*/\*/' > $temp_dir/$folder/db_structure.sql

		# Volcado de los valores de todas las tablas que inician con app_*
		mysqldump -u root -pldi14517 -t --skip-dump-date ${databases[$folder]} $(mysql -u root -pldi14517 -D ${databases[$folder]} -Bse "SHOW TABLES LIKE 'app_%'") > $temp_dir/$folder/initial_data.sql

		# Se comprueba que exista un archivo previo de la estructura, y que es diferente. Si el archivo no existe, se crea.
		rsync -c --info=NAME1 "$temp_dir/$folder/db_structure.sql" ./db_structure.sql

		# Se comprueba que exista un archivo previo de los datos iniciales, y que es diferente. Si el archivo no existe, se crea.
		rsync -c --info=NAME1 "$temp_dir/$folder/initial_data.sql" ./initial_data.sql
	else
		echo "    ERROR > PROJECT $folder NOT EXISTS"
	fi
done