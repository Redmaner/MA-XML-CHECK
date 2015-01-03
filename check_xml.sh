#!/bin/bash
# Copyright (c) 2013 - 2015, Redmaner
# This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International license
# The license can be found at http://creativecommons.org/licenses/by-nc-sa/4.0/

#########################################################################################################
# CACHING
#########################################################################################################
build_cache () {
if [ -d $CACHE ]; then
	case "$SERVER" in
		yes) rm -rf $CACHE; mkdir $CACHE;;
		 no) echo -e "${txtred}ERROR:${TXTRST} $CACHE already exsists\nDo you want to remove the cache? This can interrupt a current check!"
	    	     echo -en "(y,n): "; read cache_remove_awnser
		     if [ $cache_remove_awnser == "y" ]; then
				rm -rf $CACHE; mkdir $CACHE
		     else
				exit
		     fi;;
	esac
else
	rm -rf $CACHE; mkdir $CACHE
fi
}

clear_cache () {
rm -rf $CACHE
}

assign_vars () {
XML_TARGET_STRIPPED=$FILE_CACHE/xml.target.stripped
APOSTROPHE_RESULT=$FILE_CACHE/xml.apostrophe.result
XML_LOG_TEMP=$FILE_CACHE/XML_LOG_TEMP
}

#########################################################################################################
# START XML CHECK
#########################################################################################################
init_xml_check () {
if [ -d $LANG_DIR/$LANG_TARGET ]; then
	echo -e "${txtblu}Checking $LANG_NAME MIUI$LANG_VERSION ($LANG_ISO)${txtrst}"
	mkdir -p $CACHE/$LANG_TARGET.cached
	echo "$LANG_NAME" > $CACHE/$LANG_TARGET.cached/lang_name
	echo "$LANG_VERSION" > $CACHE/$LANG_TARGET.cached/lang_version
	DATESTAMP=$(date +"%m-%d-%Y %H:%M:%S")
	echo "$DATESTAMP" > $CACHE/$LANG_TARGET.cached/datestamp
	for apk_target in $(find $LANG_DIR/$LANG_TARGET -iname "*.apk" | sort); do
		APK=$(basename $apk_target)
		DIR=$(basename $(dirname $apk_target))
		for xml_target in $(find $apk_target -iname "arrays.xml*" -o -iname "strings.xml*" -o -iname "plurals.xml*"); do
			xml_check "$xml_target"
		done
	done
fi
}

xml_check () {
XML_TARGET=$1

if [ -e "$XML_TARGET" ]; then
	XML_TYPE=$(basename $XML_TARGET)

	FILE_CACHE=$CACHE/$LANG_TARGET.cached/$DIR-$APK-$XML_TYPE
	mkdir -p $FILE_CACHE
	assign_vars
	echo "$XML_TARGET" > $FILE_CACHE/XML_TARGET

	# Fix .part files for XML_TYPE
	if [ $(echo $XML_TYPE | grep ".part" | wc -l) -gt 0 ]; then
		case "$XML_TYPE" in
		     	strings.xml.part) XML_TYPE="strings.xml";;
			 arrays.xml.part) XML_TYPE="arrays.xml";;
			plurals.xml.part) XML_TYPE="plurals.xml";;
		esac
	fi

	case "$LANG_CHECK" in
		 basic) xml_check_basic;;
		normal) xml_check_basic; xml_check_normal;;
	esac
fi
}

#########################################################################################################
# XML CHECK
#########################################################################################################
xml_check_basic () {
# Check for XML Parser errors
XML_LOG_PARSER=$FILE_CACHE/PARSER.log
xmllint --noout $XML_TARGET 2>> $XML_LOG_PARSER
write_log_error "red" "$XML_LOG_PARSER"

# Check for doubles
XML_LOG_DOUBLES=$FILE_CACHE/DOUBLES.log
if [ "$XML_TYPE" == "strings.xml" ]; then	
	cat $XML_TARGET | grep '<string name=' | cut -d'>' -f1 | cut -d'<' -f2 | sort | uniq --repeated | while read double; do
		grep -ne "$double" $XML_TARGET >> $XML_LOG_DOUBLES
	done
	write_log_error "orange" "$XML_LOG_DOUBLES"
fi
	
# Check for apostrophe errors
case "$XML_TYPE" in
	strings.xml)
	grep "<string" $XML_TARGET > $XML_TARGET_STRIPPED
	grep -v '>"' $XML_TARGET_STRIPPED > $APOSTROPHE_RESULT;;
	*)
	grep "<item>" $XML_TARGET > $XML_TARGET_STRIPPED
	grep -v '>"' $XML_TARGET_STRIPPED > $APOSTROPHE_RESULT;;
esac

if [ -e $APOSTROPHE_RESULT ]; then
	grep "'" $APOSTROPHE_RESULT > $XML_TARGET_STRIPPED
	grep -v "'\''" $XML_TARGET_STRIPPED > $APOSTROPHE_RESULT
	if [ -e $APOSTROPHE_RESULT ]; then
		XML_LOG_APOSTROPHE=$FILE_CACHE/APOSTROPHE.log
      	      	cat $APOSTROPHE_RESULT | while read all_line; do grep -ne "$all_line" $XML_TARGET; done >> $XML_LOG_APOSTROPHE
 	fi
