#
# This script splits and merges multiple PDF files into a single PDF file. 
# It uses the PyPDF2 library to read the input PDF files and write the merged PDF file. 
# xThe merge_pdfs function takes a list of PDF files and an output file name as input, and merges the PDF files into a single PDF file. 
# The main function lists the PDF files in the current directory, merges them using the merge_pdfs function, and saves the merged PDF file as 'merged.pdf'. 
# The script can be run from the command line or as a standalone script to merge PDF files.
#

import os
import PyPDF2
from PyPDF2 import PdfWriter, PdfReader, PageObject, Transformation
#from PyPDF2.generic import ArrayObject, FloatObject, NameObject
from decimal import Decimal

#def get_indirect_object_info(reader, obj_num, gen_num):
#        indirect_object = PyPDF2.generic.IndirectObject(obj_num, gen_num, reader)
#        actual_object = indirect_object.get_object()
#        return actual_object
#
#def extract_annotations(page):
#    if '/Annots' in page:
#        return page['/Annots']
#    return []

def split_merge_pdfs(pdf_list, output):
    """
    Splits and merges PDF files.
    Args:
        pdf_list (list): A list of tuples containing the path of the PDF file and the pages to use.
        output (str): The path of the output file.
    Returns:
        None
    Raises:
        None
    """
    # Code implementation goes here
    # Create a PDF writer object
    pdf_writer = PyPDF2.PdfWriter()

    # Loop through all the PDF files
    for pdf in pdf_list:
        pdf_reader = PyPDF2.PdfReader(pdf[0])
        
        # Write to console the pdf file name and the pages to use
        print('Processing file: ' + pdf[0] + ' pages: ' + pdf[1].__str__())
        
        # Loop through all the pages in the PDF file
        for page_num in pdf[1]:
            new_page = read_page = pdf_reader.pages[page_num]
            
            # Write to console the page number
            print('  Processing page: ' + page_num.__str__())

 #           # Get the annotations from the page
 #           annotations = extract_annotations(read_page)
 #           print('    Annotations: ' + annotations.__str__())

            # Write to console the page size
            width = float(read_page.mediabox.width)
            height = float(read_page.mediabox.height)
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
                    read_page.scale_by(scale)
#                    read_page.mediabox.lowerleft = ((PyPDF2.PaperSize.A4.height - width * scale) / 2, (PyPDF2.PaperSize.A4.width - height * scale) / 2)
#                    read_page.mediabox.upperright = (PyPDF2.PaperSize.A4.height - (PyPDF2.PaperSize.A4.height - width * scale) / 2, PyPDF2.PaperSize.A4.width - (PyPDF2.PaperSize.A4.width - height * scale) / 2)
                    
                    # Write to console the new page size
                    width = float(read_page.mediabox.width)
                    height = float(read_page.mediabox.height)
                    print('    New page size (1): ' + str(width) + ' x ' + str(height))

                    #Correct page size back to A4
                    new_width, new_height = float(PyPDF2.PaperSize.A4.height), float(PyPDF2.PaperSize.A4.width)
                  
                    new_page = PageObject.create_blank_page(width=new_width, height=new_height)
                    
                    # Calculate the position to center the scaled content on the blank page
                    x_pos = (new_width - float(read_page.mediabox.width)) / 2
                    y_pos = (new_height - float(read_page.mediabox.height)) / 2

                    # Apply the translation transformation to the read_page
                    page_transformation = Transformation().translate(tx=x_pos, ty=y_pos)
                    read_page.add_transformation(page_transformation)

                    # Merge the scaled content onto the blank page
                    new_page.merge_page(read_page)

                    width = float(new_page.mediabox.width)
                    height = float(new_page.mediabox.height)
                    print('    New page size (2): ' + str(width) + ' x ' + str(height))

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
                    read_page.scale_by(scale)
#                    read_page.mediabox.lowerleft = ((PyPDF2.PaperSize.A4.height - width * scale) / 2, (PyPDF2.PaperSize.A4.width - height * scale) / 2)
#                    read_page.mediabox.upperright = (PyPDF2.PaperSize.A4.height - (PyPDF2.PaperSize.A4.height - width * scale) / 2, PyPDF2.PaperSize.A4.width - (PyPDF2.PaperSize.A4.width - height * scale) / 2)
                    
                    # Write to console the new page size
                    width = float(read_page.mediabox.width)
                    height = float(read_page.mediabox.height)
                    print('    New page size (1): ' + str(width) + ' x ' + str(height))

                    #Correct page size back to A4
                    new_width, new_height = float(PyPDF2.PaperSize.A4.width), float(PyPDF2.PaperSize.A4.height)
                  
                    new_page = PageObject.create_blank_page(width=new_width, height=new_height)

                    
                    # Calculate the position to center the scaled content on the blank page
                    x_pos = (new_width - float(read_page.mediabox.width)) / 2
                    y_pos = (new_height - float(read_page.mediabox.height)) / 2

                    # Apply the translation transformation to the read_page
                    page_transformation = Transformation().translate(tx=x_pos, ty=y_pos)
                    read_page.add_transformation(page_transformation)

                    # Merge the scaled content onto the blank page
                    new_page.merge_page(read_page)

                    width = float(new_page.mediabox.width)
                    height = float(new_page.mediabox.height)
                    print('    New page size (2): ' + str(width) + ' x ' + str(height))

            # Add the page to the PDF writer object
            pdf_writer.add_page(new_page)
            
            # Write to console the total number of pages in the PDF writer object
            #print('Added page: ' + len(pdf_writer.pages).__str__())
            # Change the foreground and background color
            print('\033[43m' + 'Added page: ' + len(pdf_writer.pages).__str__() + '\033[0m')

