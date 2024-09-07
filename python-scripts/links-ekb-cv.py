import PyPDF2
from PyPDF2.generic import ArrayObject, FloatObject, NameObject, AnnotationBuilder

def get_indirect_object_info(reader, obj_num, gen_num):
        indirect_object = PyPDF2.generic.IndirectObject(obj_num, gen_num, reader)
        actual_object = indirect_object.get_object()
        return actual_object

# Extract all the annotations from a pdfreader
def get_annotations_pdf(reader):
    # file_annotattions is a dictionary with the page and all the annotations for that page
    file_annotations = {}
    # Loop through all the pages in the pdf and extract the annotations
    for page_num, page in enumerate(reader.pages):
        annotations = get_annotations_page(page)
        file_annotations[page_num] = annotations
    return file_annotations

# Extract the annotations from the page
def get_annotations_page(page):
    if '/Annots' in page:
        return page['/Annots']
    return []

def get_annotations_link(reader, annotation):
    annotation_obj = get_indirect_object_info(reader, annotation.idnum, annotation.generation)
    if '/Subtype' in annotation_obj:
        if annotation_obj['/Subtype'] == '/Link':
            link_annotation = {
                "/Rect": annotation_obj["/Rect"],
                "/Border": annotation_obj.get("/Border"),
                "/A": annotation_obj.get("/A"),
                "/Dest": annotation_obj.get("/Dest"),            }
            return link_annotation
    return None

def create_link_annotations(reader):
    link_annotations = []
    for page_num, page in enumerate(reader.pages):
        annotations = get_annotations_page(page)
        for annotation in annotations:
            link_annotation = get_annotations_link(reader, annotation)
            if link_annotation:
                new_link_annotation = {
                    'page': page_num,
#                    'annotation': link_annotation,
                    'position': link_annotation["/Rect"],  # x, y, width, height (100, 100, 50, 50)
                    'destination': 100,  # page number (starting from 0)
                }                
                link_annotations.append(new_link_annotation)
    return link_annotations

# Print file annotations per page
def print_file_annotations(reader, file_annotations):
    for page_num, annotations in file_annotations.items():
        
        if annotations:
            print('Page: ' + page_num.__str__())       
            for annotation in annotations:
                annotation_obj = get_indirect_object_info(reader, annotation.idnum, annotation.generation)
                if '/Subtype' in annotation_obj:
                    if annotation_obj['/Subtype'] == '/Link':
                            link_annotation = {
                            "/Rect": annotation_obj["/Rect"],
                            "/Border": annotation_obj.get("/Border"),
                            "/A": annotation_obj.get("/A"),
                            "/Dest": annotation_obj.get("/Dest"),
                            "/DestObj": get_indirect_object_info(reader, annotation_obj.get("/Dest")[0].idnum, annotation_obj.get("/Dest")[0].generation)
                            }
                            print('    Annotation: ' + link_annotation.__str__())
                    print('    Annotation object: ' + annotation_obj.__str__())

def add_index_links(input_file, output_file, links, index_pages):
    with open(input_file, 'rb') as file_input:
        pdfreader = PyPDF2.PdfReader(file_input)
        pdfwriter = PyPDF2.PdfWriter()

        for page_num in range(len(pdfreader.pages)):
            page = pdfreader.pages[page_num]
            pdfwriter.add_page(page)
            print('    Page added: ' + str(len(pdfwriter.pages)))

        for page_num in index_pages:
            page = pdfwriter.pages[page_num]
            print('    Removing Annots in page index: ' + str(page_num))
            # Remove existing annotations
            if '/Annots' in page:
                page.pop('/Annots')
                print('    Annotations removed')

        for link in links:
            x1, y1, x2, y2 = link['position']
            dest_page_num = link['destination']
            wr_page_num = link['page']
            # annotation = PyPDF2.generic.DictionaryObject()
            # annotation.update({
            # '/Type': PyPDF2.generic.NameObject('/Annot'),
            # '/Subtype': PyPDF2.generic.NameObject('/Link'),
            # '/Rect': PyPDF2.generic.ArrayObject([
            #     PyPDF2.generic.FloatObject(x1),
            #     PyPDF2.generic.FloatObject(y1),
            #     PyPDF2.generic.FloatObject(x2),
            #     PyPDF2.generic.FloatObject(y2)
            #     ]),
            # '/Dest': PyPDF2.generic.ArrayObject([
            #     pdfwriter.pages[dest_page_num].indirect_ref,
            #     PyPDF2.generic.NameObject('/Fit')
            #     ])
            # })
            annotation = AnnotationBuilder.link(rect=(x1, y1, x2, y2), target_page_index=dest_page_num)

            pdfwriter.add_annotation(wr_page_num, annotation)
            print('    Annotation added: ' + annotation.__str__())

        with open(output_file, 'wb') as file_output:
            pdfwriter.write(file_output)

