# getPapers

getPapers is a simple utility for HEP physicists, to download and rename pdfs of papers, and add papers and paper information to a bibtex file.
Pair it with a bibtex manager such as kbibtex for a complete bibtex/paper management solution.
It is designed to work with inSPIRE HEP and arxiv.org, but the code would be easy to adapt to other disciplines, as required.

Usage overview
=======
run the program like so:

$ bash getPapers.sh -a [inSPIRE link to paper] myPapers.bib

and it does three things:

1. It adds the bibtex of the linked paper(s) to the bib file
2. Downloads all the papers in the bib file (unless already present) *
3. it adds information to the paper's bibtex entry - the pdf's file path, and if possible the paper's abstract too.

 * for papers not on the arxiv, it will instead let you to select the paper from a list of your files and/or opens the doi link in your browser for you, to save you some clicks.

Details
=======

Comments
-----------
Papers are downloaded preferably from the arxiv, or otherwise it can open the doi link in your browser, or you can select a previously downloaded pdf from a list.

If you pass it an inSPIRE link then it can automatically retrieve the bibtex and add it to the bibfile.

To work in tandem with a bibtex manager, it adds the pdf's file path and the paper's abstract to the bibtex.

The program's regex is designed to work with bibtex that is from inSPIRE. (other bibtex styles that use e.g. different delimeters are not currently supported)

Program structure
-----------
Pass it any number of  inSPIRE links using the -a option, and pass it your bib file as the argument:

$ bash getPapers.sh -a [inSPIRE link] -a [inSPIRE link] ... -a [inSPIRE link] myPapers.bib

For each inSPIRE link it retrieves the bibtex of the paper from the site, and adds it to the end of myPapers.bib

For each paper in myPapers.bib it generates the pdf filename "author1,author2 - year - title.pdf" and then using that:

1. It looks for it in the pwd. If it can't find it then
2. If the paper is on the arxiv it downloads the pdf to the pwd. This will work for most papers, but if it's not on the arxiv then
3. It asks the user to select the paper from a list of the files in "manuallyDownloadedPdfs" (a subfolder of the pwd). If it's not there then
4. It offers to open the paper's doi link in your default browser. The user should pass the CAPCHA on the publisher's website and save the paper to "manuallyDownloadedPdfs" with any filename. Next time the program is run this paper can be pointed out at step 3.

Motivation
-----------
I used to use proprietary software to manage my papers and bib files, but despite everything it was just too buggy. 
I decided my requirements were simple. I just wanted a program that could speed up the repetitive process of finding a paper, browsing to the bibtex online, copying it, opening the bibfile, pasting in the bibtex, saving, browsing to the pdf download page, clicking through, typing a filename, etc. 
I also wanted something that could automatically determine if I had a saved copy of all the papers I wanted.