#            if annotations:
#                temp_page = pdf_writer.pages[-1]
#                for annotation in annotations:
#                    annotation_object = get_indirect_object_info(pdf_reader, annotation.idnum, annotation.generation)
#                    annotation_object.update({
#                        '/Border': ArrayObject([FloatObject(0), FloatObject(0), FloatObject(1)])  # [Horizontal corner radius, Vertical corner radius, Border width]
#                    })
#                    print('\033[43m' + '    Annotation: ' + annotation.__str__() + ' to page: ' + len(pdf_writer.pages).__str__() + '\033[0m')
#                    print('    Annotation object: ' + annotation_object.__str__())
#                    temp_page[NameObject('/Annots')].append(annotation_object)
#                    print('    Added Annotation' + '\033[20m')
# #               temp_page[PyPDF2.generic.NameObject('/Annots')] = annotations


    # Save the merged PDF to a file
    with open(output, 'wb') as out:
        pdf_writer.write(out)

def ___main___():
    # Two dimension list with the pdf location and the pages to use
    pdf_list = [
        ['CV_EKB_Vol2.pdf', list(range(0, 16))],
        ['A/A1.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(18, 19))],
        ['A/A2.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(21, 22))],
        ['A/A3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(23, 24))],
        ['A/A4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(25, 26))],
        ['A/A5.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(28, 29))],
        ['A/A6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(30, 31))],
        ['A/A7.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(32, 33))],
        ['A/A8.pdf', list(range(0, 3))],
        ['CV_EKB_Vol2.pdf', list(range(36, 37))],
        ['CV_EKB_Vol2.pdf', list(range(37, 38))],
        ['B/B1.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(39, 40))],   
        ['B/B2.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(41, 42))],   
        ['B/B3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(43, 44))],   
        ['B/B4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(45, 46))],
        ['B/B5.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(47, 48))],
        ['B/B6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(49, 50))],
        ['B/B7.pdf', list(range(1, 2))],
        ['CV_EKB_Vol2.pdf', list(range(51, 52))],
        ['B/B8.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(53, 54))],
        ['B/B9.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(55, 56))],
        ['CV_EKB_Vol2.pdf', list(range(56, 57))],
        ['C/C1.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(59, 60))],
        ['C/C2.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(62, 63))],
        ['C/C3.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(65, 66))],
        ['C/C4.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(68, 69))],
        ['C/C5.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(71, 72))],
        ['C/C6.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(74, 75))],
        ['C/C7.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(77, 78))],
        ['C/C8.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(80, 81))],
        ['C/C9.1.pdf', list(range(0, 2))],
        ['C/C9.2.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(85, 86))],
        ['C/C10.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(88, 89))],
        ['C/C11.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(91, 92))],
        ['C/C12.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(94, 95))],
        ['C/C13.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(97, 98))],
        ['C/C14.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(100, 101))],
        ['C/C15.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(103, 104))],
        ['C/C16.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(106, 107))],
        ['C/C17.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(108, 109))],
        ['CV_EKB_Vol2.pdf', list(range(109, 110))],
        ['D/D1.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(111, 112))],
        ['D/D2.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(113, 114))],
        ['D/D3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(115, 116))],
        ['D/D4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(117, 118))],
        ['D/D5.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(120, 121))],
        ['D/D6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(122, 123))],
        ['D/D7.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(124, 125))],
        ['D/D8.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(126, 127))],
        ['D/D9.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(129, 130))],
        ['D/D10.pdf', list(range(0, 23))],
        ['CV_EKB_Vol2.pdf', list(range(153, 154))],
        ['D/D11.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(155, 156))],
        ['D/D12.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(157, 158))],
        ['D/D13.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(159, 160))],
        ['D/D14.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(161, 162))],
        ['D/D15.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(163, 164))],
        ['D/D16.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(166, 167))],
        ['D/D17.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(169, 170))],
        ['D/D18.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(172, 173))],
        ['D/D19.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(174, 175))],
        ['D/D20.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(176, 177))],
        ['D/D21.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(178, 179))],
        ['D/D22.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(181, 182))],
        ['D/D23.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(184, 185))],
        ['D/D24.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(186, 187))],
        ['D/D25.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(188, 189))],
        ['D/D26.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(190, 191))],
        ['D/D27.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(192, 193))],
        ['D/D28.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(194, 195))],
        ['D/D29.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(196, 197))],
        ['D/D30.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(198, 199))],
        ['CV_EKB_Vol2.pdf', list(range(199, 200))],
        ['E/E1.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(201, 202))],
        ['E/E2.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(203, 204))],
        ['E/E3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(205, 206))],
        ['E/E4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(207, 208))],
        ['E/E5.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(209, 210))],
        ['E/E6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(211, 212))],
        ['E/E7.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(213, 214))],
        ['E/E8.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(215, 216))],
        ['E/E9.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(217, 218))],
        ['E/E10.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(219, 220))],
        ['E/E11.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(222, 223))],
        ['E/E12.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(224, 225))],
        ['E/E13.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(226, 227))],
        ['E/E14.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(228, 229))],
        ['E/E15.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(230, 231))],
        ['CV_EKB_Vol2.pdf', list(range(231, 232))],
        ['F/F1.pdf', list(range(0, 5))],
        ['CV_EKB_Vol2.pdf', list(range(237, 238))],
        ['F/F2.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(245, 246))],
        ['F/F3.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(252, 253))],
        ['F/F4.pdf', list(range(0, 8))],
        ['CV_EKB_Vol2.pdf', list(range(261, 262))],
        ['F/F5.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(269, 270))],
        ['F/F6.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(277, 278))],
        ['F/F7.pdf', list(range(0, 16))],
        ['CV_EKB_Vol2.pdf', list(range(294, 295))],
        ['F/F8.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(297, 298))],
        ['CV_EKB_Vol2.pdf', list(range(298, 299))],
        ['G/G1/G1.1.pdf', list(range(0, 1))],
        ['G/G1/G1.2.pdf', list(range(0, 1))],
        ['G/G1/G1.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(302, 303))],
        ['G/G2/G2.1.pdf', list(range(0, 1))],
        ['G/G2/G2.2.pdf', list(range(0, 1))],
        ['G/G2/G2.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(306, 307))],
        ['G/G3/G3.1.pdf', list(range(0, 1))],
        ['G/G3/G3.2.pdf', list(range(0, 1))],
        ['G/G3/G3.3.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(315, 316))],
        ['G/G4/G4.1.pdf', list(range(0, 1))],
        ['G/G4/G4.2.pdf', list(range(0, 1))],
        ['G/G4/G4.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(319, 320))],
        ['G/G5/G5.1.pdf', list(range(0, 1))],
        ['G/G5/G5.2.pdf', list(range(0, 1))],
        ['G/G5/G5.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(323, 324))],
        ['G/G6/G6.1.pdf', list(range(0, 1))],
        ['G/G6/G6.2.pdf', list(range(0, 1))],
        ['G/G6/G6.3.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(332, 333))],
        ['G/G7/G7.1.pdf', list(range(0, 1))],
        ['G/G7/G7.2.pdf', list(range(0, 1))],
        ['G/G7/G7.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(336, 337))],
        ['G/G8/G8.1.pdf', list(range(0, 1))],
        ['G/G8/G8.2.pdf', list(range(0, 1))],
        ['G/G8/G8.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(340, 341))],
        ['G/G9/G9.1.pdf', list(range(0, 1))],
        ['G/G9/G9.2.pdf', list(range(0, 1))],
        ['G/G9/G9.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(344, 345))],
        ['G/G10/G10.1.pdf', list(range(0, 1))],
        ['G/G10/G10.2.pdf', list(range(0, 1))],
        ['G/G10/G10.3.pdf', list(range(0, 5))],
        ['CV_EKB_Vol2.pdf', list(range(352, 353))],
        ['G/G11/G11.1.pdf', list(range(0, 1))],
        ['G/G11/G11.2.pdf', list(range(0, 1))],
        ['G/G11/G11.3.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(356, 357))],
        ['G/G12/G12.1.pdf', list(range(0, 1))],
        ['G/G12/G12.2.pdf', list(range(0, 1))],
        ['G/G12/G12.3.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(363, 364))],
        ['CV_EKB_Vol2.pdf', list(range(364, 365))],
        ['H/H1.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(366, 367))],
        ['H/H2.pdf', list(range(0, 18))],
        ['CV_EKB_Vol2.pdf', list(range(385, 386))],
        ['H/H3.pdf', list(range(0, 10))],
        ['CV_EKB_Vol2.pdf', list(range(396, 397))],
        ['H/H4.pdf', list(range(0, 17))],
        ['CV_EKB_Vol2.pdf', list(range(414, 415))],
        ['H/H5.pdf', list(range(0, 11))],
        ['CV_EKB_Vol2.pdf', list(range(426, 427))],
        ['H/H6.pdf', list(range(0, 27))],
        ['CV_EKB_Vol2.pdf', list(range(454, 455))],
        ['H/H7.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(461, 462))],
        ['H/H8_H15.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(463, 464))],
        ['H/H8_H15.pdf', list(range(1, 2))],
        ['CV_EKB_Vol2.pdf', list(range(465, 466))],
        ['H/H8_H15.pdf', list(range(2, 3))],
        ['CV_EKB_Vol2.pdf', list(range(467, 468))],
        ['H/H8_H15.pdf', list(range(3, 4))],
        ['CV_EKB_Vol2.pdf', list(range(469, 470))],
        ['H/H8_H15.pdf', list(range(4, 5))],
        ['CV_EKB_Vol2.pdf', list(range(471, 472))],
        ['H/H8_H15.pdf', list(range(5, 6))],
        ['CV_EKB_Vol2.pdf', list(range(473, 474))],
        ['H/H8_H15.pdf', list(range(6, 7))],
        ['CV_EKB_Vol2.pdf', list(range(475, 476))],
        ['H/H8_H15.pdf', list(range(7, 8))],
        ['CV_EKB_Vol2.pdf', list(range(477, 478))],
        ['H/H16.pdf', list(range(0, 15))],
        ['CV_EKB_Vol2.pdf', list(range(493, 494))],
        ['H/H17.1.pdf', list(range(0, 1))],
        ['H/H17.2.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(499, 500))],
        ['H/H18.1.pdf', list(range(0, 1))],
        ['H/H18.2.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(505, 506))],
        ['H/H19.pdf', list(range(0, 7))],
        ['CV_EKB_Vol2.pdf', list(range(513, 514))],
        ['H/H20.1.pdf', list(range(0, 1))],
        ['H/H20.2.pdf', list(range(0, 8))],
        ['CV_EKB_Vol2.pdf', list(range(523, 524))],
        ['H/H21.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(528, 529))],
        ['H/H22.1.pdf', list(range(0, 1))],
        ['H/H22.2.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(534, 535))],
        ['H/H23.1.pdf', list(range(0, 1))],
        ['H/H23.2.pdf', list(range(0, 3))],
        ['CV_EKB_Vol2.pdf', list(range(539, 540))],
        ['H/H24.1.pdf', list(range(0, 1))],
        ['H/H24.2.pdf', list(range(0, 10))],
        ['CV_EKB_Vol2.pdf', list(range(551, 552))],
        ['H/H25.1.pdf', list(range(0, 1))],
        ['H/H25.2.pdf', list(range(0, 5))],
        ['CV_EKB_Vol2.pdf', list(range(558, 559))],
        ['H/H26.1.pdf', list(range(0, 1))],
        ['H/H26.2.pdf', list(range(0, 6))],
        ['CV_EKB_Vol2.pdf', list(range(566, 567))],
        ['CV_EKB_Vol2.pdf', list(range(567, 568))],
        ['I/I1.1.pdf', list(range(0, 1))],
        ['I/I1.2.pdf', list(range(0, 18))],
        ['CV_EKB_Vol2.pdf', list(range(587, 588))],
        ['I/I2.1.pdf', list(range(0, 1))],
        ['I/I2.2.pdf', list(range(0, 17))],
        ['CV_EKB_Vol2.pdf', list(range(606, 607))],
        ['I/I3.1.pdf', list(range(0, 1))],
        ['I/I3.2.pdf', list(range(0, 5))],
        ['CV_EKB_Vol2.pdf', list(range(613, 614))],
        ['I/I4.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(615, 616))],
        ['I/I5.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(617, 618))],
        ['I/I6.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(619, 620))],
        ['I/I7.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(621, 622))],
        ['I/I8.pdf', list(range(0, 4))],
        ['CV_EKB_Vol2.pdf', list(range(626, 627))],
        ['CV_EKB_Vol2.pdf', list(range(627, 628))],
        ['J/J1.pdf', list(range(0, 2))],
        ['CV_EKB_Vol2.pdf', list(range(630, 631))],
        ['J/J2.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(632, 633))],
        ['CV_EKB_Vol2.pdf', list(range(633, 634))],
        ['K/K1.pdf', list(range(0, 10))],
        ['CV_EKB_Vol2.pdf', list(range(644, 645))],
        ['K/K2.pdf', list(range(0, 1))],
        ['CV_EKB_Vol2.pdf', list(range(646, 647))]

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
