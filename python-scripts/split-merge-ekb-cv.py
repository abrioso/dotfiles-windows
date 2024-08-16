#
# This script splits and merges multiple PDF files into a single PDF file. 
# It uses the PyPDF2 library to read the input PDF files and write the merged PDF file. 
# xThe merge_pdfs function takes a list of PDF files and an output file name as input, and merges the PDF files into a single PDF file. 
# The main function lists the PDF files in the current directory, merges them using the merge_pdfs function, and saves the merged PDF file as 'merged.pdf'. 
# The script can be run from the command line or as a standalone script to merge PDF files.
#

import os
import PyPDF2

def split_merge_pdfs(pdf_list, output):
    # Create a PDF writer object
    pdf_writer = PyPDF2.PdfWriter()

    # Loop through all the PDF files
    for pdf in pdf_list:
        pdf_reader = PyPDF2.PdfReader(pdf[0])
        for page_num in pdf[1]:
            page = pdf_reader.pages[page_num]
            pdf_writer.add_page(page)
       
    # Save the merged PDF to a file
    with open(output, 'wb') as out:
        pdf_writer.write(out)

def ___main___():
    # Two dimension list with the pdf location and the pages to use
    pdf_list = [
        ['pdf1.pdf', [0, 1, 2, 3]],
        ['pdf2.pdf', [0, 1, 2, 3, 4, 5, 6, 7]],
        ['pdf3.pdf', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]]
        ['pdf4.pdf', [0-20]]
    ]
    # Output file name
    output = 'merged.pdf'

    # List the PDF files to be merged
    print('PDF files to merge:')
    for pdf in pdf_list:
        print('file: ' + pdf[0] + ' pages: ' + pdf[1])

    # Merge the PDF files
    split_merge_pdfs(pdf_list, output)
    # Print a message to indicate that the PDF files have been merged
    print('PDF files have been merged successfully to' + output + '!')

if __name__ == '__main__':
    ___main___()
