#/bin/bash
# Actualizador de archivos de idioma

# En una lista definida $projects, se busca e cada proyecto, en la carpeta locale/, cada uno de los idiomas definidos en el arreglo $locales. Dentro de ella, se buscan los archivos messages.po, y se convierten a messages.mo, para luego poder ser accedidos por gettext

# REQUERIMIENTOS
# gettext
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
		$0 "$config_files/$config_file"
	done
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "File $1 not exists!"
	exit 1
fi
project_name=`jq -r ".project_name" $1`
project_path=`jq -r ".project_path" $1`
db_host=`jq -r ".db_host" $1`
db_user=`jq -r ".db_user" $1`
db_password=`jq -r ".db_password" $1`
database=`jq -r ".database" $1`
db_prefix=`jq -r ".db_prefix" $1`
project_folder=`basename $project_path`
temp_dir=$temp_path/locale/$project_folder

# Lista de idiomas regionales
locales=`jq -c ".locales[]" "$1" | sed 's/"//g'`

echo "------------ Update language files in $project_folder"

# Directorio temporal
if [ ! -d "$temp_dir" ]; then
	mkdir -p "$temp_dir"
fi
cd $temp_dir

# Extrayendo palabras y frases de las vistas
grep -nrw "$project_path/views/" -Ee '_\([^\)]+\)' | sed -E 's/\)/\)\n/g' | grep -Ee '_\([^\)]+\)' | sed -E 's/(.*_\()([^\)]*)(\).*)/\2/' | grep -v '{{' > required.txt

# Extrayendo palabras y frases del núcleo del sistema
grep -nrw "$project_path/libs/" -Ee '_\([^\)]+\)'  | sed -E 's/\)/\)\n/g' | grep -Ee '_\([^\)]+\)' | sed -E 's/(.*_\(\")([^\)]*)(\"\).*)/\2/' | grep -v "$project_path" | grep -Ev '\$|_\(' >> required.txt
grep -nrw "$project_path/utils/" -Ee '_\([^\)]+\)'  | sed -E 's/\)/\)\n/g' | grep -Ee '_\([^\)]+\)' | sed -E 's/(.*_\(\")([^\)]*)(\"\).*)/\2/' | grep -v "$project_path" >> required.txt

# Extrayendo palabras y frases de los controladores
grep -nrw "$project_path/controllers/" -Ee '_\([^\)]+\)'  | sed -E 's/\)/\)\n/g' | grep -Ee '_\([^\)]+\)' | sed -E 's/(.*_\(\")([^\)]*)(\"\).*)/\2/' | grep -v "$project_path" >> required.txt

# Extrayendo palabras y frases de las talas del sistema
# -> Nombre de los módulos
# -> Nombre de los métodos
# -> Nombre de los temas
# -> Nombre singular y plural de los elementos
mysql --skip-column-names \
	-h "$db_host" \
	-u "$db_user" \
	-p"$db_password" \
	"$database" \
	-e "
		SELECT description FROM ${db_prefix}app_catalogs
		UNION ALL
		SELECT module_name FROM ${db_prefix}app_modules WHERE status = 1
		UNION ALL
		SELECT method_name FROM ${db_prefix}app_methods WHERE status = 1
		UNION ALL
		SELECT theme_name FROM ${db_prefix}app_themes
		UNION ALL
		SELECT element_name FROM ${db_prefix}app_elements
		UNION ALL
		SELECT singular_name FROM ${db_prefix}app_elements
		UNION ALL
		SELECT locale_name FROM ${db_prefix}app_locales
		UNION ALL
		SELECT category_name FROM ${db_prefix}app_option_categories
		UNION ALL
		SELECT option_description FROM ${db_prefix}app_options
		UNION ALL
		SELECT value_label FROM ${db_prefix}app_option_values
	" >> required.txt

# Evaluando si existe la tabla app_payment_types
app_payments=`mysql --skip-column-names \
	-h $db_host \
	-u $db_user \
	-p$db_password information_schema \
	-e "
		SELECT 1
		FROM TABLES
		WHERE TABLE_SCHEMA = '$database'
			AND TABLE_NAME = '${db_prefix}app_payment_types'
	"`
if [ "$app_payments" = "1" ]; then
	# Extrayendo las formas de pago de la base de datos
	mysql --skip-column-names -h $db_host -u $db_user -p$db_password $database -e "SELECT CONCAT('payments', type_name) FROM ${db_prefix}app_payment_types" >> required.txt
fi

# Evaluando si existe la tabla app_documents
app_documents=`mysql --skip-column-names -h $db_host -u $db_user -p$db_password information_schema -e "SELECT 1 FROM TABLES WHERE TABLE_SCHEMA = '$database' AND TABLE_NAME = '${db_prefix}app_documents'"`
if [ "$app_documents" = "1" ]; then
	# Extrayendo las formas de pago de la base de datos
	mysql --skip-column-names -h $db_host -u $db_user -p$db_password $database -e "SELECT document_name FROM ${db_prefix}app_documents" >> required.txt
fi

# Ordenando las palabras en el archivo required, y eliminando las repetidas
sort -u -o required.txt required.txt

for locale in $locales; do
	locale_dir="$temp_dir/$locale"
	if [ ! -d "$locale_dir" ]; then
		mkdir -p "$locale_dir"
	fi
	directory="$project_path/locale/$locale/LC_MESSAGES"
	if [ ! -d "$directory" ]; then
		mkdir -p "$directory"
	fi
	cd $directory
	php $script_dir/po_sort.php "$1" $locale
	rsync -c $locale_dir/messages.po $directory/messages.po
	if [ "messages.po" -nt "messages.mo" ]; then
		msgfmt messages.po
		echo "$locale Changed"
	fi
done
