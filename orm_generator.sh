#!/bin/bash
# Para cada nombre de proyecto (Carpeta = Clave) se define una base de datos (Valor)
declare -A databases
databases[blackphp]=blackphp
databases[negkit]=negkit
databases[sicoimWebApp]=sicoim
databases[acrossdesk]=acrossdesk
databases[mimakit]=mimakit

# Posibles tipos de columna en la base de datos (Se deben registrar las faltantes)
declare -A types
types[int]=int
types[smallint]=int
types[tinyint]=int
types[char]=string
types[varchar]=string
types[text]=string
types[smalltext]=string
types[tinytext]=string
types[date]=string
types[datetime]=string
types[float]=float
types[decimal]=float

# Si se ejecuta sin parámetros, se hace un volcado de todas las bases de datos definidas en el arreglo; sino, se realiza sólo de las que han sido especificadas.
if [ "$#" = "0" ]; then
	$0 ${!databases[@]}
	exit 1
fi

for folder in "$@"; do
	echo "------------ ORM for project $folder"
	if [ -v databases[$folder] ]; then
		tables=`mysql --skip-column-names -u root -pldi14517 -e "show tables from ${databases[$folder]}"`
		table_position=0
		table_name=""
		for table in $tables; do
			file=/store/blackphp/orm/$folder/$table"_model.php"
			echo "Model for table $table"
			echo "<?php" > $file
			echo "/**" >> $file
			echo " * Model for $table" >> $file
			echo " * " >> $file
			echo " * Generated by BlackPHP" >> $file
			echo " */" >> $file
			echo "" >> $file
			echo "class "$table"_model extends Model" >> $file
			echo "{" >> $file

			#Consultando columnas y creando propiedades
			columns=`mysql --skip-column-names -u root -pldi14517 -e "SELECT COLUMN_NAME, DATA_TYPE, IF(COLUMN_COMMENT = '', '-', REPLACE(COLUMN_COMMENT, ' ', '_')) AS COMMENT FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = '${databases[$folder]}' AND TABLE_NAME = '$table'"`
			column_position=0
			column_name=""
			column_type=""
			for column_data in $columns; do
				if [ $column_position -eq 0 ]; then
					column_name=$column_data
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 1 ]; then
					column_type=$column_data
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 2 ]; then
					column_comment=$column_data
					column_position=0
					echo -ne "\t/** @var ${types[$column_type]} \$$column_name" >> $file
					echo " $column_comment */" | sed 's/_/\ /g' >> $file
					echo -e "\tprivate \$$column_name;" >> $file
					echo "" >> $file
					continue
				fi
			done

			# Constructor de la clase (Inicializa nombre de la tabla y llave primaria)
			echo -e "\t/**" >> $file
			echo -e "\t * Constructor de la clase" >> $file
			echo -e "\t * " >> $file
			echo -e "\t * Inicializa las propiedades table_name y primary_key" >> $file
			echo -e "\t */" >> $file
			echo -e "\tpublic function __construct()" >> $file
			echo -e "\t{" >> $file
			echo -e "\t\t\$this->table_name = \"$table\";" >> $file
			echo -e "\t\t\$this->primary_key = \"`mysql --skip-column-names -u root -pldi14517 -e "select column_name from information_schema.KEY_COLUMN_USAGE where CONSTRAINT_NAME = 'PRIMARY' AND TABLE_SCHEMA='${databases[$folder]}' AND TABLE_NAME='$table' LIMIT 1"`\";" >> $file
			echo -e "\t}" >> $file

			# Métodos públicos para el acceso a las propiedades
			for column_data in $columns; do
				if [ $column_position -eq 0 ]; then
					echo "" >> $file
					echo -e "\tpublic function get${column_data^}()" >> $file
					echo -e "\t{" >> $file
					echo -e "\t\treturn \$this->$column_data;" >> $file
					echo -e "\t}" >> $file
					echo -e "" >> $file
					echo -e "\tpublic function set${column_data^}(\$value)" >> $file
					echo -e "\t{" >> $file
					echo -e "\t\t\$this->$column_data = \$value;" >> $file
					echo -e "\t}" >> $file
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 1 ]; then
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 2 ]; then
					column_position=0
					continue
				fi
			done

			#Fin
			echo "}" >> $file
			echo "?>" >> $file
		done

		#Sincronizar
		rsync -cr --delete --info=NAME1 /store/blackphp/orm/$folder/ /store/Clouds/Mega/www/$folder/models/orm/
	else
		echo "Project $1 not exists"
	fi
done
