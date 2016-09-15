#!/bin/bash

readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink -m $(dirname $0))
readonly MANUALDOWNLOADSFOLDER=manuallyDownloadedPdfs
readonly TITLELENGTHLIMIT=100 # to limit the number of characters in a paper's title as it appears in the paper's filename
readonly AUTHORNAMESLENGTHLIMIT=40 # to limit the number of characters of the authors' names as they appear in the paper's filename

# TO DO
# for non-arxiv papers fetch the abstracts from somewhere else. But what web source is there that will reliably have the abstract of any paper I ask for?
# when adding bibtex from an inSPIRE URL, insert the paper's abstract at that time, instead of trying our luck on the arxiv later.
# need to write code to handle if there is no doi link in the bibtex
# BUG the code to get paperAuthorsSurnames doesn't cope with some inSPIRE entries, that are not of the format "surname, firstname and surname, firstname" but something else...
# some foreign names are two words and appear as e.g. "{De Felice}, Antonio and" i.e. with curly brackets. The code does not understand these.

showHelp(){
	cat <<- _EOF_
	$PROGNAME help:
	
	This program takes a bibtex file and manages/downloads/renames pdfs in the pwd (present working directory)
	The end result is that the pwd will contain a pdf of each paper in the bibtex file, with a nice filename.
	It also updates each paper's bibtex entry (in the bibtex file) with the abstract of the paper and with the location of the pdf.
	
	It has a second useful feature - you can pass it a link to an inSPIRE page (with option -a) and it will add that paper to your bibtex, and download and rename the pdf, all in one go.
	
	USAGE: 
	Standard usage:
	  bash $PROGNAME thesisBibliography.bib
	This looks at every paper in thesisBibliography.bib in turn.
	It makes sure you have the pdf. It follows these steps:
		First it looks for the pdf in the pwd. 
		Next it tries to download it from the arxiv. 
		Next it asks you to point out the pdf from within $MANUALDOWNLOADSFOLDER. 
		Finally it tries to open a link to the paper in your default browser, so that you can save it to $MANUALDOWNLOADSFOLDER.
	It also checks if the paper's bibtex has the abstract - if not it gets the abstract from the arxiv (if possible) and adds it to the bibtex entry
	It also checks if the paper's bibtex has the file location - if not it adds a "localfile" field to the bibtex with the file location
	
	enhanced inSPIRE usage:
	  bash $PROGNAME -a https://inspirehep.net/record/1413130 thesisBibliography.bib
	This gets the bibtex from the paper at the page you linked, and adds it to thesisBibliography.bib
	Then it proceeds as in the standard usage above.
	The last entry in the bibtex file is for the paper you linked, so when it reaches the end of the bibtex file it downloads your new paper etc.
	
	_EOF_
}

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
	local paperUID="$1"
	local paperFilename="$2"
	
	# check if there is a "file" field already
	# sed to get the bibtex of this paper, then check it for a "localfile" field
	sed -n "/$paperUID/,/^}\s*$/p" $BIBFILE | grep -i '^\s*localfile\s*= ' >/dev/null
	local paperFileFieldPresent=$?
	
	if [[ $paperFileFieldPresent -ne true ]]
	then
		echo "updating the bib file with (relative) path to pdf"
		sed -i "s/$paperUID,/&\n	localfile = \"$paperFilename\",/" $BIBFILE
	else
		echo "the bib entry already has a file listed - not updating it with path to the pdf"
	fi
}
addAbstractField(){ # edits the bib file
	# local paper="$1"
	local paperUID="$1"
	local paperAbstract="$2"
	local paperAbstractSanitised="$(printf '%s\n' "$paperAbstract" | tr -d '@"' | sed 's@[\&/|$]@\\&@g')" # delete @ and " and escape the special characters \&/ (e.g. from LaTeX) suitably to appear in RHS of a sed command
	
	# check if there is an "abstract" field already
	# sed to get the bibtex of this paper, then check it for an "abstract" field
	sed -n '/$paperUID/,/^}\s*$/p' $BIBFILE | grep -i '^\s*abstract\s*= ' >/dev/null
	local paperAbstractFieldPresent=$?
	
	if [[ $paperAbstractFieldPresent -ne true ]]
	then
		echo "updating the bib file with the abstract"
		sed -i "s/$paperUID,/&\n	abstract = \"$paperAbstractSanitised\",/" $BIBFILE
	else
		echo "the bib entry already has an abstract - not updating it with the abstract"
		echo "ERROR: addAbstractField was called on bibtex that already had an abstract! That's not supposed to happen any more."
	fi
}

