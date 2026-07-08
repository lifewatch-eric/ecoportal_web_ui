module DoiRequest
  extend ActiveSupport::Concern

  def first_pending_doi_request
    return unless @submission

    identifier_request_list = @ontology.explore.identifier_requests
    identifier_request_list.select { |r| r.status == 'PENDING' }.first
  end

  def cancel_pending_doi_requests
    identifier_request_list = @ontology.explore.identifier_requests
    identifier_requests = identifier_request_list.select { |r| r.status == 'PENDING' }

    return if identifier_requests.empty?

    identifier_requests.each do |identifier_request|
      identifier_request.update(values: { status: 'CANCELED' })
    end
  end

  def submit_new_doi_request(submission_id)
    request_id_hash = {
      status: 'PENDING',
      requestType: 'DOI_CREATE',
      requestedBy: session[:user].username,
      requestDate: DateTime.now.to_s,
      submission: submission_id
    }
    @identifier_req_obj = LinkedData::Client::Models::IdentifierRequest.new(values: request_id_hash)
    saved = @identifier_req_obj.save
    return saved if response_error?(saved) # in case of error, return false

    portal_admin_emails = LinkedData::Client::Models::User.all(include: 'all').select(&:admin?).map(&:email).compact
    begin
      DoiRequestMailer.new_doi_request(@ontology, submission_id, session[:user].username,
                                       portal_admin_emails).deliver
    rescue StandardError
      nil
    end

    saved
  end
end
