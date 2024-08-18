#
# This script splits and merges multiple PDF files into a single PDF file. 
# It uses the PyPDF2 library to read the input PDF files and write the merged PDF file. 
# xThe merge_pdfs function takes a list of PDF files and an output file name as input, and merges the PDF files into a single PDF file. 
# The main function lists the PDF files in the current directory, merges them using the merge_pdfs function, and saves the merged PDF file as 'merged.pdf'. 
# The script can be run from the command line or as a standalone script to merge PDF files.
#

import os
import PyPDF2
from decimal import Decimal

def split_merge_pdfs(pdf_list, output):
    # Create a PDF writer object
    pdf_writer = PyPDF2.PdfWriter()

    # Loop through all the PDF files
    for pdf in pdf_list:
        pdf_reader = PyPDF2.PdfReader(pdf[0])
        # Write to console the pdf file name and the pages to use
        print('Processing file: ' + pdf[0] + ' pages: ' + pdf[1].__str__())
        # Loop through all the pages in the PDF file
        for page_num in pdf[1]:
            page = pdf_reader.pages[page_num]
            # Write to console the page number
            print('  Processing page: ' + page_num.__str__())
            # Write to console the page size
            width = float(page.mediabox.width)
            height = float(page.mediabox.height)
            print('    Page size: ' + str(width) + ' x ' + str(height))
            
            # Check if the page is in landscape or portrait mode
            if width > height:
                print('      Landscape mode')
                # If page is not A4, then resize it to A4
                if width != float(PyPDF2.PaperSize.A4.height) or height != float(PyPDF2.PaperSize.A4.width):
                    # Write to console information about the page size change
                    print('      Changing Page size to A4')
                    # Calculate the scale factor to fit the page to A4
                    scale_width = float(PyPDF2.PaperSize.A4.height) / float(width)
                    scale_height = float(PyPDF2.PaperSize.A4.width) / float(height)
                    scale = min(scale_width, scale_height)
                    # Write to console the scale factor
                    print('      Scale factor: ' + str(scale))
                    # Center the page and scale it to fit the new size
                    page.scale_by(scale)
                    page.mediabox.lowerleft = ((PyPDF2.PaperSize.A4.height - width * scale) / 2, (PyPDF2.PaperSize.A4.width - height * scale) / 2)
                    page.mediabox.upperright = (PyPDF2.PaperSize.A4.height - (PyPDF2.PaperSize.A4.height - width * scale) / 2, PyPDF2.PaperSize.A4.width - (PyPDF2.PaperSize.A4.width - height * scale) / 2)
                    
                    # Write to console the new page size
                    width = float(page.mediabox.width)
                    height = float(page.mediabox.height)
                    print('    New page size: ' + str(width) + ' x ' + str(height))

            else:
                print('      Portrait mode')
                # If page is not A4, then resize it to A4
                if width != float(PyPDF2.PaperSize.A4.width) or height != float(PyPDF2.PaperSize.A4.height):
                    # Write to console information about the page size change
                    print('      Changing Page size to A4')

                    # Calculate the scale factor to fit the page to A4
                    scale_width = float(PyPDF2.PaperSize.A4.height) / float(height)
                    scale_height = float(PyPDF2.PaperSize.A4.width) / float(width)
                    scale = min(scale_width, scale_height)
                    # Write to console the scale factor
                    print('      Scale factor: ' + str(scale))
                    # Center the page and scale it to fit the new size
                    page.scale_by(scale)
                    page.mediabox.lowerleft = ((PyPDF2.PaperSize.A4.height - width * scale) / 2, (PyPDF2.PaperSize.A4.width - height * scale) / 2)
                    page.mediabox.upperright = (PyPDF2.PaperSize.A4.height - (PyPDF2.PaperSize.A4.height - width * scale) / 2, PyPDF2.PaperSize.A4.width - (PyPDF2.PaperSize.A4.width - height * scale) / 2)
                    
                    # Write to console the new page size
                    width = float(page.mediabox.width)
                    height = float(page.mediabox.height)
                    print('    New page size: ' + str(width) + ' x ' + str(height))

                    #TODO: Resize the page to A4
                    page.scale_by(1)
                    page.mediabox.lowerleft = (0, 0)
                    page.mediabox.upperright = (PyPDF2.PaperSize.A4.width, PyPDF2.PaperSize.A4.height)
                    
                    width = float(page.mediabox.width)
                    height = float(page.mediabox.height)
                    print('    New page size: ' + str(width) + ' x ' + str(height))



            # Add the page to the PDF writer object
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
        ['D/D2.pdf', list(range(0, 3))],
        ['CV_EKB_Vol2.pdf', list(range(118, 119))],
