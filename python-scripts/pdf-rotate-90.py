# Description: This script rotates a PDF file 90 degrees clockwise.
import sys
from PyPDF2 import PdfReader, PdfWriter, PageObject, Transformation

def rotate_pdf(file_path):
    with open(file_path, 'rb') as file:
        pdfreader = PdfReader(file)
        pdfwriter = PdfWriter()

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

            #Create a new blank page with the rotated page size
            new_width, new_height = float(height), float(width) 
            new_page = PageObject.create_blank_page(width=new_width, height=new_height)
            
            # Merge the rotated content onto the blank page
            read_page.add_transformation(Transformation().rotate(90))
            new_page.merge_page(read_page, False)
            print('    Page Merged')

            width = float(new_page.mediabox.width)
            height = float(new_page.mediabox.height)
            print('    New page size (2): ' + str(width) + ' x ' + str(height))

            # Add the new page to the output
            pdfwriter.add_page(new_page)
            

        output_file_path = f"rotated_{file_path.split('\\')[-1]}"
        with open(output_file_path, 'wb') as output_file:
            pdfwriter.write(output_file)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Please provide the path to the PDF file(s) as command line argument(s).")
        sys.exit(1)

    for file_path in sys.argv[1:]:
        rotate_pdf(file_path)