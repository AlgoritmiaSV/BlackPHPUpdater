#!/bin/bash

# Monificador de javascript y jQuery con la API toptal.com

# REQUERIMIENTOS
# wget

#Cargando configuración inicial
script_path=`realpath $0`
script_dir=`dirname $script_path`
blackphp_path=`jq -r ".blackphp_path" $script_dir/config.json`
temp_path=`jq -r ".temp_path" $script_dir/config.json`

# Navegar hacia el directorio de BlackPHP donde se encuentrasn los scripts
dir=$blackphp_path/public/scripts
temp_folder=$temp_path/js
if [ ! -d $temp_folder ]; then
	mkdir -p $temp_folder
fi
temp_file1=$temp_folder/bpscript1.js
temp_file2=$temp_folder/bpscript2.js
cd $dir

# Verificar cuáles de los scipt son más nuevos que el último bpscript.min.js generado.
scripts=(main lists forms change_status table_calculation dialogs tree charts persistent_forms passwords required_asterisk)
group1=(change_status main lists forms passwords required_asterisk)
group2=(dialogs tree charts persistent_forms table_calculation)
modified=false
echo "------------ Minify JS"
# Imprime la fecha y hora de última generación de bpscript.min.js
# echo "    bpscript.min.js last update: `stat -c %y bpscript.min.js`"
for i in "${scripts[@]}"; do
	if [ "$i.js" -nt bpscript.min.js ]; then
		echo "    $i.js Modified"
		modified=true
	fi
done
# Si hay al menos un archivo nuevo, entonces se hace de nuevo el proceso de minificación; de lo contrario, imprime "All up to date"
if $modified; then
	echo "Minifying..."
	echo "/* BPHPSCRIPT */" > $temp_file1
	for i in ${group1[@]}; do
		cat $i.js >> $temp_file1
	done
	echo "/* BPHPSCRIPT */" > $temp_file2
	for j in ${group2[@]}; do
		cat $j.js >> $temp_file2
	done
	echo "/*BlackPHP (c)2022 - 2026 Edwin Fajardo.*/" > $dir/bpscript.min.js

	data=`php -r "echo urlencode(file_get_contents(\"$temp_file1\"));"`
	wget -q --post-data="input=$data" -O - https://www.toptal.com/developers/javascript-minifier/api/raw >> $dir/bpscript.min.js

	data=`php -r "echo urlencode(file_get_contents(\"$temp_file2\"));"`
	wget -q --post-data="input=$data" -O - https://www.toptal.com/developers/javascript-minifier/api/raw >> $dir/bpscript.min.js

	# echo ";" >> $dir/bpscript.min.js
fi
