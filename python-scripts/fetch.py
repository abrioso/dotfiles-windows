import requests
from xml.etree import ElementTree
import json

# Define the base URL and parameters
base_url = "https://www.repository.utl.pt/oaiextended/request"
params = {
    "verb": "GetRecord",
    "identifier": "oai:repository.utl.pt:10400.5/20605",
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

        # Write the extracted metadata to a JSON file
        with open('metadata.json', 'w', encoding='utf-8') as json_file:
            json.dump(data, json_file, ensure_ascii=False, indent=4)

        print("Metadata has been written to metadata.json")
    else:
        print("No metadata found")
else:
    print(f"Failed to retrieve data. HTTP Status Code: {response.status_code}")