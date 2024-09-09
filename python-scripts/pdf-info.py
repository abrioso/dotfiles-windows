# Description: This script reads and prints the information of a PDF file, such as the page size and orientation.

import sys
from PyPDF2 import PdfReader

def info_pdf(file_path):
    with open(file_path, 'rb') as file:
        pdfreader = PdfReader(file)

        # Write to console the filename
        print('Processing file: ' + file_path)

        for page_num in range(len(pdfreader.pages)):
             # Write to console the page number
            print('  Processing page: ' + page_num.__str__())

            # Get the page
            read_page = pdfreader.pages[page_num]

            # Get the page size
            width = float(read_page.mediabox.width)
            height = float(read_page.mediabox.height)

            # Write to console the page size
            print('    Page size: ' + str(width) + ' x ' + str(height))        
                        
            # Check if the page is in landscape or portrait mode
            if width > height:
                print('      Landscape mode')
            else:
                print('      Portrait mode')

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Please provide the path to the PDF file(s) as command line argument(s).")
        sys.exit(1)

    for file_path in sys.argv[1:]:
        info_pdf(file_path)