echoArxivPage(){
	local paperEprintNo="$1"
	local arxivPage="$(wget -U firefox --wait=5 --random-wait --output-document=- --quiet "http://arxiv.org/abs/$paperEprintNo")" # gets the arxiv page WITHOUT saving the page
	echo "$arxivPage"
}
saveArxivPdf(){ # finds and follows the link to the latest version of the paper
	local arxivPage="$1"
	local paperFilenameDestination="$2"
	local paperpdfURL="http://arxiv.org$(grep 'href=.*PDF' <<<"$arxivPage" | grep -o '/pdf/[^"]*')" # regex is grep for line containing the link | grep for the actual URL
	echo
	echo "---wget---"
	wget -U firefox --wait=5 --random-wait --output-document="$paperFilenameDestination" "$paperpdfURL"
	echo "---/wget---"
	echo
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
		# need to teach this to add the abstract at this point!
	fi
}

selectFileFromManualDownloadsFolder(){
	local paperFilenameSuggestion="$1"
	local paperUID="$2"
	
	local old_IFS=$IFS	# save the field separator           
	IFS=$'\n'	# new field separator
	select fileContainingPaper in $(echo -e '( CANCEL THIS MENU )'"\n""$(ls -1 $MANUALDOWNLOADSFOLDER/* )") # if manuallyDownloadedPdfs is empty this gives "ls: cannot access manuallyDownloadedPdfs/*: No such file or directory". Meh.
	do
		if [[ "$fileContainingPaper" =~ "CANCEL THIS MENU" ]]; then break; fi
		if [[ ! -f "$fileContainingPaper" ]]; then echo -e "\ninvalid choice\n"; break; fi	
		echo -e "\nrename            $fileContainingPaper            to            $paperFilenameSuggestion            ?"
		getYN && mv -i $fileContainingPaper $paperFilenameSuggestion && addFileField "$paperUID" "$paperFilenameSuggestion"
		break # you only get out of a select statement with a break statement
	done
	IFS=$old_IFS	# restore default field separator
}

isUrlIsAnInspireUrl(){
	local url="$1"
	if [[ ! ( "$url" =~ ^https?://inspirehep.net/record/[0-9][0-9]*$ ) ]]
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
	while getopts ":ha:" opt # the first colon suppress getopts' error messages and I substitute my own. The others indicate that an argument is taken.
	do
		case $opt in
		h)	showHelp; exit 0;;
		a)	LISTOFINSPIREURLS="$LISTOFINSPIREURLS $OPTARG";; # i.e. add the URL to the list of URLs
		\?)	echo invalid option "$OPTARG"; exit 1;;
		esac
	done
}

