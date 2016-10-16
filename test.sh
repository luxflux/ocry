#!/bin/bash

set -e

LANG=deu+eng

shopt -s nullglob

for f in *.jpg; do
    echo "Running OCR on $f"
    tesseract -psm 3 -l $LANG $f $f pdf
done

echo "Joining files into single PDF..."
command gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=pages.pdf test_page1.jpg.pdf test_page2.jpg.pdf
open pages.pdf
