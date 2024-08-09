import requests
from xml.etree import ElementTree

# Define the base URL and parameters
base_url = "https://www.repository.utl.pt/oaiextended/request"
params = {
    "verb": "GetRecord",
    "identifier": "oai:repository.utl.pt:10400.5/29493",
    "metadataPrefix": "oai_dc"
}

# Send the GET request to the OAI-PMH endpoint
response = requests.get(base_url, params=params)

# Check if the request was successful
if response.status_code == 200:
    # Parse the XML response
    root = ElementTree.fromstring(response.content)

    # Extract the metadata
    namespaces = {'oai_dc': 'http://www.openarchives.org/OAI/2.0/oai_dc/', 'dc': 'http://purl.org/dc/elements/1.1/'}
    metadata = root.find('.//oai_dc:dc', namespaces)

    if metadata is not None:
        data = {}
        for element in metadata:
            tag = element.tag.split('}')[1]
            data.setdefault(tag, []).append(element.text)

        # Print the extracted metadata
        for key, value in data.items():
            print(f"{key}: {value}")
    else:
        print("No metadata found")
else:
    print(f"Failed to retrieve data: {response.status_code}")