#!/bin/bash

readonly MANUALDOWNLOADSFOLDER=manuallyDownloadedPdfs
readonly TITLELENGTHLIMIT=100 # to limit the number of characters in a paper's title as it appears in the paper's filename
readonly AUTHORNAMESLENGTHLIMIT=40 # to limit the number of characters of the authors' names as they appear in the paper's filename

# TO DO
# for non-arxiv papers fetch the abstracts from somewhere else. But what web source is there that will reliably have the abstract of any paper I ask for?
# fix the "tally chart of fields appearing" thing so it copes with different spacing and capitalisations
# add feature to list the papers one needs to find oneself - i.e. the non-arxiv papers that are not present
# add feature to use inSPIRE to open the URLs of all the papers on needs to find oneself. User will still have to deal with the publishers' CAPCHAs of course, so actually retrieving non-arxiv papers presumably cannot be automated

getYN(){ # for creating simple dialogs e.g. getYN && eraseFile, or e.g. getYN || exit
        local input=""
        read -p "OK? y/n > " input </dev/tty
        if [[ "$input" == "y" ]]; then return 0; else return 1; fi
}

fixNewlineUseInBibfile(){
	local bibfile="$1"
	# sometimes the bibtex has a field split over two lines, which we dub a "line-broken field", which looks like:
	#   title = "{The Calabi-Yau string landscape
	#            heterotic (2,2) integrability catastrophe"
	# WE NEED TO FIND AND FIX THESE so that they have no line-break, thus: 
	#   title = "{The Calabi-Yau string landscape heterotic (2,2) integrability catastrophe}"
	# Currently this only works with two lines, not three or more.
	# 
	# input bibtex will have entries that look like this:
	#  1. a start line e.g.: @article{LOL2016,
	#  2. field entries and/or line-broken field entries, ending with a comma e.g.: year = "2016",
	#  3. the last line e.g.: weblink = "www.lol.com"
	#  4. closebracket matching the start line : }
	# 
	# therefore use a FEARSOME sed command to fix this:
	#  1. find a line that doesn't end with a comma - this pattern characterises these line-broken entries OR the last entry in a bibtex item
	#  2. after finding such a line, append the next line to the pattern space with the command "N"
	#  3.      IF the pattern space has a line, and then a newline character, and then a line containing only a }, then we've hit the last line, so THEN do nothing, i.e. move on, with the command "n"
	#  4. ELSE IF the pattern space has a line, and then a newline character, and then a line containing no equals signs, ending with a comma, then we've found a line-broken field, so THEN delete '\n' in the pattern space (while being careful with any whitespace) to return a non-line-broken field
	sed '/\S*[^,]\s*$/ {N
			/\n}\s*$/ n
			/^.*\n[^=]*,\s*$/ {
					s/\s*\n\s*/ /
			}
	}' "$bibfile"
}

addFileField(){ # edits the bib file
	local paper="$1"
	local paperUID="$2"
	local paperFilename="$3"
	# check if there is a "file" field already
	echo $paper| grep -i '^\s*localfile\s*= ' >/dev/null
	local paperFileFieldPresent=$?
	if [[ $paperFileFieldPresent -ne true ]]
	then
		echo "updating the bib file with (relative) path to pdf"
		#sed -i "s/^\(\s*\)year = ".*$paperYear[^,]*"/&,\n\1file = ":$paperFilename:pdf"/" $BIBFILE # should work correctly if the UID line has a comma or not === is last or not
		sed -i "s/$paperUID,/&\n	localfile = \"$paperFilename\",/" $BIBFILE
	else
		echo "the bib entry already has a file listed - not updating it with path to the pdf"
	fi
}
addAbstractField(){ # edits the bib file
	local paper="$1"
	local paperUID="$2"
	local paperAbstract="$3"
	local paperAbstractSanitised=$(printf '%s\n' "$paperAbstract" | tr -d '@"' | sed 's/[\&/|$]/\\&/g') # delete @ and " and escape the special characters \&/ (e.g. from LaTeX) suitably to appear in RHS of a sed command
	# check if there is an "abstract" field already
	echo $paper| grep -i '^\s*abstract\s*= ' >/dev/null
	local paperAbstractFieldPresent=$?
	if [[ $paperAbstractFieldPresent -ne true ]]
	then
		echo "updating the bib file with the abstract"
		#sed -i "s@^\(\s*\)year = ".*$paperYear[^,]*"@&,\n\1abstract = "\{$paperAbstractSanitised\}"@" $BIBFILE # should work correctly if the UID line has a comma or not === is last or not
		sed -i "s/$paperUID,/&\n	abstract = \"$paperAbstractSanitised\",/" $BIBFILE
	else
		echo "the bib entry already has an abstract - not updating it with the abstract"
		echo "ERROR: addAbstractField was called on bibtex that already had an abstract! That's not supposed to happen any more."
	fi
}