main(){
	if [[ $@ == *"--help"*  ]]; then showHelp; exit 0; fi
	
	LISTOFINSPIREURLS="" # holds the URLs that the user has passed to the program with the -a option
	
	readOptions "$@"
	shift $(($OPTIND-1)) # builtin function "getopts" (inside readOptions) is always used in conjunction with "shift"
	
	if [[ ! $# == 1 ]] # if number of arguments isn't exactly 1
	then
		echo "provide the name of the .bib file"
		echo "use $PROGNAME --help for full help text"
		exit 1
	fi
	BIBFILE="$1" # global variable
	
	for inspireUrl in $LISTOFINSPIREURLS
	do
		echo 
		echo adding bibtex data from URL $inspireUrl
		isUrlIsAnInspireUrl "$inspireUrl" || continue
		addBibtexToBibfile "$(getBibtexFromInspirePage $inspireUrl)"
	done
	echo "" # a blank line
	
	echo "reading $BIBFILE"
	
	echo "FYI a tally chart of fields appearing in the .bib file"
	grep -o '^[^=]* =' "$BIBFILE" | grep -o '[a-zA-Z]*' | sort | uniq --count --ignore-case

	echo "this program generally only uses the arxiv, but for non-arxiv papers it can still manage file/names and add info to the bibtex."
	echo "it will look for non-arxiv papers that have been downloaded manually in the folder $MANUALDOWNLOADSFOLDER"
	if [[ ! -d $MANUALDOWNLOADSFOLDER ]]
	then
		echo "create the $MANUALDOWNLOADSFOLDER?"
		getYN && mkdir $MANUALDOWNLOADSFOLDER
	fi
	echo "" # a blank line 
	
	local old_IFS=$IFS	# save the field separator
	IFS=@	# the field separator used in bib
	for paper in $(fixNewlineUseInBibfile "$BIBFILE")
	do
		echo "---------------------------------------"
		
		# STEP 1 : read the bibtex data into variables
		# regex in next line is: grep for author field | but delete the author tag itself | find surnames = nonblank characters before a comma | deal with {t'Hooft} | remove newlines
		local paperAuthorsSurnames="$(echo $paper | grep -io '^\s*author\s*= "[^"]*'  | sed 's/.*=\s*"\(\S.*\)/\1/' | grep -o '\S*,' | sed 's/.*Hooft.*/tHooft,/' | tr -d '\n' )" # list of names separated by commas e.g. Lu,Perkins,Pope,Stelle,
		local paperYear="$(echo $paper | grep -io '^\s*year\s*= "[^"]*'  | sed 's/.*=\s*"\(\S.*\)/\1/')"
		local paperTitle="$(echo $paper | grep -io '^\s*title\s*= "[^"]*'  | sed 's/.*=\s*"\(\S.*\)/\1/' | tr -d '{}')" # sometimes the title is saved like {Elongating Equations in Type VII String Conglomerations} so use tr to delete any brackets
		local paperTitleSanitised=$(tr -d '{}*$\/()' <<<"$paperTitle") # delete special characters from the title - most of these are actually allowed in filenames but break common bash commands (brackets are actually OK I think?)
		local paperUID="$(head -n 1 <<<$paper | sed 's/^[^{]*{\(.*\),$/\1/')" # will contain a semicolon, may contain single quote *cough* 't'Hooft *cough*
		# check the variables - it could always happen that there are weird unanticipated characters in the bib...
		problem="no problem"
		if [[ -z "$paperAuthorsSurnames" ]]; 	then problem="author name(s)"; fi
		if [[ -z "$paperYear" ]]; 		then problem="year"; fi
		if [[ -z "$paperTitle" ]]; 		then problem="title"; fi
		if [[ -z "$paperTitleSanitised" ]]; 	then problem="title"; fi
		if [[ -z "$paperUID" ]]; 		then problem="UID"; fi
		if [[ !( "$problem" == "no problem" ) ]]
		then 
			echo "couldn't read the paper's $problem from the following bibtex:"
			echo ""
			echo $paper
			echo ""
			echo "please edit the bib file $BIBFILE"
			continue
		fi
		
		# need to write code to handle the event that there is no doi field in the bibtex!
		local paperDoiLink=http://dx.doi.org/"$(echo $paper | grep -io '^\s*doi\s*= "[^"]*'  | sed 's/\s*[Dd][Oo][Ii]\s*= "//' )"
		# if [[ -z "$paperDoiLink" ]] then SOMETHING?
		
		# STEP 2: generate a filename - it's important not to change this code as it will render the previously-downloaded pdfs invisible to the program
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
		
		
		# STEP 3: store info in variables
		
		echo $paper | grep -i ARXIV >/dev/null
		local onArxiv=$?
		
		echo $paper| grep -i '^\s*localfile\s*= ' >/dev/null
		local paperFileFieldPresent=$?
		
		# move the checks for abstract/file field here, to main, from function "addAbstractField"
		echo $paper| grep -i '^\s*abstract\s*= ' >/dev/null
		local paperAbstractFieldPresent=$?
		
		[[ -e $paperFilenameSuggestion ]]
		local paperPdfPresent=$?
		
		# we may need the arxiv webpage later. If so, we download it here.
		# we're going to need the arxiv webpage if ( !paperPdfPresent && onArxiv ) || ( !paperAbstractFieldPresent && onArxiv ) = onArxiv && ( !paperPdfPresent || !paperAbstractFieldPresent )
		if [[ $onArxiv -eq true && ( $paperPdfPresent -ne true || $paperAbstractFieldPresent -ne true ) ]] # It's critical that these booleans are kept synchronised with the booleans later that lead to use of the arxivPage variable ! That's iffy design...
		then
			echo "reading arxiv webpage"
			local paperEprintNo="$(echo $paper | grep -io '^\s*eprint\s*= "[^"]*' | sed 's/\s*eprint\s*= "//')" # eprint possible formats include 1501.0006, 1106.4657, hep-th/0206219
			if [[ -z "$paperEprintNo" ]]; 		then echo "couldn't read paper's eprint number - please check the bib file"; 		continue; fi
			local arxivPage="$(echoArxivPage "$paperEprintNo")"
			# CHECK should add a check that the webpage was retrieved sucessfully / that $arxivPage contains valid data
		fi
		
		# STEP 4: make sure we have the pdf, in order of preference: already present in pwd, download from the arxiv, look for it in manuallyDownloadedPdfs, open DOI link in default browser
		echo
		echo "Looking for the pdf in pwd..."
		if [[ $paperPdfPresent -eq true ]]
		then
			echo "...found pdf"
			addFileField "$paperUID" "$paperFilenameSuggestion"
		else
			echo "...pdf not found"
			echo "Is the paper on the arxiv?..."
			if [[ $onArxiv -eq true ]]
			then
				echo "...yes"
				echo "download arxiv pdf?"
				getYN && saveArxivPdf "$arxivPage" "$paperFilenameSuggestion" && addFileField "$paperUID" "$paperFilenameSuggestion"
			else
				echo "...no"
				echo "Looking for a folder for user-downloaded pdfs..."
				if [[ -d $MANUALDOWNLOADSFOLDER ]]
				then
					echo "...found $MANUALDOWNLOADSFOLDER"
					echo
					echo "examining the follwing bibtex entry:"
					echo $paper
					echo "Can you point out this paper from among the files in $MANUALDOWNLOADSFOLDER?"
					getYN && selectFileFromManualDownloadsFolder "$paperFilenameSuggestion" "$paperUID" # this also handles moving the paper and calling addFileField
					local userSelectedFileSucess=$?
				else
					echo "...not found"
					local userSelectedFileSucess=1
				fi # end if MANUALDOWNLOADSFOLDER exists
				# branch for whether that was successful or not
				if [[ $userSelectedFileSucess -ne true ]]
				then
					echo "...Failed to get file from $MANUALDOWNLOADSFOLDER"
					echo 
					echo "You can get hold of the file yourself and put it in $MANUALDOWNLOADSFOLDER for next time the program is run"
					echo "Open the doi link '$paperDoiLink' in your default browser?"
					# need to add a check that there was a valid doi link in the bibtex!
					getYN && xdg-open "$paperDoiLink"
				# else
					# there is no "else" here. I don't know what else we can do to get hold of the paper.
				fi # end if user failed to select file
			fi # end if onArxiv
		fi # end if paperPdfPresent
		echo
		
		# STEP 5: make sure the bibtex has an abstract
		# if there is no abstract in the bibtex, but an abstract is available, then add the abstract if possible
		if [[ $paperAbstractFieldPresent -ne true && $onArxiv -eq true ]]
		then
			# regex is tr to replace all newlines with spaces (so now the webpage is one big line) | grep for the html code of the abstract | sed to extract the pure abstract text
			local paperAbstract="$(tr '\n' ' ' <<< $arxivPage | grep -o '<blockquote.*<span.*bstract.*</span>.*</blockquote>' | sed 's@.*/span> \(.*\)</blockquote.*@\1@')"
			if [[ -z "$paperAbstract" ]]
			then 
				echo "couldn't read paper's abstract"
			else
				addAbstractField "$paperUID" "$paperAbstract"
			fi
		fi
		
	done
	IFS=$old_IFS	# restore default field separator
}


main $@