# Example usage
# links = [
#     {
#         'position': (100, 100, 50, 50),  # x, y, width, height
#         'destination': 2,  # page number (starting from 0)
#         'pages': [0, 1, 2],  # pages to add the link to
#     },
#     {
#         'position': (200, 200, 50, 50),
#         'destination': 4,
#         'pages': [1, 3],  # pages to add the link to
#     },
# ]



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


def ___main___():
    
    index_file = '../EKB-CV-Vol2-PDFs/index.pdf'
    input_file = '../EKB-CV-Vol2-PDFs/input.pdf'
    output_file = '../EKB-CV-Vol2-PDFs/output.pdf'

#    pdfreader = PyPDF2.PdfReader(index_file)

    # Get the Annotations (Links) from the input file
#    file_annotations = get_annotations_pdf(pdfreader)

#    print('Annotations: ' + file_annotations.__str__())

#    print_file_annotations(pdfreader, file_annotations)

    # Create the link annotations
 #   links = create_link_annotations(pdfreader)

    links = [
        {'page': 8, 'position': [78.55, 724.4, 512.05, 756.56], 'destination': 14},
        {'page': 8, 'position': [89.55, 699.46, 511.7, 724.4], 'destination': 15},
        {'page': 8, 'position': [89.55, 674.53, 511.7, 699.46], 'destination': 18},
        {'page': 8, 'position': [89.55, 649.59, 511.7, 674.53], 'destination': 21},
        {'page': 8, 'position': [89.55, 624.65, 511.7, 649.59], 'destination': 23},
        {'page': 8, 'position': [89.55, 599.71, 511.7, 624.65], 'destination': 25},
        {'page': 8, 'position': [89.55, 574.77, 511.7, 599.71], 'destination': 28},
        {'page': 8, 'position': [89.55, 549.84, 511.7, 574.77], 'destination': 30},
        {'page': 8, 'position': [89.55, 524.9, 511.7, 549.84], 'destination': 32},
        {'page': 8, 'position': [78.55, 498.75, 512.05, 524.9], 'destination': 36},
        {'page': 8, 'position': [89.55, 473.81, 511.7, 498.75], 'destination': 37},
        {'page': 8, 'position': [89.55, 448.87, 511.7, 473.81], 'destination': 39},
        {'page': 8, 'position': [89.55, 423.93, 511.7, 448.87], 'destination': 41},
        {'page': 8, 'position': [89.55, 398.99, 511.7, 423.93], 'destination': 43},
        {'page': 8, 'position': [89.55, 374.06, 511.7, 398.99], 'destination': 45},
        {'page': 8, 'position': [89.55, 349.12, 511.7, 374.06], 'destination': 47},
        {'page': 8, 'position': [89.55, 324.18, 511.7, 349.12], 'destination': 49},
        {'page': 8, 'position': [89.55, 299.24, 511.7, 324.18], 'destination': 51},
        {'page': 8, 'position': [89.55, 274.3, 520.27, 299.24], 'destination': 53},
        {'page': 8, 'position': [78.55, 262.15, 512.2, 274.3], 'destination': 55},
        {'page': 8, 'position': [82.8, 236, 512.05, 262.15], 'destination': 55},
        {'page': 8, 'position': [89.55, 211.06, 511.7, 236], 'destination': 56},
        {'page': 8, 'position': [89.55, 186.12, 511.7, 211.06], 'destination': 59},
        {'page': 8, 'position': [89.55, 161.18, 511.7, 186.12], 'destination': 62},
        {'page': 8, 'position': [89.55, 136.25, 511.7, 161.18], 'destination': 65},
        {'page': 8, 'position': [89.55, 111.31, 511.7, 136.25], 'destination': 68},
        {'page': 8, 'position': [89.55, 86.369, 511.7, 111.31], 'destination': 71},
        {'page': 8, 'position': [89.55, 61.431, 511.7, 86.369], 'destination': 74},
        {'page': 9, 'position': [89.55, 746.2, 511.7, 771.14], 'destination': 77},
        {'page': 9, 'position': [89.55, 721.26, 511.7, 746.2], 'destination': 80},
        {'page': 9, 'position': [89.55, 696.33, 511.7, 721.26], 'destination': 85},
        {'page': 9, 'position': [89.55, 671.39, 511.7, 696.33], 'destination': 88},
        {'page': 9, 'position': [89.55, 646.45, 511.7, 671.39], 'destination': 91},
        {'page': 9, 'position': [89.55, 621.51, 511.7, 646.45], 'destination': 94},
        {'page': 9, 'position': [89.55, 596.57, 511.7, 621.51], 'destination': 97},
        {'page': 9, 'position': [89.55, 571.64, 511.7, 596.57], 'destination': 100},
        {'page': 9, 'position': [89.55, 546.7, 511.7, 571.64], 'destination': 103},
        {'page': 9, 'position': [89.55, 535.76, 516.95, 546.7], 'destination': 106},
        {'page': 9, 'position': [82.8, 510.82, 511.7, 535.76], 'destination': 106},
        {'page': 9, 'position': [78.55, 484.67, 512.05, 510.82], 'destination': 108},
        {'page': 9, 'position': [89.55, 459.73, 511.7, 484.67], 'destination': 109},
        {'page': 9, 'position': [89.55, 434.79, 511.7, 459.73], 'destination': 111},
        {'page': 9, 'position': [89.55, 409.85, 519.16, 434.79], 'destination': 113},
        {'page': 9, 'position': [89.55, 384.92, 511.7, 409.85], 'destination': 115},
        {'page': 9, 'position': [89.55, 359.98, 511.7, 384.92], 'destination': 117},
        {'page': 9, 'position': [89.55, 335.04, 511.7, 359.98], 'destination': 120},
        {'page': 9, 'position': [89.55, 310.1, 511.7, 335.04], 'destination': 122},
        {'page': 9, 'position': [89.55, 285.16, 511.7, 310.1], 'destination': 124},
        {'page': 9, 'position': [89.55, 260.23, 511.7, 285.16], 'destination': 126},
        {'page': 9, 'position': [89.55, 249.29, 512.2, 260.23], 'destination': 129},
        {'page': 9, 'position': [82.8, 224.35, 511.7, 249.29], 'destination': 129},
        {'page': 9, 'position': [89.55, 213.41, 525.24, 224.35], 'destination': 153},
        {'page': 9, 'position': [82.8, 188.48, 511.7, 213.41], 'destination': 153},
        {'page': 9, 'position': [89.55, 163.54, 511.7, 188.48], 'destination': 155},
        {'page': 9, 'position': [89.55, 138.6, 511.7, 163.54], 'destination': 157},
        {'page': 9, 'position': [89.55, 127.66, 516.95, 138.6], 'destination': 159},
        {'page': 9, 'position': [82.8, 102.72, 511.7, 127.66], 'destination': 159},
        {'page': 9, 'position': [89.55, 77.785, 511.7, 102.72], 'destination': 161},
        {'page': 10, 'position': [89.55, 746.2, 511.7, 771.14], 'destination': 163},
        {'page': 10, 'position': [89.55, 721.26, 511.7, 746.2], 'destination': 166},
        {'page': 10, 'position': [89.55, 696.33, 511.7, 721.26], 'destination': 169},
        {'page': 10, 'position': [89.55, 671.39, 511.7, 696.33], 'destination': 172},
        {'page': 10, 'position': [89.55, 646.45, 511.7, 671.39], 'destination': 174},
        {'page': 10, 'position': [89.55, 621.51, 511.7, 646.45], 'destination': 176},
        {'page': 10, 'position': [89.55, 596.57, 511.7, 621.51], 'destination': 178},
        {'page': 10, 'position': [89.55, 571.64, 511.7, 596.57], 'destination': 181},
        {'page': 10, 'position': [89.55, 546.7, 511.7, 571.64], 'destination': 184},
        {'page': 10, 'position': [89.55, 521.76, 511.7, 546.7], 'destination': 186},
        {'page': 10, 'position': [89.55, 510.82, 512.2, 521.76], 'destination': 188},
        {'page': 10, 'position': [82.8, 485.88, 511.7, 510.82], 'destination': 188},
        {'page': 10, 'position': [89.55, 460.95, 511.7, 485.88], 'destination': 190},
        {'page': 10, 'position': [89.55, 436.01, 511.7, 460.95], 'destination': 192},
        {'page': 10, 'position': [89.55, 411.07, 511.7, 436.01], 'destination': 194},
        {'page': 10, 'position': [89.55, 386.13, 511.7, 411.07], 'destination': 196},
        {'page': 10, 'position': [78.55, 359.98, 512.05, 386.13], 'destination': 198},
        {'page': 10, 'position': [89.55, 335.04, 511.7, 359.98], 'destination': 199},
        {'page': 10, 'position': [89.55, 310.1, 511.7, 335.04], 'destination': 201},
        {'page': 10, 'position': [89.55, 285.16, 511.7, 310.1], 'destination': 203},
        {'page': 10, 'position': [89.55, 260.23, 511.7, 285.16], 'destination': 205},
        {'page': 10, 'position': [89.55, 235.29, 511.7, 260.23], 'destination': 207},
        {'page': 10, 'position': [89.55, 210.35, 511.7, 235.29], 'destination': 209},
        {'page': 10, 'position': [89.55, 185.41, 511.7, 210.35], 'destination': 211},
        {'page': 10, 'position': [89.55, 160.48, 511.7, 185.41], 'destination': 213},
        {'page': 10, 'position': [89.55, 135.54, 511.7, 160.48], 'destination': 215},
        {'page': 10, 'position': [89.55, 110.6, 511.7, 135.54], 'destination': 217},
        {'page': 10, 'position': [89.55, 85.661, 511.7, 110.6], 'destination': 219},
        {'page': 10, 'position': [89.55, 60.723, 511.7, 85.661], 'destination': 222},
        {'page': 11, 'position': [89.55, 760.2, 512.88, 771.14], 'destination': 224},
        {'page': 11, 'position': [82.8, 735.26, 511.7, 760.2], 'destination': 224},
        {'page': 11, 'position': [89.55, 710.33, 511.7, 735.26], 'destination': 226},
        {'page': 11, 'position': [89.55, 685.39, 511.7, 710.33], 'destination': 228},
        {'page': 11, 'position': [78.55, 659.23, 512.05, 685.39], 'destination': 230},
        {'page': 11, 'position': [89.55, 648.3, 523.36, 659.23], 'destination': 231},
        {'page': 11, 'position': [82.8, 623.36, 511.7, 648.3], 'destination': 231},
        {'page': 11, 'position': [89.55, 612.42, 512.2, 623.36], 'destination': 237},
        {'page': 11, 'position': [82.8, 587.48, 511.7, 612.42], 'destination': 237},
        {'page': 11, 'position': [89.55, 576.54, 512.2, 587.48], 'destination': 245},
        {'page': 11, 'position': [82.8, 551.61, 511.7, 576.54], 'destination': 245},
        {'page': 11, 'position': [89.55, 540.67, 512.2, 551.61], 'destination': 252},
        {'page': 11, 'position': [82.8, 515.73, 511.7, 540.67], 'destination': 252},
        {'page': 11, 'position': [89.55, 504.79, 528.95, 515.73], 'destination': 261},
        {'page': 11, 'position': [82.8, 479.85, 511.7, 504.79], 'destination': 261},
        {'page': 11, 'position': [89.55, 468.92, 512.2, 479.85], 'destination': 269},
        {'page': 11, 'position': [82.8, 443.98, 511.7, 468.92], 'destination': 269},
        {'page': 11, 'position': [89.55, 433.04, 512.2, 443.98], 'destination': 277},
        {'page': 11, 'position': [82.8, 408.1, 511.7, 433.04], 'destination': 277},
        {'page': 11, 'position': [89.55, 383.16, 511.7, 408.1], 'destination': 294},
        {'page': 11, 'position': [78.55, 357.01, 512.05, 383.16], 'destination': 297},
        {'page': 11, 'position': [89.55, 332.07, 511.7, 357.01], 'destination': 298},
        {'page': 11, 'position': [89.55, 307.14, 511.7, 332.07], 'destination': 302},
        {'page': 11, 'position': [89.55, 296.2, 520.87, 307.14], 'destination': 306},
        {'page': 11, 'position': [82.8, 271.26, 511.7, 296.2], 'destination': 306},
        {'page': 11, 'position': [89.55, 246.32, 511.7, 271.26], 'destination': 315},
        {'page': 11, 'position': [89.55, 221.38, 511.7, 246.32], 'destination': 319},
        {'page': 11, 'position': [89.55, 210.45, 512.2, 221.38], 'destination': 323},
        {'page': 11, 'position': [82.8, 185.51, 511.7, 210.45], 'destination': 323},
        {'page': 11, 'position': [89.55, 160.57, 511.7, 185.51], 'destination': 332},
        {'page': 11, 'position': [89.55, 149.63, 512.2, 160.57], 'destination': 336},
        {'page': 11, 'position': [82.8, 124.69, 511.7, 149.63], 'destination': 336},
        {'page': 11, 'position': [89.55, 113.76, 518.96, 124.69], 'destination': 340},
        {'page': 11, 'position': [82.8, 88.818, 511.7, 113.76], 'destination': 340},
        {'page': 11, 'position': [89.55, 63.88, 515.2, 88.818], 'destination': 344},
        {'page': 12, 'position': [89.55, 746.2, 511.7, 771.14], 'destination': 352},
        {'page': 12, 'position': [89.55, 735.26, 519.7, 746.2], 'destination': 356},
        {'page': 12, 'position': [82.8, 710.33, 511.7, 735.26], 'destination': 356},
        {'page': 12, 'position': [78.55, 684.17, 512.05, 710.33], 'destination': 363},
        {'page': 12, 'position': [89.55, 659.23, 511.7, 684.17], 'destination': 364},
        {'page': 12, 'position': [89.55, 634.3, 511.7, 659.23], 'destination': 366},
        {'page': 12, 'position': [89.55, 623.36, 513.76, 634.3], 'destination': 385},
        {'page': 12, 'position': [82.8, 598.42, 511.7, 623.36], 'destination': 385},
        {'page': 12, 'position': [89.55, 573.48, 511.7, 598.42], 'destination': 396},
        {'page': 12, 'position': [89.55, 548.54, 511.7, 573.48], 'destination': 414},
        {'page': 12, 'position': [89.55, 523.61, 511.7, 548.54], 'destination': 426},
        {'page': 12, 'position': [89.55, 512.67, 512.2, 523.61], 'destination': 454},
        {'page': 12, 'position': [82.8, 487.73, 511.7, 512.67], 'destination': 454},
        {'page': 12, 'position': [89.55, 462.79, 511.7, 487.73], 'destination': 461},
        {'page': 12, 'position': [89.55, 437.85, 511.7, 462.79], 'destination': 463},
        {'page': 12, 'position': [89.55, 412.92, 511.7, 437.85], 'destination': 465},
        {'page': 12, 'position': [89.55, 387.98, 511.7, 412.92], 'destination': 467},
        {'page': 12, 'position': [89.55, 363.04, 511.7, 387.98], 'destination': 469},
        {'page': 12, 'position': [89.55, 352.1, 512.2, 363.04], 'destination': 471},
        {'page': 12, 'position': [82.8, 327.16, 511.7, 352.1], 'destination': 471},
        {'page': 12, 'position': [89.55, 316.23, 524.47, 327.16], 'destination': 473},
        {'page': 12, 'position': [82.8, 291.29, 511.7, 316.23], 'destination': 473},
        {'page': 12, 'position': [89.55, 266.35, 514.99, 291.29], 'destination': 475},
        {'page': 12, 'position': [89.55, 241.41, 526, 266.35], 'destination': 477},
        {'page': 12, 'position': [89.55, 216.48, 511.7, 241.41], 'destination': 493},
        {'page': 12, 'position': [89.55, 205.54, 512.2, 216.48], 'destination': 499},
        {'page': 12, 'position': [82.8, 180.6, 511.7, 205.54], 'destination': 499},
        {'page': 12, 'position': [89.55, 169.66, 525.92, 180.6], 'destination': 505},
        {'page': 12, 'position': [82.8, 144.72, 511.7, 169.66], 'destination': 505},
        {'page': 12, 'position': [89.55, 119.79, 511.7, 144.72], 'destination': 513},
        {'page': 12, 'position': [89.55, 108.85, 517.65, 119.79], 'destination': 523},
        {'page': 12, 'position': [82.8, 83.909, 511.7, 108.85], 'destination': 523},
        {'page': 13, 'position': [89.55, 760.2, 512.2, 771.14], 'destination': 528},
        {'page': 13, 'position': [82.8, 735.26, 511.7, 760.2], 'destination': 528},
        {'page': 13, 'position': [89.55, 724.33, 514.82, 735.26], 'destination': 534},
        {'page': 13, 'position': [82.8, 713.39, 512.2, 724.33], 'destination': 534},
        {'page': 13, 'position': [82.8, 688.45, 511.7, 713.39], 'destination': 534},
        {'page': 13, 'position': [89.55, 663.51, 511.7, 688.45], 'destination': 539},
        {'page': 13, 'position': [89.55, 638.57, 511.7, 663.51], 'destination': 551},
        {'page': 13, 'position': [89.55, 627.64, 512.2, 638.57], 'destination': 558},
        {'page': 13, 'position': [82.8, 616.7, 512.2, 627.64], 'destination': 558},
        {'page': 13, 'position': [82.8, 591.76, 511.7, 616.7], 'destination': 558},
        {'page': 13, 'position': [78.55, 565.61, 512.05, 591.76], 'destination': 566},
        {'page': 13, 'position': [89.55, 540.67, 511.7, 565.61], 'destination': 567},
        {'page': 13, 'position': [89.55, 515.73, 511.7, 540.67], 'destination': 587},
        {'page': 13, 'position': [89.55, 490.79, 511.7, 515.73], 'destination': 606},
        {'page': 13, 'position': [89.55, 465.85, 511.7, 490.79], 'destination': 613},
        {'page': 13, 'position': [89.55, 454.92, 519.78, 465.85], 'destination': 615},
        {'page': 13, 'position': [82.8, 429.98, 511.7, 454.92], 'destination': 615},
        {'page': 13, 'position': [89.55, 405.04, 511.7, 429.98], 'destination': 617},
        {'page': 13, 'position': [89.55, 380.1, 511.7, 405.04], 'destination': 619},
        {'page': 13, 'position': [89.55, 355.16, 511.7, 380.1], 'destination': 621},
        {'page': 13, 'position': [78.55, 329.01, 512.05, 355.16], 'destination': 626},
        {'page': 13, 'position': [89.55, 318.07, 516.58, 329.01], 'destination': 627},
        {'page': 13, 'position': [82.8, 293.14, 511.7, 318.07], 'destination': 627},
        {'page': 13, 'position': [89.55, 268.2, 511.7, 293.14], 'destination': 630},
        {'page': 13, 'position': [78.55, 242.04, 512.05, 268.2], 'destination': 632},
        {'page': 13, 'position': [89.55, 231.11, 512.2, 242.04], 'destination': 633},
        {'page': 13, 'position': [82.8, 206.17, 511.7, 231.11], 'destination': 633},
        {'page': 13, 'position': [89.55, 195.23, 512.2, 206.17], 'destination': 644},
        {'page': 13, 'position': [82.8, 170.29, 511.7, 195.23], 'destination': 644}
    ]

    index_pages = [8, 9, 10, 11, 12, 13]

    for link in links:
        print(link)   

    print("Adding links to EKB-CV")

    add_index_links(input_file, output_file, links, index_pages)


if __name__ == "__main__":
    ___main___()