getArxivPage(){ # wget the archive webpage - it has information we need # DEPRECATED
	echo "WARNING: function getArxivPage is deprecated!"
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
getArxivPdf(){ # wget the pdf # DEPRECATED
	echo "WARNING: function getArxivPdf is deprecated!"
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
# versions of those that avoid saving the arxiv page - will have to rename them later...
echoArxivPage(){
	local paperEprintNo="$1"
	local arxivPage="$(wget -U firefox --wait=5 --random-wait --output-document=- --quiet "http://arxiv.org/abs/$paperEprintNo")" # gets the arxiv page WITHOUT saving the page
	echo "$arxivPage"
}
saveArxivPdf(){
	local arxivPage="$1"
	local paperFilenameDestination="$2"
	local paperpdfURL="http://arxiv.org$(grep 'href=.*PDF' <<<"$arxivPage" | grep -o '/pdf/[^"]*')" # regex is grep for line containing the link | grep for the actual URL
	echo "download arxiv pdf?"
	getYN && (
		echo
		echo "---wget---"
		wget -U firefox --wait=5 --random-wait --output-document="$paperFilenameDestination" "$paperpdfURL"
		echo "---/wget---"
		echo
	)
}

addBibtexToBibfile(){
	local bibtex="$1"	
	local paperUIDLine="$(grep '@' <<< "$bibtex" | grep -o '{.*')"
	
	grep "$paperUIDLine" "$BIBFILE"
	local uidAlreadyPresent=$?
	if [[ uidAlreadyPresent -eq true ]]
	then
		echo "Error: The bib file already contains an entry with the same identifier as the paper at this inspire url"
	else
		echo "$bibtex" >> "$BIBFILE"
	fi
}

isUrlIsAnInspireUrl(){
	local url="$1"
	if [[ ! ( "$url" =~ ^https*://inspirehep.net/record/[0-9][0-9]*$ ) ]]
	then 
		echo "ERROR: argument $url is not an inSPIRE address"
		return 1
	else
		return 0
	fi
}

getBibtexFromInspirePage(){
	local inspireUrl="$1"
	
	local linkToInspireBibtexPage=$(wget --wait=5 --random-wait --output-document=- --quiet $inspireUrl | grep -i bibtex | grep -o 'href="[^"]*"' | grep -o '/record.*hx') # gets the bibtex link from the page WITHOUT saving the page
	# from that address use sed to:
	# 1. get lines from first line matching 'pagebody' until a '</pre>' is reached - this returns the body of the page including the open and close tags
	# 2. get text from the '@' that signifies the start of a bibtex entry until the line that starts with a close curlybracket that signifies the end of the bibtex entry - to get the bibtex in pure form
	local bibtex="$(wget --wait=5 --random-wait --output-document=- --quiet http://inspirehep.net$linkToInspireBibtexPage | sed -n '/pagebody/,/<\/pre>/p' | sed -n '/@/,/^}/p' )" # gets the bibtex text itself from the page WITHOUT saving the page
	# CHECK: how easy/necessary is it to put here a check that that last command suceeded and/or $bibtex contains a valid value?
	
	echo "$bibtex"
}

readOptions(){
	while getopts ":a:" opt # the first colon suppress getopts' error messages and I substitute my own. The others indicate that an argument is taken.
	do
		case $opt in
		a)	LISTOFINSPIREURLS="$LISTOFINSPIREURLS $OPTARG";; # i.e. add the URL to the list of URLs
		\?)	echo invalid option "$OPTARG"; exit 1;;
		esac
	done
}

main(){
	LISTOFINSPIREURLS="" # holds the URLs that the user has passed to the program with the -a option
	
	readOptions "$@"
	shift $(($OPTIND-1)) # builtin function "getopts" (inside readOptions) is always used in conjunction with "shift"
	
	if [[ ! $# == 1 ]] # if number of arguments isn't exactly 1
	then
		echo "provide the name of the .bib file"
		exit 1
	fi
	BIBFILE="$1" # global variable
	
	for inspireUrl in $LISTOFINSPIREURLS
	do
		echo 
		echo adding bibtex data from URL $inspireUrl
		isUrlIsAnInspireUrl $inspireUrl || continue
		addBibtexToBibfile "$(getBibtexFromInspirePage $inspireUrl)" # >> "$BIBFILE"
	done
	echo "" # a blank line
	
	echo "reading $BIBFILE"
	
	echo "FYI a tally chart of fields appearing in the .bib file"
	grep -o '^[^=]* =' "$BIBFILE" | grep '\S.*' | sort | uniq --count # | sort --numeric-sort

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
	for paper in $(fixNewlineUseInBibfile "$BIBFILE")
	do
		# STEP 1 : check if the item is suitable
		echo "---------------------------------------"
		# REMOVED the requirement that it be document type "article"
		#echo "bib item: ${paper:0:7}" # the first seven characters of the bib entry
		#if [[ ! "$paper" =~ ^article ]]; then echo "not an article - skipping..."; continue; fi # skip if not an article
		
		# STEP 2 : read the data into variables
		# regex in next line is: grep for author field | but delete the author tag itself | find surnames = nonblank characters before a comma | deal with {t'Hooft} | remove newlines
		local paperAuthorsSurnames="$(echo $paper | grep -io '^\s*author\s*= "[^"]*'  | sed 's/\s*author\s*= "//' | grep -o '\S*,' | sed 's/.*Hooft.*/tHooft,/' | tr -d '\n' )" # list of names separated by commas e.g. Lu,Perkins,Pope,Stelle,
		local paperYear="$(echo $paper | grep -io '^\s*year\s*= "[^"]*'  | sed 's/\s*year\s*= "//')"
		local paperTitle="$(echo $paper | grep -io '^\s*title\s*= "[^"]*'  | sed 's/\s*title\s*= "//' | tr -d '{}')" # sometimes the title is saved like {Elongating Equations in Type VII String Conglomerations} so use tr to delete any brackets
		local paperTitleSanitised=$(tr -d '{}*$\/()' <<<"$paperTitle") # delete special characters from the title - most of these are actually allowed in filenames but break common bash commands (brackets are actually OK I think?)
		local paperUID="$(sed -n -e 's/^article{\([^,]*\),/\1/p' <<< $paper)" # will contain a semicolon, may contain single quote *cough* 't'Hooft *cough*
		# check the variables - it could always happen that there are weird unanticipated characters in the bib...
		if [[ -z "$paperAuthorsSurnames" ]]; 	then echo "couldn't read author's names - please check the bib file"; 		continue; fi
		if [[ -z "$paperYear" ]]; 		then echo "couldn't read publication year - please check the bib file"; 	continue; fi
		if [[ -z "$paperTitle" ]]; 		then echo "couldn't read paper title - please check the bib file"; 		continue; fi
		if [[ -z "$paperTitleSanitised" ]]; 	then echo "paper title couldn't be used - please check the bib file"; 		continue; fi
		if [[ -z "$paperUID" ]]; 		then echo "couldn't read paper's UID - please check the bib file"; 		continue; fi
		
		# STEP 3: generate a filename - it's important not to change this code as it will render the previously-downloaded pdfs invisible to the program
		# for the filenames take:
		#  the surnames of the authors - if too long then replace the later authors with "et Al."
		#  the year published
		#  the paper's title - if too long then cut off the end, but then remove trailing spaces
		local paperTitleSanitisedLengthLimited=${paperTitleSanitised:0:$TITLELENGTHLIMIT}
		if [[ ${#paperAuthorsSurnames} -gt $AUTHORNAMESLENGTHLIMIT ]]
		then 
			local paperAuthorsSurnamesLengthLimited=$(grep -o '^.*,'<<<${paperAuthorsSurnames:0:$AUTHORNAMESLENGTHLIMIT})etAl
		else 
			local paperAuthorsSurnamesLengthLimited=$paperAuthorsSurnames
		fi
		# in this syntax ${varName%,} deletes a comma from the end of $varName if present, and similarly ${varName% } deletes a space if present
		paperFilenameSuggestion="${paperAuthorsSurnamesLengthLimited%,} - $paperYear - ${paperTitleSanitisedLengthLimited% }.pdf" 
		echo "target filename : $paperFilenameSuggestion"
		
		# STEP 4: branch for arxiv/non-arxiv
		# check if it is on arxiv === "ARXIV" appears in its bib entry [CHECK could improve the exact criteria for determining if something is on the arxiv...]
		echo $paper | grep -i ARXIV >/dev/null
		local onArxiv=$?
		if [[ $onArxiv -eq true ]]
		then
			echo "on arxiv"
						
			# STEP 5: store info in variables
			local paperEprintNo="$(echo $paper | grep -io '^\s*eprint\s*= "[^"]*'  | sed 's/\s*eprint\s*= "//')" # eprint possible formats include 1501.0006, 1106.4657, hep-th/0206219
			if [[ -z "$paperEprintNo" ]]; 		then echo "couldn't read paper's eprint number - please check the bib file"; 		continue; fi
			
			[[ -e $paperFilenameSuggestion ]]
			local paperPdfPresent=$?
			
			# move the checks for abstract/file field here, to main, from function "addAbstractField"
			echo $paper| grep -i '^\s*abstract\s*= ' >/dev/null
			local paperAbstractFieldPresent=$?
			
			echo $paper| grep -i '^\s*localfile\s*= ' >/dev/null
			local paperFileFieldPresent=$?
			
			# STEP 6: check for abstract field and pdf - if either are absent then we need to download the arxiv webpage
			if [[ $paperPdfPresent -ne true || $paperAbstractFieldPresent -ne true ]]
			then
				local arxivPage="$(echoArxivPage "$paperEprintNo")"
				# CHECK should add a check that the webpage was retrieved sucessfully / that $arxivPage contains valid data
			fi
			
			# STEP 7: in case somehow the pdf got saved but a localfile field was not added to the bibtex at that time, check now and add a localfile field if necessary
			if [[ $paperPdfPresent -eq true && $paperFileFieldPresent -ne true ]]
			then 
				addFileField "$paper" "$paperUID" "$paperFilenameSuggestion"
			fi
			
			# STEP 8: if do not have pdf then get it
			if [[ $paperPdfPresent -ne true ]]
			then
				saveArxivPdf "$arxivPage" "$paperFilenameSuggestion" && addFileField "$paper" "$paperUID" "$paperFilenameSuggestion"
			fi
			
			# STEP 9: if do not have abstract then add it (to the bibtex)
			# the called function "addAbstractField" already contains a check that there is not already an abstract in the bibtex - this should no longer be necessary!
			if [[ $paperAbstractFieldPresent -ne true ]]
			then
				# regex is tr to replace all newlines with spaces (so now the webpage is one big line) | grep for the html code of the abstract | sed to extract the pure abstract text
				local paperAbstract="$(tr '\n' ' ' <<< $arxivPage | grep -o '<blockquote.*<span.*bstract.*</span>.*</blockquote>' | sed 's@.*/span> \(.*\)</blockquote.*@\1@')"
				if [[ -z "$paperAbstract" ]]
				then 
					echo "couldn't read paper's abstract"
				else
					addAbstractField "$paper" "$paperUID" "$paperAbstract"
				fi
			fi
			
			# OLD - DEPRECATED
			# # STEP 5: get the webpage / make sure we have it already
			# 
			# # HOWEVER, there may be a v2 or v3 on the archive - to find out we must consult the webpage
			# local paperSavedPage=.${paperFilenameSuggestion}_arxivpage
			# if [[ -e $paperSavedPage ]]
			# then
				# echo "WEBPAGE: PRESENT (saved as $paperSavedPage)"
			# else
				# echo "WEBPAGE: ABSENT. Downloading..."
				# getArxivPage "$paperEprintNo" "$paperSavedPage"
				# if [[ $? -ne 0 ]]; then echo "error finding arxiv page"; continue; fi
			# fi
			# 
			# # -- downloaded webpage file must be present in order for this line to be reached --
			# 
			# # update the bib with the abstract from the webpage
			# # regex is tr to replace all newlines with spaces (so now the webpage is one big line) | grep for the html code of the abstract | sed to extract the pure abstract text
			# #local paperAbstract="$(tr '\n' ' ' < $paperSavedPage | grep -o '<blockquote.*<span.*bstract.*</span>.*</blockquote>' | sed 's@.*/span> \([^<>]*\)</blockquote.*@\1@')"
			# local paperAbstract="$(tr '\n' ' ' < $paperSavedPage | grep -o '<blockquote.*<span.*bstract.*</span>.*</blockquote>' | sed 's@.*/span> \(.*\)</blockquote.*@\1@')"
			# addAbstractField "$paper" "$paperUID" "$paperAbstract"
			# 
			# # STEP 6: get the pdf / make sure we have it already
			# 
			# if [[ ! -e $paperFilenameSuggestion ]] # if there is no file for the PDF
			# then # then download the pdf
				# echo "PDF: ABSENT"
				# getArxivPdf "$paperSavedPage" "$paperFilenameSuggestion" && addFileField "$paper" "$paperUID" "$paperFilenameSuggestion"
			# else
				# echo "PDF: PRESENT"
				# addFileField "$paper" "$paperUID" "$paperFilenameSuggestion" # this can handle case that there is already a file field
			# fi

		else
			echo "not on arxiv"
			
			# STEP 5: if cannot see the pdf, ask the user for the pdf, rename it, add the file location to the bibtex
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
				select fileContainingPaper in $(echo -e '( CANCEL THIS MENU )'"\n""$(ls -1 $MANUALDOWNLOADSFOLDER/* | grep -v $BIBFILE )") # if manuallyDownloadedPdfs is empty this gives "ls: cannot access manuallyDownloadedPdfs/*: No such file or directory". Meh.
				do
					if [[ "$fileContainingPaper" =~ "CANCEL THIS MENU" ]]; then break; fi
					if [[ ! -f "$fileContainingPaper" ]]; then echo -e "\ninvalid choice\n"; break; fi	
					echo -e "\nrename            $fileContainingPaper            to            $paperFilenameSuggestion            ?"
					getYN && mv -i $fileContainingPaper $paperFilenameSuggestion && addFileField "$paper" "$paperUID" "$paperFilenameSuggestion"
					break # you only get out of a select statement with a break statement
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



