#!/bin/bash
# Para cada nombre de proyecto (Carpeta = Clave) se define una base de datos (Valor)
declare -A databases
databases[blackphp]=blackphp
databases[negkit]=negkit
databases[sicoimWebApp]=sicoim
databases[mimakit]=mimakit
databases[fileManager]=files
databases[inabve]=inabve

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
types[time]=string
types[year]=int
types[float]=float
types[decimal]=float
types[double]=float
types[bigint]=int

# Si se ejecuta sin parámetros, se hace un volcado de todas las bases de datos definidas en el arreglo; sino, se realiza sólo de las que han sido especificadas.
if [ "$#" = "0" ]; then
	$0 ${!databases[@]}
	exit 1
fi

# $space sustituye los espacios en la consulta, para poder recorrer correctamente los ítems
space='||'
for folder in "$@"; do
	echo "------------ ORM for project $folder"
	if [ -v databases[$folder] ]; then
		if [ ! -d /store/bphp/orm/$folder ]; then
			mkdir -p /store/bphp/orm/$folder
		fi
		rm /store/bphp/orm/$folder/*_model.php
		tables=`mysql --skip-column-names -u root -pldi14517 -e "select TABLE_NAME, REPLACE(TABLE_TYPE, ' ', '$space') AS TTYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = '${databases[$folder]}' ORDER BY TABLE_NAME"`
		table_position=0
		table_name=""
		table_type=""
		table_count=0
		for table_data in $tables; do
			if [ $table_position -eq 0 ]; then
				table_name=$table_data
				((table_position=table_position+1))
				continue
			else
				table_type=$table_data
				table_position=0
			fi
			file=/store/bphp/orm/$folder/$table_name"_model.php"
			((table_count=table_count+1))
			echo -n -e "$table_count tables processed\r"
			echo "<?php" > $file
			echo "/**" >> $file
			echo " * Model for $table_name" >> $file
			echo " * " >> $file
			echo " * Generated by BlackPHP" >> $file
			echo " */" >> $file
			echo "" >> $file
			echo "class "$table_name"_model" >> $file
			echo "{" >> $file
			echo -e "\tuse ORM;" >> $file
			echo "" >> $file

			# Consultando columnas y creando propiedades
			# Esta consulta obtiene resultados en tres columnas
			columns=`mysql --skip-column-names -u root -pldi14517 -e "SELECT COLUMN_NAME, DATA_TYPE, IF(COLUMN_COMMENT = '', '-', REPLACE(COLUMN_COMMENT, ' ', '$space')) AS COMMENT, REPLACE(COLUMN_DEFAULT, ' ', '$space') AS CDEFAULT FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = '${databases[$folder]}' AND TABLE_NAME = '$table_name'"`
			column_position=0
			column_name=""
			column_type=""
			timestamps=false
			ts_fields=0
			soft_delete=false
			for column_data in $columns; do
				if [ $column_position -eq 0 ]; then
					column_name=$column_data
					if [ "$column_name" = "creation_user" -o "$column_name" = "creation_time" -o "$column_name" = "edition_user" -o "$column_name" = "edition_time" ]; then
						((ts_fields=ts_fields+1))
					fi
					if [ "$column_name" = "status" ]; then
						soft_delete=true
					fi
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
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 3 ]; then
					column_position=0
					echo -ne "\t/** @var ${types[$column_type]} \$$column_name" >> $file
					echo " $column_comment */" | sed -e "s/$space/\ /g" >> $file
					echo -e "\tprivate \$$column_name;" >> $file
					echo "" >> $file
				fi
			done

			# Si $ts_fields es 4, es porque se encontraron los campos necesatios para el registro
			# de timestamps
			if [ $ts_fields -eq 4 ]; then
				timestamps=true
			fi

			# PROPIEDADES GENERALES

			# Establece el nombre de la tabla
			echo "" >> $file
			echo -e "\t/** @var string \$_table_name Nombre de la tabla */" >> $file
			echo -e "\tprivate static \$_table_name = \"$table_name\";" >> $file

			# Establece el tipo de tabla
			echo "" >> $file
			echo -e "\t/** @var string \$_table_type Tipo de tabla */" >> $file
			echo -e "\tprivate static \$_table_type = \"$table_type\";" | sed -e "s/$space/\ /g" >> $file

			# Establece el nombre de la llave foránea. (Funciona sólo para llaves primarias de un
			# solo campo).
			echo "" >> $file
			echo -e "\t/** @var string \$_primary_key Llave primaria */" >> $file
			echo -e "\tprivate static \$_primary_key = \"`mysql --skip-column-names -u root -pldi14517 -e "select column_name from information_schema.KEY_COLUMN_USAGE where CONSTRAINT_NAME = 'PRIMARY' AND TABLE_SCHEMA='${databases[$folder]}' AND TABLE_NAME='$table_name' LIMIT 1"`\";" >> $file

			# Determina si la tabla soporta timestamps (creation_user, creation_time, edition_user y edition_time)
			echo "" >> $file
			echo -e "\t/** @var bool \$_timestamps La tabla usa marcas de tiempo para la inserción y edición de datos */" >> $file
			echo -e "\tprivate static \$_timestamps = $timestamps;" >> $file

			# Determina si la tabla soporta borrado suave (Se necesita un campo de estado $status)
			echo "" >> $file
			echo -e "\t/** @var bool \$_soft_delete La tabla soporta borrado suave */" >> $file
			echo -e "\tprivate static \$_soft_delete = $soft_delete;" >> $file

			# Determina si hay un campo status, y si este puede tomar un valor nulo
			is_nullable=`mysql --skip-column-names -u root -pldi14517 -e "SELECT IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = '${databases[$folder]}' AND TABLE_NAME = '$table_name' AND COLUMN_NAME = 'status'"`
			if [ "$is_nullable" = "YES" ]; then
				deleted_status="null"
			else
				deleted_status="0"
			fi
			echo "" >> $file
			echo -e "\t/** @var int|null \$_deleted_status Valor a asignar en caso de borrado suave. */" >> $file
			echo -e "\tprivate static \$_deleted_status = $deleted_status;" >> $file
			echo "" >> $file

			# Constructor de la clase
			echo -e "\t/**" >> $file
			echo -e "\t * Constructor de la clase" >> $file
			echo -e "\t * " >> $file
			echo -e "\t * Se inicializan las propiedades de la clase." >> $file
			echo -e "\t * @param bool \$default Determina si se utilizan, o no, los valores por defecto" >> $file
			echo -e "\t * definidos en la base de datos." >> $file
			echo -e "\t **/" >> $file
			echo -e "\tpublic function __construct(\$default = true)" >> $file
			echo -e "\t{" >> $file
			echo -e "\t\tif(\$default)" >> $file
			echo -e "\t\t{" >> $file
			for column_data in $columns; do
				if [ $column_position -eq 0 ]; then
					column_name=$column_data
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 1 ]; then
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 2 ]; then
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 3 ]; then
					column_position=0
					column_default=$column_data
					if [ ! "$column_default" = "NULL" ]; then
						re='^[+-]?[0-9]+([.][0-9]+)?$'
						if [[ $column_default =~ $re ]] ; then
							echo -e "\t\t\t\$this->$column_name = $column_default;" >> $file
						else
							echo -e "\t\t\t\$this->$column_name = $column_default;" | sed -e "s/$space/\ /g" >> $file
						fi
					fi
				fi
			done
			echo -e "\t\t}" >> $file
			echo -e "\t}" >> $file

			# Métodos públicos para el acceso a las propiedades.
			# En los setters está pensado realizar validaciones según el tipo de datos,
			# pero esto aún no está incluído en esta edición.
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
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 3 ]; then
					echo "" >> $file
					echo -e "\tpublic function get${column_name^}()" >> $file
					echo -e "\t{" >> $file
					echo -e "\t\treturn \$this->$column_name;" >> $file
					echo -e "\t}" >> $file
					echo -e "" >> $file
					echo -e "\tpublic function set${column_name^}(\$value)" >> $file
					echo -e "\t{" >> $file
					echo -e "\t\t\$this->$column_name = \$value === null ? null : (${types[$column_type]})\$value;" >> $file
					echo -e "\t}" >> $file
					column_position=0
				fi
			done

			# Llaves foráneas
			keys=`mysql --skip-column-names -u root -pldi14517 -e "SELECT TABLE_NAME, COLUMN_NAME,CONSTRAINT_NAME, REFERENCED_COLUMN_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_SCHEMA = '${databases[$folder]}' AND REFERENCED_TABLE_NAME = '$table_name' GROUP BY TABLE_NAME"`
			column_position=0
			rtable_name=""
			column_name=""
			constraint_name=""
			referenced_column_name=""
			for key_data in $keys; do
				if [ $column_position -eq 0 ]; then
					rtable_name=$key_data
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 1 ]; then
					column_name=$key_data
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 2 ]; then
					constraint_name=$key_data
					((column_position=column_position+1))
					continue
				fi
				if [ $column_position -eq 3 ]; then
					referenced_column_name=$key_data
					echo "" >> $file
					echo -e "\tpublic function $rtable_name()" >> $file
					echo -e "\t{" >> $file
					echo -e "\t\t${rtable_name}_model::flush();" >> $file
					echo -e "\t\treturn ${rtable_name}_model::where(\"$column_name\", \$this->$referenced_column_name);" >> $file
					echo -e "\t}" >> $file
					column_position=0
				fi
			done

			#Fin
			echo "}" >> $file
			echo "?>" >> $file
		done
		echo ""

		#Sincronizar
		rsync -cr --delete --info=NAME1 /store/bphp/orm/$folder/ /store/Clouds/Mega/www/$folder/models/orm/
	else
		echo "Project $1 not exists"
	fi
done
