#!/bin/bash

readonly MANUALDOWNLOADSFOLDER=manuallyDownloadedPdfs
readonly TITLELENGTHLIMIT=100 # to limit the number of characters in a paper's title as it appears in the paper's filename
readonly AUTHORNAMESLENGTHLIMIT=40 # to limit the number of characters of the authors' names as they appear in the paper's filename

# TO DO
# for non-arxiv papers fetch the abstracts from inSPIRE instead
# fix the "tally chart of fields appearing" thing so it copes with different spacing and capitalisations
# add feature to take a list of inSPIRE URLs as argument and automatically retrieve the bibtex, and add it to the .bib file - perhaps this functionality would be a separate script?
# add feature to list the papers one needs to find oneself - i.e. the non-arxiv papers that are not present

getYN(){ # for creating simple dialogs e.g. getYN && eraseFile, or e.g. getYN || exit
        local input=""
        read -p "OK? y/n > " input </dev/tty
        if [[ "$input" == "y" ]]; then return 0; else return 1; fi
}
addFileField(){ # edits the bib file
	local paper="$1"
	local paperUID="$2"
	local paperFilename="$3"
	# check if there is a "file" field already
	echo $paper| grep 'file\s*= ' >/dev/null
	local paperFileFieldPresent=$?
	if [[ $paperFileFieldPresent -ne true ]]
	then
		echo "updating the bib file with (relative) path to pdf"
		#sed -i "s/^\(\s*\)year = ".*$paperYear[^,]*"/&,\n\1file = ":$paperFilename:pdf"/" $BIBFILE # should work correctly if the UID line has a comma or not === is last or not
		sed -i "s/$paperUID,/&\n	localfile = \"$paperFilename\",/" $BIBFILE
	else
		echo "the bib entry already has a file listed"
	fi
}
addAbstractField(){ # edits the bib file
	local paper="$1"
	local paperUID="$2"
	local paperAbstract="$3"
	local paperAbstractSanitised=$(printf '%s\n' "$paperAbstract" | tr -d '@"' | sed 's/[\&/|$]/\\&/g') # delete @ and " and escape the special characters \&/ (e.g. from LaTeX) suitably to appear in RHS of a sed command
	# check if there is an "abstract" field already
	echo $paper| grep 'abstract\s*= ' >/dev/null
	local paperAbstractFieldPresent=$?
	if [[ $paperAbstractFieldPresent -ne true ]]
	then
		echo "updating the bib file with the abstract"
		#sed -i "s@^\(\s*\)year = ".*$paperYear[^,]*"@&,\n\1abstract = "\{$paperAbstractSanitised\}"@" $BIBFILE # should work correctly if the UID line has a comma or not === is last or not
		sed -i "s/$paperUID,/&\n	abstract = \"$paperAbstractSanitised\",/" $BIBFILE
	else
		echo "the bib entry already has an abstract"
	fi
}

getArxivPage(){ # wget the archive webpage - it has information we need
	local paperEprintNo="$1"
	local paperSavedPageDestination="$2"
	echo "download arxiv webpage?"
	getYN && (
		echo
		echo "---wget---"
		wget -U firefox "http://arxiv.org/abs/$paperEprintNo" --output-document=$paperSavedPageDestination
		echo "---/wget---"
		echo
	)
	return $?
}

getArxivPdf(){ # wget the pdf
	local paperSavedPage="$1"
	local paperFilenameDestination="$2"
	local paperpdfURL="http://arxiv.org$(grep 'href=.*PDF' $paperSavedPage | grep -o '/pdf/[^"]*')" # regex is grep for line containing the link | grep for the actual URL
	echo "download arxiv pdf?"
	getYN && (
		echo
		echo "---wget---"
		wget -U firefox "$paperpdfURL" --output-document="$paperFilenameDestination"
		echo "---/wget---"
		echo
	)
	return $?
}

