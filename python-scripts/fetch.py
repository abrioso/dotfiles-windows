import requests
from xml.etree import ElementTree
import json

# Define the base URL
base_url = "https://www.repository.utl.pt/oaiextended/request"

# List of identifiers
identifiers = [
    "oai:repository.utl.pt:10400.5/20605",
"oai:repository.utl.pt:10400.5/21462",
"oai:repository.utl.pt:10400.5/21442",
"oai:repository.utl.pt:10400.5/20604",
"oai:repository.utl.pt:10400.5/20578",
"oai:repository.utl.pt:10400.5/20576",
"oai:repository.utl.pt:10400.5/20575",
"oai:repository.utl.pt:10400.5/20784",
"oai:repository.utl.pt:10400.5/20783",
"oai:repository.utl.pt:10400.5/20577",
"oai:repository.utl.pt:10400.5/20609",
"oai:repository.utl.pt:10400.5/20607",
"oai:repository.utl.pt:10400.5/20608",
"oai:repository.utl.pt:10400.5/20624",
"oai:repository.utl.pt:10400.5/20787",
"oai:repository.utl.pt:10400.5/20591",
"oai:repository.utl.pt:10400.5/20786",
"oai:repository.utl.pt:10400.5/20785",
"oai:repository.utl.pt:10400.5/23809",
"oai:repository.utl.pt:10400.5/22304",
"oai:repository.utl.pt:10400.5/20625",
"oai:repository.utl.pt:10400.5/22622",
"oai:repository.utl.pt:10400.5/21443",
"oai:repository.utl.pt:10400.5/21444",
"oai:repository.utl.pt:10400.5/21463",
"oai:repository.utl.pt:10400.5/21440",
"oai:repository.utl.pt:10400.5/21441",
"oai:repository.utl.pt:10400.5/23791",
"oai:repository.utl.pt:10400.5/22302",
"oai:repository.utl.pt:10400.5/22680",
"oai:repository.utl.pt:10400.5/21656",
"oai:repository.utl.pt:10400.5/21758",
"oai:repository.utl.pt:10400.5/22299",
"oai:repository.utl.pt:10400.5/22303",
"oai:repository.utl.pt:10400.5/21655",
"oai:repository.utl.pt:10400.5/21696",
"oai:repository.utl.pt:10400.5/21654",
"oai:repository.utl.pt:10400.5/21657",
"oai:repository.utl.pt:10400.5/21658",
"oai:repository.utl.pt:10400.5/23799",
"oai:repository.utl.pt:10400.5/23973",
"oai:repository.utl.pt:10400.5/25050",
"oai:repository.utl.pt:10400.5/25048",
"oai:repository.utl.pt:10400.5/25049",
"oai:repository.utl.pt:10400.5/25052",
"oai:repository.utl.pt:10400.5/23803",
"oai:repository.utl.pt:10400.5/23805",
"oai:repository.utl.pt:10400.5/24802",
"oai:repository.utl.pt:10400.5/24795",
"oai:repository.utl.pt:10400.5/23807",
"oai:repository.utl.pt:10400.5/23974",
"oai:repository.utl.pt:10400.5/23834",
"oai:repository.utl.pt:10400.5/23975",
"oai:repository.utl.pt:10400.5/24219",
"oai:repository.utl.pt:10400.5/25765",
"oai:repository.utl.pt:10400.5/27110",
"oai:repository.utl.pt:10400.5/27467",
"oai:repository.utl.pt:10400.5/29489",
"oai:repository.utl.pt:10400.5/24229",
"oai:repository.utl.pt:10400.5/30422",
"oai:repository.utl.pt:10400.5/30416",
"oai:repository.utl.pt:10400.5/30414",
"oai:repository.utl.pt:10400.5/30417",
"oai:repository.utl.pt:10400.5/27968",
"oai:repository.utl.pt:10400.5/27466",
"oai:repository.utl.pt:10400.5/27468",
"oai:repository.utl.pt:10400.5/27465",
"oai:repository.utl.pt:10400.5/29491",
"oai:repository.utl.pt:10400.5/27971",
"oai:repository.utl.pt:10400.5/27970",
"oai:repository.utl.pt:10400.5/29488",
"oai:repository.utl.pt:10400.5/31090",
"oai:repository.utl.pt:10400.5/30420",
"oai:repository.utl.pt:10400.5/30421",
"oai:repository.utl.pt:10400.5/28006",
"oai:repository.utl.pt:10400.5/29493",
"oai:repository.utl.pt:10400.5/30423",
"oai:repository.utl.pt:10400.5/28003",
"oai:repository.utl.pt:10400.5/27969",
"oai:repository.utl.pt:10400.5/30431",
"oai:repository.utl.pt:10400.5/31096",
"oai:repository.utl.pt:10400.5/31089",
"oai:repository.utl.pt:10400.5/31092"
]

# Loop through each identifier
for identifier in identifiers:
    # Define the parameters for the current identifier
    params = {
        "verb": "GetRecord",
        "identifier": identifier,
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
            json_filename = f'metadata_{identifier.split("/")[-1]}.json'
            with open(json_filename, 'w', encoding='utf-8') as json_file:
                json.dump(data, json_file, ensure_ascii=False, indent=4)

            print(f"Metadata for {identifier} has been written to {json_filename}")
        else:
            print(f"No metadata found for {identifier}")
    else:
        print(f"Failed to retrieve data for {identifier}. HTTP Status Code: {response.status_code}")