#        ['D/D3.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(121, 122))],
        ['D/D4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(123, 124))],
        ['D/D5.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(125, 126))],
        ['D/D6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(127, 128))],
        ['D/D7.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(130, 131))],
        ['D/D8.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(132, 133))],
        ['D/D9.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(134, 135))],
        ['D/D10.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(136, 137))],
        ['D/D11.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(139, 140))],
        ['D/D12.pdf', list(range(0, 23))],
        ['CV_EKB_Vol2.pdf', list(range(163, 164))],
        ['D/D13.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(165, 166))],
        ['D/D14.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(167, 168))],
        ['D/D15.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(169, 170))],
        ['D/D16.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(171, 172))],
        ['D/D17.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(173, 174))],
        ['D/D18.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(176, 177))],
        ['D/D19.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(179, 180))],
        ['D/D20.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(182, 183))],
        ['D/D21.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(184, 185))],
        ['D/D22.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(186, 187))],
#        ['D/D23.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(188, 189))],
        ['D/D24.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(190, 191))],
        ['D/D25.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(192, 193))],
        ['D/D26.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(195, 196))],
        ['D/D27.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(198, 199))],
        ['D/D28.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(200, 201))],
        ['D/D29.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(202, 203))],
#        ['D/D30.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(204, 205))],
        ['D/D31.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(206, 207))],
        ['D/D32.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(208, 209))],
        ['CV_EKB_Vol2.pdf', list(range(209, 210))],
        ['E/E1.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(211, 212))],
        ['E/E2.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(213, 214))],
        ['E/E3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(215, 216))],
        ['E/E4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(217, 218))],
        ['E/E5.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(219, 220))],
        ['E/E6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(221, 222))],
        ['E/E7.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(223, 224))],
        ['E/E8.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(225, 226))],
        ['E/E9.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(227, 228))],
        ['E/E10.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(229, 230))],
        ['E/E11.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(231, 232))],
        ['E/E12.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(233, 234))],
        ['E/E13.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(235, 236))],
        ['E/E14.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(238, 239))],
        ['E/E15.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(240, 241))],
        ['E/E16.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(242, 243))],
        ['E/E17.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(244, 245))],
        ['E/E18.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(246, 247))],
        ['CV_EKB_Vol2.pdf', list(range(247, 248))],
        ['F/F1.pdf', list(range(0, 5))],
        ['CV_EKB_Vol2.pdf', list(range(253, 254))],
        ['F/F2.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(261, 262))],
        ['F/F3.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(268, 269))],
        ['F/F4.pdf', list(range(0, 8))],
        ['CV_EKB_Vol2.pdf', list(range(279, 278))],
        ['F/F5.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(285, 286))],
        ['F/F6.pdf', list(range(0, 16))],
        ['CV_EKB_Vol2.pdf', list(range(302, 303))],
        ['F/F7.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(310, 311))],
        ['CV_EKB_Vol2.pdf', list(range(311, 312))],
        ['G/G1/G1.1.pdf', list(range(0, 1))],
        ['G/G1/G1.2.pdf', list(range(0, 1))],
        ['G/G1/G1.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(315, 316))],
        ['G/G2/G2.1.pdf', list(range(0, 1))],
        ['G/G2/G2.2.pdf', list(range(0, 1))],
        ['G/G2/G2.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(319, 320))],
        ['G/G3/G3.1.pdf', list(range(0, 1))],
        ['G/G3/G3.2.pdf', list(range(0, 1))],
        ['G/G3/G3.3.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(328, 329))],
        ['G/G4/G4.1.pdf', list(range(0, 1))],
        ['G/G4/G4.2.pdf', list(range(0, 1))],
        ['G/G4/G4.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(332, 333))],
        ['G/G5/G5.1.pdf', list(range(0, 1))],
        ['G/G5/G5.2.pdf', list(range(0, 1))],
        ['G/G5/G5.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(336, 337))],
        ['G/G6/G6.1.pdf', list(range(0, 1))],
        ['G/G6/G6.2.pdf', list(range(0, 1))],
        ['G/G6/G6.3.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(345, 346))],
        ['G/G7/G7.1.pdf', list(range(0, 1))],
        ['G/G7/G7.2.pdf', list(range(0, 1))],
        ['G/G7/G7.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(349, 350))],
        ['G/G8/G8.1.pdf', list(range(0, 1))],
        ['G/G8/G8.2.pdf', list(range(0, 1))],
        ['G/G8/G8.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(353, 354))],
        ['G/G9/G9.1.pdf', list(range(0, 1))],
        ['G/G9/G9.2.pdf', list(range(0, 1))],
        ['G/G9/G9.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(357, 358))],
        ['G/G10/G10.1.pdf', list(range(0, 1))],
        ['G/G10/G10.2.pdf', list(range(0, 1))],
        ['G/G10/G10.3.pdf', list(range(0, 5))],
        ['CV_EKB_Vol2.pdf', list(range(365, 366))],
        ['G/G11/G11.1.pdf', list(range(0, 1))],
        ['G/G11/G11.2.pdf', list(range(0, 1))],
        ['G/G11/G11.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(369, 370))],
        ['G/G12/G12.1.pdf', list(range(0, 1))],
        ['G/G12/G12.2.pdf', list(range(0, 1))],
        ['G/G12/G12.3.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(376, 377))],
        ['CV_EKB_Vol2.pdf', list(range(377, 378))],
        ['H/H1.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(379, 380))],
        ['H/H2.pdf', list(range(0, 18))],
        ['CV_EKB_Vol2.pdf', list(range(398, 399))],
        ['H/H3.pdf', list(range(0, 10))],
        ['CV_EKB_Vol2.pdf', list(range(409, 410))],
        ['H/H4.pdf', list(range(0, 17))],
        ['CV_EKB_Vol2.pdf', list(range(427, 428))],
        ['H/H5.pdf', list(range(0, 11))],
        ['CV_EKB_Vol2.pdf', list(range(439, 440))],
        ['H/H6.pdf', list(range(0, 27))],
        ['CV_EKB_Vol2.pdf', list(range(467, 468))],
        ['H/H7.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(474, 475))],
        ['H/H8_H15.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(476, 477))],
        ['H/H8_H15.pdf', list(range(1, 2))],
        ['CV_EKB_Vol2.pdf', list(range(478, 479))],
        ['H/H8_H15.pdf', list(range(2, 3))],
        ['CV_EKB_Vol2.pdf', list(range(480, 481))],
        ['H/H8_H15.pdf', list(range(3, 4))],
        ['CV_EKB_Vol2.pdf', list(range(482, 483))],
        ['H/H8_H15.pdf', list(range(4, 5))],
        ['CV_EKB_Vol2.pdf', list(range(484, 485))],
        ['H/H8_H15.pdf', list(range(5, 6))],
        ['CV_EKB_Vol2.pdf', list(range(486, 487))],
        ['H/H8_H15.pdf', list(range(6, 7))],
        ['CV_EKB_Vol2.pdf', list(range(488, 489))],
        ['H/H8_H15.pdf', list(range(7, 8))],
        ['CV_EKB_Vol2.pdf', list(range(490, 491))],
        ['H/H16.pdf', list(range(0, 15))],
        ['CV_EKB_Vol2.pdf', list(range(506, 507))],
        ['H/H17.1.pdf', list(range(0, 1))],
        ['H/H17.2.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(512, 513))],
        ['H/H18.1.pdf', list(range(0, 1))],
        ['H/H18.2.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(518, 519))],
        ['H/H19.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(526, 527))],
        ['H/H20.1.pdf', list(range(0, 1))],
        ['H/H20.2.pdf', list(range(0, 8))],
        ['CV_EKB_Vol2.pdf', list(range(536, 537))],
        ['H/H21.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(541, 542))],
        ['H/H22.1.pdf', list(range(0, 1))],
        ['H/H22.2.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(547, 548))]

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
