#!/bin/bash

# Creación de una versión de lanzamiento de proyectos derivados de BlackPHP

# El objetivo de este script es generar una versión de lanzamiento de los proyectos, sin comentarios, sin archivos propios de las entidades, y con todos los archivos minificados (PHP, CSS, HTML y JavaScripts), listo para subir a la web, actualizarlo en otro servidor, o llevarlo en formato zip.
# Los Javascript no se minifican aquí, porque antes de esto debió realizarse el poceso de minificación de archivos JS que está en otro de los scripts

# Para esta operación, se necesitan permisos de root (Sólo en Linux)
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	command="${0} ${@}"
	su -c "$command"
	exit 1
fi

#Cargando configuración inicial
script_path=`realpath $0`
script_dir=`dirname $script_path`
temp_path=`jq -r ".temp_path" $script_dir/config.json`
config_files=$script_dir/projects
cd $config_files

# Si se ejecuta sin parámetros, se hace un volcado de todas las bases de datos definidas en el arreglo; sino, se realiza sólo de las que han sido especificadas.
if [ "$#" = "0" ]; then
	for config_file in `ls -I "_*"`
	do
		$0 "$config_file"
	done
	exit 1
fi
if [ "$#" -gt "1" ]; then
	for config_file in "$@"
	do
		$0 "$config_file"
	done
	exit 1
fi

config_file=$1
if [[ "$config_file" != *.json ]]; then
	config_file="${config_file}.json"
fi

if [ ! -f "$config_file" ]; then
	echo "File $config_file not exists!"
	exit 1
fi
project_name=`jq -r ".project_name" $config_file`
project_path=`jq -r ".project_path" $config_file`
database=`jq -r ".database" $config_file`
project_folder=`basename $project_path`
temp_dir=$temp_path/locale/$project_folder
echo "------------ Releasing $project_name"

# Carpeta de producción, donde se encontrarán los archivos resultantes
production=$temp_path/production/$project_folder
if [ ! -d "$production" ]; then
	mkdir -p "$production"
fi

# Todos los lanzamientos. En esta carpeta estarán los archivos zip de cada vez que se ejecute el script
releases=$temp_path/releases/$project_folder
if [ ! -d "$releases" ]; then
	mkdir -p "$releases"
fi

# Creación de un archivo JSON con la fecha de lanzamiento
cd $project_path
echo "    Setting date..."
last_update=`jq -r ".last_update" app_info.json`
modified=`find . -type f -newermt "$last_update" ! -name "app_info.json" ! -name "*_updates.sql" ! -path "./node_modules/*" ! -path "./composer/*" ! -path "./.git/*" ! -path "./.vscode/*" | wc -l`
if [ $modified -gt "0" ]; then
	last_update=`date +"%Y-%m-%d %H:%M:%S"`
	number=`jq -r ".number" app_info.json`
	number=$((number+1))
	app_info=`cat app_info.json`
	echo $app_info | jq --arg last_update "$last_update" --arg number "$number" '.last_update |= "\($last_update)" | .number |= "\($number)"' > app_info.json
fi
# Sincronización de archivos no sujetos a minificación, como las imágenes, fuentes, y archivos que previamente hayan sido minificados
echo "    Syncing..."
rsync -cr --delete --chown=fajardo:fajardo --chmod=D755,F644 \
	--exclude ".git" \
	--exclude ".gitignore" \
	--exclude "entities/" \
	--exclude "db/mysql/history/" \
	--exclude "node_modules/" \
	--exclude ".vscode" \
	--include "default_config.php" \
	--exclude "*.php" \
	--exclude "public/scripts/main.js" \
	--exclude "public/scripts/lists.js" \
	--exclude "public/scripts/forms.js" \
	--exclude "public/scripts/change_status.js" \
	--exclude "public/scripts/table_calculation.js" \
	--exclude "public/scripts/dialogs.js" \
	--exclude "public/scripts/tree.js" \
	--exclude "public/scripts/charts.js" \
	--exclude "public/scripts/persistent_forms.js" \
	--exclude "public/scripts/passwords.js" \
	--exclude "public/scripts/required_asterisk.js" \
	--include "public/scripts/*/*.js" \
	--include "public/scripts/*.js" \
	--exclude "*.html" \
	--include "*.min.css" \
	--exclude "*.css" \
	--exclude "CHANGELOG.*" \
	--exclude "changelog.*" \
	--exclude "*.scss" \
	--exclude "messages.po" \
	--info=NAME1 $project_path/ $production/

