import PyPDF2
from PyPDF2.generic import ArrayObject, FloatObject, NameObject

def get_indirect_object_info(reader, obj_num, gen_num):
        indirect_object = PyPDF2.generic.IndirectObject(obj_num, gen_num, reader)
        actual_object = indirect_object.get_object()
        return actual_object

# Extract all the annotations from a pdfreader
def get_pdf_annotations(reader):
    # file_annotattions is a dictionary with the page and all the annotations for that page
    file_annotations = {}
    # Loop through all the pages in the pdf and extract the annotations
    for page_num, page in enumerate(reader.pages):
        annotations = extract_annotations_page(page)
        file_annotations[page_num] = annotations
    return file_annotations

# Extract the annotations from the page
def extract_annotations_page(page):
    if '/Annots' in page:
        return page['/Annots']
    return []

# Print file annotations per page
def print_file_annotations(file_annotations):
    for page_num, annotations in file_annotations.items():
        print('Page: ' + page_num.__str__())
        for annotation in annotations:
            print('    Annotation: ' + annotation.__str__())

def add_internal_links(pdf_file, links):
    with open(pdf_file, 'rb') as file:
        pdf = PyPDF2.PdfReader(file)
        output = PyPDF2.PdfWriter()

        for page_num in range( len(pdf.pages)):
            page = pdf.pages[page_num]
            annotations = page['/Annots'] if '/Annots' in page else []

            for link in links:
                x, y, width, height = link['position']
                dest_page_num = link['destination']

                if page_num in link['pages']:
                    annotation = PyPDF2.generic.DictionaryObject()
                    annotation.update({
                    '/Type': PyPDF2.generic.NameObject('/Annot'),
                    '/Subtype': PyPDF2.generic.NameObject('/Link'),
                    '/Rect': PyPDF2.generic.ArrayObject([
                        PyPDF2.generic.FloatObject(x),
                        PyPDF2.generic.FloatObject(y),
                        PyPDF2.generic.FloatObject(x + width),
                        PyPDF2.generic.FloatObject(y + height)
                    ]),
                    '/Dest': PyPDF2.generic.ArrayObject([
                        pdf.pages[dest_page_num].indirect_ref,
                        PyPDF2.generic.NameObject('/Fit')
                    ])
                })

                    annotations.append(annotation)

            page.update({
                '/Annots': annotations
            })

            output.add_page(page)

        with open('output.pdf', 'wb') as output_file:
            output.write(output_file)

# Example usage
links = [
    {
        'position': (100, 100, 50, 50),  # x, y, width, height
        'destination': 2,  # page number (starting from 0)
        'pages': [0, 1, 2],  # pages to add the link to
    },
    {
        'position': (200, 200, 50, 50),
        'destination': 4,
        'pages': [1, 3],  # pages to add the link to
    },
]


#           # Get the annotations from the page
 #           annotations = extract_annotations(read_page)
 #           print('    Annotations: ' + annotations.__str__())

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
    
    index_file = 'index.pdf'
    input_file = 'input.pdf'
    output_file = 'output.pdf'

    pdfreader = PyPDF2.PdfReader(index_file)

    # Get the Annotations (Links) from the input file
    file_annotations = get_pdf_annotations(pdfreader)

    print('Annotations: ' + file_annotations.__str__())

#    print("Adding links to EKB-CV")

 #   add_internal_links('input.pdf', links)


if __name__ == "__main__":
    ___main___()