import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect () {
    const separator = ",";
    const rows = document.querySelectorAll('table#ontology_notes tr');
    const csv = [];
    for (let i = 0; i < rows.length; i++) {
        const row = [], cols = rows[i].querySelectorAll('td, th');
        for (let j = 0; j < cols.length; j++) {
            let data = cols[j].innerText.replace(/(\r\n|\n|\r)/gm, '').replace(/(\s\s)/gm, ' ')
            data = data.replace(/"/g, '""');
            row.push(data);
        }
        csv.push(row.join(separator));
    }
    this.csv_string = csv.join('\n');
  }

  downloadCSV () {
    this.#generateDownloadFile(this.csv_string, 'csv')
  }

  #generateDownloadFile (content, fileExtension) {
    var element = document.createElement('a')
    // TODO: change MIME type?
    element.setAttribute('href', 'data:application/rdf+json;charset=utf-8,' + encodeURIComponent(content))
    element.setAttribute('download', jQuery(document).data().bp.ontology.acronym + '_metadata.' + fileExtension)
    element.style.display = 'none'
    document.body.appendChild(element)
    element.click()
    document.body.removeChild(element)
  }
}