# Minificación y copia de archivos PHP
echo "    Minifying PHP..."
while read -r php_file; do
	if [ ! -f "$production/$php_file" -o "$project_path/$php_file" -nt "$production/$php_file" ]; then
		rsync "$project_path/$php_file" "$production/$php_file"
		php_directory=`dirname "$production/$php_file"`
		if [[ "$php_directory" == "$production/./controllers"* ]]; then
			variable_list=$temp_path/vars.txt
			grep -v 'protected $' "$production/$php_file" | grep -v 'public $' | grep -v 'private $' | grep -Ee '\$[A-Za-z0-9_]+' | sed -E 's/\$/\n\$/g' | sed -E 's/(\$[A-Za-z0-9_]+)(.*)/\1/g' | grep -Ev '\s' > $variable_list
			sort -ru -o $variable_list $variable_list
			var_index=0
			letters=({a..z})
			count=${#letters[@]}
			prefix_index=-1
			reserved=false
			sed -i "s/\(public\|private\|protected\)\( \\$\)/___\1___/g" "$production/$php_file"
			for var in `cat $variable_list`; do
				for item in \$this \$_POST \$_GET \$_SERVER \$_SESSION \$_FILES \$_COOKIE \$_REQUEST \$_ENV '$";'; do
					if [[ "$var" == "$item" ]]; then
						reserved=true
						break
					fi
				done
				if [[ $reserved == true ]]; then
					reserved=false
					continue
				fi
				prefix=""
				var_name=${letters[var_index]}
				if [ $prefix_index -gt -1 ]; then
					prefix=${letters[prefix_index]}
				fi
				sed -i "s/$var/\$#TEMP#$prefix$var_name/g" "$production/$php_file"
				((var_index=var_index+1))
				if [ $var_index -eq $count ]; then
					var_index=0
					((prefix_index=prefix_index+1))
				fi
			done
			sed -i "s/___\(public\|private\|protected\)___/\1 $/g" "$production/$php_file"
			sed -i "s/#TEMP#//g" "$production/$php_file"
		fi
		production_code=`/usr/bin/php -w $production/$php_file`
		echo "$production_code" > $production/$php_file
		echo "    $php_file"
	fi
done < <(find . -type f -name "*.php" ! -name "default_config.php" ! -path "./entities/*")

# Minificación y copia de archivos CSS
echo "    Minifying CSS..."
while read -r css_file; do
	if [ ! -f "$production/$css_file" -o "$project_path/$css_file" -nt "$production/$css_file" ]; then
		echo "    $css_file"
		cat $css_file | sed -e "s|/\*\(\\\\\)\?\*/|/~\1~/|g" -e "s|/\*[^*]*\*\+\([^/][^*]*\*\+\)*/||g" -e "s|\([^:/]\)//.*$|\1|" -e "s|^//.*$||" | tr '\n' ' ' | sed -e "s|/\*[^*]*\*\+\([^/][^*]*\*\+\)*/||g" -e "s|/\~\(\\\\\)\?\~/|/*\1*/|g" -e "s|\s\+| |g" -e "s| \([{;:,]\)|\1|g" -e "s|\([{;:,]\) |\1|g" > $production/$css_file
	fi
done < <(find . -type f -name "*.css" ! -name "*.min.css" ! -path "./node_modules/*")

# Minificación y copia de archivos HTML
echo "    Minifying HTML..."
while read -r html_file; do
	if [ ! -f "$production/$html_file" -o "$project_path/$html_file" -nt "$production/$html_file" ]; then
		cat $html_file | sed ':a;N;$!ba;s/>\s*</></g' > $production/$html_file
		echo "    $html_file"
	fi
done < <(find . -type f -name "*.html" ! -path "./node_modules/*")

# Exportando node_modules; sólo las carpetas de distribución.
node_dir=$temp_path/node_modules/
if [ ! -d $node_dir ]; then
	mkdir -p $node_dir
fi
node_folders=$node_dir/$project_folder.txt
echo "" > $node_folders
for i in `cat $project_path/libs/View.php | grep "node_modules" | grep -v "=" | tr -d "'" | tr -d ","`; do
	dirname $i >> $node_folders
done
sort -u -o $node_folders $node_folders
for i in `cat $node_folders | sed '/^$/d'`; do
	if [ ! -d $production/$i/ ]; then
		mkdir -p $production/$i/
	fi
	rsync -cr --delete --exclude "docs" --chown=fajardo:fajardo --chmod=D755,F644 --info=NAME1 $project_path/$i/ $production/$i/
done

# Navegando hacia la carppeta de producción
cd $production

# Eliminando archivos innecesarios
# La comprobación de pwd y $production se hace para evitar eliminar algun archivo por error
# en caso de que cd $production haya fallado
if [ "`pwd`" = "$production" ]; then
	while read -r file_name; do
		if [ ! -f "$project_path/$file_name" ] && [ ! -d "$project_path/$file_name" ]; then
			rm -rv $file_name
		fi
	done < <(find .)
fi

# Compresión en un archivo zip que irá a la carpeta releases
zip_file=$releases/release_`/bin/date +\%Y\%m\%d\%H\%M\%S`.zip
zip -rqdg $zip_file ./
chown -R fajardo:fajardo $production/
chown -R fajardo:fajardo $releases/