fi
write_log_error "brown" "$XML_LOG_APOSTROPHE"

# Check for '+' at the beginning of a line, outside <string>
XML_LOG_PLUS=$FILE_CACHE/PLUS.log
grep -ne "+ * <s" $XML_TARGET >> $XML_LOG_PLUS
write_log_error "blue" "$XML_LOG_PLUS"
}

xml_check_normal () {
# Check for untranslateable strings, arrays, plurals using ignorelist
XML_LOG_UNTRANSLATEABLE=$FILE_CACHE/UNTRANSLATEABLE.log
if [ $(cat $IGNORELIST | grep ''$APK' '$XML_TYPE' ' | wc -l) -gt 0 ]; then
	cat $IGNORELIST | grep 'all '$APK' '$XML_TYPE' ' | while read all_line; do
		init_ignorelist $(cat $IGNORELIST | grep "$all_line")
		grep -ne '"'$ITEM_NAME'"' $XML_TARGET
	done >> $XML_LOG_UNTRANSLATEABLE
	cat $IGNORELIST | grep ''$DIR' '$APK' '$XML_TYPE' ' | while read all_line; do
		init_ignorelist $(cat $IGNORELIST | grep "$all_line")
		grep -ne '"'$ITEM_NAME'"' $XML_TARGET
	done >> $XML_LOG_UNTRANSLATEABLE
	if [ "$DIR" != "main" ]; then
		cat $IGNORELIST | grep 'devices '$APK' '$XML_TYPE' ' | while read all_line; do
			init_ignorelist $(cat $IGNORELIST| grep "$all_line")
			grep -ne '"'$ITEM_NAME'"' $XML_TARGET
		done >> $XML_LOG_UNTRANSLATEABLE
	fi
fi

# Check for untranslateable strings and arrays due automatically search for @
case "$XML_TYPE" in 
	strings.xml) cat $XML_TARGET | grep '@android\|@string\|@color\|@drawable' | cut -d'>' -f1 | cut -d'"' -f2 | while read auto_search_target; do
				if [ $(cat $AUTO_IGNORELIST | grep 'folder="all" application="'$APK'" file="'$XML_TYPE'" name="'$auto_search_target'"/>' | wc -l) == 0 ]; then
					grep -ne '"'$auto_search_target'"' $XML_TARGET; continue
				else
					continue
				fi
				if [ $(cat $AUTO_IGNORELIST | grep 'folder="'$DIR'" application="'$APK'" file="'$XML_TYPE'" name="'$auto_search_target'"/>' | wc -l) == 0 ]; then
					grep -ne '"'$auto_search_target'"' $XML_TARGET; continue
				else
					continue
				fi
				if [ "$DIR" != "main" ]; then
					if [ $(cat $AUTO_IGNORELIST | grep 'folder="devices" application="'$APK'" file="'$XML_TYPE'" name="'$auto_search_target'"/>' | wc -l) == 0 ]; then
						grep -ne '"'$auto_search_target'"' $XML_TARGET
					fi
				fi
		     done >> $XML_LOG_UNTRANSLATEABLE;;
	 arrays.xml) cat $XML_TARGET | grep 'name="' | while read arrays; do
				ARRAY_TYPE=$(echo $arrays | cut -d' ' -f1 | cut -d'<' -f2)
				ARRAY_NAME=$(echo $arrays | cut -d'>' -f1 | cut -d'"' -f2)
				if [ $(arrays_parse $ARRAY_NAME $ARRAY_TYPE $XML_TARGET | grep '@android\|@string\|@color\|@drawable' | wc -l) -gt 0 ]; then
					if [ $(cat $AUTO_IGNORELIST | grep 'folder="all" application="'$APK'" file="'$XML_TYPE'" name="'$ARRAY_NAME'"' | wc -l) -eq 0 ]; then
						grep -ne '"'$ARRAY_NAME'"' $XML_TARGET; continue
					else
						continue
					fi
					if [ $(cat $AUTO_IGNORELIST | grep 'folder="'$DIR'" application="'$APK'" file="'$XML_TYPE'" name="'$ARRAY_NAME'"' | wc -l) -eq 0 ]; then
						grep -ne '"'$ARRAY_NAME'"' $XML_TARGET; continue
					else
						continue
					fi
					if [ "$DIR" != "main" ]; then
						if [ $(cat $AUTO_IGNORELIST | grep 'folder="devices" application="'$APK'" file="'$XML_TYPE'" name="'$ARRAY_NAME'"' | wc -l) -eq 0 ]; then
							grep -ne '"'$ARRAY_NAME'"' $XML_TARGET
						fi
					fi
				fi
		     done >> $XML_LOG_UNTRANSLATEABLE;;
esac
write_log_error "pink" "$XML_LOG_UNTRANSLATEABLE"
}

#########################################################################################################
# XML CHECK LOGGING
#########################################################################################################
write_log_error () {
if [ -s $2 ]; then
	echo '</script><span class="'$1'"><script class="error" type="text/plain">' >> $XML_LOG_TEMP
	cat $2 >> $XML_LOG_TEMP
fi
rm -f $2
}
