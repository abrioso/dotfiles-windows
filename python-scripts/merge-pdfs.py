#
# This script merges multiple PDF files into a single PDF file. 
# It uses the PyPDF2 library to read the input PDF files and write the merged PDF file. 
# The merge_pdfs function takes a list of PDF files and an output file name as input, and merges the PDF files into a single PDF file. 
# The main function lists the PDF files in the current directory, merges them using the merge_pdfs function, and saves the merged PDF file as 'merged.pdf'. 
# The script can be run from the command line or as a standalone script to merge PDF files.
#

import os
import PyPDF2

def merge_pdfs(pdf_list, output):
    # Create a PDF writer object
    pdf_writer = PyPDF2.PdfWriter()

    # Loop through all the PDF files
    for pdf in pdf_list:
        pdf_reader = PyPDF2.PdfReader(pdf)
        for page_num in range(len(pdf_reader.pages)):
            page = pdf_reader.pages[page_num]
            pdf_writer.add_page(page)
    
    # Save the merged PDF to a file
    with open(output, 'wb') as out:
        pdf_writer.write(out)

def ___main___():
    # List to store the PDF files
    pdf_files = []

    # Select the PDF files to merge using the current directory
    for file in os.listdir():
        if file.endswith('.pdf'):
            pdf_files.append(file)
    
    # List the PDF files to be merged
    print('PDF files to merge:')
    for pdf in pdf_files:
        print(pdf)

    # Merge the PDF files
    merge_pdfs(pdf_files, 'merged.pdf')
    # Print a message to indicate that the PDF files have been merged
    print('PDF files have been merged successfully!')

if __name__ == '__main__':
    ___main___()
