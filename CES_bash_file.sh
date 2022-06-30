#!/bin/sh

#-------------------------------------------------------------------------------
# Name:        	CES_bash_file.sh
# Purpose:     	Calls every piece of code in the project, from raw data input
#		through final analyses
#
# Author:      	Ryan Kellogg
#
# Created:     	11 May, 2022
#
# To run:	Open a bash shell, change the directory to your local repository,
#		and then type the command:
#		bash -x CES_bash_file.sh |& tee CES_bash_file.out.txt
#-------------------------------------------------------------------------------


# DEFINE PATH
if [ "$HOME" = "/c/Users/kelloggr" ]; then
        CODEDIR=C:/Work/CESequivalence
        DBDIR="C:/Users/kelloggr/Dropbox/CESequivalence"
elif [ "$HOME" = "/c/Users/kelloggr1" ]; then
        CODEDIR=C:/Work/CESequivalence
        DBDIR="C:/Users/kelloggr/Dropbox/CESequivalence"
fi

# STATA INSTALLS
stataSE-64 -e do $CODEDIR/code/stata_installs.do

# DELETE EVERYTHING IN INTERMEDIATE DATA IN DROPBOX
find "$DBDIR/IntermediateData" -type f -delete

# DELETE ALL FIGURES, TABLES, AND SINGLE NUM TEX FILES STORED IN REPO RESULTS
find "$CODEDIR/paper/figures" -type f -delete
find "$CODEDIR/paper/figures_slides" -type f -delete
find "$CODEDIR/paper/single_num_tex" -type f -delete

# COPY CARTOON FIGURES FROM DROPBOX TO REPO
cp "$DBDIR/CartoonFigures/Cartoon0.png" "$CODEDIR/paper/figures"
cp "$DBDIR/CartoonFigures/Cartoon1.png" "$CODEDIR/paper/figures"
cp "$DBDIR/CartoonFigures/Cartoon2.png" "$CODEDIR/paper/figures"
cp "$DBDIR/CartoonFigures/Cartoon3.png" "$CODEDIR/paper/figures"

# RUN THE BUILD SCRIPTS
stataSE-64 -e do $CODEDIR/code/build/EIAdata/Load_EIA923.do
stataSE-64 -e do $CODEDIR/code/build/EIAdata/Load_3_1_Generator.do
stataSE-64 -e do $CODEDIR/code/build/EIAdata/MergeEIAdata.do
stataSE-64 -e do $CODEDIR/code/build/EIAdata/ExportEIADataToMatlab.do
stataSE-64 -e do $CODEDIR/code/build/EIAdata/HistoricCoalMWh.do

# RUN THE SIMULATIONS
matlab -nosplash -wait -nodesktop -r "cd $CODEDIR/code/analysis; mainscript; exit"

# COMPILE THE PAPER
cd $CODEDIR/paper
pdflatex -output-directory=$CODEDIR/paper EEPEpaper.tex
bibtex refs
pdflatex -output-directory=$CODEDIR/paper EEPEpaper.tex
pdflatex -output-directory=$CODEDIR/paper EEPEpaper.tex
pdflatex -output-directory=$CODEDIR/paper EEPEpaper.tex

#clean up log files
rm *.log

exit
