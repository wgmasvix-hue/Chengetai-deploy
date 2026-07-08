package dspace10

import "fmt"

type Images struct {
	Backend string
	Solr    string
	Angular string
}

var versions = map[string]Images{
	"10.0": {
		Backend: "dspace/dspace:dspace-10.0",
		Solr:    "dspace/dspace-solr:dspace-10.0",
		Angular: "dspace/dspace-angular:dspace-10.0",
	},
	"9.3": {
		Backend: "dspace/dspace:dspace-9.3",
		Solr:    "dspace/dspace-solr:dspace-9_x",
		Angular: "dspace/dspace-angular:dspace-9.3",
	},
}

func GetImages(version string) (Images, error) {
	img, ok := versions[version]
	if !ok {
		return Images{}, fmt.Errorf("unsupported DSpace version: %s", version)
	}

	return img, nil
}
