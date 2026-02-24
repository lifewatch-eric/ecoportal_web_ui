class DoiRequestMailer < ApplicationMailer
  def new_doi_request(ontology, submission_id, requester_username)
    @ontology = ontology
    @submission_id = submission_id
    @requester_username = requester_username

    mail(
      to: $SUPPORT_EMAIL,
      subject: "New DOI request pending for #{ontology.name} (#{ontology.acronym})"
    )
  end
end