main(){
	if [[ ! $# == 1 ]] # if number of arguments isn't exactly 1
	then
		echo "provide the name of the .bib file"
		exit 1
	fi
	BIBFILE=$1 # global variable
	echo "reading $BIBFILE"
	
	echo "FYI a tally chart of fields appearing in the .bib file"
	grep -o '^[^=]* =' $BIBFILE | grep '\S.*' | sort | uniq --count # | sort --numeric-sort

	echo "this program generally only uses the arxiv, but for non-arxiv papers it can still manage file/names and add info to the bibtex."
	echo "it will look for non-arxiv papers that have been downloaded manually in the folder $MANUALDOWNLOADSFOLDER"
	if [[ ! -d $MANUALDOWNLOADSFOLDER ]]
	then
		echo "create the $MANUALDOWNLOADSFOLDER?"
		getYN && mkdir $MANUALDOWNLOADSFOLDER
	fi
	echo "" # a blank line 
	
	old_IFS=$IFS	# save the field separator           
	IFS=@	# the field separator used in bib
	for paper in $(cat $BIBFILE)
	do
		# STEP 1 : check if the item is suitable
		echo "---------------------------------------"
		echo "bib item: ${paper:0:7}" # the first seven characters of the bib entry
		if [[ ! "$paper" =~ ^article ]]; then continue; fi # skip if not an article
		
		# STEP 2 : read the data into variables
		# regex in next line is: grep for author field | but delete the author tag itself | find surnames = nonblank characters before a comma | deal with {t'Hooft} | remove newlines
		local paperAuthorsSurnames="$(echo $paper | grep -o 'author\s*= "[^"]*'  | sed 's/author\s*= "//' | grep -o '\S*,' | sed 's/.*Hooft.*/tHooft,/' | tr -d '\n' )" # list of names separated by commas e.g. Lu,Perkins,Pope,Stelle,
		local paperYear="$(echo $paper | grep -o 'year\s*= "[^"]*'  | sed 's/year\s*= "//')"
		local paperTitle="$(echo $paper | grep -o 'title\s*= "[^"]*'  | sed 's/title\s*= "//' | tr -d '{}')" # sometimes the title is saved like {Elongating Equations in Type VII String Conglomerations} so use tr to delete any brackets
		local paperTitleSanitised=$(tr -d '{}*$\/()' <<<"$paperTitle") # delete special characters from the title - most of these are actually allowed in filenames but break common bash commands (brackets are actually OK I think?)
		local paperUID="$(sed -n -e 's/article{\([^,]*\),/\1/p' <<< $paper)" # will contain a semicolon, may contain single quote *cough* 't'Hooft *cough*
		# check the variables - it could always happen that there are weird unanticipated characters in the bib...
		if [[ -z "$paperAuthorsSurnames" ]]; then echo "couldn't read author's names - please check the bib file"; continue; fi
		if [[ -z "$paperYear" ]]; then echo "couldn't read publication year - please check the bib file"; continue; fi
		if [[ -z "$paperTitle" ]]; then echo "couldn't read paper title - please check the bib file"; continue; fi
		if [[ -z "$paperTitleSanitised" ]]; then echo "paper title couldn't be used - please check the bib file"; continue; fi
		if [[ -z "$paperUID" ]]; then echo "couldn't read paper's UID - please check the bib file"; continue; fi
		
		# for the filenames take:
		#  the surnames of the authors - if too long then replace the later authors with "et Al."
		#  the year published
		#  the paper's title - if too long then cut off the end, but then remove trailing spaces
		local paperTitleSanitisedLengthLimited=${paperTitleSanitised:0:$TITLELENGTHLIMIT}
		if [[ ${#paperAuthorsSurnames} -gt $AUTHORNAMESLENGTHLIMIT ]]
		then local paperAuthorsSurnamesLengthLimited=$(grep -o '^.*,'<<<${paperAuthorsSurnames:0:$AUTHORNAMESLENGTHLIMIT})etAl
		else local paperAuthorsSurnamesLengthLimited=$paperAuthorsSurnames
		fi
		paperFilenameSuggestion="${paperAuthorsSurnamesLengthLimited%,} - $paperYear - ${paperTitleSanitisedLengthLimited% }.pdf" 
		echo "target filename : $paperFilenameSuggestion"
		
		# STEP 3: branch for arxiv/non-arxiv
		# check if it is on arxiv === "ARXIV" appears in its bib entry
		echo $paper | grep -i ARXIV >/dev/null
		local onArxiv=$?
		if [[ $onArxiv -eq true ]]
		then
			echo "on arxiv"
			local paperEprintNo="$(echo $paper | grep -o 'eprint\s*= "[^"]*'  | sed 's/eprint\s*= "//')" # possible formats include 1501.0006, 1106.4657, hep-th/0206219
			
			# STEP 4: get the webpage / make sure we have it already
			
			# HOWEVER, there may be a v2 or v3 on the archive - to find out we must consult the webpage
			local paperSavedPage=.${paperFilenameSuggestion}_arxivpage
			if [[ -e $paperSavedPage ]]
			then
				echo "WEBPAGE: PRESENT (saved as $paperSavedPage)"
			else
				echo "WEBPAGE: ABSENT. Downloading..."
				getArxivPage "$paperEprintNo" "$paperSavedPage"
				if [[ $? -ne 0 ]]; then echo "error finding arxiv page"; continue; fi
			fi
			
			# -- downloaded webpage file must be present in order for this line to be reached --
			
			# update the bib with the abstract from the webpage
			# regex is tr to replace all newlines with spaces (so now the webpage is one big line) | grep for the html code of the abstract | sed to extract the pure abstract text
			#local paperAbstract="$(tr '\n' ' ' < $paperSavedPage | grep -o '<blockquote.*<span.*bstract.*</span>.*</blockquote>' | sed 's@.*/span> \([^<>]*\)</blockquote.*@\1@')"
			local paperAbstract="$(tr '\n' ' ' < $paperSavedPage | grep -o '<blockquote.*<span.*bstract.*</span>.*</blockquote>' | sed 's@.*/span> \(.*\)</blockquote.*@\1@')"
			addAbstractField "$paper" "$paperUID" "$paperAbstract"
			
			# STEP 5: get the pdf / make sure we have it already
			
			if [[ ! -e $paperFilenameSuggestion ]] # if there is no file for the PDF
			then # then download the pdf
				echo "PDF: ABSENT"
				getArxivPdf "$paperSavedPage" "$paperFilenameSuggestion" && addFileField "$paper" "$paperUID" "$paperFilenameSuggestion"
			else
				echo "PDF: PRESENT"
				addFileField "$paper" "$paperUID" "$paperFilenameSuggestion" # this can handle case that there is already a file field
			fi

		else
			echo "not on arxiv"
			# if it is not available on the arXiv then:
			# NOT APPLICABLE (STEP 4: get the webpage / make sure we have it already) - could retrieve the abstract from the inspire page instead?
			# STEP 5: find the pdf
			if [[ ! -e $paperFilenameSuggestion ]] # if there is no file for the PDF
			then # then ask the user to point out the pdf
				echo "PDF: ABSENT OR WRONGLY NAMED"
				if [[ ! -d $MANUALDOWNLOADSFOLDER ]]; then echo "could not find the folder for manually downloaded pdfs"; continue; fi
				echo -e "\nThis paper is not on the arxiv. \nPlease browse its information and select a file from the PWD \n\npaper's bibtex entry : \n\n$paper\n"
				# ask the user to identify this paper from among the files from the manual downloads folder
				echo "if this paper is present please select it from within $MANUALDOWNLOADSFOLDER, by typing the number. Cancel this menu by entering '1' or using CTRL-D"
				echo ""
				slightly_old_IFS=$IFS	# save the field separator           
				IFS=$'\n'	# new field separator
				select fileContainingPaper in $(echo -e '( CANCEL THIS MENU )'"\n""$(ls -1 $MANUALDOWNLOADSFOLDER/* | grep -v $BIBFILE )")
				do
					if [[ "$fileContainingPaper" =~ "CANCEL THIS MENU" ]]; then break; fi
					if [[ ! -f "$fileContainingPaper" ]]; then echo -e "\ninvalid choice\n"; break; fi	
					echo -e "\nrename            $fileContainingPaper            to            $paperFilenameSuggestion            ?"
					getYN && mv -i $fileContainingPaper $paperFilenameSuggestion && addFileField "$paper" "$paperUID" "$paperFilenameSuggestion"
					break
				done
				IFS=$slightly_old_IFS	# restore default field separator
			else # if there is already a file for the pdf
				echo "PDF: PRESENT"
				addFileField "$paper" "$paperUID" "$paperFilenameSuggestion"  # this can handle case that there is already a file field
			fi
			
		fi
	done
	IFS=$old_IFS	# restore default field separator
}


main $@



