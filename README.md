# getPapers
takes a .bib file made up of bibtex from inSPIRE, and handles managing a directory of the papers

it's designed to work with bibtex from inSPIRE. Other bibtex may use different delimeters and would need the regex to be modified accordingly.

it takes your .bib file, and for each article in it it checks if it is available on the arxiv or not.

For papers on the arxiv it downloads the arxiv page, adds the paper's abstract to the .bib file, downloads the paper, and adds the paper's filename to the .bib file. 
For papers no on the arxiv it asks you to locate the pdf file from the PWD, and add's the paper's filename to the .bib file.

Adding the filename to the .bib file allows a bib manager, such as KBibTex (which I use), to read the filename from the .bib file and open the file for you.
