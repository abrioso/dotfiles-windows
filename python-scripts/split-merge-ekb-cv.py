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
        ['CV_EKB_Vol2.pdf', list(range(0, 18))],
        ['A/A1.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(20, 21))],
        ['A/A2.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(23, 24))],
        ['A/A3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(25, 26))],
        ['A/A4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(27, 28))],
        ['A/A5.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(30, 31))],
        ['A/A6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(32, 33))],
        ['A/A7.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(34, 35))],
        ['A/A8.pdf', list(range(0, 3))],
        ['CV_EKB_Vol2.pdf', list(range(38, 39))],
        ['CV_EKB_Vol2.pdf', list(range(39, 40))],
        ['CV_EKB_Vol2.pdf', list(range(40, 41))],   # TODO: Replace with 'B/B1.pdf', list(range(0, 1)) for the correct file
        ['CV_EKB_Vol2.pdf', list(range(41, 42))],   
        ['CV_EKB_Vol2.pdf', list(range(42, 43))],   # TODO: Replace with 'B/B2.pdf', list(range(0, 1)) for the correct file
        ['CV_EKB_Vol2.pdf', list(range(43, 44))],   
        ['B/B3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(45, 46))],   
        ['B/B4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(47, 48))],
        ['CV_EKB_Vol2.pdf', list(range(48, 49))],   # TODO: Replace with 'B/B5.pdf', list(range(0, 1)) for the correct file
        ['CV_EKB_Vol2.pdf', list(range(49, 50))],
        ['CV_EKB_Vol2.pdf', list(range(50, 51))],   # TODO: Replace with 'B/B6.pdf', list(range(0, 1)) for the correct file
        ['CV_EKB_Vol2.pdf', list(range(51, 52))],
        ['CV_EKB_Vol2.pdf', list(range(52, 53))],   # TODO: Replace with 'B/B7.pdf', list(range(0, 1)) for the correct file
        ['CV_EKB_Vol2.pdf', list(range(53, 54))],
        ['B/B8.pdf', list(range(0, 1))],   # TODO: Replace with  for the correct file
        ['CV_EKB_Vol2.pdf', list(range(55, 56))],
        ['B/B9.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(57, 58))],
        ['CV_EKB_Vol2.pdf', list(range(58, 59))],
        ['C/C1.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(61, 62))],
        ['C/C2.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(64, 65))],
        ['C/C3.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(67, 68))],
#        ['C/C4.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(70, 71))],
        ['C/C5.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(73, 74))],
        ['C/C6.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(76, 77))],
        ['C/C7.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(79, 80))],
        ['C/C8.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(82, 83))],
        ['C/C9.1.pdf', list(range(0, 2))],
        ['C/C9.2.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(87, 88))],
#        ['C/C10.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(90, 91))],
#        ['C/C11.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(93, 94))],
        ['C/C12.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(96, 97))],
#        ['C/C13.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(99, 100))],
        ['C/C14.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(102, 103))],
        ['C/C15.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(105, 106))],
#        ['C/C16.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(108, 109))],
#        ['C/C17.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(110, 111))],
        ['CV_EKB_Vol2.pdf', list(range(111, 112))],
        ['D/D1.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(114, 115))],
#        ['D/D2.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(117, 118))],
#        ['D/D3.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(120, 121))],
        ['D/D4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(122, 123))],
        ['D/D5.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(124, 125))],
        ['D/D6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(126, 127))],
        ['D/D7.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(129, 130))],
        ['D/D8.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(131, 132))],
        ['D/D9.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(133, 134))],
        ['D/D10.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(135, 136))],
        ['D/D11.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(138, 139))],
        ['D/D12.pdf', list(range(0, 23))],
        ['CV_EKB_Vol2.pdf', list(range(162, 163))],
        ['D/D13.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(164, 165))],
        ['D/D14.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(166, 167))],
        ['D/D15.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(168, 169))],
        ['D/D16.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(170, 171))],
        ['D/D17.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(172, 173))],
        ['D/D18.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(175, 176))],
        ['D/D19.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(178, 179))],
        ['D/D20.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(181, 182))],
        ['D/D21.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(183, 184))],
        ['D/D22.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(185, 186))],
#        ['D/D23.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(187, 188))],
        ['D/D24.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(189, 190))],
        ['D/D25.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(191, 192))],
        ['D/D26.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(194, 195))],
        ['D/D27.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(197, 198))],
        ['D/D28.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(199, 200))],
        ['D/D29.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(201, 202))],
#        ['D/D30.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(203, 204))],
        ['D/D31.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(205, 206))],
        ['D/D32.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(207, 208))],
        ['CV_EKB_Vol2.pdf', list(range(208, 209))]
    ]

    # Output file name
    output = 'merged.pdf'

    # List the PDF files to be merged
    print('PDF files to merge:')
    for pdf in pdf_list:
        print('file: ' + pdf[0] + ' pages: ' + pdf[1].__str__())

    # Merge the PDF files
    split_merge_pdfs(pdf_list, output)
    # Print a message to indicate that the PDF files have been merged
    print('PDF files have been merged successfully to ' + output + '!')

if __name__ == '__main__':
    ___main___()
