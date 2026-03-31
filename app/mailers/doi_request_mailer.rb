class DoiRequestMailer < ApplicationMailer
  def new_doi_request(ontology, submission_id, requester_username, admin_emails = [])
    @ontology = ontology
    @submission_id = submission_id
    @requester_username = requester_username

    recipients = admin_emails.presence || [$SUPPORT_EMAIL]

    mail(
      to: recipients,
      from: $SUPPORT_EMAIL,
      subject: "New DOI request pending for #{ontology.name} (#{ontology.acronym})"
    )
  end
end
